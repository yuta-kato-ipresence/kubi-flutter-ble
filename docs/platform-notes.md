# Platform Notes

`kubi_flutter_ble` の各 OS / Web プラットフォーム別の挙動・既知制約・必要権限を集約する。
SSOT は `lib/src/kubi_ble.dart` (dartdoc) と `docs/api-design.md`、本ファイルは **実装者・利用者向けの運用ガイド** に徹する。

---

## 共通

- BLE stack は `universal_ble ^1.2.0` を採用 (`KubiBleImpl` 内部で wrap)。
- スキャンフィルタは `withNamePrefix: ['kubi']` を固定 (`KubiBle.scan()`)。
- GATT サービス UUID: `2a001800-2803-2801-2800-1d9ff2d5c442` (servo-spec.md §2.2)。
- 全てのコマンドは `UniversalBle.queueType = QueueType.perDevice` で **デバイスごとに直列化** される (D2)。

---

## Android

### 必要権限 (Android 12+)

`android/app/src/main/AndroidManifest.xml` に以下を追加:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Android 11 以下のみ。位置情報が BLE scan に必要 -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />
```

`KubiBle.scan()` を呼ぶ前にランタイム権限を取得する:

```dart
await UniversalBle.requestPermissions();
```

### 実装メモ

- `onConnectionChange` は **OS 経由で非同期** に発火。`disconnect()` 内で即座に `disconnected` を emit するが、後追いで再度同イベントが natural disconnect 判定で来る可能性があるため `_explicitDisconnectInProgress` flag で除外している (D3)。
- `getSystemDevices(withServices: [...])` は OS にキャッシュされた bonded device を返す。アプリ初回起動時は空。

---

## iOS / macOS

### 必要 entitlement

`ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Kubi 本体と通信するために BLE を使用します。</string>
```

macOS は `macos/Runner/DebugProfile.entitlements` および `Release.entitlements` に:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

### 実装メモ

- iOS の `getSystemDevices` は **直近に接続した既知デバイス** を返す (CoreBluetooth `retrieveConnectedPeripherals`/`retrievePeripherals` 相当)。
- iOS は disconnecting 中間状態を OS 側から返すケースがあるため、`connectionStateStream` で `disconnecting` を一度経由してから `disconnected` に到達することがある。

---

## Web (Chrome / Edge)

### 既知制約

- **`tryAutoConnect()` は常に `null` を返す** (D5)。`universal_ble` v1.2.0 が `navigator.bluetooth.getDevices()` を wrap していないため、永続接続候補を取得できない。
- ブラウザの BLE 仕様により **`scan()` を呼ぶ前にユーザージェスチャー** (ボタンクリック等) が必要。
- 一部ブラウザでは `requestDevice` ダイアログがネイティブ UI なので、`KubiBle.scan().first` で受け取った 1 件目以外を選択する手段はない (ブラウザ側で UI 完結)。

### 必要 origin

- HTTPS 必須 (`localhost` は例外)。
- Origin Trial 等の追加設定は不要 (Web Bluetooth は安定 API)。

---

## D-meta 実機検証チェックリスト

以下を **Phase 5 の実機検証フェーズ** で消化する (✅ = 検証済、⏳ = 未消化):

### scan / connect 基本系
- [ ] ⏳ Android: `kubi` prefix のデバイスを scan して列挙、connect 成功
- [ ] ⏳ iOS: 同上
- [ ] ⏳ macOS: 同上
- [ ] ⏳ Web (Chrome): `scan()` 呼出にユーザージェスチャー必要、`requestDevice` 経由で 1 件接続
- [ ] ⏳ scan timeout で stream が完了する (onDone) ことを各 OS で確認

### protocol / moveTo
- [ ] ⏳ `getCommandedPosition` / `getActualPosition` が register notify から正しい角度を返す (UUID 経路確認)
- [ ] ⏳ `moveTo(MoveSpec.independent)`: panUuid / tiltUuid に正しい servo 値が乗ること
- [ ] ⏳ `moveTo(MoveSpec.synced)`: panTime / requiredTiltVel / クランプ が物理的に同期着地すること
- [ ] ⏳ `subscribePosition(commanded/actual/both)` が overlap せず順次 poll すること (`pollSkipped` debug emit を観測)

### 切断 / 再接続
- [ ] ⏳ user disconnect → `DisconnectReason.user` で 1 度だけ emit
- [ ] ⏳ アダプタ OFF (poweredOff): 接続中なら `deviceLost` emit、auto-reconnect が schedule される
- [ ] ⏳ デバイス電源 OFF (natural disconnect): `deviceLost` emit → auto-reconnect 線形バックオフが動作 (`retryDelay × attempt`)
- [ ] ⏳ `maxRetries` 到達後 `reconnectExhausted` で abandon
- [ ] ⏳ Web: `tryAutoConnect()` が常に `null` を返すこと

### エラー系
- [ ] ⏳ register read timeout (motorPositionUuid に notify を返さない) → `BleRegisterReadTimeoutError`
- [ ] ⏳ settle timeout → `BleSettleTimeoutError`
- [ ] ⏳ disconnect 中の write → `BleNotConnectedError`
- [ ] ⏳ availability `unauthorized`: auto-reconnect が abandon され、`autoReconnectAbandoned` debug emit

### Android 12+ 権限
- [ ] ⏳ `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` を runtime 拒否した場合のエラーパス確認

---

## 既知の TODO (Phase 5+)

- [ ] iOS の background mode (`bluetooth-central`) 設定有無の動作差分
- [ ] Linux / Windows desktop サポートは universal_ble v1.2.0 が limited、当面 Tier-2 扱い
- [ ] `requestMtu` を呼ぶか否か (現状は呼んでいないが、Android で iOS と比べ Notify が遅い場合に検討)
