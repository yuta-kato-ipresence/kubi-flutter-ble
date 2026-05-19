# docs honesty cleanup (Phase 5 準備)

> **Status**: ✅ 完了 (`docs: align all documents with implementation (Phase 5 prep)` commit)
> FakeKubiBle 撤回路線で決着 → skeleton 削除、Issue #6 で v0.3 以降に再評価。
> 詳細は本ファイル末尾の §5 DoD チェックリスト参照。

> Phase 1〜4 完了後、全文書を実装と一致させるための整理計画。
> 「実装との一致」「正直さ」「第三者がゼロから読める」の 3 原則で進める。

---

## 0. 現状サマリー (2026-05 時点)

- 実装: `lib/src/kubi_ble_impl.dart` (約 1300 行)、TS web-kubi-ble v0.8 完全移植済
- テスト: `test/kubi_ble_impl_test.dart` 7/7 pass
- example: `example/lib/main.dart` を全 API 露出版に拡張済 (約 930 行)、`example/README.md` 新設済
- `flutter analyze` 0 error/0 warning (本体 + example 両方)
- 直近コミット: `3c0b471` (Phase 4 完了時点)

---

## 1. 文書の嘘 / 古文インベントリ

### 1.1 `README.md` (96 行) — **全面リライト要**

| 箇所 | 嘘・古文 | 修正方針 |
|------|--------|---------|
| L3 | "Status: 🚧 Design phase complete. Implementation not yet started." | 実装完了 (v0.2.0-draft) を明示 |
| L17-23 Phase 表 | Phase 2/2.5/3/4/5 全部 🚧 Pending | Phase 1-4 ✅、Phase 5 (実機検証 + 0.2.0 release) のみ未消化 |
| L25 | 「設計議論の正本: queue/v0.8-alignment-review.md」 | 「正本」表現は **設計書 (api-design.md) の権限を侵食**。queue は「設計議論ログ (歴史)」に格下げ |
| L27 "## Planned Features" | 実装済の機能を「予定」と書いている | "## Features" にして実装済を列挙 |
| L37 "## Architecture (Phase 2 完了後の想定)" | 既に現状 | "Architecture" に変更 + 各注記 ("Phase 3") を削除 |
| L46 注記 "(Phase 3)" | 同上 | 削除 |
| L67-74 ドキュメント表 | OK だが第三者目線で example/README へのリンクが無い | example/README.md 追加 |
| L85 "FakeKubiBle を公式提供、mockito/mocktail 不要" | **嘘** (skeleton で全 method `UnimplementedError`) | FakeKubiBle 決着方針に合わせて修正 (§3 参照) |

加えて、第三者ゼロ読みのために以下を新設すべき:
- 何ができるパッケージかの 3 行サマリー
- Installation (pubspec.yaml に `kubi_flutter_ble:` を追加する手順)
- Quick Start (10 行で接続→moveTo)
- example/ への動線
- Testing (`flutter test`)

### 1.2 `docs/api-design.md` (510 行) — **実装一致 audit + リンク修正**

| 箇所 | 問題 | 修正 |
|------|------|------|
| §3.1 (L125) | `FakeKubiBle` を「テスト専用 in-memory fake」と紹介 | FakeKubiBle 決着に合わせる (§3) |
| §3.2 (L131) | `scan({Duration?, ScanFilter?})` の表記 | 実装は `scan({Duration? timeout})` のみ (ScanFilter は内部固定)。表記を `scan({Duration?})` に統一 |
| §3.7 (L175-183) エラー階層 | `BleCommandError` 派生に `BleRegisterReadTimeoutError` のみ | Phase 3 で追加した `BleProtocolError` を追記 |
| §4.5 U5 (L281-302) | 動かないコード例 (`fake.simulateError(...)`) | FakeKubiBle 決着に合わせる (§3) |
| §6.1 マトリクス (L407) | "FakeKubiBle (testing 用)" を採用済 API として記載 | 同上 |
| §7 (L431-438) | 検証ステータス全部 "未検証 (Phase 3)" | Phase 3 (実装) は完了。"実機検証 Pending (Phase 5)" に |
| §7 (L440) | `queue/universal-ble-investigation.md` 参照 | 実ファイル名 `queue/phase-2.5-universal-ble-investigation.md` |
| §9.2 SSOT マトリクス (L507) | 同じく `queue/universal-ble-investigation.md` 参照 | 同上 |

### 1.3 `docs/platform-notes.md` (124 行)

| 箇所 | 問題 | 修正 |
|------|------|------|
| L87 | 「以下を **Phase 4 の実機検証フェーズで消化する**」 | Phase 4 (example + 文書) は完了。実機検証は Phase 5 (D-meta フェーズ) として独立 |
| L120 | 「既知の TODO (Phase 4+)」 | "Phase 5+" or "v0.3+" |

