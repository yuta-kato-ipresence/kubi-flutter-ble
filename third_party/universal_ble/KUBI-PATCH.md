# Vendored `universal_ble` — KUBI patch notes

このディレクトリは [`universal_ble`](https://pub.dev/packages/universal_ble) を **そのまま** vendoring した
コピーです (pub.dev 取得物の bit-for-bit クローン)。下記の **1 行 patch** だけが
オリジナルとの差分です。

## なぜ vendor + patch しているか

`universal_ble` の Web 実装は `startScan` 内で **無条件に
`navigator.bluetooth.BluetoothDevice.watchAdvertisements()` を呼ぶ** ところがあり、
これは Chromium の experimental Web Bluetooth API で renderer プロセス自体を
クラッシュさせる既知バグが存在する ([WebBluetoothCG/web-bluetooth#538][538],
[chromestatus #5180688812736512][cs])。

`watchAdvertisements()` は「ペアリング後にデバイスの advertisement を継続監視する」
ための拡張で、Kubi のユースケース (ペアリング → connect → GATT 通信) には不要。
そのため当該呼び出しを **skip** する 1 行 patch を当てている。

[538]: https://github.com/WebBluetoothCG/web-bluetooth/issues/538
[cs]: https://chromestatus.com/feature/5180688812736512

## A/B 検証ログ

将来「もう Chrome 側で直ったのでは？」と剥がしたくなった人 (= 未来の自分) のために、検証事実を記録する。

| 日付       | 環境                                                            | patch       | 結果                                     |
| ---------- | --------------------------------------------------------------- | ----------- | ---------------------------------------- |
| 2026-05-19 | macOS 26.3 (Tahoe) + Chrome Canary 150.0.7844.0                 | **無効化**  | `scan` 起動時に renderer プロセスがクラッシュ (タブが消える、console 出力なし) |
| 2026-05-19 | macOS 26.3 (Tahoe) + Chrome Canary 150.0.7844.0                 | **有効**    | 正常に scan / connect / GATT 通信が成立 |

つまり Chrome stable 148 で観測される **Issue #7 (TCC 起因の renderer kill)** と、本 patch が回避する **`watchAdvertisements` 由来 renderer crash** は **独立な 2 つのバグ**。
Chrome バージョンを 150 系に上げても後者は直っていない。

剥がしてよいかの再評価が必要になったら、上記同じ手順 (`return;` 行を一時無効化 → `flutter run -d chrome` → scan) を踏み、**クラッシュしないことを実機で確認してから** vendoring を撤去すること。

## ベースバージョン

- **`universal_ble` 1.2.0** (pub.dev hash `8325ca9f...`)

## Patch 一覧

### 1. `_watchDeviceAdvertisements` を no-op に

- **ファイル**: `lib/src/universal_ble_web/universal_ble_web.dart`
- **行**: `_watchDeviceAdvertisements` 関数の本体冒頭
- **追加内容** (2 行):

  ```dart
  Future<void> _watchDeviceAdvertisements(BluetoothDevice device) async {
    return; // [KUBI-PATCH] skip watchAdvertisements — Chrome renderer crash bug (see third_party/universal_ble/KUBI-PATCH.md)
    // ignore: dead_code
    try {
      ...
  ```

- **anchor**: `[KUBI-PATCH] skip watchAdvertisements`
  - `tools/verify-vendored-patches.sh` がこの anchor を検査する。
  - 上流更新で本 patch が消えた場合、CI が落ちる。

## 上流追従手順

最小手順 (詳細は repo ルートの README「ベンダー依存」節):

```bash
# 1. 新バージョンを pub-cache に取らせる
(cd /tmp && rm -rf _ubup && mkdir _ubup && cd _ubup &&
  printf 'name: x\nenvironment: {sdk: ^3.0.0}\ndependencies: {universal_ble: ^X.Y.Z}\n' > pubspec.yaml &&
  dart pub get)

# 2. third_party/universal_ble を丸ごと差し替え
cd <repo-root>
rm -rf third_party/universal_ble
cp -r ~/.pub-cache/hosted/pub.dev/universal_ble-X.Y.Z third_party/universal_ble

# 3. 上記 Patch 一覧の通り再適用 (該当箇所に `return; // [KUBI-PATCH] ...` を追加)

# 4. CI 検査と pub get
bash tools/verify-vendored-patches.sh
flutter pub get && (cd example && flutter pub get)
flutter analyze
```

## 完全に元に戻したい場合

```bash
rm -rf third_party/universal_ble
cp -r ~/.pub-cache/hosted/pub.dev/universal_ble-1.2.0 third_party/universal_ble
```

…で pristine 状態に戻る。ただし `dependency_overrides` を解除しないと
パッチ無しの universal_ble が動き、Web で Chrome がクラッシュする点に注意。
