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

## Web

Web Bluetooth は **ブラウザと OS の協調**に強く依存する領域で、native プラットフォームと比べて挙動が脆い。
本パッケージで吸収できる部分と、ユーザー環境に依存する部分を区別して扱う。

### ブラウザ互換性マトリクス

| OS | ブラウザ | Web Bluetooth | 備考 |
|---|---|---|---|
| Windows | Chrome / Edge / Brave | ◎ | 標準的に動作 |
| macOS (〜Sequoia 25) | Chrome / Edge / Brave | ◎ | 標準的に動作 |
| macOS (Tahoe 26+) | **Chrome stable ≤ 148** | ✗ | **renderer crash**。後述 |
| macOS (Tahoe 26+) | Chrome 150+ / Canary / Edge stable | ◎ | macOS 26 の TCC 強化に対応済 |
| iOS / iPadOS | Safari, Mobile Chrome, Mobile Edge | ✗ | Apple が Web Bluetooth を実装しない方針 |
| iOS / iPadOS | **Bluefy** (`com.basiclyl.bluefy`) | ◎ | サードパーティブラウザで Web Bluetooth を提供。**iOS の唯一の選択肢** |
| Android | Chrome / Edge | ◎ | 標準的に動作 |
| Linux | Chrome | △ | BlueZ 起因で時々不安定 |

### macOS 26 (Tahoe) + Chrome ≤ 148 stable の renderer crash

**症状**: `flutter run -d chrome` で起動し Scan / requestDevice を呼ぶと、Chrome タブが消える (renderer プロセスが kill される)。
ブラウザコンソールには何も出ない。dev server のログにも出ない。

**原因**: macOS 26 (Tahoe) は Bluetooth プライバシー強制 (TCC) を強化しており、`navigator.bluetooth.requestDevice` を呼んだプロセスに対して、
Chrome 148 stable は適切な entitlement / Info.plist エントリで応答できず、OS が renderer を kill する。
Chromium 側のコードは 149/150 で対応済みのため、Chrome stable が 150 系に上がれば自然解消する。

**確認方法** (将来同種事象が起きた場合の手順):

```bash
# 直近の Chrome renderer crash dump を確認
/bin/ls -lt "$HOME/Library/Application Support/Google/Chrome/Crashpad/completed/" | head -3

# crash dump 内の TCC marker を検索
/usr/bin/strings "<dump_path>" | grep -iE "Bluetooth|NSBluetoothAlwaysUsageDescription|usage description"
```

`NSBluetoothAlwaysUsageDescription` 関連の文字列が出れば TCC kill 確定。

**回避策**:

