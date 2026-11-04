# Dia 23.11 crash report migration

## Original behavior inspected

The original Dia crash screen reads a crash record containing process name, crashing thread, device information, exception message and stack trace. It offers copying, a feedback action, and clears the pending-report flag when opened. The original crash manager persists the record in crash.log and marks it pending for the next app launch.

The original optional stack control converts UTF-8 bytes into lowercase hexadecimal. This is reversible encoding, not cryptographic encryption. FX labels it accurately rather than claiming confidentiality.

## FX implementation

- FxDiaCrashStore installs in the FX Application process and delegates each fatal Java exception to the previously installed Android/Xposed handler after attempting to persist a report. FxDiaNativeCrashCapture installs Dia 23.11's original Breakpad JNI callback in the FX process only.
- The record is stored in the FX private files directory using AtomicFile. JSON size and field lengths are bounded, writes are synced, and records are not uploaded automatically. The reader accepts Dia 23.11's original unversioned CrashInfo JSON fields, preserving an existing crash.log across migration. The original digXposed disable_java_crash_capture and has_crash flags are recognized.
- The next FX launch checks the pending flag and opens the native report Activity. Users can also enter it from Dia's Developer and Monitoring category.
- Copy and share are explicit user actions. The export formatter redacts the original raw report before optional reversible HEX stack encoding, so secrets remain detectable in both export modes. The native Android share sheet replaces the original third-party feedback deep link.
- Capture can be disabled in the report screen. The original encrypt_stack preference name and default-on behavior are preserved. Explicitly enabling capture in FX clears the old Dia opt-out flag after a successful preference commit; failed persistence is reported and the switch is reverted. The original libbreakpad.so binaries are staged from the Dia 23.11 source artifact for arm64-v8a and armeabi-v7a. The Java bridge preserves the exact JNI class/method and four-String callback descriptor. Minidumps are stored under FX private files/dia-native-crash; crash.log stores the minidump path, native information, native thread trace and JVM thread snapshot. Unsupported ABIs report Native capture unavailable. Scope remains limited to the FX app process; LSPosed target processes and kernel crashes are not claimed.

## Verification boundary

FxDiaCrashRecordTest covers UTF-8 HEX output, raw versus HEX rendering, bounded fields and Native report formatting. The shell regression checks Java handler delegation, private AtomicFile persistence, original JNI descriptor/export, both shipped ABIs and native UI status. Android installation and physical-device crash/relaunch behavior remain pending.


## Clearing crash data safely

The report clear action removes the Java crash record and pending flags together with the direct regular-file contents of `files/dia-native-crash/`. It refuses symlinked paths and unexpected nested directories; it never recursively traverses that directory. A failed filesystem or preference operation is reported as unconfirmed/possibly partial cleanup rather than a success message; the UI does not claim that every report file was preserved. The host regression covers normal deletion, symlink targets, nested folders and an already-absent dump directory.
