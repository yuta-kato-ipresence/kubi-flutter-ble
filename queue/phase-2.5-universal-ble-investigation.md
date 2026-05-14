# Phase 2.5 — universal_ble v1.2.0 API 調査レポート

> 目的: Phase 3 (KubiBleImpl 実装) 着手前に universal_ble の API 表面を把握し、
> 設計書 v0.2.0-draft の前提と矛盾する点・追加で決めるべき点を洗い出す。

## 1. universal_ble v1.2.0 API 表面 (利用予定分のみ)

### 1.1 Static facade (`UniversalBle.*`)

| API | シグネチャ | 用途 |
|-----|---------|------|
| `getBluetoothAvailabilityState()` | `Future<AvailabilityState>` | BLE 可用性 (6 値: unknown/resetting/unsupported/unauthorized/poweredOff/poweredOn) |
| `availabilityStream` | `Stream<AvailabilityState>` | 可用性変化 |
| `requestPermissions({bool withAndroidFineLocation})` | `Future<void>` | Android/iOS 権限要求 |
| `hasPermissions(...)` | `Future<bool>` | 権限チェック (Win/Linux/Web は常に true) |
| `startScan({ScanFilter?, PlatformConfig?})` | `Future<void>` | scan 開始 |
| `stopScan()` | `Future<void>` | scan 停止 |
| `scanStream` | `Stream<BleDevice>` | scan 結果 (重複あり) |
| `connect(deviceId, {timeout, autoConnect})` | `Future<void>` (ConnectionException) | timeout 既定 60 秒 |
| `disconnect(deviceId, {timeout})` | `Future<void>` | disconnect (auto-reconnect も止める) |
| `connectionStream(deviceId)` | `Stream<bool>` | true=connected, false=disconnected (**中間状態は流れない**) |
| `getConnectionState(deviceId)` | `Future<BleConnectionState>` | 同期取得 (4 値: Android/Apple のみ中間値) |
| `discoverServices(deviceId, {withDescriptors, timeout})` | `Future<List<BleService>>` | service discovery |
| `subscribeNotifications(deviceId, service, char, {timeout})` | `Future<void>` | **新 API** (setNotifiable は deprecated) |
| `unsubscribe(deviceId, service, char, {timeout})` | `Future<void>` | notification 停止 |
| `characteristicValueStream(deviceId, charId)` | `Stream<Uint8List>` | notify/indicate の値 stream |
| `read(deviceId, service, char, {timeout})` | `Future<Uint8List>` | **新 API** (readValue deprecated) |
| `write(deviceId, service, char, value, {withoutResponse, timeout})` | `Future<void>` | **新 API** (writeValue deprecated) |
| `getSystemDevices({withServices, timeout})` | `Future<List<BleDevice>>` | **Web 非対応** |
| `requestMtu(deviceId, expectedMtu, {timeout})` | `Future<int>` | MTU 要求 (best-effort) |
| `setLogLevel(BleLogLevel)` | `Future<void>` | debug log |
| `queueType` (setter) | `QueueType` | global / perDevice / none |
| `clearQueue([id])` | `void` | queue クリア |
| `setInstance(UniversalBlePlatform)` | `void` | **mock 注入用 (テストに有用)** |

### 1.2 Callback (静的フィールド、deprecated 気味だが現存)

```dart
UniversalBle.onConnectionChange = (deviceId, isConnected, error) { ... };
UniversalBle.onScanResult       = (BleDevice device) { ... };
UniversalBle.onAvailabilityChange = (AvailabilityState state) { ... };
```

`Stream` 版 (`connectionStream` / `scanStream` / `availabilityStream`) と
**両方ある**。我々は基本 Stream 側を使う方針だが、**`onConnectionChange` の `error: String?` は Stream 側に出てこない**
(`connectionStream` は `bool` しか返さない) ため、disconnect の error 理由を取るには
**callback 側を併用するか、`bleConnectionUpdateStreamController` (記録用 internal) を直接購読する必要あり**。

### 1.3 値型

- `BleDevice { String deviceId; String? name; String? rawName; int? rssi; bool? paired; ... }`
  - `name` は ASCII 範囲外を strip + trim 済 (`rawName` は raw)
  - `BleDevice.connectionState` getter (= `UniversalBle.getConnectionState(deviceId)` の便利版)
