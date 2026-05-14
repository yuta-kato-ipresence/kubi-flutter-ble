/// 4 phase 移動イベントのフェーズ (`MoveEvent.phase`)。
///
/// 1. [start]: `moveTo` 受理、GATT lock 取得試行開始。
/// 2. [commanded]: 軸 config + 目標値の write 完了 (servo にコマンドが届いた)。
/// 3. [settled]: 物理到達検出 (tolerance 内)。`MoveResultSettled` で moveTo Future が完了。
/// 4. [cancelled]: 新しい moveTo / disconnect / cancel token のいずれかで中断。
enum MovePhase { start, commanded, settled, cancelled }
