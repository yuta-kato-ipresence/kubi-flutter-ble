# kubi_flutter_ble — example app

このディレクトリは [`kubi_flutter_ble`](../) パッケージの **全機能を 1 画面に露出した検証用アプリ** です。
利用者が API の使い方を確認するデモであり、開発者が実機検証 (D-meta) を行うハーネスでもあります。

> パッケージの設計・思想は [`../README.md`](../README.md) を、設計理由の詳細は
> [`../docs/api-design.md`](../docs/api-design.md) を参照してください。

## このアプリで何ができるか

- パッケージの公開 API (`KubiBle` interface の 21 members) を **すべて** ボタン/スライダー/スイッチで叩ける
- 接続状態 / availability / `KubiState` / 全 `BleDebugEvent` を **同時に観測** できる
  (タブ分けしていないので、操作した瞬間に全パネルに変化が反映される)
- [`../docs/platform-notes.md`](../docs/platform-notes.md) の実機検証チェックリストを **1 アプリで踏める**

## 動かし方

> 依存解決のため、初回は `flutter pub get` を `example/` 直下で実行してください。

### Android

```bash
cd example
flutter pub get
flutter run -d <android-device-id>
```

- Android 12+ では `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` の **runtime permission** が必要です
  (詳細は [`../docs/platform-notes.md`](../docs/platform-notes.md) の Android セクション)
- 12 未満なら `BLUETOOTH` / `ACCESS_FINE_LOCATION`

### iOS

```bash
cd example
flutter pub get
flutter run -d <ios-device-id>
```

- `ios/Runner/Info.plist` に `NSBluetoothAlwaysUsageDescription` を追加
  (シミュレーターでは BLE は使えません、実機必須)

### macOS

```bash
cd example
flutter pub get
flutter run -d macos
```

- `macos/Runner/*.entitlements` に `com.apple.security.device.bluetooth` を追加
- App Sandbox を有効にしている場合は同じくその下に Bluetooth 権限が必要

### Web

```bash
cd example
flutter pub get
flutter run -d chrome
```

- **Scan ボタンの押下は「ユーザージェスチャー」起点が必須** (Web Bluetooth 仕様)
- `tryAutoConnect` は Web では **常に `null`** を返します
  (universal_ble v1.2.0 が `navigator.bluetooth.getDevices()` を wrap していないため、設計判断 D5)
- HTTPS or localhost が必須

## 画面構成

起動するとステータスバー (接続状態 + availability + isMoving chip) が常時表示され、その下に 5 つのセクションが折りたたみ式で並びます。

### 📡 Connection

| 項目 | 対応 API |
|------|----------|
| Scan / Stop scan | `scan(timeout:)` / Stream cancel |
| requestDevice | `requestDevice(timeout:)` |
| tryAutoConnect | `tryAutoConnect()` |
| Disconnect | `disconnect()` |
| Auto-reconnect スイッチ + maxRetries / retryDelay スライダー | `setAutoReconnect(AutoReconnectConfig)` / `null` で off |
| 検出デバイスリスト → 各行の connect ボタン | `connect(KubiDevice)` |
| currentConnectionState 表示 | `currentConnectionState` (sync getter) |

`availability` 表示はステータスバーに常時、変化は Events ログにも出ます (`availabilityStream`)。

### 🎮 Control

| 項目 | 対応 API |
|------|----------|
| pan / tilt スライダー + setTarget ボタン | `setTarget(target:, speed:)` |
| Live モード スイッチ | 上記をスライダーの `onChangeEnd` で連射 (latest-value buffer の挙動を確認可能) |
| pan / tilt スライダー + moveTo ボタン | `moveTo(target:, spec:, cancel:)` |
| MoveSpec 切替 (`independent (uniform)` / `independent (perAxis)` / `synced`) | `MoveSpec.independent` (`MoveSpeed.uniform` / `MoveSpeed.perAxis`) / `MoveSpec.synced` |
| 各 speed スライダー (1〜100) | 上記の引数 |
| Cancel ボタン | `CancelToken.cancel()` |
| 直近結果 (settled / cancelled / error) | `MoveResult` の sealed 分岐 |
| default speed スライダー + setDefaultSpeed ボタン | `setDefaultSpeed(MoveSpeed)` / `defaultSpeed` |

### 👁 Observation

