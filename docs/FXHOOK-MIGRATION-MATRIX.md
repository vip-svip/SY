# FX Hook migration matrix — FX 1.0.0

This tracked matrix clarifies that the unified APK has two runtime entrypoints but is not equivalent to full API-101 feature parity.

## Capture privacy status

| Legacy capability | API-101 status |
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
