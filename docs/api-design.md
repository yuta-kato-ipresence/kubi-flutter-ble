# kubi_flutter_ble API 設計書

> **Version**: 0.1.0-draft
> **Target**: Dart ^3.11.0, Flutter ^3.32.0
> **Base**: kubi-web-ble (TS) v0.8 API + Flutter 最適化

---

## 1. 設計思想

### 1.1 Flutter エコシステムとの統合
- **イベントは `Stream<T>` で提供**: `StreamBuilder`, `ValueListenableBuilder` 等と直接接続可能
- **状態の集約**: 接続状態・位置・移動フラグを `KubiState` Record で一元化し、`ValueNotifier<KubiState>` としても公開
- **非同期は `Future<T>` で統一**: コールバック地獄を避ける

### 1.2 TS 版との機能対応
TS 版 `KubiBle` インターフェースの全メソッド・型を再現。ただし「Flutter で自然に使える形」に再設計。

---

## 2. アーキテクチャ

```
┌─────────────────────────────────────────┐
│  Flutter App (UI Layer)                 │
│  - StreamBuilder<MoveEvent>             │
│  - ValueListenableBuilder<KubiState>    │
│  - FutureBuilder<MoveResult>            │
└──────────────┬──────────────────────────┘
               │ uses
┌──────────────▼──────────────────────────┐
│  KubiBle (Abstract Interface)           │
│  - Stream-based events                  │
│  - Future-based commands                │
│  - ValueNotifier-compatible state       │
└──────────────┬──────────────────────────┘
               │ implements
┌──────────────▼──────────────────────────┐
│  KubiBleImpl                            │
│  - universal_ble ラッパー               │
│  - GATT lock / pending buffer           │
│  - settle polling                       │
└──────────────┬──────────────────────────┘
               │ delegates
┌──────────────▼──────────────────────────┐
│  KubiProtocol (Pure Functions)          │
│  - payload 組み立て / パース            │
│  - 角度・速度変換                       │
└─────────────────────────────────────────┘
```

---

## 3. 公開 API (`KubiBle`)

### 3.1 接続層

```dart
abstract interface class KubiBle {
  /// デバイス選択ダイアログを表示し選択結果を返す
  Future<KubiDevice> requestDevice();

  /// GATT 接続
  Future<void> connect(KubiDevice device, {Duration? timeout});

  /// 切断
  Future<void> disconnect();

  /// 自動再接続設定
  void setAutoReconnect(bool enabled, {int? maxRetries, Duration? retryDelay});

  /// 既知デバイスへの自動接続を試行（Web: getDevices, Native: systemDevices）
  Future<KubiDevice?> tryAutoConnect();

  /// 接続状態の Stream（購読時に現在値が即座に emit）
  Stream<BleConnectionState> get connectionStateStream;

  /// 現在の接続状態（同期取得）
  BleConnectionState get currentConnectionState;
}
```

### 3.2 動作層（書く）

```dart
  /// 物理到達まで await。連打時は前の Future が cancelled で resolve
  Future<MoveResult> moveTo({
    required double pan,
    required double tilt,
    MoveSpeed? speed,
    SettleOptions? settle,
    CancelToken? cancelToken,
  });

  /// Fire-and-forget（joystick 連打用）。最新値バッファで動作
  Future<PanTiltAngles> setTarget({
    required double pan,
    required double tilt,
    MoveSpeed? speed,
  });

  /// 既定速度を設定
  void setDefaultSpeed(MoveSpeed speed);

  /// 既定速度を取得
  MoveSpeed get defaultSpeed;
```

### 3.3 観測層（読む）

```dart
  /// Goal Position レジスタ (0x1e) を読む
  Future<PanTiltAngles> getCommandedPosition();

  /// Present Position レジスタ (0x24) を読む
  Future<PanTiltAngles> getActualPosition();

  /// 物理到達まで polling 待ち
  Future<PanTiltAngles> waitUntilSettled({
    Duration? timeout,
    double? thresholdDegrees,
  });

  /// 位置の定期購読（commanded / actual / both）
  Stream<PositionSnapshot> subscribePosition({
    Duration? interval,
    PositionSource source,
  });
```

### 3.4 イベント層

```dart
  /// 4 phase 移動イベント
  Stream<MoveEvent> get onMove;

  /// デバッグイベント
  Stream<BleDebugEvent> get onDebugEvent;

  /// デバッグログ有効化
  set debugLogging(bool enabled);
}
```

---

## 4. 型定義

### 4.1 `MoveSpeed` (sealed class)

```dart
sealed class MoveSpeed {
  const MoveSpeed();
}

final class MoveSpeedUniform extends MoveSpeed {
  final double speed; // [1, 100]
  const MoveSpeedUniform(this.speed);
}

final class MoveSpeedPerAxis extends MoveSpeed {
  final double pan;
  final double tilt;
  const MoveSpeedPerAxis({required this.pan, required this.tilt});
}
```

### 4.2 `MoveResult` (sealed class)