| 項目 | 対応 API |
|------|----------|
| commanded / actual の getCommanded / getActual ボタン | `getCommandedPosition()` / `getActualPosition()` |
| subscribePosition: intervalMs slider + PositionSource 選択 + start/stop | `subscribePosition(SubscribePositionOptions)` |
| latest snapshot 表示 | Stream の最新値 |
| waitUntilSettled (moveTo の値を target に流用) + Cancel | `waitUntilSettled(target:, cancel:)` |

### 📊 KubiState (ValueListenable)

`state` (`ValueListenable<KubiState>`) の全 field を一覧表示:
`connectionState` / `commanded` / `actual` / `isMoving` / `lastError`。

`ValueListenableBuilder` で UI に bind した時の挙動をそのまま観察できます。

### 📜 Events

すべてのストリームのログを時系列 (最新が上) で 200 件保持:

- 種別フィルタ: `connection` (`connectionStateStream` + `availabilityStream`) / `move` (`onMove` + 操作系エラー) / `debug` (`onDebugEvent`)
- `debug` 表示時は **11 種の `BleDebugEventType` を個別 ON/OFF** できる
  (`notificationRaw` / `registerRead` / `registerReadTimeout` / `pollSkipped` /
  `listenerError` / `connectionStateChange` /
  `autoReconnectScheduled` / `autoReconnectAttempt` / `autoReconnectSuccess` /
  `autoReconnectFailed` / `autoReconnectAbandoned`)
- 各エントリは monospace + color-coded (種別ごと) で表示

右上のゴミ箱アイコンでログ全消去。

## 検証チェックリストとの対応

[`../docs/platform-notes.md`](../docs/platform-notes.md) の **D-meta 実機検証チェックリスト** の各項目を、このアプリでどう踏むかの早見表:

| チェック項目 | 操作手順 | 観測ポイント |
|------------|----------|------------|
| 接続成立 | Connection: Scan → 検出行 connect | ステータスバーが `connected` に / Events に `state=connected` |
| 明示切断 | Connection: Disconnect | Events に `state=disconnected reason=user` |
| auto-reconnect (成功) | auto-reconnect=on で接続 → Kubi 電源 off → on | Events に `autoReconnectScheduled` → `autoReconnectAttempt` → `autoReconnectSuccess` |
| auto-reconnect (max 到達) | maxRetries=2 で電源 off のまま放置 | Events に `autoReconnectFailed` ×N → `autoReconnectAbandoned` |
| availability lost | 接続中に OS の Bluetooth を OFF | ステータスバー availability=`poweredOff` / Events に `state=disconnected reason=deviceLost` |
| cancel-on-newer (moveTo) | moveTo 実行 → 完了前に値変更して moveTo 再実行 | 前者の result が `cancelled` / Events に `phase=cancelled` |
| latest-value buffer (setTarget) | Live モード ON で slider を素早く左右に振る | スムーズに最終位置へ追従 (中間値は drop されているが UI 上は気にならない) |
| register read timeout | Kubi を抜いて (or disconnect 後) getCommanded を押下 | Events に `registerReadTimeout` (BleNotConnectedError の場合もあり) |
| MoveSpec.synced 計算 | moveTo を synced で大角度実行 | 両軸が **同時刻** に settle (Events の `phase=settled` が 1 つ) |
| poll skipped | subscribePosition start + 同時に moveTo 連打 | Events に `pollSkipped` が混じる |
| MoveSpeed.perAxis | moveTo を perAxis で pan=100 tilt=10 | tilt の方が圧倒的に遅く到達 |
| Cancel (moveTo) | moveTo 中に Cancel ボタン | result=`cancelled` |
| Cancel (waitUntilSettled) | wait 中に cancel | `BleUserCancelledError` (Events に出る) |
| KubiState fan-in | 任意の操作中 KubiState セクションを観察 | commanded / actual / isMoving / lastError が連動して変化 |

> 補足: `listenerError` の検証はアプリ内 UI から行えません (利用者の listener throw を起こす必要があるため)。
> 必要なら一時的にこの example の listener (initState 内) に `throw` を仕込んで確認してください。

## トラブルシュート

| 症状 | 原因候補 |
|------|----------|
| Scan 押しても何も検出されない | Bluetooth OFF / 権限未許可 / Web で gesture 起点になっていない |
| connect 直後に切断される | Kubi 側に既に他端末が接続している / pairing 残骸 |
| moveTo が永遠に終わらない | settle tolerance に届いていない (機械的引っ掛かり) → Cancel 後に SettleOptions を緩めて再試行 |
| Web で `tryAutoConnect` が常に null | 仕様 (D5)。Scan からやり直す |

詳細は [`../docs/platform-notes.md`](../docs/platform-notes.md) を参照。
