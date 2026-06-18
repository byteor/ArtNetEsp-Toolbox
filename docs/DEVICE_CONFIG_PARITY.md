# Device Config UI Parity

How ArtNetApp's **Configure device** screen stays logically identical (layout +
behavior) to the ArtNetEsp firmware's own web config SPA.

## Authoritative source

- **Contract:** - the firmware's "[REST API & UI Design Contract](https://github.com/byteor/ArtNetEsp/blob/main/docs/API_UX_DESIGN.md)". **This document wins on
  conflict** with firmware source or this file.
- **Pinned version:** contract **v1.0.0** (firmware 2026.2.x).
- **Client constant:** `kSupportedContractVersion` in
  [device_config_client.dart](../lib/features/device_config/data/device_config_client.dart).
  Keep it equal to the contract version this app targets.

> **WiFi is intentionally out of scope.** The v1.0.0 contract envelope has no
> `wifi` key and the SPA has only three tabs (General · Devices · System); WiFi
> is configured via the device's captive portal + `POST /reset-wifi`.

## Flutter implementation map

| Concern                                                 | File                                                                                                           |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Schema model (envelope, `hw`, `dmx`, `DmxType`, `info`) | [domain/device_config_model.dart](../lib/features/device_config/domain/device_config_model.dart)               |
| REST client (GET/POST, 202→re-GET, auth, errors)        | [data/device_config_client.dart](../lib/features/device_config/data/device_config_client.dart)                 |
| State/draft/dirty/save controller                       | [data/device_config_providers.dart](../lib/features/device_config/data/device_config_providers.dart)           |
| Auth: default creds + per-host cache                    | [data/device_credentials_store.dart](../lib/features/device_config/data/device_credentials_store.dart)         |
| Full-screen modal UI (tabs + sections)                  | [presentation/device_config_screen.dart](../lib/features/device_config/presentation/device_config_screen.dart) |
| Entry point (Configure button on active devices)        | [scan_screen.dart](../lib/features/scan/presentation/scan_screen.dart) `_DeviceTile`                           |

## Section / field parity (contract §7.3)

**General** → saves `{host, universe}`

| Contract control                 | JSON key   | Flutter widget             |
| -------------------------------- | ---------- | -------------------------- |
| Hostname (text, maxlen 31)       | `host`     | `_StrField` (maxLength 31) |
| Art-Net universe (number, min 0) | `universe` | `_IntField` (min 0)        |

**Devices** → saves `{dmx: [all cards]}` (whole array; empty = no-op → disable via `DISABLED`)

| Contract control         | JSON key     | Shown for                     | Flutter                                     |
| ------------------------ | ------------ | ----------------------------- | ------------------------------------------- |
| Type (select)            | `type`       | always                        | `DropdownButtonFormField<DmxType>`          |
| Start channel (1–512)    | `channel`    | always                        | `_IntField` (1–512)                         |
| GPIO pin (≥0)            | `pin`        | BINARY, DIMMER, SERVO         | `_IntField`, gated by `DmxType.showsPin`    |
| Active level (HIGH/LOW)  | `level`      | BINARY, DIMMER                | dropdown, `DmxType.showsLevel`              |
| On/off threshold (0–255) | `threshold`  | BINARY                        | `_IntField`, `DmxType.showsThreshold`       |
| Strobe pulse (≥0)        | `pulse`      | DIMMER                        | `_IntField`, `DmxType.showsPulse`           |
| Strobe multiplier (≥1)   | `multiplier` | DIMMER                        | `_IntField`, `DmxType.showsMultiplier`      |
| Blackout on signal loss  | `blackout`   | all except DISABLED           | `CheckboxListTile`, `DmxType.showsBlackout` |
| + Add device / Remove    | —            | cap at `info.max_dmx_devices` | `addDevice`/`removeDevice`                  |

New-device defaults (`DmxDevice.freshDefault`): `{channel:1, type:BINARY, pin:2, level:HIGH, multiplier:1, pulse:10, threshold:127, blackout:true}`.

**System**

- **Firmware** (only when `info.ota`): a card whose `http://<host>.local/update` URL is a tappable hyperlink that opens the device's OTA page in an external browser (`url_launcher`). No in-app/embedded OTA view — see "Known simplifications".
- **Advanced** (collapsible) → saves `{hw}`: `freq` (min 100), `longPressDelay` (min 500), `ledPin` (≥0), `buttonPin` (≥0), `wifiPowerSave` (switch), `authEnabled` (switch revealing `authUser`/`authPass`).
- **Power & WiFi**: **Reboot** and **Reset WiFi**, each behind a confirm `AlertDialog` (Reset-WiFi styled as danger).

## Client semantics to uphold (contract §5.4, §7.2)

- **Async save:** `POST /config` returns **202**; the client waits ~500 ms then re-`GET /config` (3× retry/backoff) and uses that as the new baseline.
- **Partial, section-scoped:** only the edited section's keys are sent (`generalPayload` / `devicesPayload` / `hwPayload`). `dmx` is sent whole.
- **Dirty tracking:** per-section deep compare (`jsonEncode` of the section payload) of `draft` vs `saved`; Save is disabled when clean/busy (Devices also when empty).
- **Reboot banner** clears via the 5 s `GET /status` poll once the device reports `_needReboot:false`.
- **Auth:** `401` on a mutating call → the client retries the same call with each
  available credential in order — the session's current creds, then those
  **remembered for this host**, then the app-wide **default** (Settings ›
  _Device authentication_) — sending `Authorization: Basic …`. The first set that
  succeeds is adopted for the session and **remembered per host** (so the next
  visit is pre-authenticated). Only when every candidate is rejected does the
  inline credentials prompt appear (pre-filled from the default). The contract
  has **no factory-default credentials** (`hw.authUser`/`hw.authPass` default to
  `""`), so the app's "default" is whatever the user enters in Settings.
  - **Storage:** the default and per-host credentials are kept **encrypted at
    rest** via `flutter_secure_storage` (iOS/macOS Keychain; Android
    Keystore-wrapped AES-GCM) — never in plaintext `shared_preferences`. They are
    decoded once at startup into memory for synchronous reads and written through
    on change. Implementation:
    [device_credentials_store.dart](../lib/features/device_config/data/device_credentials_store.dart).
    macOS requires the Keychain Sharing entitlement (added to both
    `macos/Runner/*.entitlements`).
- **Size/`info.ota`:** respect `info.max_dmx_devices`; show the OTA card only when `info.ota`.

## Known simplifications (vs the web SPA)

- In this config screen the OTA updater's `http://<host>.local/update` URL is a hyperlink that opens the device's OTA page in an external browser (via `url_launcher`, like the Scan list's device IP) rather than embedding the OTA flow in-app.
- Visual styling follows the app's Material 3 theme rather than the firmware's `style.css` (the contract does not mandate CSS; only information architecture + behavior must match).

## Keeping in sync

The contract is **versioned with an append-only changelog** (`API_UX_DESIGN.md`
§2, §10). When the firmware bumps its contract version:

1. Read every changelog entry **newer than** `kSupportedContractVersion`.
2. Apply additive changes to the model / client / UI and this parity table.
3. Bump `kSupportedContractVersion` to match.
4. For a `Breaking` entry, also handle the `configVersion` migration the contract describes.

A codegen approach (generating Dart from the firmware `web/src/types.ts`) was
considered and rejected: the contract doc is the human-authoritative source, is
already versioned, and the schema is small enough to mirror by hand.