- 開発時: `CHROME_EXECUTABLE=/Applications/Google\ Chrome\ Canary.app/Contents/MacOS/Google\ Chrome\ Canary flutter run -d chrome` で Canary を使用。
- エンドユーザー: ブラウザ側のリリース待ち。本パッケージ側で事前検出する手段はない (renderer が即座に kill されるため JS から見えない)。
- tracking: [Issue #7](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/7)

### iOS / iPadOS は Bluefy が事実上必須

iOS / iPadOS の Safari、Mobile Chrome、Mobile Edge は **すべて Web Bluetooth を実装していない** (Apple のポリシー)。
iOS で Web アプリから BLE デバイスにアクセスするには **[Bluefy](https://apps.apple.com/jp/app/bluefy-web-ble-browser/id1492822055)**
(App Store の Web Bluetooth 対応ブラウザ) をユーザーがインストールして利用する必要がある。

このため、本パッケージを Web ビルドで配布する場合、iOS ユーザー向けの導線として:
- アプリ説明 / ランディングページに「iOS では Bluefy をご利用ください」と明記
- 検出した UA が iOS Safari / iOS Chrome の場合は、UI 上で Bluefy への誘導を出す

…を実装側 (このパッケージを使うアプリ) の責務として案内する。Bluefy 内では Chrome と概ね同じ挙動 (Web Bluetooth API 仕様準拠) になる。

### `optionalServices` の宣言が必須

Web Bluetooth のセキュリティモデルでは、`navigator.bluetooth.requestDevice` の picker 表示時に **アクセス予定のサービス UUID を宣言** しないと、
接続後の `getPrimaryService` が `SecurityError: Tried getting blocklisted UUID` で拒否される。

本パッケージは `KubiBle.scan()` で内部的に以下を universal_ble に渡しており、利用者側で対応不要:

```dart
PlatformConfig(
  web: WebOptions(
    optionalServices: [servoServiceUuid],
  ),
)
```

ただし将来 servo-spec が更新されてサービス UUID が増えた場合、`kubi_protocol.dart` に定数を追加するだけでなく
`KubiBleImpl.scan()` の `optionalServices` リストにも追加する必要がある点に注意。

### `scanStream` は broadcast で buffer されない

`universal_ble.scanStream` は broadcast stream で **listener が居ない瞬間の emit は失われる**。
Web の `startScan` は picker await の中で同期的に `scanStream.add()` を呼ぶため、`startScan` の Future 完了後に subscribe すると emit を取り逃す。

本パッケージは `KubiBleImpl.scan()` で **`scanStream.listen` を `startScan` 呼出の前に置く** ことでこの race を回避している。将来 scan 関連を編集する際はこの順序を崩さないこと。

### ユーザージェスチャー必須

`navigator.bluetooth.requestDevice` (= 本パッケージの `scan()` / `requestDevice()`) は **ユーザー操作 (ボタンクリック等) を起点に呼ぶ必要がある**。
`initState` / アプリ起動直後の自動実行は不可。これは Web Bluetooth 仕様レベルの制約で、本パッケージでは制御できない。

### HTTPS context

Web Bluetooth は secure context (`https://` または `localhost`) でのみ動作。`http://` で配信されたページからは
`navigator.bluetooth === undefined` となり、`KubiBle.scan()` は失敗する。

### `tryAutoConnect()` は常に `null`

`universal_ble` v1.2.0 が `navigator.bluetooth.getDevices()` (Web Bluetooth の bonded device 列挙 API) を wrap していないため、
Web では `tryAutoConnect()` は常に `null` を返す (D5)。永続接続候補のセッション間共有はできない。

### picker UI はブラウザ任せ

`requestDevice` ダイアログはブラウザのネイティブ UI で、本パッケージ / Flutter からは制御不能。
`KubiBle.scan()` で受け取った最初の 1 件以外を select する手段はない (picker 内で 1 件選んだ時点で stream 完了)。

### `watchAdvertisements` のクラッシュ回避 (vendoring)

`universal_ble` v1.2.0 の Web 実装は scan 後に `BluetoothDevice.watchAdvertisements()` を無条件呼び出ししており、これは Chromium の experimental API で renderer crash の既知バグがある
([WebBluetoothCG/web-bluetooth#538](https://github.com/WebBluetoothCG/web-bluetooth/issues/538))。
本パッケージは `third_party/universal_ble/` に universal_ble を vendoring し、`_watchDeviceAdvertisements` を no-op にする 1 行 patch を当てて回避している。詳細は [`third_party/universal_ble/KUBI-PATCH.md`](../third_party/universal_ble/KUBI-PATCH.md)。

---

## 実機検証チェックリスト (D-meta)

実機での動作検証項目は **[Issue #8 Device verification matrix](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8)** で集約・追跡している。本ファイルは canonical な「検証項目リスト」として残し、進捗 (どの環境で踏んだか) は Issue #8 を SoT とする。

検証済環境:
- ✅ Web (Chrome Canary 150.0.7844.0 + macOS 26.3, 2026-05-19) — scan / connect / `optionalServices` declare 経由の GATT アクセス確認

### scan / connect 基本系
- [ ] Android: `kubi` prefix のデバイスを scan して列挙、connect 成功
- [ ] iOS: 同上 (Safari / Mobile Chrome は Web Bluetooth 未実装、Bluefy 必須)
- [ ] iOS Bluefy: scan / connect 成功
- [ ] macOS: 同上
- [x] Web (Chrome Canary 150 + macOS 26.3): `scan()` 呼出にユーザージェスチャー必要、`requestDevice` 経由で 1 件接続
- [ ] Web (Chrome stable / Edge / Brave): 未確認
- [ ] scan timeout で stream が完了する (onDone) ことを各 OS で確認

### protocol / moveTo
- [ ] `getCommandedPosition` / `getActualPosition` が register notify から正しい角度を返す (UUID 経路確認)
- [ ] `moveTo(MoveSpec.independent)`: panUuid / tiltUuid に正しい servo 値が乗ること
- [ ] `moveTo(MoveSpec.synced)`: panTime / requiredTiltVel / クランプ が物理的に同期着地すること
- [ ] `subscribePosition(commanded/actual/both)` が overlap せず順次 poll すること (`pollSkipped` debug emit を観測)

### 切断 / 再接続
- [ ] user disconnect → `DisconnectReason.user` で 1 度だけ emit
- [ ] アダプタ OFF (poweredOff): 接続中なら `deviceLost` emit、auto-reconnect が schedule される
- [ ] デバイス電源 OFF (natural disconnect): `deviceLost` emit → auto-reconnect 線形バックオフが動作 (`retryDelay × attempt`)
- [ ] `maxRetries` 到達後 `reconnectExhausted` で abandon
- [x] Web: `tryAutoConnect()` が常に `null` を返すこと (D5、設計上確定済)

### エラー系
- [ ] register read timeout (motorPositionUuid に notify を返さない) → `BleRegisterReadTimeoutError`
- [ ] settle timeout → `BleSettleTimeoutError`
- [ ] disconnect 中の write → `BleNotConnectedError`
- [ ] availability `unauthorized`: auto-reconnect が abandon され、`autoReconnectAbandoned` debug emit

### Android 12+ 権限
- [ ] `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` を runtime 拒否した場合のエラーパス確認

---

## 既知の TODO / 検証保留事項

- [ ] iOS の background mode (`bluetooth-central`) 設定有無の動作差分
- [ ] Linux / Windows desktop サポートは universal_ble v1.2.0 で limited、当面 Tier-2 扱い (保証対象外)
- [ ] `requestMtu` を呼ぶか否か (現状は呼んでいないが、Android で iOS と比べ Notify が遅い場合に検討)
