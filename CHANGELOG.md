# Changelog

本ファイルは [Keep a Changelog](https://keepachangelog.com/) 準拠で記載する。
本パッケージは Semantic Versioning に従う ([詳細は設計書 §8](docs/api-design.md#8-バージョニング互換性ポリシー))。

## [Unreleased] — 0.2.0-draft

### Added (設計レベル)
- **設計書 v0.2.0-draft** (`docs/api-design.md`): SSOT 原則を徹底し、API カタログを dartdoc に移管。設計理由・ユースケース (U1-U5)・横断パターン・バージョニングポリシーに集中する構成へ全面改訂
- **U5 (テスト/モック)** ユースケースを明文化。`KubiBle` が `abstract interface class` であることで `mocktail` / `mockito` での mock を可能にする (v0.2 では公式 fake は未提供、v0.3 以降検討 — Issue #6)
- **`KubiState` + `ValueListenable`** を Flutter 一級市民拡張として本体 API に昇格 (TS 版に対応物なし、集約 view、二重事実源ではないと明記)
- **横断パターンの恒久文書化**: GATT lock + latest-value buffer / settle 検出 / listener 隔離 / cancel 伝搬 / 自動再接続 state machine / Stream セマンティクス
- **バージョニングポリシー**: deprecation policy / MSDV / Keep a Changelog 運用 / 破壊的変更告知
- `queue/api-design-revision-plan.md`: 設計書改訂の意思決定ログ (中立レビュアー sub-agent の Conditional Go + 7 条件すべて反映)
- `queue/phase-2.5-universal-ble-investigation.md`: universal_ble v1.2.0 API 表面の調査レポート (D1-D5 決定根拠)
- `KubiBle.scan({Duration?})` (`Stream<KubiDevice>`): 周辺 Kubi の逐次列挙 API (D1)。`requestDevice({Duration})` は scan の最初の 1 件を返す convenience に再定義
- `KubiBle.availabilityStream` (`Stream<BleAvailability>`): OS BLE adapter 可用性の監視 (D4、§5.8 新節)。Flutter 拡張
- `BleAvailability` enum (6 値、universal_ble の `AvailabilityState` を rewrap)

### Changed (v0.1.0-draft → v0.2.0-draft、破壊的変更)
- `MoveSpeed`: TS の `number | {pan,tilt}` から **sealed class + factory** (`MoveSpeed.uniform(int)` / `.perAxis(...)`) に。値の単位は `int` (1〜100)
- `MoveSpec`: 新設 sealed class (`MoveSpec.independent({speed?})` / `.synced({maxSpeed})`)。`moveTo` のシグネチャを `moveTo({target, spec, settle, cancel})` に変更
- `MoveResult`: 両 variant (`MoveResultSettled` / `MoveResultCancelled`) に `target: PanTiltAngles` を必須化
- `PositionSnapshot`: Record から **immutable `final class`** に昇格、`timestamp: DateTime` / `isMoving: bool` 必須
- `subscribePosition`: callback 形式を廃止、`Stream<PositionSnapshot>` に統一。broadcast / 即 emit なし / cancel で内部 Timer 停止
- `ConnectionStateEvent`: 新設 immutable class、`state` / `reason: DisconnectReason?` / `timestamp` を持つ。`connectionStateStream` の payload
- `onMove` / `onDebugEvent`: 同上
- `BleDebugEventType`: TS 11 値に完全 1:1 対応 (notificationRaw / registerRead / registerReadTimeout / pollSkipped / listenerError / connectionStateChange / autoReconnect{Scheduled|Attempt|Success|Failed|Abandoned})
- `BleDebugEvent`: リッチフィールド (type/timestamp/characteristic?/bytes?/hex?/message?/detail?) を持つ immutable class
- `BleSettleTimeoutError`: `target` / `lastObserved` / `elapsedMs` 必須
- `BleRegisterReadTimeoutError`: `BleCommandError` 派生、`motorId` (1 or 2) / `addr` / `elapsedMs` 必須
- 全 `KubiBleError` 派生を **`final class`** に統一 (Dart 3 exhaustive switch 有効化)
- `KubiDevice`: `BleDevice` (universal_ble) を public getter で曝す API を廃止、内部に閉じる
- `getCommandedPosition()`: 同期 cache を廃止、`Future<PanTiltAngles>` async に統一
- `KubiProtocol`: クラス廃止、top-level 関数・定数群に変更 (package-private、export しない)
- `kubi_protocol.dart` に PAN/TILT_VELOCITY_TABLE (補正テーブル) を完全コピー、デフォルト定数群 (settleDefault*, subscribeDefault*, readRegisterDefault*) を集約
- `PositionSource` enum 新設 (`commanded` / `actual` / `both`)
- **`AutoReconnectConfig`**: フィールドを `maxRetries` + `retryDelay: Duration` の 2 つに整理 (B3、`enabled` 廃止 → `null` で無効化)。バックオフは **線形** (`retryDelay × attempt`、kubi-ble TS と挙動一致)
- **`requestDevice()`** シグネチャ変更: `requestDevice({Duration timeout = 5s})`、内部実装は `scan().first` の convenience (D1)
- **`KubiBle.tryAutoConnect()`** の Web 既知制約を明文化: universal_ble v1.2.0 が `navigator.bluetooth.getDevices()` を wrap しないため Web では常に `null` を返す (D5)

### Removed
- `experimentalSetAcceleration` / `ServoAcceleration` / `REG.ACCELERATION` / `clampAcceleration` (TS 採用しない、理由 [§6.3](docs/api-design.md#63-採用しない-ts-api))
- `KubiProtocol.parsePosition` (誤実装。`parseRegisterReadResponse(bytes, byteWidth)` に置換済、Phase 3 で実装と一体化)
- 旧 `kubiServiceUuid = 0000e001` / `ledUuid = 0000e002` (誤った UUID、A2 で削除済)
- `lib/src/testing/fake_kubi_ble.dart` / `lib/testing.dart` (Phase 5 prep cleanup): v0.2.0-draft 設計時に検討した公式 `FakeKubiBle` は skeleton (全 method `UnimplementedError`) のままで実装に至らなかったため、誤誘導を避けるべく entry ごと削除。v0.3 以降の本実装は Issue #6 で追跡

### Fixed (実装、A 系)
- 全 GATT UUID を kubi-ble servo-spec.md §2.2 完全準拠に修正 (A1)
- `servoAngle` の数式・clamp 範囲を kubi-ble v0.8 と一致 (A4)
- 速度関連定数を整理 (A5/A5.b)、`defaultMoveSpeed=100` / `minMoveSpeed=1` / `maxMoveSpeed=100`

### Added (実装、KubiBleImpl + テスト)

- `KubiBleImpl`: TS `web-kubi-ble.ts` v0.8 を Dart に移植した本実装 (`lib/src/kubi_ble_impl.dart`、約 1300 行)
  - **scan**: `Stream<KubiDevice>` first-class、`ScanFilter(withNamePrefix: ['kubi'])` + `seen` で dedupe、onCancel で `stopScan` 呼出
  - **connect / disconnect**: 中間状態 (connecting/disconnecting) を手動 emit、`onConnectionChange` から natural disconnect を `_explicitDisconnectInProgress` flag で判定 (D3)、`ConnectionException.message` を `BleConnectionError` に rewrap
  - **availability lost (D4)**: poweredOff/unauthorized/resetting で接続中なら強制 disconnect + `deviceLost` emit + best-effort `UniversalBle.disconnect`、unsupported/unauthorized で auto-reconnect abandon
  - **register read (`_readRegister`)**: `_readChain` で直列化、`_pendingRead`+`_pendingMotorId`+`_pendingAddr` で 1:1 照合 (mismatched header は notify 黙殺)、`BleRegisterReadTimeoutError` (timeout) / `BleProtocolError` (malformed) を区別、`getCommandedPosition` / `getActualPosition` を 2 read + `valToAngle` で実装
  - **moveTo**: `_lastCommanded` を `_writeMoveSequence` 成功時に更新 (TS と完全一致)、`MoveSpec.synced` で panTime / requiredTiltVel / `tiltSpeedFromVelocity` / `[1,100]` クランプを TS と完全一致で計算、`_writeMoveSequence` で **tilt config → pan config → pan target → tilt target** の順 (TS 完全一致、テストで実証)、`_ActiveMove` で cancel-on-newer、4-phase emit (start/commanded/settled/cancelled)、`CancelToken.whenCancelled` を `.asStream().listen` で hook
  - **setTarget**: `_setTargetWriteInflight` flag + `_pendingSetTarget` latest-value buffer (B10)、進行中 moveTo を `_cancelActiveMove` で cancel
  - **`_settleLoop` / `waitUntilSettled`**: tolerance 内で settled、timeout で `BleSettleTimeoutError`、cancel で early return / `BleUserCancelledError` throw
  - **subscribePosition**: 再帰 `Timer` (overlap 防止) + `busy` flag + `_pendingRead != null` check で skip、skip 時 `pollSkipped` debug emit、`PositionSource` 3 値 fan-in、broadcast、`isMoving = _activeMove != null && !completed`
  - **auto-reconnect**: 線形バックオフ (`retryDelay × attempt`)、`maxRetries` で `autoReconnectAbandoned` debug + `reconnectExhausted` 状態 emit、`tryAutoConnect` は kIsWeb で null (D5)、native は `getSystemDevices(withServices: [servoServiceUuid])` から name prefix `kubi` で 1 件目を connect、connect 成功で counter reset + timer cancel
  - **`KubiState` fan-in**: connection / commanded / actual / isMoving / lastError を各 hook から `_updateState` で集約、connect 成功で lastError clear
  - **listener 隔離 (C9)**: `_safeAdd` で listener throw を `BleDebugEventType.listenerError` に隔離、Stream 自体は壊さない
- `BleProtocolError extends BleCommandError`: register read 不正長 / write 失敗をラップする新派生エラー
- **テスト基盤** (`test/`): `FakeUniversalBlePlatform extends UniversalBlePlatform` (UniversalBle.setInstance 経由で差し替え)、writes / subscribed 履歴記録 + `pushRegisterNotify` / `emitAvailability` 等の駆動 helper
- **テストケース** (7 件全 pass): scan dedupe / connect transition + motorPositionUuid subscribe / connect failure / register read 1:1 照合 (mismatched header 無視) / register read timeout / moveTo write 順序 (TS 完全一致を実証) / availability poweredOff → deviceLost

### Added (実装、example + ドキュメント)

- `example/lib/main.dart` を本実装版に刷新: 1 画面 sectioned layout (Connection / Control / Observation / KubiState / Events) で **公開 API 21 members を全て露出** した検証用アプリ (約 930 行)
- `example/README.md` 新設: 動かし方 (Android / iOS / macOS / Web) / 画面構成 / D-meta チェックリスト 1:1 対応表 / トラブルシュート
- `docs/platform-notes.md` 新設: Android 12+ 権限 (BLUETOOTH_SCAN/CONNECT)、iOS/macOS entitlement (NSBluetoothAlwaysUsageDescription, com.apple.security.device.bluetooth)、Web 制約 (ユーザージェスチャー必須 / `tryAutoConnect` は常に null = D5)、D-meta 実機検証チェックリスト


### Fixed (Web BLE 経路、実機検証で発見)
- `KubiBleImpl.scan`: `UniversalBle.scanStream.listen` を `UniversalBle.startScan` の **呼出前** に移動。`scanStream` は broadcast (buffer 無し) で、Web の `startScan` は requestDevice picker の await の中で同期的に `scanStream.add` を呼ぶため、subscribe を後置すると emit を取り逃して device が永遠に列挙されない race があった。native は影響を受けないが Web で必須の修正
- `KubiBleImpl.scan`: `PlatformConfig.web.optionalServices: [servoServiceUuid]` を宣言。Web Bluetooth のセキュリティモデルは picker 表示時に services を declare しないと、接続後 `getPrimaryService` が `SecurityError: Tried getting blocklisted UUID` で拒否される。native では `PlatformConfig` は無視されるため常時付与で問題なし

### Added (Web 関連ドキュメント)
- `docs/platform-notes.md` の Web 節を大幅補強: ブラウザ互換性マトリクス、macOS 26 + Chrome ≤ 148 stable の renderer crash (Issue #7)、iOS は Bluefy が事実上必須、`optionalServices` / `scanStream` race / ユーザージェスチャー / HTTPS context などの諸制約を網羅

### Added (vendoring)
- `third_party/universal_ble/` に `universal_ble` 1.2.0 を vendoring。Web (Chrome) で `BluetoothDevice.watchAdvertisements()` が renderer プロセスをクラッシュさせる既知バグ ([WebBluetoothCG/web-bluetooth#538](https://github.com/WebBluetoothCG/web-bluetooth/issues/538)) を 1 行 patch (`_watchDeviceAdvertisements` を no-op 化) で回避。`pubspec.yaml` / `example/pubspec.yaml` に `dependency_overrides` で差し替えを宣言
  - **A/B 検証済 (2026-05-19)**: patch を一時的に外して `flutter run -d chrome` で踏むと、macOS 26.3 + Chrome Canary 150.0.7844.0 でも `scan` 起動時に renderer がクラッシュすることを確認。Issue #7 (TCC 起因の Chrome 148 stable crash) とは独立のバグで、Chrome バージョン更新では解消しないため、本 patch は (上流が `watchAdvertisements` 呼出を gate するまで) 必須
- `tools/verify-vendored-patches.sh`: vendoring した patch の anchor (`[KUBI-PATCH]`) が消失していないかを検査する shell script。CI (`verify-patches` job) で実行
- `.gitattributes`: `third_party/**` を `linguist-vendored=true` に。GitHub の言語統計から除外し、PR diff で折りたたみ
- `third_party/universal_ble/KUBI-PATCH.md`: vendoring の理由・patch の所在・上流追従手順を記録
- README に "ベンダー依存" 節を追加し、運用ルールを文書化

### Deprecated
- (なし — 0.x 期間は破壊的変更を許容、deprecated の旅路は 1.0 以降開始)

### Security
- (なし)

### Migration Guide (v0.1.0-draft → v0.2.0-draft)

> 0.1.0-draft は未公開のため形式上の Migration Guide。実利用者は不在。

```dart
// Before (0.1.0-draft)
await kubi.moveTo(pan: 45, tilt: 10, speed: 80);
final pos = kubi.getCommandedPosition();  // 同期

// After (0.2.0-draft)
await kubi.moveTo(
  target: const PanTiltAngles(pan: 45, tilt: 10),
  spec: const MoveSpec.independent(speed: MoveSpeed.uniform(80)),
);
final pos = await kubi.getCommandedPosition();  // 非同期
```

---

## [0.1.0-draft] — 未公開

### Added
- 初期スキャフォールド
- 抽象 interface `KubiBle` (callback 形式)
- `KubiProtocol` (class、static メソッド)
- 基本型 (`KubiDevice` / `PanTiltAngles` / `MoveResult` / `MoveEvent`)
- エラー階層スケルトン
- 設計書 v0.1.0-draft

> 注: 0.1.0-draft は API 検討段階のため pub.dev には公開していない。
