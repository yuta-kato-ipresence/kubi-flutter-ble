import 'dart:async';

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
  final KubiBle _kubi = KubiBleImpl();
  StreamSubscription<KubiDevice>? _scanSub;
  StreamSubscription<PositionSnapshot>? _posSub;

  final List<KubiDevice> _found = <KubiDevice>[];
  bool _scanning = false;
  String _log = '';
  PositionSnapshot? _latest;

  @override
  void initState() {
    super.initState();
    _kubi.connectionStateStream.listen((e) {
      _append('connection: ${e.state} (${e.reason ?? '-'})');
    });
    _kubi.onDebugEvent.listen((e) {
      if (e.type == BleDebugEventType.autoReconnectAttempt ||
          e.type == BleDebugEventType.autoReconnectFailed ||
          e.type == BleDebugEventType.autoReconnectAbandoned ||
          e.type == BleDebugEventType.autoReconnectSuccess) {
        _append('debug: ${e.type.name} ${e.message ?? ''}');
      }
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _posSub?.cancel();
    _kubi.dispose();
    super.dispose();
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log = '$line\n$_log'.split('\n').take(20).join('\n'));
  }

  Future<void> _startScan() async {
    await _scanSub?.cancel();
    setState(() {
      _found.clear();
      _scanning = true;
    });
    _scanSub = _kubi.scan(timeout: const Duration(seconds: 10)).listen(
      (dev) => setState(() => _found.add(dev)),
      onError: (Object e) {
        _append('scan error: $e');
        setState(() => _scanning = false);
      },
      onDone: () => setState(() => _scanning = false),
    );
  }

  Future<void> _connect(KubiDevice dev) async {
    try {
      await _kubi.connect(dev);
      _append('connected to ${dev.name ?? dev.id}');
      _kubi.setAutoReconnect(
        AutoReconnectConfig(maxRetries: 3),
      );
      await _posSub?.cancel();
      _posSub = _kubi.subscribePosition().listen(
        (snap) => setState(() => _latest = snap),
        onError: (Object e) => _append('pos error: $e'),
      );
    } on KubiBleError catch (e) {
      _append('connect failed: $e');
    }
  }

  Future<void> _moveTo(double pan, double tilt) async {
    try {
      final result = await _kubi.moveTo(
        target: PanTiltAngles(pan: pan, tilt: tilt),
        spec: const MoveSpec.independent(speed: MoveSpeed.uniform(60)),
      );
      _append(switch (result) {
        MoveResultSettled() => 'settled at ${result.actual}',
        MoveResultCancelled() => 'cancelled',
      });
    } on KubiBleError catch (e) {
      _append('moveTo error: $e');
    }
  }

  Future<void> _disconnect() async {
    await _posSub?.cancel();
    _posSub = null;
    await _kubi.disconnect();
    setState(() => _latest = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kubi BLE')),
      body: ValueListenableBuilder<KubiState>(
        valueListenable: _kubi.state,
        builder: (ctx, state, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Connection: ${state.connectionState.name}'),
              if (state.lastError != null)
                Text('Error: ${state.lastError}',
                    style: const TextStyle(color: Colors.red)),
              Text('Commanded: ${state.commanded ?? '-'}'),
              Text('Actual: ${state.actual ?? '-'}'),
              Text('Moving: ${state.isMoving}'),
              const Divider(),
              Row(children: [
                ElevatedButton(
                  onPressed: _scanning ? null : _startScan,
                  child: Text(_scanning ? 'Scanning...' : 'Scan'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      state.connectionState == BleConnectionState.connected
                          ? _disconnect
                          : null,
                  child: const Text('Disconnect'),
                ),
              ]),
              Expanded(
                child: ListView(children: [
                  for (final d in _found)
                    ListTile(
                      title: Text(d.name ?? d.id),
                      subtitle: Text(d.id),
                      onTap: () => _connect(d),
                    ),
                ]),
              ),
              if (state.connectionState == BleConnectionState.connected) ...[
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  ElevatedButton(
                      onPressed: () => _moveTo(-45, 0),
                      child: const Text('← -45')),
                  ElevatedButton(
                      onPressed: () => _moveTo(0, 0),
                      child: const Text('center')),
                  ElevatedButton(
                      onPressed: () => _moveTo(45, 0),
                      child: const Text('+45 →')),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  ElevatedButton(
                      onPressed: () => _moveTo(0, 20),
                      child: const Text('tilt +20')),
                  ElevatedButton(
                      onPressed: () => _moveTo(0, -20),
                      child: const Text('tilt -20')),
                ]),
              ],
              if (_latest != null)
                Text('Last poll: pan=${_latest!.commanded?.pan.toStringAsFixed(1)}, '
                    'tilt=${_latest!.commanded?.tilt.toStringAsFixed(1)} '
                    'isMoving=${_latest!.isMoving}'),
              const Divider(),
              Container(
                height: 120,
                padding: const EdgeInsets.all(8),
                color: Colors.black12,
                child: SingleChildScrollView(
                  child: Text(_log,
                      style: const TextStyle(fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

