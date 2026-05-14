/// `subscribePosition` で観測する位置の種別。
enum PositionSource {
  /// Goal Position レジスタ (0x1e) — コマンドされた目標値。
  commanded,

  /// Present Position レジスタ (0x24) — 物理的な現在位置。
  actual,

  /// 両方を 1 tick で読み、両者を含む `PositionSnapshot` を配信。
  both,
}