- `BleConnectionState { connected, disconnected, connecting, disconnecting }` ← **enum 値順注意** (Dart 標準と異なる)
- `AvailabilityState { unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }`
- `ScanFilter { withServices, withManufacturerData, withNamePrefix, exclusionFilters }`
- `BleService { uuid, characteristics: List<BleCharacteristic> }`
- 例外: `UniversalBleException` (base) / `ConnectionException` / `PairingException` / `WebBluetoothGloballyDisabled`

### 1.4 重要な内部仕様

- **`connect()` の挙動**: `_platform.connect()` を呼びつつ `bleConnectionUpdateStreamController` を購読、`isConnected==true` を Future で待つ。timeout 超過で `ConnectionException("Failed to connect")`。
- **`BleCommandQueue`**: 内部で **read/write/notify を直列化**している。default は `QueueType.global` (全デバイス共通 queue)、`perDevice` / `none` に変更可能。global timeout は既定 10 秒 (`UniversalBle.timeout` で変更可能)。
- **iOS/macOS の read 副作用**: `read()` 呼び出しが `onValueChange` / `characteristicValueStream` をトリガーする (= notification と同じ stream に値が流れる)。
- **`disconnect()` は auto-reconnect も停止する** (universal_ble 内部仕様、明示)。

---

## 2. 設計書 v0.2.0-draft の前提との突き合わせ

### 2.1 ✅ 整合する点

- `universal_ble` の `BleConnectionState` 4 値 = 設計書 `BleConnectionState` enum と完全一致
- `Uint8List` ベースの GATT I/O = `kubi_protocol.dart` の現行実装と整合
- `setInstance(UniversalBlePlatform)` でテスト時の差し替えが可能 (KubiBleImpl 単体テストも書ける)
- `subscribeNotifications` / `read` / `write` の新 API がそろっており、callback API への退避が不要

### 2.2 ⚠️ 設計書/Phase 2 で再検討が必要な点

#### A. `requestDevice()` の実装方針 ← **最重要決定事項**

**問題**: universal_ble に `requestDevice` 相当の API は無い。すべて scan ベース。

設計書 §3.2 では:
> `requestDevice()` 選択ダイアログ → `KubiDevice`

これを実装するには 3 つの選択肢:

- **案 A**: 内部で `startScan(ScanFilter(withNamePrefix: ['kubi']))` → `scanStream` の最初の 1 件を返す → `stopScan()`
  - 利点: API 通り
  - 欠点: 「複数の Kubi が近くにある」ケースで利用者が選べない (1 個目が必ず選ばれる)
- **案 B**: `requestDevice()` を廃止し、代わりに `scan({Duration timeout}) → Stream<KubiDevice>` を提供
  - 利点: Flutter UI で選択 widget を作るときに自然
  - 欠点: 設計書を改訂必要 (B 系 Decision に追加)
- **案 C**: 両方提供。`requestDevice()` は内部で scan して 1 個目を返す convenience、`scan()` は強い API
  - 利点: U1 (joystick) のような単純ユースケースは便利、上級者は scan を使える
  - 欠点: API 表面が増える

**推奨**: 案 C。設計書に `Stream<KubiDevice> scan({Duration timeout, ScanFilter? filter})` を追加し、`requestDevice` は `scan().first.timeout(...)` のラッパーとする。

#### B. GATT queue の二重化リスク ← **アーキテクチャ判断**

**問題**: universal_ble は内部で **`BleCommandQueue` (global queue)** を持ち、すべての write/read を直列化する。我々の設計書 §5.1 では「KubiBleImpl 内部に GATT lock を持つ」としているため、**lock が 2 段になる**。

- 案 X: `UniversalBle.queueType = QueueType.none` を起動時に設定 → 我々が完全制御
  - 利点: latest-value buffer / moveTo cancel-on-newer / pollSkipped 等の制御が一段で済む
  - 欠点: universal_ble のエラー処理 (timeout 等) を自前で再実装する必要が出る可能性
- 案 Y: universal_ble の queue に任せ、我々は「latest-value buffer」と「moveTo cancel」のみ管理
  - 利点: universal_ble の検証済 queue を利用、我々のコードが薄くなる
  - 欠点: queue が device 横断 (global) なので、複数 Kubi 接続時に互いをブロック → ただし複数 Kubi 接続は本パッケージのスコープ外
