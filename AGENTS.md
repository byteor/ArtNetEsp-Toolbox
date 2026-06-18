# AGENTS.md — working in this repository

Guidance for future coding agents (and humans). Read this before changing code.

## Project purpose

A foreground-only Flutter diagnostic app (Android + iOS) for **Art-Net/DMX** and
**mDNS/Bonjour** discovery and control on the local network. It is a
proof-of-concept intended to grow into a multi-page production tool for many
device types and firmware versions, so structure and clean seams matter more
than feature breadth.

## Architecture overview

Feature-first, layered. Pure logic is isolated from Flutter so it is unit
testable and reusable.

```
UI (presentation)  ->  controllers/providers (Riverpod)  ->  data services
                                                              |        |
                                                  domain codec (pure)  core/network seam
```

- **domain/** — pure Dart. Art-Net packet building/parsing, value objects. No
  Flutter, no sockets, no plugins. Fully unit tested.
- **data/** — services that use the network seam + domain codec, plus the
  Riverpod controllers/state for each feature.
- **presentation/** — widgets/screens only. No packet logic, no raw sockets.
- **core/** — cross-cutting: `network/` (UDP transport seam, multicast lock,
  Wi-Fi info), `settings/` (model, repository, providers), `logging/`.

State management is **Riverpod 3** with plain `Notifier`/`Provider` (no codegen,
no `build_runner`). The transport is hidden behind `UdpTransport` so a native
Swift/Kotlin implementation can replace `dart:io` later without touching
services or UI. mDNS is hidden behind `MdnsDiscovery`.

## Important directories

| Path | What lives here |
|---|---|
| `lib/features/artnet/domain/` | Pure Art-Net codec (`art_poll`, `art_poll_reply`, `art_dmx`, constants, opcodes) + `artnet_node`. **Change packet logic here.** |
| `lib/features/artnet/data/` | `ArtnetService` (discover/monitor/transmit) + Riverpod controllers. |
| `lib/features/artnet/presentation/` | Discovery/Monitor/Transmit tabs + the `ArtnetShell` tab host. |
| `lib/features/mdns/` | `MdnsDiscovery` interface, `nsd` impl, record model, controller, screen. |
| `lib/features/dashboard/`, `lib/features/settings/` | Dashboard + Settings screens/controllers. |
| `lib/core/network/` | `UdpTransport` seam + `DartUdpTransport`, `MulticastLock`, `NetworkInfoService`, network providers. |
| `lib/core/settings/`, `lib/core/logging/` | Settings model/repo/providers; `AppLogger`. |
| `lib/shared/widgets/` | Reusable widgets (`StatusTile`, `LabeledTextField`, `LogView`). |
| `test/` | Pure-Dart codec tests. |
| `docs/` | Protocol + platform notes + manual test checklist. |

## Coding conventions

- Material 3. Keep the UI minimal and functional.
- One feature per folder; within a feature use `domain/ data/ presentation/`.
- Controllers/state hold logic; **widgets stay thin** and read providers.
- Prefer immutable state classes with `copyWith`. Avoid nullable "reset" fields
  in state — use sentinels (`-1`, `''`) so `copyWith` stays simple.
- Logging goes through `AppLogger` (tag + message). User-visible errors should
  also be surfaced in the relevant screen, not just logged.
- `flutter analyze` must be clean and `flutter test` green before you finish.

## How to add a new device type

1. Create `lib/features/<device>/` with `domain/`, `data/`, `presentation/`.
2. Put pure protocol/codec in `domain/` (unit-tested), the service + Riverpod
   controllers in `data/`, and screens in `presentation/`.
3. Reuse `core/network` (UDP) or add a new seam interface if a new transport is
   needed — keep it behind an interface like `UdpTransport`/`MdnsDiscovery`.
4. Add a destination (or a tab) in `lib/app.dart` (see below).
5. If it advertises over mDNS, add its service type to the Settings default and
   to iOS `Info.plist` `NSBonjourServices`.

## How to add a new screen

- **Top-level destination:** add the screen to `_screens` and a
  `NavigationDestination` in `lib/app.dart` (`RootShell`). The screen provides
  its own `Scaffold` + `AppBar`.
- **Art-Net sub-tab:** add a `Tab` + child in
  `lib/features/artnet/presentation/artnet_shell.dart`. Sub-tab bodies do NOT
  use their own `Scaffold` (the shell provides it).

## How to modify Art-Net packet handling safely

- Edit only `lib/features/artnet/domain/`. Do not parse/build packets in
  widgets or services.
- **Write/extend tests first** in `test/art_*_test.dart`, including malformed,
  truncated and garbage inputs. Then change the codec.
- Respect endianness: **OpCodes are little-endian**, but the **ArtDmx Length is
  big-endian**. See `docs/ARTNET_NOTES.md` for exact offsets.
- Every read from a received buffer must be bounds-checked.

## Non-negotiable rules

1. **Packet parsing must never trust network input.** Parsers validate the
   Art-Net ID and opcode first, bounds-check every multi-byte read, clamp
   declared lengths to the bytes actually present, and return `null`/partial
   rather than throwing. New parsing code must keep this contract and have tests
   that feed it garbage.
2. **Local-network permission behaviour must be tested on real iOS and Android
   devices.** The iOS Simulator and Android emulator do not reproduce Local
   Network permission, broadcast filtering, or multicast behaviour. Do not claim
   discovery works based on emulator/simulator runs.
3. **Keep core packet logic independent from widgets.** `domain/` is pure Dart
   with no Flutter, socket, or plugin imports, so it stays unit-testable and
   reusable. If you find yourself importing `package:flutter` into `domain/`,
   stop and move the logic.

## How to run tests

```bash
flutter test            # all unit tests
flutter test test/art_dmx_test.dart   # a single file
flutter analyze         # static analysis (must be clean)
```

## How to run the app

```bash
flutter pub get
flutter devices
flutter run -d <deviceId>
```

First install the toolchain with `bash scripts/bootstrap.sh` if needed. Use a
real device for any local-network testing.

## Platform caveats

- iOS: Local Network permission (iOS 14+) gates everything; `NSBonjourServices`
  is an allow-list for mDNS types; limited broadcast is unreliable; no multicast
  entitlement is needed for Art-Net broadcast or `nsd`-based mDNS.
- Android: hold the Wi-Fi multicast lock (already wired via `MainActivity.kt`)
  to receive broadcast/multicast; some OEMs still filter aggressively.
- Networks: AP/client isolation, guest Wi-Fi and VPNs commonly block
  client-to-client discovery. Surface these as user-visible hints, not silent
  failures.
