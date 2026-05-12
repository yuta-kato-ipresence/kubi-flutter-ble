import 'package:flutter/material.dart';
import 'package:kubi_flutter_ble/kubi_flutter_ble.dart';

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
  final _kubi = KubiBleImpl();
  String _status = 'Disconnected';

  Future<void> _connect() async {
    try {
      final device = await _kubi.requestDevice();
      await _kubi.connect(device);
      setState(() => _status = 'Connected: ${device.name}');
    } on BleUserCancelledError {
      setState(() => _status = 'Cancelled');
    } on BleConnectionError catch (e) {
      setState(() => _status = 'Connection failed: $e');
    }
  }

  Future<void> _move() async {
    try {
      final result = await _kubi.moveTo(pan: 45, tilt: 10, speed: 80);
      switch (result) {
        case MoveResultSettled(:final actual):
          setState(
            () => _status = 'Arrived at ${actual.pan}°, ${actual.tilt}°',
          );
        case MoveResultCancelled():
          setState(() => _status = 'Move cancelled');
      }
    } on KubiBleError catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _disconnect() async {
    await _kubi.disconnect();
    setState(() => _status = 'Disconnected');
  }

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
            ElevatedButton(onPressed: _connect, child: const Text('Connect')),
            ElevatedButton(
              onPressed: _move,
              child: const Text('Move to 45°, 10°'),
            ),
            ElevatedButton(
              onPressed: _disconnect,
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}
