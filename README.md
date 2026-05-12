# kubi_flutter_ble

> **Status**: 🚧 Design phase complete. Implementation not yet started.

A modern Flutter BLE package for Kubi robotic devices.

This is a **ground-up rewrite** of `kubi_flutter_plugin` with:
- Cross-platform BLE support via `universal_ble` (iOS, Android, macOS, Windows, Linux, Web)
- Type-safe API using Dart 3 sealed classes and pattern matching
- Stream-based events for natural Flutter UI integration
- TS-side (`kubi-web-ble`) feature parity with Flutter-idiomatic design

## Current Status

| Phase | Status | Description |
|-------|--------|-------------|
| 1 | ✅ Complete | Repository scaffolding |
| 2 | ✅ Complete | API design (`docs/api-design.md`) |
| 3 | 🚧 Pending | `KubiBleImpl` core implementation |
| 4 | 🚧 Pending | `KubiProtocol` tests |
| 5 | 🚧 Pending | Example app |
| 6 | 🚧 Pending | Documentation & release |

## Planned Features

- Physical arrival await (`moveTo`)
- Fire-and-forget with latest value buffer (`setTarget`)
- 4-phase move events via `Stream<MoveEvent>`
- GATT lock for burst safety
- Auto-reconnect and `tryAutoConnect`
- Register-based position reading (`getCommandedPosition` / `getActualPosition`)
- Type-safe error hierarchy with sealed classes

## Architecture

```
lib/
├── kubi_flutter_ble.dart          # Main exports
└── src/
    ├── kubi_ble.dart              # KubiBle abstract interface
    ├── kubi_ble_impl.dart         # Implementation (TODO: Phase 3)
    ├── kubi_protocol.dart         # BLE payload pure functions
    ├── types/                     # Data types
    │   ├── kubi_device.dart
    │   ├── pan_tilt_angles.dart
    │   ├── move_result.dart
    │   └── move_event.dart
    └── errors/                    # Error hierarchy
        └── kubi_ble_error.dart
```

## API Design

See [`docs/api-design.md`](docs/api-design.md) for the complete API specification.

## Design Decisions

- **BLE Library**: `universal_ble` (6-platform support, built-in command queue)
- **Dart SDK**: ^3.11.0 (latest stable for long-term support)
- **Events**: `Stream<T>` instead of callbacks for Flutter-native integration
- **State**: `ValueNotifier<KubiState>` planned for UI binding
- **Error Handling**: `sealed class` hierarchy with exhaustive pattern matching

## Relationship to `kubi_flutter_plugin`

This package replaces `kubi_flutter_plugin` for new development:
- `kubi_flutter_plugin`: Maintenance mode only (bug fixes, no new features)
- `kubi_flutter_ble`: Active development, modern API, cross-platform from day one

## License

BSD-3-Clause
