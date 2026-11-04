# Dia 23.11 crash report migration

## Original behavior inspected

The original Dia crash screen reads a crash record containing process name, crashing thread, device information, exception message and stack trace. It offers copying, a feedback action, and clears the pending-report flag when opened. The original crash manager persists the record in crash.log and marks it pending for the next app launch.

The original optional stack control converts UTF-8 bytes into lowercase hexadecimal. This is reversible encoding, not cryptographic encryption. FX labels it accurately rather than claiming confidentiality.

## FX implementation

- FxDiaCrashStore installs in the FX Application process and delegates each fatal exception to the previously installed Android/Xposed handler after attempting to persist a report.
- The record is stored in the FX private files directory using AtomicFile. JSON size and field lengths are bounded, writes are synced, and records are not uploaded automatically.
- The next FX launch checks the pending flag and opens the native report Activity. Users can also enter it from Dia's Developer and Monitoring category.
- Copy and share are explicit user actions. The native Android share sheet replaces the original third-party feedback deep link.
- Capture can be disabled in the report screen. Scope is limited to uncaught Java exceptions in the FX app process; LSPosed target processes, native crash signals and kernel crashes are not claimed.

## Verification boundary

FxDiaCrashRecordTest covers UTF-8 HEX output, raw versus HEX rendering, and bounded fields. The shell regression checks manifest registration, exception-handler delegation, private atomic persistence and native UI wiring. Android installation and physical-device crash/relaunch behavior remain pending.