```dart
sealed class MoveResult {
  const MoveResult();
}

final class MoveResultSettled extends MoveResult {
  final PanTiltAngles actual;
  const MoveResultSettled({required this.actual});
}

final class MoveResultCancelled extends MoveResult {
  const MoveResultCancelled();
}
```

### 4.3 `PositionSnapshot` (Record)

```dart
typedef PositionSnapshot = ({
  PanTiltAngles? commanded,
  PanTiltAngles? actual,
});
```

### 4.4 `MoveEvent`

```dart
enum MovePhase { start, commanded, settled, cancelled }

final class MoveEvent {
  final MovePhase phase;
  final PanTiltAngles? target;
  final PanTiltAngles? actual;

  const MoveEvent({required this.phase, this.target, this.actual});
}
```

### 4.5 `BleDebugEvent`

```dart
final class BleDebugEvent {
  final BleDebugEventType type;
  final String message;
  final DateTime timestamp;

  const BleDebugEvent({
    required this.type,
    required this.message,
    required this.timestamp,
  });
}

enum BleDebugEventType {
  gattWrite,
  gattRead,
  gattError,
  pollSkipped,
  listenerError,
  stateChange,
}
```

### 4.6 その他

```dart
final class PanTiltAngles {
  final double pan;
  final double tilt;
  const PanTiltAngles({required this.pan, required this.tilt});
}

final class KubiDevice {
  final String deviceId;
  final String? name;
  final bool isSystemDevice;
}

enum BleConnectionState { disconnected, connecting, connected, disconnecting }

enum PositionSource { commanded, actual, both }

class SettleOptions {
  final Duration? timeout;
  final double? thresholdDegrees;
  const SettleOptions({this.timeout, this.thresholdDegrees});
}

class CancelToken {
  bool get isCancelled;
  void cancel();
}
```

---

## 5. エラー階層

```dart
sealed class KubiBleError implements Exception {
  final String message;
  const KubiBleError(this.message);
}

class BleUnavailableError extends KubiBleError {
  const BleUnavailableError(super.message);
}

class BleUserCancelledError extends KubiBleError {
  const BleUserCancelledError() : super('User cancelled');
}

class BleConnectionError extends KubiBleError {
  const BleConnectionError(super.message);
}

class BleNotConnectedError extends KubiBleError {
  const BleNotConnectedError() : super('Not connected');
}

class BleCommandError extends KubiBleError {
  const BleCommandError(super.message);
}

class BleSettleTimeoutError extends KubiBleError {
  final PanTiltAngles? lastObserved;
  const BleSettleTimeoutError({this.lastObserved})
    : super('Settle timed out');
}
```

---

## 6. TS 版との対応表

| TS 版 | Dart 版 | 変更点 |
|-------|---------|--------|
| `moveTo(pan, tilt, options?)` | `moveTo({pan, tilt, speed, settle, cancelToken})` | named params + Flutter 型 |
| `setTarget(pan, tilt, options?)` | `setTarget({pan, tilt, speed})` | named params |
| `onMove(callback)` | `Stream<MoveEvent> get onMove` | Stream（最適化） |
| `onConnectionStateChange(cb)` | `Stream<BleConnectionState>` | Stream（最適化） |
| `onDebugEvent(cb)` | `Stream<BleDebugEvent>` | Stream（最適化） |
| `subscribePosition(opts, cb)` | `Stream<PositionSnapshot>` | Stream + Record（最適化） |
| `MoveSpeed` union | `sealed class MoveSpeed` | Dart 3 pattern matching |
| `MoveResult` discriminated | `sealed class MoveResult` | Dart 3 exhaustive switch |

---

## 7. 使用例

```dart
final kubi = KubiBleImpl();

// 接続
final device = await kubi.requestDevice();
await kubi.connect(device);

// Stream で移動イベントを監視
kubi.onMove.listen((event) {
  print('Phase: ${event.phase}');
});

// 物理到達まで待つ
final result = await kubi.moveTo(
  pan: 45,
  tilt: 10,
  speed: MoveSpeedUniform(80),
);
switch (result) {
  case MoveResultSettled(:final actual):
    print('Arrived at $actual');
  case MoveResultCancelled():
    print('Cancelled');
}

// 切断
await kubi.disconnect();
```

---

## 8. 今後の検討事項

### 8.1 `ValueNotifier<KubiState>` の追加
UI 統合をさらに楽にするため、以下のような集約状態を `ValueNotifier` として公開する案：

```dart
class KubiState {
  final BleConnectionState connectionState;
  final PanTiltAngles? position;
  final bool isMoving;
  final KubiBleError? lastError;
}
```

### 8.2 `Riverpod` / `Provider` 用ラッパー
将来的に、以下のような Provider 定義を example または別パッケージで提供：

```dart
final kubiProvider = Provider<KubiBle>((ref) => KubiBleImpl());
final kubiStateProvider = StreamProvider<KubiState>((ref) {
  final kubi = ref.watch(kubiProvider);
  // ...
});
```

### 8.3 Web BLE 対応の詳細
`universal_ble` の Web 実装では `withServices` が必須となるため、Kubi 固有の Service UUID を `ScanFilter` に含める必要あり。実装時に対応。
