// ignore_for_file: avoid_print
//
// kubi_flutter_ble の **検証用 example アプリ**。
//
// 設計方針:
// - 1 画面に全 API を露出 (スクロールで完結、状態を同時観測)
// - 各機能はセクション (ExpansionTile) で折りたたみ可能
// - 実機検証用: docs/platform-notes.md のチェックリストを 1 アプリで踏める
//
// 公開 API のうちカバーしている項目:
//   接続: scan / requestDevice / connect / disconnect /
//         setAutoReconnect / tryAutoConnect /
//         connectionStateStream / currentConnectionState / availabilityStream
//   動作: setTarget / moveTo (+ CancelToken) / setDefaultSpeed / defaultSpeed
//   観測: getCommandedPosition / getActualPosition / waitUntilSettled /
//         subscribePosition
//   イベント: onMove / onDebugEvent / state (ValueListenable<KubiState>)
//   ライフサイクル: dispose

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kubi_flutter_ble/kubi_flutter_ble.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'kubi_flutter_ble example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ===========================================================================
// HomePage: 状態保持 + ストリーム購読 + 全セクション orchestration
// ===========================================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---- BLE インスタンス ----
  final KubiBle _kubi = KubiBleImpl();

  // ---- Subscriptions ----
  StreamSubscription<KubiDevice>? _scanSub;
  StreamSubscription<PositionSnapshot>? _posSub;
  StreamSubscription<ConnectionStateEvent>? _connSub;
  StreamSubscription<BleAvailability>? _availSub;
  StreamSubscription<MoveEvent>? _moveSub;
  StreamSubscription<BleDebugEvent>? _debugSub;

  // ---- Scan 結果 ----
  final List<KubiDevice> _devices = <KubiDevice>[];
  bool _scanning = false;

  // ---- Availability 直近値 ----
  BleAvailability _availability = BleAvailability.unknown;

  // ---- Auto-reconnect 設定 UI ----
  bool _autoReconnectEnabled = false;
  int _maxRetries = 3;
  int _retryDelayMs = 1500;

  // ---- Control: setTarget ----
  double _targetPan = 0;
  double _targetTilt = 0;
  bool _liveMode = false; // true なら slider 変更時に setTarget を呼ぶ

  // ---- Control: moveTo ----
  double _movePan = 0;
  double _moveTilt = 0;
  _MoveSpecKind _moveSpecKind = _MoveSpecKind.independentUniform;
  int _uniformSpeed = 60;
  int _panSpeed = 60;
  int _tiltSpeed = 60;
  int _syncedMaxSpeed = 60;
  CancelToken? _moveCancel;
  String? _lastMoveResult;

  // ---- Default speed ----
  int _defaultSpeedValue = 100;

  // ---- Observation ----
  PanTiltAngles? _commandedReadout;
  PanTiltAngles? _actualReadout;
  bool _subscribing = false;
  int _subscribeIntervalMs = 200;
  PositionSource _subscribeSource = PositionSource.both;
  PositionSnapshot? _latestSnapshot;

  // ---- waitUntilSettled (standalone) ----
  String? _lastSettleResult;
  CancelToken? _settleCancel;

  // ---- Events log ----
  final List<_LogEntry> _events = <_LogEntry>[];
  bool _showConnection = true;
  bool _showMove = true;
  bool _showDebug = true;
  final Set<BleDebugEventType> _enabledDebugTypes =
      Set<BleDebugEventType>.from(BleDebugEventType.values);

  static const int _maxLogEntries = 200;

  // ---- KubiState はパッケージの ValueListenable を直接 build で読む ----

  @override
  void initState() {
    super.initState();
    _connSub = _kubi.connectionStateStream.listen((e) {
      _addLog(_LogKind.connection,
          'state=${e.state.name} reason=${e.reason?.name ?? '-'}');
    });
    _availSub = _kubi.availabilityStream.listen((v) {
      setState(() => _availability = v);
      _addLog(_LogKind.connection, 'availability=${v.name}');
    });
    _moveSub = _kubi.onMove.listen((e) {
      _addLog(_LogKind.move,
          'phase=${e.phase.name} target=${_fmt(e.target)} actual=${_fmt(e.actual)}');
    });
    _debugSub = _kubi.onDebugEvent.listen((e) {
      if (!_enabledDebugTypes.contains(e.type)) return;
      _addLog(_LogKind.debug,
          '${e.type.name} ${e.message ?? ''} ${e.hex != null ? '[${e.hex}]' : ''}');
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _posSub?.cancel();
    _connSub?.cancel();
    _availSub?.cancel();
    _moveSub?.cancel();
    _debugSub?.cancel();
    _kubi.dispose();
    super.dispose();
  }

  // -------------------- helpers --------------------

  void _addLog(_LogKind kind, String msg) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, _LogEntry(DateTime.now(), kind, msg));
      if (_events.length > _maxLogEntries) {
        _events.removeRange(_maxLogEntries, _events.length);
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(PanTiltAngles? a) =>
      a == null ? '-' : '(${a.pan.toStringAsFixed(1)}, ${a.tilt.toStringAsFixed(1)})';

  // -------------------- 接続系アクション --------------------

  Future<void> _startScan() async {
    await _scanSub?.cancel();
    setState(() {
      _devices.clear();
      _scanning = true;
    });
    _addLog(_LogKind.connection, 'scan start');
    _scanSub = _kubi.scan(timeout: const Duration(seconds: 10)).listen(
      (d) => setState(() => _devices.add(d)),
      onError: (Object e) {
        _addLog(_LogKind.connection, 'scan error: $e');
        setState(() => _scanning = false);
      },
      onDone: () {
        _addLog(_LogKind.connection, 'scan done (${_devices.length} found)');
        setState(() => _scanning = false);
      },
    );
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    setState(() => _scanning = false);
  }

  Future<void> _requestDevice() async {
    setState(() => _scanning = true);
    try {
      final d = await _kubi.requestDevice(
        timeout: const Duration(seconds: 5),
      );
      setState(() {
        if (!_devices.any((e) => e.id == d.id)) _devices.add(d);
      });
      _addLog(_LogKind.connection, 'requestDevice -> ${d.name ?? d.id}');
    } on KubiBleError catch (e) {
      _addLog(_LogKind.connection, 'requestDevice failed: $e');
    } on TimeoutException catch (e) {
      _addLog(_LogKind.connection, 'requestDevice timeout: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(KubiDevice d) async {
    try {
      _addLog(_LogKind.connection, 'connect -> ${d.name ?? d.id}');
      await _kubi.connect(d);
    } on KubiBleError catch (e) {
      _addLog(_LogKind.connection, 'connect failed: $e');
      _toast('connect failed: $e');
    }
  }

  Future<void> _disconnect() async {
    await _stopSubscribe();
    try {
      await _kubi.disconnect();
    } on KubiBleError catch (e) {
      _addLog(_LogKind.connection, 'disconnect error: $e');
    }
  }

  void _applyAutoReconnect() {
    if (_autoReconnectEnabled) {
      _kubi.setAutoReconnect(
        AutoReconnectConfig(
          maxRetries: _maxRetries,
          retryDelay: Duration(milliseconds: _retryDelayMs),
        ),
      );
      _addLog(_LogKind.connection,
          'auto-reconnect on (max=$_maxRetries, delay=${_retryDelayMs}ms)');
    } else {
      _kubi.setAutoReconnect(null);
      _addLog(_LogKind.connection, 'auto-reconnect off');
    }
  }

  Future<void> _tryAutoConnect() async {
    try {
      final d = await _kubi.tryAutoConnect();
      _addLog(_LogKind.connection, 'tryAutoConnect -> ${d?.name ?? d?.id ?? 'null'}');
      if (d != null) {
        setState(() {
          if (!_devices.any((e) => e.id == d.id)) _devices.add(d);
        });
      } else {
        _toast('no known device (Web は常に null)');
      }
    } on KubiBleError catch (e) {
      _addLog(_LogKind.connection, 'tryAutoConnect error: $e');
    }
  }

  // -------------------- 動作系 --------------------

  MoveSpeed _buildMoveSpeed() {
    switch (_moveSpecKind) {
      case _MoveSpecKind.independentUniform:
        return MoveSpeed.uniform(_uniformSpeed);
      case _MoveSpecKind.independentPerAxis:
        return MoveSpeed.perAxis(pan: _panSpeed, tilt: _tiltSpeed);
      case _MoveSpecKind.synced:
        return MoveSpeed.uniform(_uniformSpeed); // unused; synced path 別
    }
  }

  MoveSpec _buildMoveSpec() {
    switch (_moveSpecKind) {
      case _MoveSpecKind.independentUniform:
      case _MoveSpecKind.independentPerAxis:
        return MoveSpec.independent(speed: _buildMoveSpeed());
      case _MoveSpecKind.synced:
        return MoveSpec.synced(maxSpeed: _syncedMaxSpeed);
    }
  }

  Future<void> _doSetTarget() async {
    try {
      await _kubi.setTarget(
        target: PanTiltAngles(pan: _targetPan, tilt: _targetTilt),
        speed: _buildMoveSpeed(),
      );
    } on KubiBleError catch (e) {
      _addLog(_LogKind.move, 'setTarget error: $e');
    }
  }

  Future<void> _doMoveTo() async {
    final cancel = CancelToken();
    setState(() {
      _moveCancel = cancel;
      _lastMoveResult = null;
    });
    try {
      final r = await _kubi.moveTo(
        target: PanTiltAngles(pan: _movePan, tilt: _moveTilt),
        spec: _buildMoveSpec(),
        cancel: cancel,
      );
      final txt = switch (r) {
        MoveResultSettled(:final actual) => 'settled actual=${_fmt(actual)}',
        MoveResultCancelled() => 'cancelled',
      };
      _addLog(_LogKind.move, 'moveTo -> $txt');
      if (mounted) setState(() => _lastMoveResult = txt);
    } on KubiBleError catch (e) {
      _addLog(_LogKind.move, 'moveTo error: $e');
      if (mounted) setState(() => _lastMoveResult = 'error: $e');
    } finally {
      if (mounted && identical(_moveCancel, cancel)) {
        setState(() => _moveCancel = null);
      }
    }
  }

  void _cancelMove() {
    _moveCancel?.cancel();
    _addLog(_LogKind.move, 'moveTo cancel requested');
  }

  void _applyDefaultSpeed() {
    _kubi.setDefaultSpeed(MoveSpeed.uniform(_defaultSpeedValue));
    _addLog(_LogKind.move, 'setDefaultSpeed($_defaultSpeedValue)');
  }

  // -------------------- 観測系 --------------------

  Future<void> _refreshCommanded() async {
    try {
      final v = await _kubi.getCommandedPosition();
      setState(() => _commandedReadout = v);
    } on KubiBleError catch (e) {
      _addLog(_LogKind.move, 'getCommanded error: $e');
    }
  }

  Future<void> _refreshActual() async {
    try {
      final v = await _kubi.getActualPosition();
      setState(() => _actualReadout = v);
    } on KubiBleError catch (e) {
      _addLog(_LogKind.move, 'getActual error: $e');
    }
  }

  Future<void> _startSubscribe() async {
    await _posSub?.cancel();
    final stream = _kubi.subscribePosition(
      SubscribePositionOptions(
        intervalMs: _subscribeIntervalMs,
        source: _subscribeSource,
      ),
    );
    setState(() => _subscribing = true);
    _posSub = stream.listen(
      (s) => setState(() => _latestSnapshot = s),
      onError: (Object e) =>
          _addLog(_LogKind.move, 'subscribePosition error: $e'),
      onDone: () {
        if (mounted) setState(() => _subscribing = false);
      },
    );
  }

  Future<void> _stopSubscribe() async {
    await _posSub?.cancel();
    _posSub = null;
    if (mounted) setState(() => _subscribing = false);
  }

  Future<void> _doWaitUntilSettled() async {
    final cancel = CancelToken();
    setState(() {
      _settleCancel = cancel;
      _lastSettleResult = null;
    });
    try {
      final r = await _kubi.waitUntilSettled(
        target: PanTiltAngles(pan: _movePan, tilt: _moveTilt),
        cancel: cancel,
      );
      final txt = 'settled actual=${_fmt(r.actual)}';
      _addLog(_LogKind.move, 'waitUntilSettled -> $txt');
      if (mounted) setState(() => _lastSettleResult = txt);
    } on KubiBleError catch (e) {
      _addLog(_LogKind.move, 'waitUntilSettled error: $e');
      if (mounted) setState(() => _lastSettleResult = 'error: $e');
    } finally {
      if (mounted && identical(_settleCancel, cancel)) {
        setState(() => _settleCancel = null);
      }
    }
  }

  // -------------------- build --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('kubi_flutter_ble example'),
        actions: [
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => setState(_events.clear),
          ),
        ],
      ),
      body: ValueListenableBuilder<KubiState>(
        valueListenable: _kubi.state,
        builder: (ctx, state, _) {
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildStatusBar(state),
              _buildConnectionSection(state),
              _buildControlSection(state),
              _buildObservationSection(state),
              _buildStateSection(state),
              _buildEventsSection(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(KubiState state) {
    final color = switch (state.connectionState) {
      BleConnectionState.connected => Colors.green,
      BleConnectionState.connecting => Colors.orange,
      BleConnectionState.disconnecting => Colors.orange,
      BleConnectionState.disconnected => Colors.grey,
    };
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.circle, color: color, size: 14),
            const SizedBox(width: 8),
            Text(state.connectionState.name,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 16),
            Text('availability: ${_availability.name}'),
            const Spacer(),
            if (state.isMoving)
              const Chip(
                avatar: Icon(Icons.directions_run, size: 16),
                label: Text('moving'),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Section 1: Connection ----------

  Widget _buildConnectionSection(KubiState state) {
    final connected = state.connectionState == BleConnectionState.connected;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('📡 Connection'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: Text(_scanning ? 'Scanning…' : 'Scan'),
              onPressed: _scanning ? null : _startScan,
            ),
            OutlinedButton(
              onPressed: _scanning ? _stopScan : null,
              child: const Text('Stop scan'),
            ),
            OutlinedButton(
              onPressed: _scanning ? null : _requestDevice,
              child: const Text('requestDevice'),
            ),
            OutlinedButton(
              onPressed: _tryAutoConnect,
              child: const Text('tryAutoConnect'),
            ),
            FilledButton.tonal(
              onPressed: connected ? _disconnect : null,
              child: const Text('Disconnect'),
            ),
          ]),
          const SizedBox(height: 8),
          Text('currentConnectionState: ${_kubi.currentConnectionState.name}'),
          const Divider(),
          // Auto-reconnect
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-reconnect'),
            value: _autoReconnectEnabled,
            onChanged: (v) {
              setState(() => _autoReconnectEnabled = v);
              _applyAutoReconnect();
            },
          ),
          Row(children: [
            const Text('maxRetries: '),
            Expanded(
              child: Slider(
                value: _maxRetries.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: '$_maxRetries',
                onChanged: (v) => setState(() => _maxRetries = v.toInt()),
                onChangeEnd: (_) {
                  if (_autoReconnectEnabled) _applyAutoReconnect();
                },
              ),
            ),
            Text('$_maxRetries'),
          ]),
          Row(children: [
            const Text('retryDelay ms: '),
            Expanded(
              child: Slider(
                value: _retryDelayMs.toDouble(),
                min: 100,
                max: 5000,
                divisions: 49,
                label: '${_retryDelayMs}ms',
                onChanged: (v) => setState(() => _retryDelayMs = v.toInt()),
                onChangeEnd: (_) {
                  if (_autoReconnectEnabled) _applyAutoReconnect();
                },
              ),
            ),
            Text('${_retryDelayMs}ms'),
          ]),
          const Divider(),
          Text('Devices (${_devices.length})',
              style: Theme.of(context).textTheme.titleSmall),
          if (_devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('(none)', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._devices.map((d) => ListTile(
                  dense: true,
                  title: Text(d.name ?? '(unnamed)'),
                  subtitle: Text(d.id),
                  trailing: ElevatedButton(
                    onPressed: connected ? null : () => _connect(d),
                    child: const Text('connect'),
                  ),
                )),
        ],
      ),
    );
  }

  // ---------- Section 2: Control ----------

  Widget _buildControlSection(KubiState state) {
    final connected = state.connectionState == BleConnectionState.connected;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('🎮 Control'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          // --- setTarget ---
          Text('setTarget (fire-and-forget, latest-value buffered)',
              style: Theme.of(context).textTheme.titleSmall),
          _angleSlider('pan', _targetPan, -90, 90, (v) {
            setState(() => _targetPan = v);
          }, onChangeEnd: (_) {
            if (_liveMode && connected) _doSetTarget();
          }),
          _angleSlider('tilt', _targetTilt, -45, 45, (v) {
            setState(() => _targetTilt = v);
          }, onChangeEnd: (_) {
            if (_liveMode && connected) _doSetTarget();
          }),
          Row(children: [
            FilledButton(
              onPressed: connected ? _doSetTarget : null,
              child: const Text('setTarget'),
            ),
            const SizedBox(width: 16),
            Switch(
              value: _liveMode,
              onChanged: (v) => setState(() => _liveMode = v),
            ),
            const Text('Live (slider 操作中に setTarget を連射)'),
          ]),
          const Divider(),
          // --- moveTo ---
          Text('moveTo (await physical settle)',
              style: Theme.of(context).textTheme.titleSmall),
          _angleSlider('pan', _movePan, -90, 90,
              (v) => setState(() => _movePan = v)),
          _angleSlider('tilt', _moveTilt, -45, 45,
              (v) => setState(() => _moveTilt = v)),
          Wrap(spacing: 8, children: [
            for (final kind in _MoveSpecKind.values)
              ChoiceChip(
                label: Text(kind.label),
                selected: _moveSpecKind == kind,
                onSelected: (_) => setState(() => _moveSpecKind = kind),
              ),
          ]),
          if (_moveSpecKind == _MoveSpecKind.independentUniform)
            _intSlider('uniform speed', _uniformSpeed, 1, 100,
                (v) => setState(() => _uniformSpeed = v)),
          if (_moveSpecKind == _MoveSpecKind.independentPerAxis) ...[
            _intSlider('pan speed', _panSpeed, 1, 100,
                (v) => setState(() => _panSpeed = v)),
            _intSlider('tilt speed', _tiltSpeed, 1, 100,
                (v) => setState(() => _tiltSpeed = v)),
          ],
          if (_moveSpecKind == _MoveSpecKind.synced)
            _intSlider('synced maxSpeed', _syncedMaxSpeed, 1, 100,
                (v) => setState(() => _syncedMaxSpeed = v)),
          Row(children: [
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('moveTo'),
              onPressed: connected && _moveCancel == null ? _doMoveTo : null,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Cancel'),
              onPressed: _moveCancel != null ? _cancelMove : null,
            ),
          ]),
          if (_lastMoveResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('last result: $_lastMoveResult'),
            ),
          const Divider(),
          // --- default speed ---
          _intSlider('default speed', _defaultSpeedValue, 1, 100,
              (v) => setState(() => _defaultSpeedValue = v)),
          Row(children: [
            OutlinedButton(
              onPressed: _applyDefaultSpeed,
              child: const Text('setDefaultSpeed'),
            ),
            const SizedBox(width: 16),
            Text('current: ${_describeSpeed(_kubi.defaultSpeed)}'),
          ]),
        ],
      ),
    );
  }

  String _describeSpeed(MoveSpeed s) => switch (s) {
        MoveSpeedUniform(:final speed) => 'uniform($speed)',
        MoveSpeedPerAxis(:final pan, :final tilt) => 'perAxis($pan, $tilt)',
      };

  // ---------- Section 3: Observation ----------

  Widget _buildObservationSection(KubiState state) {
    final connected = state.connectionState == BleConnectionState.connected;
    return Card(
      child: ExpansionTile(
        title: const Text('👁 Observation'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(
              child: Text('commanded: ${_fmt(_commandedReadout)}'),
            ),
            OutlinedButton(
              onPressed: connected ? _refreshCommanded : null,
              child: const Text('getCommanded'),
            ),
          ]),
          Row(children: [
            Expanded(
              child: Text('actual: ${_fmt(_actualReadout)}'),
            ),
            OutlinedButton(
              onPressed: connected ? _refreshActual : null,
              child: const Text('getActual'),
            ),
          ]),
          const Divider(),
          Text('subscribePosition',
              style: Theme.of(context).textTheme.titleSmall),
          _intSlider(
            'intervalMs',
            _subscribeIntervalMs,
            50,
            1000,
            (v) => setState(() => _subscribeIntervalMs = v),
          ),
          Wrap(spacing: 8, children: [
            for (final s in PositionSource.values)
              ChoiceChip(
                label: Text(s.name),
                selected: _subscribeSource == s,
                onSelected: (_) => setState(() => _subscribeSource = s),
              ),
          ]),
          Row(children: [
            FilledButton(
              onPressed: connected && !_subscribing ? _startSubscribe : null,
              child: const Text('start'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _subscribing ? _stopSubscribe : null,
              child: const Text('stop'),
            ),
          ]),
          if (_latestSnapshot != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'latest: cmd=${_fmt(_latestSnapshot!.commanded)} '
                'act=${_fmt(_latestSnapshot!.actual)} '
                'moving=${_latestSnapshot!.isMoving}',
              ),
            ),
          const Divider(),
          Text('waitUntilSettled (standalone, target = moveTo の値)',
              style: Theme.of(context).textTheme.titleSmall),
          Row(children: [
            FilledButton(
              onPressed: connected && _settleCancel == null
                  ? _doWaitUntilSettled
                  : null,
              child: const Text('wait'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _settleCancel != null
                  ? () => _settleCancel?.cancel()
                  : null,
              child: const Text('cancel'),
            ),
          ]),
          if (_lastSettleResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('result: $_lastSettleResult'),
            ),
        ],
      ),
    );
  }

  // ---------- Section 4: KubiState ----------

  Widget _buildStateSection(KubiState state) {
    return Card(
      child: ExpansionTile(
        title: const Text('📊 KubiState (ValueListenable)'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          _kv('connectionState', state.connectionState.name),
          _kv('commanded', _fmt(state.commanded)),
          _kv('actual', _fmt(state.actual)),
          _kv('isMoving', '${state.isMoving}'),
          _kv('lastError', state.lastError?.toString() ?? '-'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 140, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v, style: const TextStyle(fontFamily: 'monospace'))),
          ],
        ),
      );

  // ---------- Section 5: Events ----------

  Widget _buildEventsSection() {
    final filtered = _events.where((e) {
      switch (e.kind) {
        case _LogKind.connection:
          return _showConnection;
        case _LogKind.move:
          return _showMove;
        case _LogKind.debug:
          return _showDebug;
      }
    }).toList();
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('📜 Events (${filtered.length}/${_events.length})'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Wrap(spacing: 8, children: [
            FilterChip(
              label: const Text('connection'),
              selected: _showConnection,
              onSelected: (v) => setState(() => _showConnection = v),
            ),
            FilterChip(
              label: const Text('move'),
              selected: _showMove,
              onSelected: (v) => setState(() => _showMove = v),
            ),
            FilterChip(
              label: const Text('debug'),
              selected: _showDebug,
              onSelected: (v) => setState(() => _showDebug = v),
            ),
          ]),
          if (_showDebug)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final t in BleDebugEventType.values)
                  FilterChip(
                    label: Text(t.name, style: const TextStyle(fontSize: 11)),
                    selected: _enabledDebugTypes.contains(t),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _enabledDebugTypes.add(t);
                      } else {
                        _enabledDebugTypes.remove(t);
                      }
                    }),
                  ),
              ]),
            ),
          const Divider(),
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(4),
            ),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('(no events)',
                        style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final e = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Text(
                          '${_ts(e.timestamp)} [${e.kind.name}] ${e.msg}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: switch (e.kind) {
                              _LogKind.connection => Colors.blue.shade800,
                              _LogKind.move => Colors.purple.shade800,
                              _LogKind.debug => Colors.grey.shade700,
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _ts(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

  // ---------- 共通 widgets ----------

  Widget _angleSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {ValueChanged<double>? onChangeEnd}) {
    return Row(children: [
      SizedBox(width: 40, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
      SizedBox(
          width: 60,
          child: Text(value.toStringAsFixed(1), textAlign: TextAlign.end)),
    ]);
  }

  Widget _intSlider(
      String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(children: [
      SizedBox(width: 120, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (v) => onChanged(v.toInt()),
        ),
      ),
      SizedBox(width: 50, child: Text('$value', textAlign: TextAlign.end)),
    ]);
  }
}

// ===========================================================================
// supporting types (local to this example)
// ===========================================================================

enum _MoveSpecKind {
  independentUniform('independent (uniform)'),
  independentPerAxis('independent (perAxis)'),
  synced('synced');

  const _MoveSpecKind(this.label);
  final String label;
}

enum _LogKind { connection, move, debug }

class _LogEntry {
  _LogEntry(this.timestamp, this.kind, this.msg);
  final DateTime timestamp;
  final _LogKind kind;
  final String msg;
}
