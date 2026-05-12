# kubi_flutter_ble

A modern Flutter BLE package for Kubi robotic devices.

## Features

- Cross-platform BLE support (iOS, Android, macOS, Windows, Linux, Web)
- Physical arrival await (`moveTo`)
- Fire-and-forget with latest value buffer (`setTarget`)
- 4-phase move events
- GATT lock for burst safety
- Type-safe error hierarchy

## Getting Started

### Installation

```yaml
dependencies:
  kubi_flutter_ble: ^0.1.0
```

### Usage

```dart
import 'package:kubi_flutter_ble/kubi_flutter_ble.dart';

final kubi = KubiBleImpl();

// Connect
final device = await kubi.requestDevice();
await kubi.connect(device);

// Move to position (awaits physical arrival)
final result = await kubi.moveTo(pan: 45, tilt: 10, speed: 80);
if (result case MoveResultSettled(:final actual)) {
  print('Reached: ${actual.pan}°, ${actual.tilt}°');
}

// Disconnect
await kubi.disconnect();
```

## Architecture

```
lib/
├── kubi_flutter_ble.dart          # Main exports
└── src/
    ├── kubi_ble.dart              # KubiBle abstract interface
    ├── kubi_ble_impl.dart         # Implementation
    ├── kubi_protocol.dart         # BLE payload pure functions
    ├── types/                     # Data types
    │   ├── kubi_device.dart
    │   ├── pan_tilt_angles.dart
    │   ├── move_result.dart
    │   └── move_event.dart
    └── errors/                    # Error hierarchy
        └── kubi_ble_error.dart
```

## License

BSD-3-Clause
