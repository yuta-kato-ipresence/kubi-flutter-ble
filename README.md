# kubi_flutter_ble

> **Status**: 🚧 Design phase complete. Implementation not yet started.

A modern Flutter BLE package for Kubi robotic devices.

This is a **ground-up rewrite** of `kubi_flutter_plugin` with:
- Cross-platform BLE support via `universal_ble` (iOS, Android, macOS, Windows, Linux, Web)
- Type-safe API using Dart 3 sealed classes and pattern matching
- Stream-based events for natural Flutter UI integration
- TS-side (`kubi-web-ble`) feature parity with Flutter-idiomatic design

## Current Status

| Phase | Status | Description |
|-------|--------|-------------|
| 0 | ✅ Complete | Repository scaffolding |
| 1 | ✅ Complete | API design v0.2.0-draft (`docs/api-design.md`、SSOT 原則準拠) |
| 2 | 🚧 Pending | 型定義刷新 / `kubi_protocol` top-level 化 / lint 調整 |
| 2.5 | 🚧 Pending | universal_ble 一括動作検証 (`queue/universal-ble-investigation.md`) |
| 3 | 🚧 Pending | `KubiBleImpl` 実装 + 実機検証 |
| 4 | 🚧 Pending | テスト・example app・`FakeKubiBle` 公式 fake |
| 5 | 🚧 Pending | 0.2.0 リリース |

設計議論の正本: [`queue/v0.8-alignment-review.md`](queue/v0.8-alignment-review.md) (B/C/D 全 30+ 項目決着済)

## Planned Features

- Physical arrival await (`moveTo`)
- Fire-and-forget with latest value buffer (`setTarget`)
- 4-phase move events via `Stream<MoveEvent>`
- GATT lock for burst safety
- Auto-reconnect and `tryAutoConnect`
- Register-based position reading (`getCommandedPosition` / `getActualPosition`)
- Type-safe error hierarchy with sealed classes

## Architecture (Phase 2 完了後の想定)

```
lib/
├── kubi_flutter_ble.dart          # 公開 API entry point
├── testing.dart                   # FakeKubiBle 提供 (widget test 用)
└── src/
    ├── kubi_ble.dart              # KubiBle abstract interface
    ├── kubi_ble_impl.dart         # universal_ble 実装 (Phase 3)
    ├── kubi_protocol.dart         # GATT/プロトコル top-level 関数 (package-private)
    ├── types/                     # immutable value types
    │   ├── kubi_device.dart       # KubiDevice (id + name のみ)
    │   ├── pan_tilt_angles.dart
    │   ├── move_speed.dart        # sealed: MoveSpeed.uniform / .perAxis
    │   ├── move_spec.dart         # sealed: MoveSpec.independent / .synced
    │   ├── move_result.dart       # sealed: MoveResultSettled / Cancelled (target 必須)
    │   ├── move_event.dart        # 4 phase イベント
    │   ├── position_snapshot.dart # immutable class (Record ではない)
    │   ├── ble_debug_event.dart   # リッチフィールド + 11 種 enum
    │   ├── kubi_state.dart        # 集約 view (Flutter 拡張)
    │   ├── settle_options.dart
    │   ├── subscribe_position_options.dart
    │   ├── auto_reconnect_config.dart
    │   └── cancel_token.dart      # AbortSignal 相当の最小実装
    ├── errors/                    # sealed final class
    │   └── kubi_ble_error.dart
    └── testing/                   # テスト用 fake (export は lib/testing.dart 経由)
        └── fake_kubi_ble.dart
```

## ドキュメント / SSOT

| 文書 | 担当範囲 |
|------|---------|
| dartdoc (`lib/src/**/*.dart`) | API シグネチャ・パラメータ意味・例外・Stream セマンティクス |
| [`docs/api-design.md`](docs/api-design.md) | 設計理由 / ユースケース (U1-U5) / 横断パターン / バージョニングポリシー |
| [`CHANGELOG.md`](CHANGELOG.md) | バージョン間の差分・破壊的変更・採用/不採用の意思決定 |
| [`queue/v0.8-alignment-review.md`](queue/v0.8-alignment-review.md) | 設計議論ログ (B/C/D 全項目の Decision 履歴) |

**鉄則**: 同じ事実を 2 箇所に書かない (SSOT 原則、設計書 §2.1 参照)

## 設計判断ハイライト

- **BLE ライブラリ**: `universal_ble` (6 platform 対応、内部 command queue)
- **Dart SDK**: ^3.11.0 (Dart 3 sealed class / pattern matching を活用)
- **Stream-first**: callback registration は採らない、すべて `Stream<T>`
- **集約状態**: `ValueListenable<KubiState>` を Flutter 一級市民拡張として本体 API に
- **エラー階層**: `sealed class` + `final class` で exhaustive switch
- **テスト**: `FakeKubiBle` を公式提供、`mockito`/`mocktail` 不要
- **不採用 TS API**: `experimentalSetAcceleration` 系 (実験 API、主要 UC に不要)

## Relationship to `kubi_flutter_plugin`

This package replaces `kubi_flutter_plugin` for new development:
- `kubi_flutter_plugin`: Maintenance mode only (bug fixes, no new features)
- `kubi_flutter_ble`: Active development, modern API, cross-platform from day one

## License

BSD-3-Clause