内容自体は実装と一致しており、追加修正は不要。

### 1.4 `CHANGELOG.md` (110 行)

| 箇所 | 問題 | 修正 |
|------|------|------|
| L44 | "`parsePosition` ... `parseRegisterReadResponse` に置換予定、Phase 3 で実装と一体化" | 「置換済」に |
| 構造 | "### Added (実装、Phase 4)" (L53) が "### Added (実装、Phase 3)" (L57-72) より先にある | 時系列順 (Phase 3 → Phase 4) に並び替え |

### 1.5 `queue/v0.8-alignment-review.md` (1065 行)

| 箇所 | 問題 | 修正 |
|------|------|------|
| L1013 | "Phase 4 ✅ (部分)" | 「部分」の中身 (実機検証残) を明示。本体 (example + 文書) は完了 |

archive 戦略: 案 C (README から「設計議論ログ (歴史)」として明示してリンク維持) を推奨。
内容資産価値が高く (B/C/D 全 30+ 項目の Decision 履歴)、削除や別ディレクトリ化はリスクが多い。

---

## 2. `FakeKubiBle` 実態の確認

- `lib/src/testing/fake_kubi_ble.dart`: 118 行、全 method が `throw UnimplementedError()`
- `lib/testing.dart`: export entry は存在 (skeleton を export している)
- パッケージ内テストは `FakeUniversalBlePlatform` (`test/fake_universal_ble_platform.dart`) を使用しており、`FakeKubiBle` は **未使用**
- 役割: パッケージ「利用者」が自分のアプリの widget test を BLE 実機なしで書くため (mocktail の手作業 stub を省略)

---

## 3. `FakeKubiBle` 決着方針候補

| 案 | 内容 | コスト | 対 docs 影響 |
|----|------|--------|-------------|
| A 正直 | docs を「未提供、v0.3 で計画」と明記。§4.5 U5 のコード例は「現状は mocktail を使う」に書き換え。`testing.dart` export は skeleton のまま保持 (将来用 placeholder) | 30 分 | 設計書 §4.5 §3.1 §6.1 を全部書き換え、README §85 も同様 |
| B 実装 | 最低限機能する FakeKubiBle を実装 (in-memory state + simulate API)。docs はそのまま生かせる | 2-3 時間 + テスト追加 | docs は微修正で済む |
| C 棚上げ | skeleton 維持、docs に「Phase 5 で実装予定」と注記 | 15 分 | A と類似だが「予定」明示 |

**推奨**: A (正直路線)。理由:
- パッケージの将来 (社内専用 / pub.dev 公開) が未確定の現在、未実装機能を売りに載せるのは不誠実
- mocktail/mockito は Flutter 標準的、利用者は自前で十分対応可能
- 後日「やはり公式 fake を提供」となれば B に格上げ可能 (互換は壊さない、追加 API)

---

## 4. 作業順序の提案

依存関係を最小化した順 (各ステップで以降の判断材料が揃う):

1. **FakeKubiBle 決着方針確定** (ユーザー判断、§3 参照)
2. **`CHANGELOG.md`** 微修正 (L44 stale + Phase 3/4 順序)
3. **`docs/platform-notes.md`** Phase 番号修正 (Phase 4 → 5、TODO 章)
4. **`docs/api-design.md`** 実装一致化:
   - §3.2 ScanFilter 表記訂正
   - §3.7 エラー階層に `BleProtocolError` 追記
   - §7 検証ステータス更新 + ファイル名修正
   - §9.2 ファイル名修正
   - §3.1/§4.5/§6.1 FakeKubiBle 関連を §3 決定に合わせる
5. **`README.md` 全面リライト** (第三者ゼロ読み目線、上記すべての修正と整合)
6. **`queue/v0.8-alignment-review.md`** L1013 Phase 4 完了表記
7. **`example/README.md`** リンク先 (api-design / platform-notes) の整合最終確認
8. **`flutter analyze` + `flutter test`** 全部 0 error / 全 pass を再確認
9. **commit** "docs: align all documents with implementation (Phase 5 prep)"

---

## 5. 完了の定義 (DoD)

- [x] 全文書の "Phase X Pending" 記述が実態と一致 (Phase 1-4 ✅ / Phase 5 ⏳ のみ)
- [x] `FakeKubiBle` に関する記述がどの文書でも「実装の現状」と一致 — **撤回・削除路線で決着**。skeleton 削除 + Issue #6 でフォロー
- [x] api-design.md 内の **シグネチャ表記** が実装と一致 (ScanFilter / エラー階層 / etc)
- [x] 内部リンク (file path / anchor) がすべて生きている
- [x] README が第三者ゼロ知識で「何ができるか」「どう使うか」「どこに何があるか」を理解させる
- [x] `flutter analyze` 0 error / 0 warning (本体 + example)
- [x] `flutter test` 7/7 pass
