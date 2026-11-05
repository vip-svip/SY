# FX Hook migration matrix — FX 1.0.0

This tracked matrix clarifies that the unified APK has two runtime entrypoints but is not equivalent to full API-101 feature parity.

## API-101 wired feature status (CI/source verified; device behavior pending)

| Feature | UI/config/runtime wiring | Scope and limitation |
|---|---|---|
| Built-in ad recognition | Automatic classifier and package-scoped View observers | Eligible LSPosed target processes; does not require per-app ad switches or Remote Files. |
| Member/Billing diagnostics | Native per-app opt-in and bounded read-only runtime probes | Diagnostic only; never alters rewards, purchases, login or server entitlements. |
| Android ID / EXIF | Per-app config and modern runtime hooks | Narrow API-level transforms; not equivalent to all legacy device-identity or metadata spoofing switches. |
| Clipboard read block | Per-app opt-in and selected read API interception | Not OS clipboard permission revocation. |
| Clipboard isolation | Separate master/per-target config and process-local shadow hooks | Single-package process only; not OS-wide or cross-app isolation; mutually exclusive with clipboard read block. |
| Sensors | Per-app sensor selection and rate policy | Selected sensor enumeration/rate APIs; not full hardware or native sensor-path coverage. |
| Wi-Fi scan | Global master plus per-app target gate | Intercepts selected WifiManager scan APIs only; association, DNS, VPN and sockets remain untouched. |
| Notification listener reads | Global master plus per-app target gate | Selected listener registration/read APIs; does not change OS permission state or notification posting/display. |
| Notification permission query | Native target editor, publisher master/per-target fields, parser, runtime and status reporting | Masks selected app-visible permission-status queries only; does not grant/revoke Android permissions. |
| Microphone silence / access denial | Per-app config and AudioRecord/MediaRecorder runtime hooks | Silence affects supported AudioRecord.read overloads; access denial affects supported recording-start APIs. Native capture paths remain unverified. |
| Camera access denial | Per-app config and Camera/Camera2 open-request hooks | Explicitly denies supported open requests; does not spoof absent hardware or synthesize fake frames. |
| Location access denial | Per-app config and supported LocationManager read/update hooks | Not a system-wide passive-location provider shutdown or GNSS spoof. |
| MediaStore query block | Per-app config and ContentResolver query hook | Returns an empty cursor for selected content://media queries; does not block file access or writes. |

The unified APK contains both the legacy Xposed entrypoint and modern libxposed API-101 entrypoint under one applicationId. This packaging result is not full migration of the 75 historical switches. The unified APK retains the legacy Xposed entrypoint for allowed legacy controls that have not yet been ported to API-101. In the inventory below, “not migrated” means “not implemented in the modern API-101 runtime”; it does not automatically mean the legacy implementation is absent. High-risk legacy controls listed in `DISABLED_EVASION_KEYS` are intentionally fail-closed, while API-101-owned features are suppressed in the legacy entrypoint to prevent duplicate hooks. Every row above is CI/source verified; OnePlus 12 + KernelSU + LSPosed runtime verification remains outstanding.

## Capture privacy status

| Legacy capability | API-101 status |
| MediaStore listing block (`block_mediastore`) | `media_store_query_block` returns an empty cursor only for `content://media` queries from a selected single-package process; it does not block file access or writes. |
|---|---|
| Camera disabled / cameraNull | `camera_access_block` explicitly denies Camera/Camera2 open requests. It does not return fake camera frames or spoof hardware absence. |
| passive location hiding | `location_access_block` explicitly denies supported LocationManager read/update APIs. It is not a system-wide passive-location provider shutdown. |
| mic_block error mode | `mic_access_block` explicitly denies AudioRecord/MediaRecorder recording start. |
| mic_block silence mode | `mic_silence` zeroes successfully-read regions for supported AudioRecord.read overloads. It is not OS permission revocation or universal native capture coverage. |
| audio_fp_block noise perturbation | Intentionally not migrated; it alters captured samples. |
| mic_hw_hide hardware spoofing | Intentionally not migrated; explicit recording denial is a different behavior. |
| mic_block noise mode | Intentionally not reproduced. |

Parser/serializer/UI fields and API-101 runtime gates exist for the explicit denial/silence controls. Host tests cover parser/serializer and buffer policy. Runtime injection, MediaRecorder behavior, Camera2/LocationManager overload coverage, and native capture paths still require OnePlus 12 device verification.

## Migration rule

A safer explicit denial is not labeled behavior-equivalent to legacy spoofing. Unknown/shared-process conditions must remain fail-open. The single APK dual-entry architecture must not be represented as full migration of all 75 legacy switches.
