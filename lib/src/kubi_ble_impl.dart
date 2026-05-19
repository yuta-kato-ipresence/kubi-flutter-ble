import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kIsWeb;
import 'package:universal_ble/universal_ble.dart' as ub;

import 'errors/kubi_ble_error.dart';
import 'kubi_ble.dart';
import 'kubi_protocol.dart' as proto;
import 'types/auto_reconnect_config.dart';
import 'types/ble_availability.dart';
import 'types/ble_connection_state.dart';
import 'types/ble_debug_event.dart';
import 'types/cancel_token.dart';
import 'types/connection_state_event.dart';
import 'types/disconnect_reason.dart';
import 'types/kubi_device.dart';
import 'types/kubi_state.dart';
import 'types/move_event.dart';
import 'types/move_phase.dart';
import 'types/move_result.dart';
import 'types/move_spec.dart';
import 'types/move_speed.dart';
import 'types/pan_tilt_angles.dart';
import 'types/position_snapshot.dart';
import 'types/position_source.dart';
import 'types/settle_options.dart';
import 'types/subscribe_position_options.dart';

/// `KubiBle` の本番実装 (universal_ble 1.2 backend)。
///
/// **設計の要点 (api-design §5):**
/// - GATT write/read の直列化は `UniversalBle` 内蔵の per-device queue に委譲
///   (D2、constructor で `queueType = QueueType.perDevice` を設定)
/// - self-lock は「moveTo cancel-on-newer」「latest-value buffer」
///   「subscribe poll skip」のアプリケーション層ロジックのみ
/// - 接続中間状態 (`connecting` / `disconnecting`) は本クラスが手動 emit (D3)
/// - `availabilityStream` を listen し、`poweredOff` / `unauthorized` / `resetting`
///   検知時に内部 disconnect する (D4)
///
/// テスト時は `UniversalBle.setInstance(...)` で `UniversalBlePlatform` を mock
/// できるため、本クラス自体は backend を直接受け取らない。
final class KubiBleImpl implements KubiBle {
  /// インスタンスを生成し、universal_ble の per-device queue (D2) を構成する。
  ///
  /// `defaultSpeed` を省略した場合、`MoveSpeed.uniform(100)` (= 全速) が初期値。
  KubiBleImpl({MoveSpeed? defaultSpeed})
      : _defaultSpeed = defaultSpeed ??
            const MoveSpeed.uniform(proto.defaultMoveSpeed) {
    ub.UniversalBle.queueType = ub.QueueType.perDevice;
    _wireGlobalCallbacks();
    _availabilitySub = ub.UniversalBle.availabilityStream.listen(
      _handleAvailability,
      onError: (Object e, StackTrace st) {
        _emitDebug(BleDebugEventType.listenerError,
            message: 'availabilityStream error: $e');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 内部状態
  // ---------------------------------------------------------------------------

  KubiDevice? _device;
  // ignore: prefer_final_fields  // 後続 todo (p3-connect) で書き換え予定
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  MoveSpeed _defaultSpeed;
  // ignore: unused_field  // p3-auto-reconnect で参照
  AutoReconnectConfig? _autoReconnect;

  /// 利用者からの明示 `disconnect()` 中フラグ。
  /// `onConnectionChange` callback の自然 disconnect (deviceLost/error) と区別する。
  bool _explicitDisconnectInProgress = false;

  // ---- register read 1:1 照合 (p3-protocol-rw) ----
  Completer<Uint8List>? _pendingRead;
  int? _pendingMotorId;
  int? _pendingAddr;
  StreamSubscription<Uint8List>? _notifySub;
  /// register read を直列化する mutex (B10、未来 of 直前 read).
  Future<void> _readChain = Future<void>.value();

  // ---- moveTo / setTarget (p3-moveto) ----
  _ActiveMove? _activeMove;
  /// `setTarget` の write が in-flight 中かどうか。
  bool _setTargetWriteInflight = false;
  /// in-flight 中に来た最新 `setTarget` 入力 (latest-value buffer、§5.1 / B10)。
  PanTiltAngles? _pendingSetTarget;
  MoveSpeed? _pendingSetTargetSpeed;
  /// 直近 commanded position (synced モードの arc-ratio 計算用、§B6)。
  /// `_writeMoveSequence` 成功後に更新する (TS `_lastCommanded` と完全一致)。
  PanTiltAngles? _lastCommanded;

  // ---- auto-reconnect (p3-auto-reconnect) ----
  Timer? _reconnectTimer;
  /// 既に消化した attempt 数 (1-based: schedule 完了時点でこの値)。
  int _reconnectAttempt = 0;
  bool _disposed = false;

  final ValueNotifier<KubiState> _state = ValueNotifier(KubiState.initial);

  final StreamController<ConnectionStateEvent> _connectionStateCtl =
      StreamController.broadcast();
  final StreamController<BleAvailability> _availabilityCtl =
      StreamController.broadcast();
  final StreamController<MoveEvent> _moveCtl = StreamController.broadcast();
  final StreamController<BleDebugEvent> _debugCtl =
      StreamController.broadcast();

  StreamSubscription<ub.AvailabilityState>? _availabilitySub;

  // ---------------------------------------------------------------------------
  // KubiBle implementation (Phase 3 後続 todo で順次実装)
  // ---------------------------------------------------------------------------

  @override
  Stream<KubiDevice> scan({Duration? timeout}) {
    final ctl = StreamController<KubiDevice>();
    final seen = <String>{};
    StreamSubscription<ub.BleDevice>? sub;
    Timer? timeoutTimer;

    Future<void> stop() async {
      timeoutTimer?.cancel();
      timeoutTimer = null;
      await sub?.cancel();
      sub = null;
      try {
        await ub.UniversalBle.stopScan();
      } on Object catch (_) {
        // stopScan は best-effort (既に停止済の場合等)。
      }
      if (!ctl.isClosed) await ctl.close();
    }

    ctl.onListen = () async {
      // CRITICAL: scanStream は broadcast (バッファ無し) なので、emit を取り逃さないよう
      // startScan の前に subscribe しておく必要がある。
      // Web の universal_ble は requestDevice picker の await 内で scanStream.add() を
      // 同期的に呼ぶため、startScan の Future 完了後に subscribe すると emit を逃す。
      sub = ub.UniversalBle.scanStream.listen(
        (dev) {
          if (ctl.isClosed) return;
          if (seen.add(dev.deviceId)) {
            _safeAdd(ctl, KubiDevice(id: dev.deviceId, name: dev.name));
          }
        },
        onError: (Object e, StackTrace st) {
          if (!ctl.isClosed) ctl.addError(e, st);
        },
      );
      try {
        await ub.UniversalBle.startScan(
          scanFilter: ub.ScanFilter(
            withNamePrefix: const [proto.deviceNamePrefix],
          ),
          // Web Bluetooth では requestDevice 時に optionalServices を宣言しないと
          // 接続後 getPrimaryService が SecurityError (blocklisted UUID) になる。
          // native では PlatformConfig は無視されるため、常時付与で問題ない。
          platformConfig: ub.PlatformConfig(
            web: ub.WebOptions(
              optionalServices: const [proto.servoServiceUuid],
            ),
          ),
        );
      } on Object catch (e, st) {
        ctl.addError(BleUnavailableError('startScan failed: $e'), st);
        await stop();
        return;
      }
      if (timeout != null) {
        timeoutTimer = Timer(timeout, stop);
      }
    };
    ctl.onCancel = stop;
    return ctl.stream;
  }

  @override
  Future<KubiDevice> requestDevice({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      return await scan(timeout: timeout).first;
    } on StateError {
      throw TimeoutException(
        'No Kubi device found within ${timeout.inMilliseconds}ms',
        timeout,
      );
    }
  }

  @override
  Future<void> connect(
    KubiDevice device, {
    Duration timeout = const Duration(milliseconds: proto.connectionTimeoutMs),
  }) async {
    if (timeout.inMicroseconds <= 0) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (_connectionState != BleConnectionState.disconnected) {
      throw const BleConnectionError(
        'Already connected/connecting. Call disconnect() first.',
      );
    }
    _device = device;
    _explicitDisconnectInProgress = false;
    _setConnectionState(BleConnectionState.connecting);
    try {
      await ub.UniversalBle.connect(device.id, timeout: timeout);
      await ub.UniversalBle.discoverServices(device.id);
      await ub.UniversalBle.subscribeNotifications(
        device.id,
        proto.servoServiceUuid,
        proto.motorPositionUuid,
      );
      _notifySub = ub.UniversalBle
          .characteristicValueStream(device.id, proto.motorPositionUuid)
          .listen(
        _handleNotification,
        onError: (Object e, StackTrace st) {
          _emitDebug(
            BleDebugEventType.listenerError,
            message: 'characteristicValueStream error: $e',
          );
        },
      );
      _setConnectionState(BleConnectionState.connected);
      // p3-auto-reconnect: 成功 = カウンタ reset。
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } on Object catch (e) {
      _device = null;
      _setConnectionState(
        BleConnectionState.disconnected,
        reason: DisconnectReason.error,
      );
      if (e is ub.ConnectionException) {
        throw BleConnectionError('connect failed: ${e.message}');
      }
      throw BleConnectionError('connect failed: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    final dev = _device;
    if (dev == null) return;
    _explicitDisconnectInProgress = true;
    // user intent: 進行中の auto-reconnect schedule は破棄。
    _cancelReconnectSchedule();
    _setConnectionState(
      BleConnectionState.disconnecting,
      reason: DisconnectReason.user,
    );
    try {
      await ub.UniversalBle.disconnect(dev.id);
    } on Object catch (e) {
      _emitDebug(
        BleDebugEventType.connectionStateChange,
        message: 'disconnect call failed (continuing): $e',
      );
    }
    await _notifySub?.cancel();
    _notifySub = null;
    _failPendingRead('disconnected');
    _cancelActiveMove('disconnected by user');
    _lastCommanded = null;
    _setConnectionState(
      BleConnectionState.disconnected,
      reason: DisconnectReason.user,
    );
    _device = null;
    _explicitDisconnectInProgress = false;
  }

  @override
  void setAutoReconnect(AutoReconnectConfig? config) {
    _autoReconnect = config;
  }

  @override
  Future<KubiDevice?> tryAutoConnect() async {
    // D5: Web は universal_ble v1.2.0 が getDevices を wrap してないので常に null。
    if (kIsWeb) return null;
    try {
      final devices = await ub.UniversalBle.getSystemDevices(
        withServices: <String>[proto.servoServiceUuid],
      );
      ub.BleDevice? candidate;
      for (final d in devices) {
        final n = d.name;
        if (n != null && n.startsWith(proto.deviceNamePrefix)) {
          candidate = d;
          break;
        }
      }
      if (candidate == null) return null;
      final kdev = KubiDevice(id: candidate.deviceId, name: candidate.name);
      await connect(kdev);
      return kdev;
    } on Object catch (e) {
      _emitDebug(
        BleDebugEventType.connectionStateChange,
        message: 'tryAutoConnect failed: $e',
      );
      return null;
    }
  }

  @override
  Stream<ConnectionStateEvent> get connectionStateStream =>
      _connectionStateCtl.stream;

  @override
  BleConnectionState get currentConnectionState => _connectionState;

  @override
  Stream<BleAvailability> get availabilityStream => _availabilityCtl.stream;

  @override
  Future<void> setTarget({
    required PanTiltAngles target,
    MoveSpeed? speed,
  }) async {
    _requireConnected();
    final clamped = proto.clampPanTilt(target.pan, target.tilt);
    final effectiveSpeed = speed ?? _defaultSpeed;
    // 進行中 moveTo を cancel-on-newer (§3.2.3 / §5.1)。
    _cancelActiveMove('superseded by setTarget');
    // latest-value buffer: write が既に走っていたら最新値を覚えるだけ。
    if (_setTargetWriteInflight) {
      _pendingSetTarget = clamped;
      _pendingSetTargetSpeed = effectiveSpeed;
      return;
    }
    _setTargetWriteInflight = true;
    try {
      var curTarget = clamped;
      var curSpeed = effectiveSpeed;
      while (true) {
        final speeds = _resolveSpeeds(
          MoveSpec.independent(speed: curSpeed),
          curTarget,
        );
        await _writeMoveSequence(curTarget, speeds.$1, speeds.$2);
        final next = _pendingSetTarget;
        if (next == null) break;
        curTarget = next;
        curSpeed = _pendingSetTargetSpeed ?? effectiveSpeed;
        _pendingSetTarget = null;
        _pendingSetTargetSpeed = null;
      }
    } finally {
      _setTargetWriteInflight = false;
    }
  }

  @override
  Future<MoveResult> moveTo({
    required PanTiltAngles target,
    MoveSpec spec = const MoveSpec.independent(),
    SettleOptions settle = const SettleOptions(),
    CancelToken? cancel,
  }) async {
    _requireConnected();
    final clamped = proto.clampPanTilt(target.pan, target.tilt);

    // 1. 既存 moveTo を cancel-on-newer。
    _cancelActiveMove('superseded by newer moveTo');

    final active = _ActiveMove(target: clamped, cancelToken: cancel);
    _activeMove = active;
    _updateState((s) => s.copyWith(isMoving: true));

    // cancel token hookup (登録時点で既に cancelled の場合は flag を立てる)。
    StreamSubscription<void>? cancelSub;
    if (cancel != null) {
      if (cancel.isCancelled) {
        active.cancelled = true;
      } else {
        cancelSub = cancel.whenCancelled.asStream().listen((_) {
          active.cancelled = true;
        });
      }
    }

    final stamp = DateTime.now();
    try {
      final speeds = _resolveSpeeds(spec, clamped);

      _safeAdd(
        _moveCtl,
        MoveEvent(
          phase: MovePhase.start,
          target: clamped,
          timestamp: stamp,
        ),
      );

      if (active.cancelled) {
        return _completeCancelled(active, clamped);
      }

      await _writeMoveSequence(clamped, speeds.$1, speeds.$2);

      _safeAdd(
        _moveCtl,
        MoveEvent(
          phase: MovePhase.commanded,
          target: clamped,
          timestamp: DateTime.now(),
        ),
      );

      if (active.cancelled) {
        return _completeCancelled(active, clamped);
      }

      // settle wait (cancellable + timeout-aware)。
      final actual = await _settleLoop(clamped, settle, active);
      if (active.cancelled) {
        return _completeCancelled(active, clamped);
      }

      _safeAdd(
        _moveCtl,
        MoveEvent(
          phase: MovePhase.settled,
          target: clamped,
          actual: actual,
          timestamp: DateTime.now(),
        ),
      );
      final result = MoveResultSettled(target: clamped, actual: actual);
      if (!active.completer.isCompleted) {
        active.completer.complete(result);
      }
      return result;
    } catch (e) {
      if (e is KubiBleError) _setLastError(e);
      if (!active.completer.isCompleted) {
        active.completer.completeError(e);
      }
      rethrow;
    } finally {
      await cancelSub?.cancel();
      if (identical(_activeMove, active)) _activeMove = null;
      _updateState((s) => s.copyWith(isMoving: _activeMove != null));
    }
  }

  @override
  void setDefaultSpeed(MoveSpeed speed) {
    _defaultSpeed = speed;
  }

  @override
  MoveSpeed get defaultSpeed => _defaultSpeed;

  @override
  Future<PanTiltAngles> getCommandedPosition() async {
    final pan = await _readRegister(1, proto.regGoalPosition, 2);
    final tilt = await _readRegister(2, proto.regGoalPosition, 2);
    final angles = PanTiltAngles(
      pan: proto.valToAngle(pan),
      tilt: proto.valToAngle(tilt),
    );
    _updateState((s) => s.copyWith(commanded: angles));
    return angles;
  }

  @override
  Future<PanTiltAngles> getActualPosition() async {
    final pan = await _readRegister(1, proto.regPresentPosition, 2);
    final tilt = await _readRegister(2, proto.regPresentPosition, 2);
    final angles = PanTiltAngles(
      pan: proto.valToAngle(pan),
      tilt: proto.valToAngle(tilt),
    );
    _updateState((s) => s.copyWith(actual: angles));
    return angles;
  }

  @override
  Future<MoveResultSettled> waitUntilSettled({
    required PanTiltAngles target,
    SettleOptions options = const SettleOptions(),
    CancelToken? cancel,
  }) async {
    _requireConnected();
    final clamped = proto.clampPanTilt(target.pan, target.tilt);
    final tPan = proto.servoAngle(clamped.pan);
    final tTilt = proto.servoAngle(clamped.tilt);
    final sw = Stopwatch()..start();
    PanTiltAngles? lastObserved;
    while (true) {
      if (cancel != null && cancel.isCancelled) {
        throw const BleUserCancelledError('waitUntilSettled cancelled');
      }
      if (sw.elapsedMilliseconds > options.timeoutMs) {
        throw BleSettleTimeoutError(
          target: clamped,
          lastObserved: lastObserved,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }
      final actual = await getActualPosition();
      lastObserved = actual;
      final dPan = (proto.servoAngle(actual.pan) - tPan).abs();
      final dTilt = (proto.servoAngle(actual.tilt) - tTilt).abs();
      if (dPan <= options.toleranceLsb && dTilt <= options.toleranceLsb) {
        return MoveResultSettled(target: clamped, actual: actual);
      }
      await Future.any<void>([
        Future<void>.delayed(Duration(milliseconds: options.pollIntervalMs)),
        if (cancel != null) cancel.whenCancelled,
      ]);
    }
  }

  @override
  Stream<PositionSnapshot> subscribePosition([
    SubscribePositionOptions options = const SubscribePositionOptions(),
  ]) {
    final intervalMs = options.intervalMs < proto.subscribeMinIntervalMs
        ? proto.subscribeMinIntervalMs
        : options.intervalMs;
    final source = options.source;
    late StreamController<PositionSnapshot> ctl;
    Timer? timer;
    var busy = false;

    Future<void> tick() async {
      if (ctl.isClosed) return;
      final connected = _device != null &&
          _connectionState == BleConnectionState.connected;
      // GATT lock 取れない時は skip (§5.6 / B17)。
      if (!connected || busy || _pendingRead != null) {
        _emitDebug(
          BleDebugEventType.pollSkipped,
          detail: <String, Object?>{
            'reason': !connected
                ? 'disconnected'
                : busy
                    ? 'tick busy'
                    : 'register read in flight',
          },
        );
        if (!ctl.isClosed) {
          timer = Timer(Duration(milliseconds: intervalMs), tick);
        }
        return;
      }
      busy = true;
      try {
        final ts = DateTime.now();
        final isMoving = _activeMove != null &&
            !_activeMove!.completer.isCompleted;
        PositionSnapshot snap;
        switch (source) {
          case PositionSource.commanded:
            final c = await getCommandedPosition();
            snap = PositionSnapshot(
              timestamp: ts,
              isMoving: isMoving,
              commanded: c,
            );
          case PositionSource.actual:
            final a = await getActualPosition();
            snap = PositionSnapshot(
              timestamp: ts,
              isMoving: isMoving,
              actual: a,
            );
          case PositionSource.both:
            final c = await getCommandedPosition();
            final a = await getActualPosition();
            snap = PositionSnapshot(
              timestamp: ts,
              isMoving: isMoving,
              commanded: c,
              actual: a,
            );
        }
        _safeAdd(ctl, snap);
      } on Object catch (e) {
        _emitDebug(
          BleDebugEventType.listenerError,
          message: 'subscribePosition tick error: $e',
        );
      } finally {
        busy = false;
        if (!ctl.isClosed) {
          timer = Timer(Duration(milliseconds: intervalMs), tick);
        }
      }
    }

    ctl = StreamController<PositionSnapshot>.broadcast(
      onListen: () {
        // 即時 1 回目を起動 (TS と整合)。
        tick();
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
        ctl.close();
      },
    );
    return ctl.stream;
  }

  @override
  Stream<MoveEvent> get onMove => _moveCtl.stream;

  @override
  Stream<BleDebugEvent> get onDebugEvent => _debugCtl.stream;

  @override
  ValueListenable<KubiState> get state => _state;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _availabilitySub?.cancel();
    await _notifySub?.cancel();
    _failPendingRead('disposed');
    _cancelActiveMove('disposed');
    _cancelReconnectSchedule();
    await _connectionStateCtl.close();
    await _availabilityCtl.close();
    await _moveCtl.close();
    await _debugCtl.close();
    _state.dispose();
  }

  // ---------------------------------------------------------------------------
  // 内部 helper (Phase 3 後続 todo で実装が肉付けされる)
  // ---------------------------------------------------------------------------

  void _wireGlobalCallbacks() {
    ub.UniversalBle.onConnectionChange =
        (String deviceId, bool isConnected, String? error) {
      // 自分の管理デバイス以外は無視 (他コンシューマ共存対応)。
      if (_device == null || deviceId != _device!.id) return;
      if (isConnected) {
        // 通常の connect ルートで状態遷移は行うため、ここでは debug emit のみ。
        _emitDebug(
          BleDebugEventType.connectionStateChange,
          message: 'onConnectionChange: connected',
          detail: {'deviceId': deviceId},
        );
        return;
      }
      // 切断検知。
      if (_explicitDisconnectInProgress) {
        // disconnect() ルートで処理済 (or 処理中) のため、二重 emit しない。
        return;
      }
      final reason = error != null
          ? DisconnectReason.error
          : DisconnectReason.deviceLost;
      final lostDevice = _device;
      _device = null;
      _failPendingRead('disconnected (callback)');
      _cancelActiveMove('disconnected (callback)');
      _lastCommanded = null;
      _setConnectionState(BleConnectionState.disconnected, reason: reason);
      if (error != null) {
        _emitDebug(
          BleDebugEventType.connectionStateChange,
          message: 'unexpected disconnect: $error',
          detail: {'deviceId': deviceId, 'error': error},
        );
      }
      // p3-auto-reconnect: 自然切断で auto-reconnect 設定があれば schedule。
      if (lostDevice != null) {
        _scheduleAutoReconnect(lostDevice);
      }
    };
  }

  /// `_connectionState` を更新し、`connectionStateStream` と `KubiState` に反映する。
  void _setConnectionState(
    BleConnectionState next, {
    DisconnectReason? reason,
  }) {
    if (_disposed) return;
    if (_connectionState == next) return;
    _connectionState = next;
    final event = ConnectionStateEvent(
      state: next,
      reason: reason,
      timestamp: DateTime.now(),
    );
    _safeAdd(_connectionStateCtl, event);
    _updateState(
      (s) => s.copyWith(
        connectionState: next,
        clearLastError: next == BleConnectionState.connected,
      ),
    );
    _emitDebug(
      BleDebugEventType.connectionStateChange,
      message: 'state=$next reason=$reason',
    );
  }

  void _handleAvailability(ub.AvailabilityState raw) {
    final mapped = _mapAvailability(raw);
    _safeAdd(_availabilityCtl, mapped);
    // D4: 接続中に adapter が使えなくなったら強制 disconnect + deviceLost emit。
    final isLost = mapped == BleAvailability.poweredOff ||
        mapped == BleAvailability.unauthorized ||
        mapped == BleAvailability.resetting;
    final isConnectedOrConnecting =
        _connectionState == BleConnectionState.connected ||
            _connectionState == BleConnectionState.connecting;
    if (isLost && isConnectedOrConnecting && _device != null) {
      final dev = _device!;
      _device = null;
      _failPendingRead('availability lost');
      _cancelActiveMove('availability lost');
      _lastCommanded = null;
      _setConnectionState(
        BleConnectionState.disconnected,
        reason: DisconnectReason.deviceLost,
      );
      // best-effort で stack 側にも切断指示 (失敗は握り潰す)。
      // ignore: unawaited_futures
      ub.UniversalBle.disconnect(dev.id).catchError((Object _) {});
      // p3-auto-reconnect (D4): adapter lost で reschedule。
      _scheduleAutoReconnect(dev);
    }
    // D4: unsupported / unauthorized は永続的に再接続不能 → 既存 schedule を abandon。
    if (mapped == BleAvailability.unsupported ||
        mapped == BleAvailability.unauthorized) {
      _abandonAutoReconnect(reason: 'availability=$mapped');
    }
  }

  // ignore: unused_element
  BleAvailability _mapAvailability(ub.AvailabilityState s) {
    switch (s) {
      case ub.AvailabilityState.unknown:
        return BleAvailability.unknown;
      case ub.AvailabilityState.resetting:
        return BleAvailability.resetting;
      case ub.AvailabilityState.unsupported:
        return BleAvailability.unsupported;
      case ub.AvailabilityState.unauthorized:
        return BleAvailability.unauthorized;
      case ub.AvailabilityState.poweredOff:
        return BleAvailability.poweredOff;
      case ub.AvailabilityState.poweredOn:
        return BleAvailability.poweredOn;
    }
  }

  /// listener throw を `BleDebugEventType.listenerError` に隔離する (C9)。
  void _safeAdd<T>(StreamController<T> ctl, T value) {
    if (ctl.isClosed) return;
    try {
      ctl.add(value);
    } on Object catch (e, st) {
      _emitDebug(
        BleDebugEventType.listenerError,
        message: 'listener throw on ${T.toString()}: $e',
        detail: <String, Object?>{'stack': st.toString()},
      );
    }
  }

  void _emitDebug(
    BleDebugEventType type, {
    String? characteristic,
    String? message,
    Map<String, Object?>? detail,
  }) {
    if (_debugCtl.isClosed) return;
    final event = BleDebugEvent(
      type: type,
      timestamp: DateTime.now(),
      characteristic: characteristic,
      message: message,
      detail: detail,
    );
    try {
      _debugCtl.add(event);
    } on Object catch (_) {
      // listenerError 自身でループしないよう、ここでは握り潰す。
    }
  }

  /// `KubiState` を copyWith で更新 (C5/E7、後続 todo で各 stream listener から呼ぶ)。
  void _updateState(
    KubiState Function(KubiState current) update,
  ) {
    if (_disposed) return;
    final next = update(_state.value);
    if (next != _state.value) _state.value = next;
  }

  /// `KubiState.lastError` を更新するヘルパー。connect 成功で `_setConnectionState`
  /// 側が `clearLastError: true` で消す。
  void _setLastError(KubiBleError err) {
    _updateState((s) => s.copyWith(lastError: err));
  }

  // 「未接続なら throw」共通ガード。
  void _requireConnected() {
    if (_device == null ||
        _connectionState != BleConnectionState.connected) {
      throw const BleNotConnectedError('Not connected to a Kubi device');
    }
  }

  // ===================================================================
  // register read (1:1 照合) — p3-protocol-rw
  // ===================================================================

  /// register read を直列実行する。
  ///
  /// `[motorId, addr]` を `regRead{1,2}ByteUuid` に write し、
  /// `motorPositionUuid` notify から `[motorId, addr, ...payload]` の応答を
  /// 待って payload を `parseRegisterReadResponse` で復号する。
  ///
  /// - timeout: `proto.readRegisterDefaultTimeoutMs`
  /// - 応答 header (motorId/addr) 不一致は無視 (他コマンドの応答を素通り)
  /// - 不正長 payload は `BleProtocolError`
  /// - timeout は `BleRegisterReadTimeoutError`
  Future<int> _readRegister(int motorId, int addr, int byteWidth) async {
    _requireConnected();
    assert(motorId == 1 || motorId == 2);
    assert(byteWidth == 1 || byteWidth == 2);

    final prev = _readChain;
    final completer = Completer<int>();
    _readChain = completer.future
        .then<void>((_) {})
        .catchError((Object _) {});
    try {
      await prev;
    } on Object catch (_) {/* swallow upstream */}

    if (_device == null ||
        _connectionState != BleConnectionState.connected) {
      final err = const BleNotConnectedError('Not connected to a Kubi device');
      completer.completeError(err);
      throw err;
    }

    final notifyCompleter = Completer<Uint8List>();
    _pendingRead = notifyCompleter;
    _pendingMotorId = motorId;
    _pendingAddr = addr;

    final sw = Stopwatch()..start();
    final cmd = proto.encodeRegisterReadCmd(motorId, addr);
    final readUuid =
        byteWidth == 2 ? proto.regRead2ByteUuid : proto.regRead1ByteUuid;

    try {
      try {
        await ub.UniversalBle.write(
          _device!.id,
          proto.servoServiceUuid,
          readUuid,
          cmd,
        );
      } on Object catch (e) {
        _clearPending();
        final err = BleProtocolError('register read write failed: $e');
        completer.completeError(err);
        throw err;
      }

      Uint8List bytes;
      try {
        bytes = await notifyCompleter.future.timeout(
          Duration(milliseconds: proto.readRegisterDefaultTimeoutMs),
        );
      } on TimeoutException {
        _clearPending();
        _emitDebug(
          BleDebugEventType.registerReadTimeout,
          characteristic: proto.motorPositionUuid,
          detail: <String, Object?>{
            'motorId': motorId,
            'addr': addr,
            'elapsedMs': sw.elapsedMilliseconds,
          },
        );
        final err = BleRegisterReadTimeoutError(
          motorId: motorId,
          addr: addr,
          elapsedMs: sw.elapsedMilliseconds,
        );
        completer.completeError(err);
        throw err;
      }
      _clearPending();

      // header (motorId/addr) は _handleNotification 側で照合済 (matched 時のみ
      // complete されるため、ここで再 check する必要はないが念のため defensive)。
      if (bytes.length < 2 + byteWidth ||
          bytes[0] != motorId ||
          bytes[1] != addr) {
        final err = BleProtocolError(
          'register read response malformed '
          '(motorId=$motorId, addr=$addr, bytes=${bytes.length})',
        );
        completer.completeError(err);
        throw err;
      }
      final value = proto.parseRegisterReadResponse(
        bytes.sublist(2),
        byteWidth,
      );
      if (value == null) {
        final err = BleProtocolError(
          'register read parse failed (byteWidth=$byteWidth, '
          'len=${bytes.length - 2})',
        );
        completer.completeError(err);
        throw err;
      }
      _emitDebug(
        BleDebugEventType.registerRead,
        characteristic: proto.motorPositionUuid,
        detail: <String, Object?>{
          'motorId': motorId,
          'addr': addr,
          'byteWidth': byteWidth,
          'value': value,
          'elapsedMs': sw.elapsedMilliseconds,
        },
      );
      completer.complete(value);
      return value;
    } catch (_) {
      // completer は既に completeError 済 (上で throw した場合)。
      rethrow;
    }
  }

  void _clearPending() {
    _pendingRead = null;
    _pendingMotorId = null;
    _pendingAddr = null;
  }

  void _failPendingRead(String reason) {
    final p = _pendingRead;
    if (p != null && !p.isCompleted) {
      p.completeError(BleProtocolError('pending read aborted: $reason'));
    }
    _clearPending();
  }

  void _handleNotification(Uint8List bytes) {
    _emitDebug(
      BleDebugEventType.notificationRaw,
      characteristic: proto.motorPositionUuid,
      detail: <String, Object?>{'len': bytes.length},
    );
    final pending = _pendingRead;
    final motorId = _pendingMotorId;
    final addr = _pendingAddr;
    if (pending == null || pending.isCompleted) return;
    if (bytes.length < 2 || bytes[0] != motorId || bytes[1] != addr) {
      // 別コマンドの応答 or 自発 notify。無視。
      return;
    }
    pending.complete(bytes);
  }

  // ===================================================================
  // auto-reconnect — p3-auto-reconnect
  // ===================================================================

  /// 自然切断 (deviceLost / error) 後に呼ばれる。
  /// `_autoReconnect == null` なら no-op。`maxRetries` 超で abandon。
  void _scheduleAutoReconnect(KubiDevice device) {
    final cfg = _autoReconnect;
    if (cfg == null) return;
    if (_explicitDisconnectInProgress) return;
    if (_disposed) return;
    if (_reconnectAttempt >= cfg.maxRetries) {
      _abandonAutoReconnect(reason: 'maxRetries reached');
      return;
    }
    _reconnectAttempt += 1;
    final attempt = _reconnectAttempt;
    final delay = cfg.retryDelay * attempt;
    _emitDebug(
      BleDebugEventType.autoReconnectScheduled,
      detail: <String, Object?>{
        'attempt': attempt,
        'maxRetries': cfg.maxRetries,
        'delayMs': delay.inMilliseconds,
      },
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _runReconnectAttempt(device));
  }

  Future<void> _runReconnectAttempt(KubiDevice device) async {
    if (_disposed) return;
    if (_explicitDisconnectInProgress) return;
    if (_autoReconnect == null) return;
    final attempt = _reconnectAttempt;
    _emitDebug(
      BleDebugEventType.autoReconnectAttempt,
      detail: <String, Object?>{'attempt': attempt},
    );
    try {
      await connect(device);
      // connect() 成功側で _reconnectAttempt = 0 に reset 済 + timer cancel。
      _emitDebug(
        BleDebugEventType.autoReconnectSuccess,
        detail: <String, Object?>{'attempt': attempt},
      );
    } on Object catch (e) {
      _emitDebug(
        BleDebugEventType.autoReconnectFailed,
        message: '$e',
        detail: <String, Object?>{'attempt': attempt},
      );
      // 次 attempt を schedule (maxRetries 内なら線形に伸びる)。
      _scheduleAutoReconnect(device);
    }
  }

  /// 進行中の schedule を破棄するだけ (counter は触らない)。
  /// `disconnect()` (user intent) の冒頭で呼ぶ。
  void _cancelReconnectSchedule() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
  }

  /// `autoReconnectAbandoned` を emit + `reconnectExhausted` で disconnected を再 emit。
  void _abandonAutoReconnect({required String reason}) {
    final hadPending = _reconnectTimer != null || _reconnectAttempt > 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final attempts = _reconnectAttempt;
    _reconnectAttempt = 0;
    if (!hadPending && _autoReconnect == null) return;
    _emitDebug(
      BleDebugEventType.autoReconnectAbandoned,
      message: reason,
      detail: <String, Object?>{'attempts': attempts},
    );
    // disconnected 状態の場合のみ reconnectExhausted を emit (二重 emit 抑止)。
    if (_connectionState == BleConnectionState.disconnected) {
      // 既に disconnected で _setConnectionState の equality guard に弾かれるため、
      // ConnectionStateEvent を直接 _safeAdd する。
      _safeAdd(
        _connectionStateCtl,
        ConnectionStateEvent(
          state: BleConnectionState.disconnected,
          reason: DisconnectReason.reconnectExhausted,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  // ===================================================================
  // moveTo / setTarget — p3-moveto
  // ===================================================================

  /// 進行中 `moveTo` を「cancelled」に確定させて完了する (cancel-on-newer)。
  ///
  /// 既に完了済 / 未走の場合は no-op。`MoveEvent.cancelled` も emit する。
  void _cancelActiveMove(String reason) {
    final prev = _activeMove;
    if (prev == null) return;
    if (prev.completer.isCompleted) return;
    prev.cancelled = true;
    _safeAdd(
      _moveCtl,
      MoveEvent(
        phase: MovePhase.cancelled,
        target: prev.target,
        timestamp: DateTime.now(),
      ),
    );
    prev.completer.complete(MoveResultCancelled(target: prev.target));
  }

  /// `moveTo` 内部で、cancel 検知後に Cancelled で完結させる定型処理。
  MoveResult _completeCancelled(_ActiveMove active, PanTiltAngles target) {
    _safeAdd(
      _moveCtl,
      MoveEvent(
        phase: MovePhase.cancelled,
        target: target,
        timestamp: DateTime.now(),
      ),
    );
    final result = MoveResultCancelled(target: target);
    if (!active.completer.isCompleted) {
      active.completer.complete(result);
    }
    return result;
  }

  /// `MoveSpec` から (panSpeed, tiltSpeed) を解決する。
  ///
  /// - `independent`: `speed` (uniform/perAxis) → そのまま、null → `_defaultSpeed`
  /// - `synced`: TS `_resolveSpeeds` (web-kubi-ble.ts §_resolveSpeeds、issue #12)
  ///   と完全一致。`_lastCommanded` (前 commanded) との arc 比で tilt 速度を逆算する:
  ///     1. prev == null → both = maxSpeed
  ///     2. panArc == 0 || tiltArc == 0 → both = maxSpeed (片軸動き)
  ///     3. それ以外: panTime = panArc / panVelocity(maxSpeed)、
  ///        requiredTiltVel = tiltArc / panTime、
  ///        tiltSpeed = tiltSpeedFromVelocity(requiredTiltVel) を [1,100] でクランプ
  (int, int) _resolveSpeeds(MoveSpec spec, PanTiltAngles target) {
    switch (spec) {
      case MoveSpecIndependent(:final speed):
        final s = speed ?? _defaultSpeed;
        switch (s) {
          case MoveSpeedUniform(:final speed):
            final c = proto.clampSpeed(speed);
            return (c, c);
          case MoveSpeedPerAxis(:final pan, :final tilt):
            return (proto.clampSpeed(pan), proto.clampSpeed(tilt));
        }
      case MoveSpecSynced(:final maxSpeed):
        final base = proto.clampSpeed(maxSpeed);
        final prev = _lastCommanded;
        if (prev == null) return (base, base);
        final panArc = (target.pan - prev.pan).abs();
        final tiltArc = (target.tilt - prev.tilt).abs();
        if (panArc == 0 || tiltArc == 0) return (base, base);
        final panTime = panArc / proto.panVelocity(base);
        final requiredTiltVel = tiltArc / panTime;
        var tiltSpeed = proto.tiltSpeedFromVelocity(requiredTiltVel);
        if (tiltSpeed < proto.minMoveSpeed) tiltSpeed = proto.minMoveSpeed;
        if (tiltSpeed > proto.maxMoveSpeed) tiltSpeed = proto.maxMoveSpeed;
        return (base, tiltSpeed);
    }
  }

  /// `panTiltConfigUuid` に tilt/pan 個別 speed を書き、`panUuid` / `tiltUuid` に
  /// それぞれの目標 servo 値 (BE 2 byte) を書く。TS `_writeMoveSequence` と完全一致。
  ///
  /// 失敗時は `BleNotConnectedError` か `BleProtocolError` を throw する。
  Future<void> _writeMoveSequence(
    PanTiltAngles target,
    int panSpeed,
    int tiltSpeed,
  ) async {
    if (_device == null ||
        _connectionState != BleConnectionState.connected) {
      throw const BleNotConnectedError('Not connected to a Kubi device');
    }
    final deviceId = _device!.id;
    final panVal = proto.servoAngle(target.pan);
    final tiltVal = proto.servoAngle(target.tilt);
    try {
      // tilt config (motorId=2)
      await ub.UniversalBle.write(
        deviceId,
        proto.servoServiceUuid,
        proto.panTiltConfigUuid,
        proto.buildAxisConfigPayload(
          axisFlag: 0x02,
          servoFlag: proto.defaultServoFlag,
          axisSpeed: tiltSpeed,
        ),
      );
      // pan config (motorId=1)
      await ub.UniversalBle.write(
        deviceId,
        proto.servoServiceUuid,
        proto.panTiltConfigUuid,
        proto.buildAxisConfigPayload(
          axisFlag: 0x01,
          servoFlag: proto.defaultServoFlag,
          axisSpeed: panSpeed,
        ),
      );
      // pan target
      await ub.UniversalBle.write(
        deviceId,
        proto.servoServiceUuid,
        proto.panUuid,
        proto.buildAxisPayload(panVal),
      );
      // tilt target
      await ub.UniversalBle.write(
        deviceId,
        proto.servoServiceUuid,
        proto.tiltUuid,
        proto.buildAxisPayload(tiltVal),
      );
      _lastCommanded = target;
      _updateState((s) => s.copyWith(commanded: target));
    } on Object catch (e) {
      if (_device == null ||
          _connectionState != BleConnectionState.connected) {
        final err = const BleNotConnectedError('Disconnected during write');
        _setLastError(err);
        throw err;
      }
      final err = BleProtocolError('moveTo write failed: $e');
      _setLastError(err);
      throw err;
    }
  }

  /// settle 検出ループ。tolerance 内に収束したら actual を返す。
  ///
  /// - `active.cancelled` が true になったら現在値を返して呼び出し側に委ねる。
  /// - `options.timeoutMs` 超過で `BleSettleTimeoutError` を throw。
  Future<PanTiltAngles> _settleLoop(
    PanTiltAngles target,
    SettleOptions options,
    _ActiveMove active,
  ) async {
    final tPan = proto.servoAngle(target.pan);
    final tTilt = proto.servoAngle(target.tilt);
    final sw = Stopwatch()..start();
    PanTiltAngles? lastObserved;
    while (true) {
      if (active.cancelled) return lastObserved ?? target;
      if (sw.elapsedMilliseconds > options.timeoutMs) {
        throw BleSettleTimeoutError(
          target: target,
          lastObserved: lastObserved,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }
      final actual = await getActualPosition();
      lastObserved = actual;
      final dPan = (proto.servoAngle(actual.pan) - tPan).abs();
      final dTilt = (proto.servoAngle(actual.tilt) - tTilt).abs();
      if (dPan <= options.toleranceLsb && dTilt <= options.toleranceLsb) {
        return actual;
      }
      await Future.any<void>([
        Future<void>.delayed(Duration(milliseconds: options.pollIntervalMs)),
        if (active.cancelToken != null) active.cancelToken!.whenCancelled,
      ]);
    }
  }
}

/// 進行中の `moveTo` の状態 (cancel-on-newer / cancel token を一括管理)。
final class _ActiveMove {
  final PanTiltAngles target;
  final CancelToken? cancelToken;
  final Completer<MoveResult> completer = Completer<MoveResult>();
  bool cancelled = false;

  _ActiveMove({required this.target, this.cancelToken});
}
