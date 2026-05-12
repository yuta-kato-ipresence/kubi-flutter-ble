import 'package:flutter/material.dart';

// TODO(Phase 6): Update example to use kubi_flutter_ble package
// import 'package:kubi_flutter_ble/kubi_flutter_ble.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kubi BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const KubiPage(),
    );
  }
}

class KubiPage extends StatefulWidget {
  const KubiPage({super.key});

  @override
  State<KubiPage> createState() => _KubiPageState();
}

class _KubiPageState extends State<KubiPage> {
  // TODO(Phase 6): Initialize KubiBleImpl when available
  // final _kubi = KubiBleImpl();
  String _status = 'Implementation pending - see docs/api-design.md';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kubi BLE')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status),
            const SizedBox(height: 20),
            const Text(
              'Example app will be updated after core implementation.',
            ),
          ],
        ),
      ),
    );
  }
}
