# kubi_flutter_ble — 設計書

> **Version**: 0.2.0-draft
> **Target SDK**: Dart ^3.11.0, Flutter ^3.32.0
> **Base**: kubi-web-ble (TypeScript) v0.8 API
>
> **本書は API リファレンスではない**。
> API シグネチャ・パラメータ意味・例外・Stream セマンティクスは **dartdoc (pub.dev / IDE) を SSOT** とする。
> 本書は **「なぜこの設計か」「どう使い分けるか」「どんなパターンで実装されているか」** を恒久的に記録する。

---

## 目次

1. [パッケージのスコープ](#1-パッケージのスコープ)
2. [設計原則](#2-設計原則)
3. [API surface map](#3-api-surface-map)
4. [ユースケース別ガイド](#4-ユースケース別ガイド)
5. [横断アーキテクチャパターン](#5-横断アーキテクチャパターン)
6. [TS v0.8 との関係](#6-ts-v08-との関係)
7. [プラットフォーム前提](#7-プラットフォーム前提)
8. [バージョニング・互換性ポリシー](#8-バージョニング互換性ポリシー)
9. [付録: 一次ソース / 関連文書](#9-付録-一次ソース--関連文書)

---

## 1. パッケージのスコープ

### 1.1 解決する利用者の問題 (ユースケース)

| ID | 利用者の目的 | 中核 API | 詳細 |
|----|-------------|----------|------|
| U1 | ジョイスティック / GUI スライダーで Kubi をリアルタイム操縦 | `setTarget` | [§4.1](#41-u1-リアルタイム操縦-setTarget) |
| U2 | 「特定角度に向けて、到達後に次の処理」をスクリプト実行 | `moveTo` + `MoveSpec` + `SettleOptions` | [§4.2](#42-u2-到達待ち付き-goto-moveto) |
| U3 | 接続が切れても自動復帰する常駐アプリ | `setAutoReconnect` + `tryAutoConnect` | [§4.3](#43-u3-自動再接続) |
| U4 | UI に接続状態と現在角度を双方向 bind | `state` (`ValueListenable<KubiState>`) | [§4.4](#44-u4-ui-bind-state) |
| U5 | アプリのウィジェットテストで Kubi を mock | `KubiBle` interface + `mocktail` 等 | [§4.5](#45-u5-テスト--モック) |

### 1.2 非スコープ (本パッケージは扱わない)

- **LED / バッテリ / button** — kubi-ble の Custom Status service。将来別途検討
- **加速度プロファイル** — TS の `experimentalSetAcceleration` 等は採用しない (理由 [§6.3](#63-採用しない-ts-api))
- **複数 Kubi の同時管理** — シングル接続前提。複数管理は呼び出し側で `KubiBle` インスタンスを並べる
- **permission UI** — universal_ble の責務。本パッケージは scan/connect/notify/write の thin wrapper

---

## 2. 設計原則

### 2.1 SSOT 原則

API のシグネチャ・パラメータ意味・例外・Stream セマンティクスは **dartdoc** が唯一の正本。
本書は「なぜそう設計したか / どう組み合わせるか」のみを書き、実装と二重管理しない。

**鉄則**: 本書からメソッド名を *narrative の中で* 出すのは可。
ただし `Future<MoveResult> moveTo({required double pan, ...})` のような **完全シグネチャ列挙は禁止**。

### 2.2 Stream-first

callback registration (`void Function() onX(listener)` 形式) は採らず、すべて `Stream<T>` で公開する。

理由:
- `StreamBuilder` / `await for` / `.transform` 等の Dart asynchronous primitives と直結
- subscription 解放が `StreamSubscription.cancel()` で統一、unsubscribe 関数の取り回し不要
- 複数購読・broadcast 制御を Dart 標準セマンティクスに委譲できる

[§5.6 Stream セマンティクス](#56-stream-セマンティクス) で詳述。

### 2.3 sealed + final class でコンパイル時保証

`MoveSpec` / `MoveSpeed` / `MoveResult` / `KubiBleError` は `sealed class` + `final class` 派生。
Dart 3 の exhaustive switch で「ケース漏れ」をコンパイル時検出する。

TS 版の discriminated union (`type MoveSpec = { kind: 'independent' } | { kind: 'synced' }`) を Dart の型システムに翻訳した結果、より強い保証になる。

### 2.4 immutable value type

`PanTiltAngles` / `PositionSnapshot` / `MoveEvent` / `BleDebugEvent` / `KubiState` は **`final class` + `package:meta` の `@immutable` + 手書き `==`/`hashCode`/`toString`**。

選択基準:
- **`final class`**: フィールドが意味的に名前を持ち、API stability が必要なもの (= 上記すべて)
- **`Record`**: ローカル一時値 / 内部 helper の戻り値。**公開 API には使わない** (`PositionSnapshot` を v0.1.0-draft で Record にしていたのは設計ミス、v0.2 で class 化)

`Uint8List` 等の参照同値性しかない型を含む場合は `package:collection` の `ListEquality` または `Object.hashAll` を使う。

### 2.5 Flutter 一級市民拡張: `KubiState` + `ValueListenable`

`KubiBle` には `ValueListenable<KubiState> get state` を提供する。
`KubiState` は `connectionState / commanded / actual / isMoving / lastError` を集約した immutable snapshot。

> **Flutter 拡張ラベル**: TS 版に対応する API はない。
> ただし `state` の中身は `connectionStateStream` / `subscribePosition` / `onMove` / `onDebugEvent` の各 Stream で観測可能な情報の **集約 view** であり、二重事実源ではない。
> 内部実装は `ValueNotifier<KubiState>` 1 つを各 Stream の listener から `copyWith` 更新する単純な fan-in。

採用理由:
- Flutter UI 統合 (`ValueListenableBuilder`) と直結する慣習に合わせる
- 「現在の接続状態と現在角度を一画面に出す」が UC4 の現実。Stream を 4 本 listen して個別 setState するのは Flutter 文化に逆行

### 2.6 fail-fast

TS の defensive fallback (JS 弱型由来の `if (typeof x !== 'number') return null` 等) は **踏襲しない**。
Dart の型システム + `assert` + `ArgumentError` で早期失敗する。

### 2.7 Visibility & maturity アノテーション

`package:meta` の以下を運用する:

- `@experimental` — API は将来変更予定、利用は自己責任
- `@internal` — package 外から使うべきでない (export しないことで担保するのが第一手段、`@internal` は補助)
- `@Deprecated('use X instead. Removed in v1.0.')` — 廃止予定。最低 1 minor version は残す ([§8](#8-バージョニング互換性ポリシー))

---

## 3. API surface map

> 本節は **「どこから読み始めるか」の地図** であり、シグネチャは **dartdoc を見よ**。
> 各 symbol に対する詳細 (パラメータ・戻り値・例外・スレッド/Stream セマンティクス) は対応する `lib/src/**/*.dart` の dartdoc が SSOT。

### 3.1 中核インターフェース

| Symbol | 役割 | 詳細リンク |
|--------|------|-----------|
| `KubiBle` (`abstract interface class`) | 公開 API の窓口。テストでは `mocktail` 等で mock 可能 ([U5](#45-u5-テスト--モック)) | `lib/src/kubi_ble.dart` |
| `KubiBleImpl` | universal_ble を使った実装。production はこれを `new` する | `lib/src/kubi_ble_impl.dart` |

### 3.2 接続・ライフサイクル

| Symbol | 用途 | UC |
|--------|------|----|
| `scan({Duration?})` (`Stream<KubiDevice>`) | 周辺の Kubi を逐次列挙 (利用者が UI で選ぶ場合)。`ScanFilter(withNamePrefix: ['kubi'])` は内部固定 | U1-U4 初回接続 |
| `requestDevice({Duration timeout = 5s})` | scan の最初の 1 件を返す convenience | U1-U4 初回接続 |
| `connect(KubiDevice)` | GATT 接続 | 全 UC |
| `disconnect()` | 明示切断 | 全 UC |
| `setAutoReconnect(...)` / `tryAutoConnect()` | 自動再接続。Web は常に null を返す (D5、`queue/phase-2.5-universal-ble-investigation.md`) | U3 |
| `connectionStateStream` (`Stream<ConnectionStateEvent>`) | 状態遷移 + `DisconnectReason?` + `timestamp` | U4 |
| `currentConnectionState` (sync) | 同期取得 | 任意 |
| `availabilityStream` (`Stream<BleAvailability>`) | OS BLE adapter の可用性 ([§5.8](#58-availability-監視)) | U4 |

### 3.3 動作 (write)

| Symbol | 用途 | UC |
|--------|------|----|
| `setTarget(...)` | Fire-and-forget、latest-value 圧縮 | U1 |
| `moveTo(target: PanTiltAngles, spec: MoveSpec, settle: SettleOptions, cancel: CancelToken)` | 物理到達 await | U2 |
| `setDefaultSpeed(...)` / `defaultSpeed` getter | 既定速度 | 任意 |

### 3.4 観測 (read)

| Symbol | 用途 | UC |
|--------|------|----|
| `getCommandedPosition()` (`Future`) | Goal Position レジスタ (0x1e) | U2 検証 |
| `getActualPosition()` (`Future`) | Present Position レジスタ (0x24) | U2 検証 |
| `waitUntilSettled(...)` | 物理到達 polling | `moveTo` 内部、利用者直接呼び出しも可 |
| `subscribePosition(SubscribePositionOptions)` (`Stream<PositionSnapshot>`) | 位置の定期購読 | U4 |

### 3.5 イベント

| Symbol | 用途 |
|--------|------|
| `onMove` (`Stream<MoveEvent>`) | 4 phase 移動イベント (start / commanded / settled / cancelled) |
| `onDebugEvent` (`Stream<BleDebugEvent>`) | 観測・診断イベント ([§4.6](#46-デバッグ--observability)) |
| `state` (`ValueListenable<KubiState>`) | UI bind ([§4.4](#44-u4-ui-bind-state)) |

### 3.6 値型・列挙

`PanTiltAngles` / `KubiDevice` / `PositionSnapshot` / `MoveEvent` / `BleDebugEvent` / `KubiState` / `ConnectionStateEvent` /
`MoveSpeed` (sealed) / `MoveSpec` (sealed) / `MoveResult` (sealed) /
`SettleOptions` / `SubscribePositionOptions` / `AutoReconnectConfig` / `CancelToken` /
`BleConnectionState` (enum) / `DisconnectReason` (enum) / `MovePhase` (enum) / `BleDebugEventType` (enum) / `PositionSource` (enum) / `BleAvailability` (enum)

### 3.7 エラー階層 (sealed)

```
KubiBleError (sealed)
 ├─ BleUnavailableError
 ├─ BleUserCancelledError
 ├─ BleConnectionError
 ├─ BleNotConnectedError
 ├─ BleCommandError
 │   ├─ BleRegisterReadTimeoutError
 │   └─ BleProtocolError
 └─ BleSettleTimeoutError
```

すべて `final class`、`@immutable`、Dart 3 exhaustive switch 対応。

### 3.8 protocol 内部 (非公開)

`lib/src/kubi_protocol.dart` の top-level 関数 (servoAngle / panVelocity / etc) と GATT UUID 定数群は **package-private** (export しない)。
利用者がプロトコル直叩きすべきユースケースは想定しない。

---

## 4. ユースケース別ガイド

### 4.1 U1 リアルタイム操縦 (`setTarget`)

**典型**: ゲームパッドや画面スライダーから 1 秒間に 30〜60 回値が来る。

```dart
joystick.onChanged.listen((axis) {
  kubi.setTarget(
    target: PanTiltAngles(pan: axis.x * 150, tilt: axis.y * 30),
    speed: const MoveSpeed.uniform(80),
  );
});
```

**設計判断**:

- `setTarget` は **fire-and-forget**。返り値の `Future` は「BLE write が ack された時点」で resolve するが、**通常は await しない**
- 連続呼び出しは内部の **latest-value buffer** で「最新だけ」に圧縮される ([§5.1](#51-並行制御))。古い中間値が GATT に詰まらない
- `MoveSpec` は指定不要 (`independent` 既定)。同期動作が要るケースは U2 が普通

**よくある誤用**:
- `await kubi.setTarget(...)` を 60Hz でブロック → BLE 帯域に律速されて入力遅延。ack を待つな

### 4.2 U2 到達待ち付き GoTo (`moveTo`)

**典型**: 「正面を向いて → 写真撮影 → 横を向く」のような順次スクリプト。

```dart
final result = await kubi.moveTo(
  target: const PanTiltAngles(pan: 0, tilt: 0),
  spec: const MoveSpec.synced(maxSpeed: 60),  // pan/tilt が同時に到達
  settle: const SettleOptions(timeoutMs: 5000),
);
switch (result) {
  case MoveResultSettled(:final actual, :final target):
    // 到達検出 (tolerance 内)
  case MoveResultCancelled(:final target):
    // 新しい moveTo / disconnect / cancel token のいずれかでキャンセル
}
```

**設計判断**:

- `MoveSpec.independent` (各軸独立) と `.synced` (両軸同時到達のため slow 軸基準で速度配分) を **sealed factory** で排他化
- `SettleOptions` は polling interval / tolerance (servo LSB 単位) / timeout を指定可能。指定しなければ各 default 定数 ([B16] 参照)
- `cancel: CancelToken?` で外部キャンセル可能。`cancel.cancel()` で `MoveResultCancelled` が即返る
- `MoveResultSettled` / `MoveResultCancelled` のどちらも `target` を持つ。「キャンセルされた時の意図された target」が UI で必要だから

### 4.3 U3 自動再接続

```dart
kubi.setAutoReconnect(const AutoReconnectConfig(
  maxRetries: 5,
  retryDelay: Duration(milliseconds: 500),
));
// 無効化したい場合: kubi.setAutoReconnect(null);
final restored = await kubi.tryAutoConnect();  // 起動時、過去接続済デバイスへ
```

**設計判断**:

- `tryAutoConnect` は Native で `UniversalBle.getSystemDevices(withServices: [servoServiceUuid])` を呼ぶ
- <a id="d5-web-tryautoconnect"></a>**Web 既知制約 (D5)**: universal_ble v1.2.0 は `navigator.bluetooth.getDevices()` を wrap していないため、Web の `tryAutoConnect()` は **常に `null` を返す** (利用者は `requestDevice()` か `scan()` から再選択する)。Web 対応は v0.x の non-goal ([§6.3](#63-対応しない-non-goals))
- permission がないとき、または該当デバイスがない場合は `null` を返す (例外ではない、「探したが居ない」は正常系)
- 自動再接続中の挙動 (scheduled / attempt / success / failed / abandoned) は `BleDebugEvent` で完全観測可能 ([§4.6](#46-デバッグ--observability))

### 4.4 U4 UI bind (`state`)

```dart
ValueListenableBuilder<KubiState>(
  valueListenable: kubi.state,
  builder: (_, s, __) => Column(children: [
    Text('Connection: ${s.connectionState.name}'),
    Text('Pos: ${s.actual ?? s.commanded ?? "-"}'),
    if (s.isMoving) const CircularProgressIndicator(),
    if (s.lastError != null) Text('Error: ${s.lastError}', style: errorStyle),
  ]),
)
```

**設計判断**:

- 個別 Stream (`connectionStateStream` / `subscribePosition` / `onMove` / `onDebugEvent`) を 4 本 listen するのは Flutter UI として煩雑。`KubiState` 1 つに集約 view を提供する
- 個別 Stream は **「現在値即 emit」しない素の Stream**。current value が欲しい場合は `state` getter から取る、という責務分担
- TS 側に対応物なし。**Flutter 拡張**として明示 ([§2.5](#25-flutter-一級市民拡張-kubistate--valuelistenable))

### 4.5 U5 テスト / モック

`KubiBle` は `abstract interface class` なので、利用者は `mocktail` / `mockito`
で mock を作成できる:

```dart
// widget test で KubiBle を mocktail で mock
class _FakeKubiBle extends Mock implements KubiBle {}

testWidgets('shows error on connection failure', (tester) async {
  final fake = _FakeKubiBle();
  when(() => fake.connectionStateStream).thenAnswer((_) => Stream.value(
    ConnectionStateEvent(
      state: BleConnectionState.disconnected,
      reason: DisconnectReason.error,
      timestamp: DateTime.now(),
    ),
  ));
  // ...
});
```

**設計判断**:

- `KubiBle` を `abstract interface class` にしている最大の動機の一つはモッカビリティ。
  Dart 3 では interface class 経由で `implements` 側に **すべての member を実装する義務** が
  生じるので、interface の追加変更がテストコード側で必ず検出される
- v0.2 ではパッケージ公式の `FakeKubiBle` は **提供しない**。理由:
  - 21 members + 6 Stream + `ValueListenable` を正しく simulate する Fake は約 300-500 行
    の独立した実装と保守が必要
  - 実機検証 (Phase 5) で観測される接続シーケンス / move レイテンシ / debug event 順序
    が固まる前に Fake を確定させると、widget test が green でも実機と乖離する最悪パターンを誘発する
  - 当面は `mocktail` で利用者個別 stub。21 members の手書きは確かに冗長だが、
    必要なメソッドだけ stub する方が `MoveSpec.synced` のような分岐を網羅するより簡潔
- 将来の公式 Fake は Issue #6 で追跡。Phase 5 完了後にユーザー要望と実機挙動の両方が揃った時点で再評価

### 4.6 デバッグ / observability

`onDebugEvent` (`Stream<BleDebugEvent>`) は内部状態遷移を全て観測可能にする。
`BleDebugEventType` enum で 11 種類分類 (notificationRaw / registerRead / registerReadTimeout / pollSkipped / listenerError / connectionStateChange / autoReconnectScheduled / Attempt / Success / Failed / Abandoned)。

利用シナリオ:
- 開発中: `kubi.onDebugEvent.listen(print)` で全イベントログ
- production: `listenerError` のみ Sentry 等に送信、他は破棄
- 自動再接続の挙動可視化: `autoReconnect*` 系を UI のステータスバーに出す

---

## 5. 横断アーキテクチャパターン

> 本節は実装方針の **不変な抽象** を記録する。
> 実装詳細 (private メソッド名・キャッシュ秒数等) は dartdoc / source code が SSOT。本節は変えにくい設計判断のみ。

### 5.1 並行制御

- **GATT lock (薄い)**: write/read の直列化は **`universal_ble` 内蔵の `BleCommandQueue` に委ねる** (D2 / `queue/phase-2.5-universal-ble-investigation.md`)。`KubiBleImpl` の constructor で `UniversalBle.queueType = QueueType.perDevice` を設定する。我々の self-lock は「moveTo cancel-on-newer」「latest-value buffer」「subscribe poll skip」のような **アプリケーション層のロジック** にだけ持つ
- **latest-value buffer**: lock 取得待ち中の `setTarget` は「最新値だけ」に上書きされ、中間値は drop。joystick UC で BLE 帯域を浪費しない
- **moveTo の cancel-on-newer**: 新しい `moveTo` または `setTarget` 到来で進行中の `moveTo` Future は `MoveResultCancelled` で resolve。古い command を絶対に上書きしない

### 5.2 settle 検出

- tolerance (servo LSB 単位、既定 [B16] 参照) で「到達」を判定
- polling は **再帰 Timer** (Timer.periodic ではない)。前回完了後に次を schedule することで drift と overlap を防ぐ
- `actual` レジスタの直前読み値を短時間キャッシュし、subscribe との競合を避ける

### 5.3 listener 隔離

任意の Stream listener が throw しても、**他 listener / 内部ループに伝播させない**。
throw された例外は `BleDebugEventType.listenerError` の `BleDebugEvent` として観測可能化する。

理由: 1 利用者の bug で BLE 通信全体が止まる事故を防ぐ。Flutter UI で onError を握りつぶすコードを書かれても安全。

### 5.4 cancel 伝搬

`CancelToken` は AbortSignal 相当の最小 API (`cancel()` / `isCancelled` / `Future<void> get whenCancelled`)。
`Completer<void>` ベースの薄い実装。

伝搬経路: 利用者が `cancel.cancel()` → token の future complete → `moveTo` 内 polling ループが `whenCancelled` race で抜ける → `MoveResultCancelled` 返却。

### 5.5 自動再接続

state machine:

```
idle ─(disconnect 検出)→ scheduled ─(delay)→ attempt
attempt ─(成功)→ idle (発火: success)
attempt ─(失敗 & retry < max)→ scheduled (発火: failed)
attempt ─(失敗 & retry == max)→ abandoned
```

- 各遷移で `BleDebugEvent.autoReconnect*` を発火
- backoff は **線形** (`retryDelay × attempt`、1-based)。指数バックオフは採用しない (B3 Decision、kubi-ble TS と挙動一致)
- abandoned 後は `tryAutoConnect()` の手動呼び出しが必要

### 5.6 Stream セマンティクス

すべての公開 Stream に共通する規約:

- **broadcast** (複数購読可能、購読数ゼロでも内部 listen を維持しない設計は採らない — 内部 source は一つ)
- **購読時の現在値即 emit はしない**。current value が欲しい場合は対応する getter (`currentConnectionState` / `state.commanded` 等) から取得
- **エラーは `addError` で配信、Stream は close しない**。recoverable な BLE エラーで購読が切れたら UI が壊れる
- **Stream が close するのは `disconnect()` 後のクリーンアップ時のみ**
- `cancel()` で内部リソースを解放する subscription は明示する (例: `subscribePosition` の Timer)

### 5.7 値型の `==` / `hashCode`

すべての immutable value type (`@immutable`) は手書き `==`/`hashCode`/`toString`。
`equatable` パッケージは production 依存を増やすため使わない。
`Uint8List` 等のフィールドは `Object.hashAll` + `package:collection` の `ListEquality` で内容比較。

### 5.8 Availability 監視

`UniversalBle.availabilityStream` (= `Stream<AvailabilityState>`) を `KubiBleImpl` constructor で listen する。

- 接続前に `unsupported` / `unauthorized` / `poweredOff` を検知 → `connect()` は `BleUnavailableError` を即 throw
- **接続中に `poweredOff` / `unauthorized` / `resetting` を検知 → 内部 `disconnect()` を呼び `ConnectionStateEvent(state: disconnected, reason: deviceLost)` を emit**
- 自動再接続が有効でも、`unsupported` / `unauthorized` の間は abandon (BLE 自体が無効なため意味なし)
- 公開 `availabilityStream` は `BleAvailability` enum (universal_ble の 6 値を rewrap、外部依存を漏らさない) で配信

設計判断: TS 版に対応物なし、これも **Flutter 拡張** ([§2.5](#25-flutter-一級市民拡張-kubistate--valuelistenable))。Flutter の OS 統合観点で、Bluetooth が突然 OFF になるシナリオを UI から扱えるよう公式サポートする。

---

## 6. TS v0.8 との関係

### 6.1 機能 parity マトリクス (形が変わるもののみ)

| TS 版 | Dart 版 | 変更理由 |
|-------|---------|---------|
| `onConnectionStateChange(cb)` | `connectionStateStream` (`Stream<ConnectionStateEvent>`) | Stream 化 + `DisconnectReason` enum + timestamp 必須 (B2) |
| `onMove(cb)` | `onMove` getter (`Stream<MoveEvent>`) | 同上 |
| `onDebugEvent(cb)` | `onDebugEvent` getter (`Stream<BleDebugEvent>`) | 同上 |
| `subscribePosition(opts, cb)` | `subscribePosition(opts)` (`Stream<PositionSnapshot>`) | 同上 + Stream cancel で polling 停止 |
| `MoveSpeed = number \| {pan,tilt}` | `sealed class MoveSpeed` + factory | Dart 3 exhaustive switch |
| `MoveSpec = {sync?, maxSpeed?}` | `sealed class MoveSpec` + factory | independent/synced 排他をコンパイル時保証 |
| `MoveResult = {settled, ...}` | `sealed class MoveResult` | 同上 |
| `AbortSignal` (Web 標準) | `CancelToken` (自前最小) | Dart に AbortSignal 相当の標準型がない |
| `MoveOptions.signal` | `moveTo(cancel: CancelToken?)` | named param で意図明示 |
| `Promise<T>` | `Future<T>` | 言語標準 |
| (なし) | `state` (`ValueListenable<KubiState>`) | Flutter 拡張 ([§2.5](#25-flutter-一級市民拡張-kubistate--valuelistenable)) |

### 6.2 採用する TS 設計判断

- GATT lock + latest-value buffer による並行制御 ([§5.1](#51-並行制御))
- 補正テーブル (PAN/TILT_VELOCITY_TABLE) を完全コピー (実機検証済の値)
- 4 phase MoveEvent (start / commanded / settled / cancelled)
- subscribePosition の 3 工夫 (Timer 再帰化 / actual キャッシュ / batch atomic read)

### 6.3 採用しない TS API

| API | 不採用理由 |
|-----|-----------|
| `experimentalSetAcceleration` / `ServoAcceleration` / `REG.ACCELERATION` / `clampAcceleration` | 実験 API、実機検証不足、Kubi v0.8 利用者の主要 UC に不要 |

> **運用ルール**: 不採用 API が 5 件を超えたら `docs/non-goals.md` に分離する。
> CHANGELOG には採用/不採用の意思決定を必ず記載する。

---

## 7. プラットフォーム前提

本パッケージは `universal_ble` の薄いラッパーである。

「動作対象」(コードパスが存在する) と「保証対象」(`kubi_flutter_ble` 側で検証・サポートする) を分けて整理する。

| Platform | universal_ble サポート | 動作対象 (コード) | 保証対象 (検証) |
|----------|----------------------|------------------|----------------|
| Android | ✅ | full | 未検証 ([Issue #8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8)) |
| iOS | ✅ | full | 未検証 ([Issue #8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8))。Safari / Mobile Chrome は Web Bluetooth 未実装、Bluefy 必須 |
| macOS | ✅ | full | 未検証 ([Issue #8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8)) |
| Web | ✅ | Web Bluetooth API、scan は `requestDevice` のみ。`tryAutoConnect` は常に null (D5) | Chrome Canary 150 + macOS 26.3 で ✅ 済。他環境は [Issue #8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8)。macOS 26 + Chrome ≤ 148 stable は [Issue #7](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/7) |
| Windows | ✅ | universal_ble v1.2.0 では limited (Tier-2 扱い、`docs/platform-notes.md` 参照) | 保証対象外 |
| Linux | ✅ | universal_ble v1.2.0 では BlueZ 経由で limited (Tier-2 扱い) | 保証対象外 |

詳細な制約マトリクス (Web の `withServices` 必須要件 / Native の permission / `getSystemDevices` の挙動 / write with-response 強制等) は `queue/phase-2.5-universal-ble-investigation.md` (歴史・調査ログ) を参照。
プラットフォーム別の権限設定・既知制約は **`docs/platform-notes.md`** が SSOT、実機検証進捗は **[Issue #8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8)** が canonical。

本パッケージは:
- permission UI を提供しない (利用側で `permission_handler` 等を併用)
- universal_ble の API ギャップを埋める shim は最小限。「universal_ble が落ちたら本パッケージも落ちる」設計

---

## 8. バージョニング・互換性ポリシー

### 8.1 セマンティック・バージョニング

- **0.x**: 破壊的変更を許容 (実装中。本書 v0.2.0-draft も v0.1.0-draft からの破壊的変更)
- **1.0 への昇格条件**:
  1. TS 版 (kubi-ble) v1.0 リリース
  2. iOS / Android / Web の実機検証完了
  3. CHANGELOG が完備、API surface 凍結

### 8.2 deprecation policy

- 廃止予定 API には `@Deprecated('use X instead. Removed in vN.')` を付与
- **最低 1 minor version は残す** (例: v0.5 で deprecated → v0.6 では残存 → v0.7 で削除)
- 1.0 以降は最低 2 minor version は残す
- `dart fix` 対応のため `migrate_to:` ヒントを dartdoc に書く

### 8.3 Minimum Supported Dart/Flutter Version (MSDV)

- Dart `^3.11.0` / Flutter `^3.32.0` (現在の latest stable)
- MSDV の引き上げは minor version で許容、必ず CHANGELOG に明記
- universal_ble の MSDV と歩調を合わせる

### 8.4 CHANGELOG 運用

- [Keep a Changelog](https://keepachangelog.com/) 準拠
- カテゴリ: Added / Changed / Deprecated / Removed / Fixed / Security
- pub.dev のスコア要件 (CHANGELOG.md 存在 + バージョン記載) を満たす

### 8.5 破壊的変更の告知

- CHANGELOG に **必ず** Migration Guide セクションを書く
- `queue/` は議論ログ専用、利用者向け告知には使わない
- 1.0 以降で major bump の規模が大きい場合は別途 `docs/migration/vN.md` の新設を検討する (0.x 期間は CHANGELOG 内で完結)

---

## 9. 付録: 一次ソース / 関連文書

### 9.1 一次ソース

| ソース | 役割 |
|-------|------|
| **kubi-ble** (TypeScript v0.8) | API 仕様の正本。本パッケージは feature parity を目指す |
| **kubi-ble/docs/servo-spec.md** | GATT / レジスタの物理仕様 |
| **kubi_flutter_plugin** | 旧 Flutter 実装。bug fix only、新規開発は本パッケージへ |
| **universal_ble** | BLE 抽象化基盤 |

### 9.2 SSOT マトリクス

| 文書 / コード | SSOT として担う範囲 |
|---|---|
| `lib/src/**/*.dart` の **dartdoc** | API シグネチャ・パラメータ意味・例外・Stream セマンティクス |
| `docs/api-design.md` (本書) | 設計理由 / ユースケース / 横断パターン / プラットフォーム前提 / TS との関係 / バージョニングポリシー |
| `lib/src/kubi_protocol.dart` の dartdoc | プロトコル数値変換ロジック (補正テーブル等) の意味 |
| `docs/platform-notes.md` | OS 別の必須権限・既知制約 (実機検証進捗は [Issue #8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8) が canonical) |
| `third_party/universal_ble/KUBI-PATCH.md` | vendoring patch の根拠と A/B 検証ログ |
| kubi-ble/docs/servo-spec.md (参照) | GATT / レジスタの物理仕様 |
| `README.md` | 利用者エントリポイント (インストール → 最小例 → リンク集) |
| `CHANGELOG.md` | バージョン間の差分・破壊的変更・採用/不採用の意思決定記録 |
| `example/` | UC1〜U5 を 1:1 で動かすデモ |

### 9.3 歴史・調査ログ (SSOT ではない)

`queue/` 配下は **過去の設計議論・調査記録の保管庫**。現役の正本ではなく、「なぜそう決めたか」を後追いするための歴史として残している。

| ファイル | 範囲 |
|---|---|
| `queue/v0.8-alignment-review.md` | TS v0.8 整合レビュー (B/C/D 全 30+ 項目の Decision 履歴) |
| `queue/phase-2.5-universal-ble-investigation.md` | universal_ble v1.2.0 動作調査結果 / platform 別制約マトリクス |
| `queue/api-design-revision-plan.md` | 設計書改訂計画 (中立レビュアー条件付き Go の追跡) |
| `queue/docs-honesty-cleanup.md` | 文書整理計画 (Phase 5 prep 時のもの) |

**鉄則**: 同じ事実を 2 箇所に書かない。本書から dartdoc に移管した内容は本書側から削除する。
