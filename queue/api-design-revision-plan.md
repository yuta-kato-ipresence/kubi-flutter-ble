# `docs/api-design.md` v0.2.0-draft 改訂計画

> **Status**: ドラフト中、レビュー待ち
> **Source of authority**: 本文書は「設計書をどう書き換えるか」のメタ計画であり、確定後は破棄してよい。

---

## 0. 改訂のゴール

ユーザー指示 (本セッション):

1. **大胆に Dart 文化へ最適化**してよい (TS API の機械的写しではない)
2. **SSOT 原則** — 実装方針・API 詳細を文書と実装の両方に書かない。実装の dartdoc を SSOT とし、設計書からは API カタログを排除する
3. **API 設計はユースケース起点で考える** (利用者の問題から逆算)
4. **横断的な実装パターン**を恒久的に文書化する (リファクタ時の指針として)
5. **全関連文書で整合性を取る** (README / queue/ / dartdoc / docs/)

---

## 1. 現状診断 (api-design.md v0.1.0-draft)

| 節 | 内容 | 問題 |
|---|---|---|
| §1 設計思想 | 3 行 | 浅い。Flutter 拡張ラベルなし、ユースケース観点なし |
| §2 アーキテクチャ図 | レイヤ図 | OK だが KubiState 抜け |
| §3 公開 API | メソッドシグネチャ列挙 | **SSOT 違反** — dartdoc と二重管理になる |
| §4 型定義 | コードブロック列挙 | **SSOT 違反** — class 定義の写し |
| §5 エラー階層 | コードブロック | **SSOT 違反** |
| §6 TS 対応表 | 表 | 価値あり、ただし v0.8 ベースに更新必須 |
| §7 使用例 | snippet | 価値あり、ただしユースケース別に拡充すべき |
| §8 今後の検討事項 | KubiState / Riverpod / Web | C5 で KubiState は本体採用 → §8.1 廃止。Riverpod は example 移譲、Web は platform-notes (Phase 2.5) 移譲 |

加えて、本セッションで決定した B/C/D 系 30+ 項目 (`queue/v0.8-alignment-review.md` 正本) が一切反映されていない。

---

## 2. 改訂後の役割定義 (SSOT マトリクス)

| 文書 / コード | SSOT として担う範囲 |
|---|---|
| `lib/src/**/*.dart` の **dartdoc** | API シグネチャ・パラメータ意味・例外・スレッド/Stream セマンティクス |
| `docs/api-design.md` (改訂後) | **設計理由 / ユースケース / 横断パターン / プラットフォーム前提 / TS との関係** |
| `docs/servo-spec.md` (kubi-ble 側、参照) | GATT/レジスタの物理仕様 |
| `README.md` | 利用者エントリポイント (インストール → 最小例 → 関連リンク) |
| `queue/v0.8-alignment-review.md` | **議論ログ** (決定後も「なぜそう決めたか」の歴史として保持) |
| `queue/universal-ble-investigation.md` (Phase 2.5 新設) | universal_ble 動作確認結果、platform 別制約マトリクス |

**鉄則**: 同じ事実を 2 箇所に書かない。設計書から dartdoc に移管した内容は設計書側から削除する。

---

## 3. 改訂後の節構成案