- 案 Z: `QueueType.perDevice` を起動時に設定、自前 lock も持つ
  - 二重化は残るが per-device に絞れる

**推奨**: 案 Y + `QueueType.perDevice` (設計書 §5.1 に「universal_ble queue を信頼し、self-lock は最小限」と注記)。

#### C. `connectionStream` が中間状態を返さない ← **観測ロジック調整**

**問題**: `UniversalBle.connectionStream(deviceId)` は `Stream<bool>` のみ。`connecting` / `disconnecting` 中間状態は流れない。

設計書 §3.2 の `Stream<ConnectionStateEvent>` で 4 状態すべてを発信したい場合:

- **解**: `connect()` 開始時に **手動で `ConnectionStateEvent(state: connecting)` を emit**、`connectionStream` で `true` 受信時に `connected` を emit、disconnect 開始時に `disconnecting` emit、`false` 受信で `disconnected` emit。
- **`error` 取得**: `UniversalBle.onConnectionChange = (deviceId, isConnected, error) { ... }` を併設し、`error != null` を `DisconnectReason.error`、`error == null` の自然 disconnect を `DisconnectReason.deviceLost` にマップ。

→ Phase 3 KubiBleImpl で実装ロジックとして対応可能、設計書側の API は変える必要なし。

#### D. `AvailabilityState` の扱い ← **設計書追記候補**

設計書では `BleUnavailableError` を「BLE が無効 / 権限なし / unsupported」で投げると書いてあるが、
**接続中に Bluetooth が OFF になった場合の挙動**が未規定。

候補:
- `availabilityStream` を listen し、`poweredOff` / `unauthorized` / `unsupported` / `resetting` を検知したら:
  - 接続中: `disconnect()` を内部で呼び `ConnectionStateEvent(state: disconnected, reason: deviceLost)` を emit
  - 自動再接続が有効でも abandon (BLE 自体が無いので無意味)
- これを設計書 §5.x に追記する

#### E. `tryAutoConnect()` の Web 対応 ← **既知制約として明文化**

`UniversalBle.getSystemDevices()` は **Web 非対応**。
Web で過去接続済みデバイスを取得するには `navigator.bluetooth.getDevices()` を直接叩く必要があるが、
universal_ble v1.2.0 は wrapper を提供していない (調査済)。

候補:
- 案: Web で `tryAutoConnect()` は常に `null` を返す (= 利用者が `requestDevice()` を呼び直す)
- もしくは web 専用の dart:html / package:web を使った実装を kubi-flutter-ble 側で書く

**推奨**: 当面は前者 (常に null)。Web 対応は別 issue として queue に残す。

### 2.3 🔴 設計書/CHANGELOG の修正必要箇所

(Phase 2.5 完了後に対応):

1. **設計書 §3.2** に `Stream<KubiDevice> scan({Duration? timeout, ScanFilter? filter})` を追加 (案 C 採用なら)
2. **設計書 §5.1** に「universal_ble の global queue を `perDevice` に切り替え、self-lock は最小限」を注記
3. **設計書 §5.x (新節)** に「BLE availability の監視と auto-disconnect」を追加
4. **設計書 §3.2 / §4.3** に「Web の `tryAutoConnect()` は常に null を返す既知制約」を注記
5. **CHANGELOG** に `scan()` 追加 (Added セクション)、availability 監視仕様を追記

---

## 3. Phase 3 着手前に確定すべき決定事項 (まとめ)

| ID | 決定事項 | 推奨 |
|----|---------|------|
| D1 | `requestDevice()` の実装方針 | 案 C (`scan()` + 1 個目を返す convenience) |
| D2 | GATT queue 二重化 | 案 Y (universal_ble queue に任せ、`QueueType.perDevice`) |
| D3 | `connectionStream` 中間状態の補完方法 | 手動 emit + `onConnectionChange` callback で error 取得 |
| D4 | `AvailabilityState` 監視 | `availabilityStream` を listen、poweredOff で auto-disconnect |
| D5 | Web の `tryAutoConnect()` | 常に null を返す (既知制約として明文化) |

これらの決定がついたら設計書/CHANGELOG を更新し、Phase 3 (KubiBleImpl 実装) に着手する。
