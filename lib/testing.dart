/// Test 用 entry point。production code からは import しないこと。
///
/// `FakeKubiBle` 等の test-only 実装をここから export する。
/// production 依存を増やさないため、本 library は `kubi_flutter_ble.dart`
/// 本体とは別 entry に分離している (api-design §4.5 / U5)。
///
/// 使い方:
/// ```dart
/// import 'package:kubi_flutter_ble/testing.dart';
///
/// testWidgets('shows error on connection failure', (tester) async {
///   final fake = FakeKubiBle();
///   await tester.pumpWidget(MyApp(kubi: fake));
///   fake.simulateError(const BleConnectionError('test'));
///   await tester.pump();
/// });
/// ```
library;

export 'src/testing/fake_kubi_ble.dart';