```
# kubi_flutter_ble — 設計書 (v0.2.0-draft)

> **本書はユーザー向け API リファレンスではない**。API 詳細は dartdoc / pub.dev を参照。
> 本書は「なぜこの設計か」「どう使い分けるか」「どんなパターンで実装されているか」を恒久的に記録する。

## 1. パッケージのスコープ
1.1 解決する利用者の問題 (4 ユースケース)
   - U1: ジョイスティック / GUI スライダーで Kubi をリアルタイム操縦したい
   - U2: スクリプトから「特定角度に向けて、到達後に次の処理を続行」したい
   - U3: 接続が切れても自動で復帰する常駐アプリを書きたい
   - U4: UI に接続状態と現在角度を双方向 bind したい
1.2 非スコープ
   - LED / バッテリ / button (Custom Status service, v0.8+ で別途検討)
   - 加速度プロファイル (TS の experimentalSetAcceleration 系は採用しない)
   - 物理 1 台以外の同時管理 (シングル接続前提)

## 2. 設計原則
2.1 SSOT: API は dartdoc を見よ。本書は「設計理由」のみ
2.2 Stream-first: callback registration を排し、`Stream<T>` で StreamBuilder 直結
2.3 sealed + final class: MoveSpec / MoveResult / MoveSpeed / KubiBleError を Dart 3 exhaustive switch で型安全に
2.4 immutable value type: PanTiltAngles / PositionSnapshot / MoveEvent / BleDebugEvent / KubiState は @immutable + 手書き ==/hashCode
2.5 Flutter 一級市民拡張: `ValueListenable<KubiState>` を本体 API に昇格 (TS には存在しない、Flutter 専用)
2.6 fail-fast: TS の defensive fallback (JS 弱型由来) は踏襲せず ArgumentError で早期失敗

## 3. 参照する一次ソース
- kubi-ble (TypeScript v0.8): 仕様の正本。本パッケージは feature parity を目指す
- kubi-ble/docs/servo-spec.md: GATT / レジスタの物理仕様
- kubi_flutter_plugin: 旧実装。bug fix のみ。新規開発は本パッケージへ
- universal_ble: BLE 抽象化基盤。本パッケージはこのラッパー

## 4. ユースケース別 API ガイド
4.1 U1 (joystick): `setTarget` + 内部 latest-value buffer + GATT lock の役割分担
   - なぜ Future が即 resolve しないか (latest-value 圧縮の意味)
   - speed の与え方 (`MoveSpeed.uniform` / `.perAxis`)
4.2 U2 (await arrival): `moveTo` + `MoveSpec` + `SettleOptions`
   - independent vs synced の意思決定フロー
   - SettleTimeoutError の扱い
   - CancelToken の使いどころ (新しい moveTo で古いものをキャンセル可能)
4.3 U3 (auto-reconnect): `setAutoReconnect` + `tryAutoConnect`
   - Web (getDevices) と Native (getSystemDevices) の違いの吸収
   - permission がないとき null
4.4 U4 (UI bind): `state` (ValueListenable) + 個別 Stream の使い分け
   - **個別 Stream は素の Stream**。「現在値即 emit」が欲しい場合は `state` から取れ
   - `ValueListenableBuilder<KubiState>` 例
4.5 デバッグ: `BleDebugEvent` の各 type の意味と用途

## 5. 横断アーキテクチャパターン
5.1 並行制御
   - GATT lock: 全 write/read を直列化
   - latest-value buffer: 連続 setTarget を「最新だけ」に圧縮
   - 「lock 中に来た新しい moveTo は古い Future を MoveResultCancelled で resolve」
5.2 settle 検出
   - tolerance (LSB 単位) + polling 再帰 Timer (drift 防止)
   - `_lastObservedActual` 1 秒キャッシュで重複読み回避
5.3 listener 隔離
   - `_safeNotify` ヘルパで try/catch、throw は `BleDebugEventType.listenerError` に変換
   - 1 listener の例外が他 listener や本体ループを止めない
5.4 cancel 伝搬
   - CancelToken は AbortSignal 相当の最小 API (cancel / isCancelled / whenCancelled)
   - 古い moveTo は「新しい moveTo」「disconnect」「明示 cancel」のいずれでもキャンセル
5.5 自動再接続
   - 指数 backoff + max retry
   - state machine: scheduled → attempt → (success | failed → next attempt | abandoned)
   - 各遷移を BleDebugEvent で観測可能に

## 6. TS v0.8 との関係
6.1 機能 parity 表 (TS API → Dart API の対応、形が変わるもののみ列挙)
6.2 Dart 文化に寄せた意図的差異
   - callback → Stream (#3 で詳述)
   - JSON-ish object option → sealed class (MoveSpec)
   - Promise → Future
   - 1 段集約状態 KubiState (Flutter 拡張)
6.3 採用しない TS API
   - experimentalSetAcceleration / ServoAcceleration / REG.ACCELERATION / clampAcceleration
   - 理由: 加速度制御は実機検証なしの実験 API、Kubi v0.8 利用者の主要ユースケースに不要

## 7. プラットフォーム前提
- universal_ble マトリクスは `queue/universal-ble-investigation.md` (Phase 2.5) を参照
- 本書では「責務境界」のみ記述: 本パッケージは scan/connect/notify/write の thin wrapper、permission UI は提供しない

## 8. バージョニング / 互換性
- 0.x: 破壊的変更を許容 (本セッションの v0.2.0-draft も v0.1.0-draft からの破壊的変更)
- 1.0 への昇格条件: TS v1.0 リリース + 全 platform 実機検証完了

## 9. 関連文書のマップ
- §2 SSOT マトリクスを再掲、リンク集として
```

