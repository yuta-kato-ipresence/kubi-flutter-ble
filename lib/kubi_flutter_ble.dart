/// Kubi BLE for Flutter.
///
/// 公開エントリポイント。`KubiBle` インターフェースと、その引数・戻り値となる
/// すべての value type / sealed type / enum / error をここから export する。
///
/// テスト用 `FakeKubiBle` は production 依存を増やさないため
/// `package:kubi_flutter_ble/testing.dart` から別 entry で提供する。
///
/// 内部 protocol 定数 (`kubi_protocol.dart`) は **package-private** (export しない)。
library;

// 中核インターフェース
export 'src/kubi_ble.dart';
export 'src/kubi_ble_impl.dart';

// エラー (sealed)
export 'src/errors/kubi_ble_error.dart';

// 列挙
export 'src/types/ble_availability.dart';
export 'src/types/ble_connection_state.dart';
export 'src/types/ble_debug_event.dart' show BleDebugEventType;
export 'src/types/disconnect_reason.dart';
export 'src/types/move_phase.dart';
export 'src/types/position_source.dart';

// Value types
export 'src/types/auto_reconnect_config.dart';
export 'src/types/ble_debug_event.dart' show BleDebugEvent;
export 'src/types/cancel_token.dart';
export 'src/types/connection_state_event.dart';
export 'src/types/kubi_device.dart';
export 'src/types/kubi_state.dart';
export 'src/types/move_event.dart';
export 'src/types/pan_tilt_angles.dart';
export 'src/types/position_snapshot.dart';
export 'src/types/settle_options.dart';
export 'src/types/subscribe_position_options.dart';

// Sealed value types
export 'src/types/move_result.dart';
export 'src/types/move_spec.dart';
export 'src/types/move_speed.dart';
