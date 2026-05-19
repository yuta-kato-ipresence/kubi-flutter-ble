# kubi_flutter_ble

> Flutter package for controlling **Kubi** robotic devices over Bluetooth Low Energy (BLE).
> Cross-platform via [`universal_ble`](https://pub.dev/packages/universal_ble) — iOS / Android / macOS / Windows / Linux / Web。

**Status**: `v0.2.0-draft` 実装完了 + Web 実機検証済。他プラットフォーム実機検証 ([Issue #8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8)) は未消化、`pub.dev` 公開前です。

## できること

- **接続**: `scan` で周辺 Kubi を Stream 列挙、`connect` / `disconnect` で GATT 接続管理
- **操縦 (低レイテンシ)**: `setTarget` — ジョイスティック / スライダー用、latest-value buffer で BLE 帯域を浪費しない
- **到達待ち (スクリプト)**: `moveTo` — `MoveSpec.independent` / `.synced` + `SettleOptions` で「到達後に次の処理」を `Future` で await
- **位置観測**: `getCommandedPosition` / `getActualPosition` (1 shot) と `subscribePosition` (Stream、再帰 Timer で overlap 防止)
- **自動再接続**: `setAutoReconnect(AutoReconnectConfig)` — 線形バックオフ、`maxRetries` 到達で abandon
- **UI 統合**: `state` (`ValueListenable<KubiState>`) — `ValueListenableBuilder` で接続状態 + 位置 + 移動中 flag を 1 つの集約 view にバインド
- **観測性**: `onMove` (4-phase 移動イベント) / `onDebugEvent` (11 種、register read / poll skip / auto-reconnect 等)
- **型安全エラー**: `KubiBleError` を sealed class で階層化、Dart 3 の exhaustive switch 対応

## インストール

```yaml
dependencies:
  kubi_flutter_ble:
    git:
      url: https://github.com/yuta-kato-ipresence/kubi-flutter-ble.git
      ref: main
```

`pub.dev` 公開前のため、当面は git 依存で取得してください。

プラットフォーム別の必須権限・entitlement は **[`docs/platform-notes.md`](docs/platform-notes.md)** にまとめています (Android 12+ の `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`、iOS の `NSBluetoothAlwaysUsageDescription`、Web のユーザージェスチャー要件、等)。

## Quick Start

```dart
import 'package:kubi_flutter_ble/kubi_flutter_ble.dart';

final kubi = KubiBleImpl();

// 1) 最初に見つかった Kubi に接続
final device = await kubi.requestDevice(timeout: const Duration(seconds: 5));
if (device == null) return;
await kubi.connect(device);

// 2) 到達待ちで 45°/10° に動かす
final result = await kubi.moveTo(
  target: const PanTiltAngles(pan: 45, tilt: 10),
  spec: const MoveSpec.independent(speed: MoveSpeed.uniform(80)),
);
switch (result) {
  case MoveResultSettled(:final target):
    print('settled at $target');
  case MoveResultCancelled(:final target):
    print('cancelled before reaching $target');
}

// 3) UI に bind
ValueListenableBuilder<KubiState>(
  valueListenable: kubi.state,
  builder: (_, s, __) => Text(
    '${s.connectionState} commanded=${s.commanded} actual=${s.actual}',
  ),
);
```

より広い API カバレッジは **[`example/`](example/)** を参照 (公開 API 21 members を全て露出した検証用アプリ、起動してそのまま実機検証ハーネスとして使えます)。

## 進捗

API 設計 / 本実装 / ユニットテスト (7/7 pass) / example app / Web 実機検証は完了済。

残作業は [GitHub Issues](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues) を参照:

- **[#4](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/4)** v0.2.0 release preparation
- **[#8](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/8)** Device verification matrix (Android / iOS / macOS) — Web は ✅ 済
- **[#9](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/9)** `kubi-web-ble` 側仕様変更の追従棚卸し
- **[#5](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/5)** `MoveSpeed` 値域拡張 (kubi-ble v0.9 連携)
- **[#6](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/6)** 公式 `FakeKubiBle` 提供 (v0.3 以降)
- **[#7](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/7)** Web Bluetooth crash on Chrome 148 stable / macOS 26 (外部依存)

## アーキテクチャ

```
lib/
├── kubi_flutter_ble.dart          # 公開 API entry point (これだけ import すれば良い)
└── src/
    ├── kubi_ble.dart              # KubiBle abstract interface class (21 members)
    ├── kubi_ble_impl.dart         # universal_ble を使った実装 (約 1300 行)
    ├── kubi_protocol.dart         # GATT UUID / 補正テーブル / 数値変換 (package-private)
    ├── types/                     # immutable value types (sealed + final)
    └── errors/                    # KubiBleError sealed 階層
```

設計原則・各 type の選択理由・横断パターン (GATT lock / latest-value buffer / settle 検出 / cancel 伝搬 / 自動再接続 state machine / Stream セマンティクス) は [`docs/api-design.md`](docs/api-design.md) を参照。

## テスト

```bash
flutter test           # ユニットテスト (FakeUniversalBlePlatform 経由、7 ケース)
flutter analyze        # 0 error / 0 warning
cd example && flutter analyze   # 同上
```

利用者がアプリ側で widget test を書く場合、`KubiBle` は `abstract interface class` なので `mocktail` / `mockito` で mock できます。v0.2 ではパッケージ公式の Fake は同梱していません ([Issue #6](https://github.com/yuta-kato-ipresence/kubi-flutter-ble/issues/6) で v0.3 以降に検討)。

## ドキュメント

| 文書 | 担当範囲 |
|------|---------|
| dartdoc (`lib/src/**/*.dart`) | API シグネチャ・パラメータ・例外・Stream セマンティクス (SSOT) |
| [`docs/api-design.md`](docs/api-design.md) | 設計理由 / ユースケース U1-U5 / 横断パターン / バージョニングポリシー |
| [`docs/platform-notes.md`](docs/platform-notes.md) | OS 別の必須権限・既知制約・D-meta 実機検証チェックリスト |
| [`example/README.md`](example/README.md) | 検証用 example app の使い方と D-meta チェックリスト 1:1 対応 |
| [`CHANGELOG.md`](CHANGELOG.md) | バージョン間の差分・破壊的変更・採用/不採用の意思決定記録 |

**鉄則**: 同じ事実を 2 箇所に書かない (SSOT 原則、[`docs/api-design.md §2.1`](docs/api-design.md#21-ssot-原則))。

過去の設計議論ログ・調査記録は [`queue/`](queue/) 配下に歴史としてのみ保持しています (現役の正本ではありません)。

## 設計判断ハイライト

- **BLE ライブラリ**: `universal_ble` (6 platform 対応、内部 `BleCommandQueue` を `QueueType.perDevice` で活用)
- **Dart SDK**: `^3.11.0` (sealed class / pattern matching を活用、Dart 3 exhaustive switch でケース漏れをコンパイル時検出)
- **Stream-first**: callback registration は採らない、すべて `Stream<T>` で broadcast
- **集約状態**: `ValueListenable<KubiState>` を Flutter 一級市民拡張として本体 API に
- **GATT 直列化**: universal_ble の per-device queue に委譲。我々の self-lock は「moveTo cancel-on-newer」「`setTarget` latest-value buffer」「subscribe poll skip」のアプリ層ロジックのみ
- **不採用 TS API**: `experimentalSetAcceleration` 系 (実験 API、実機検証不足、主要 UC に不要)

## `kubi_flutter_plugin` との関係

本パッケージは旧 `kubi_flutter_plugin` を **新規開発向けに置き換える** ものです:

- `kubi_flutter_plugin`: maintenance mode (bug fix のみ、新機能停止)
- `kubi_flutter_ble`: 現行開発、modern API、Day 1 から cross-platform

## ベンダー依存 (`third_party/universal_ble`)

`universal_ble` を `third_party/universal_ble/` に **vendoring** し、`dependency_overrides` で差し替えています。
これは Web (Chrome) で `universal_ble` がスキャン時に呼ぶ `BluetoothDevice.watchAdvertisements()` が
**Chromium の renderer プロセスをクラッシュさせる既知バグ**を持っているためです
([WebBluetoothCG/web-bluetooth#538](https://github.com/WebBluetoothCG/web-bluetooth/issues/538))。
当該 API は Kubi のユースケース (ペアリング → connect → GATT) では不要なので skip します。

**差分はわずか 1 行**で、`return;` を 1 つ追加して `_watchDeviceAdvertisements` を no-op にするだけ。
詳細は [`third_party/universal_ble/KUBI-PATCH.md`](third_party/universal_ble/KUBI-PATCH.md) を参照してください。

### Patch の保護

`tools/verify-vendored-patches.sh` が patch の anchor (`[KUBI-PATCH] skip watchAdvertisements`)
を grep で検査します。CI (`.github/workflows/ci.yml` の `verify-patches` job) で毎回実行されるので、
上流追従時に patch を再適用し忘れると CI が落ちる仕組みです。

### 上流追従手順

新しい `universal_ble` のリリースに追従したくなったとき:

```bash
# 1. 新バージョン X.Y.Z を pub-cache に取らせる
(cd /tmp && rm -rf _ubup && mkdir _ubup && cd _ubup &&
  printf 'name: x\nenvironment: {sdk: ^3.0.0}\ndependencies: {universal_ble: ^X.Y.Z}\n' > pubspec.yaml &&
  dart pub get)

# 2. third_party/universal_ble を丸ごと差し替え
rm -rf third_party/universal_ble
cp -r ~/.pub-cache/hosted/pub.dev/universal_ble-X.Y.Z third_party/universal_ble

# 3. 1 行 patch を再適用
#    lib/src/universal_ble_web/universal_ble_web.dart の
#    _watchDeviceAdvertisements 関数の冒頭に下記を挿入:
#      return; // [KUBI-PATCH] skip watchAdvertisements — Chrome renderer crash bug (see third_party/universal_ble/KUBI-PATCH.md)
#      // ignore: dead_code

# 4. 検査
bash tools/verify-vendored-patches.sh
flutter pub get && (cd example && flutter pub get)
flutter analyze
```

差分はすべて単一 commit にまとめると、後で何が変わったかが `git log third_party/universal_ble/` で追えます。

### `third_party/` 配下に手を入れないこと

`third_party/universal_ble/` は KUBI-PATCH 以外、**手で変更しない**ルールです。
バグ修正や機能追加は本リポジトリ側 (`lib/`) で吸収するか、upstream に PR してください。

## License

BSD-3-Clause