---

## 4. 削除する内容 (SSOT 違反、dartdoc に移管)

- §3.1 〜 §3.4 の全メソッドシグネチャ列挙 → dartdoc に移管
- §4.1 〜 §4.6 の全 class 定義列挙 → dartdoc に移管
- §5 のエラー階層コード列挙 → dartdoc に移管
- §8.1 KubiState 「今後の検討事項」 → §2.5 と §4.4 で本体採用として記述

設計書に残るコードブロックは「使用例 (実コード)」と「ユースケース解説の擬似コード」のみに絞る。

---

## 5. 関連文書の同時更新

| 文書 | 改訂内容 |
|---|---|
| `README.md` | Status 表更新 (Phase 2 ✅ → Design v0.2 確定)、Architecture 図に KubiState 追加、設計書/queue/ への正しいリンク |
| `lib/src/**/*.dart` | Phase 2 で全面書き換え。本書の SSOT 移管前提で **dartdoc を充実させる** |
| `queue/v0.8-alignment-review.md` | 改訂後の docs を反映、F 系 Phase 1 を完了マーク |
| `queue/universal-ble-investigation.md` | Phase 2.5 新設 (本改訂タイミングではスケルトンのみ) |

---

## 6. 確認したい論点 (レビュアー sub-agent への質問)

1. **本書のスコープは「設計理由・パターン・ユースケース」に絞ってよいか**? それとも「最小限の API overview」も残すべき (pub.dev の README から飛んでくる読者向け)?
2. **§4 ユースケース別 API ガイド** — 4 つで十分か。U5 として「複数 Kubi の管理」「カスタム scan filter」等を書くべきか?
3. **SSOT 鉄則を貫くと、設計書のメソッド名すら出さないことになる**が、それは読みにくくないか? どこまで「dartdoc を見よ」で済ませてよいか?
4. **§6.3 採用しない TS API** をここに書くと「将来採用したくなったら更新が必要」だが、別文書 (CHANGELOG / non-goals.md) に分離すべきか?
5. **`KubiState` を Flutter 拡張として first-class 公開**することの是非。TS 側に存在しないので feature parity の観点で議論余地あり

---

## 7. 進行手順

- [ ] 本書を `general-purpose` sub-agent (作成者バイアス排除のため文脈最小化) にレビュー依頼
- [ ] レビュー結果を本書末尾に追記、論点を解消
- [ ] `docs/api-design.md` を v0.2.0-draft として全面書き換え
- [ ] README.md を整合更新
- [ ] `queue/v0.8-alignment-review.md` の F-Phase 1 を完了マーク
- [ ] 本書を保持 (議論ログとして) または破棄 (確定後不要なら) を判断
