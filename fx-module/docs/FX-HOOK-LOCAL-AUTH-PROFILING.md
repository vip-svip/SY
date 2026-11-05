# FX Hook 1.0.0 — Local authorization profiling

This profiler focuses on local authorization implementations: preferences,
DataStore, Room/SQLite, files, encrypted preferences, and keystore-related types.
It examines declared member names and types only. It does not read stored values,
open databases/files, access keystore material, or invoke application methods.

The output is evidence for selecting a real authorization decision point; storage
references alone are not proof that a field grants membership. Local state may be
cached, signed, encrypted, or recomputed from multiple sources.

The next runtime integration step is an explicit per-package, per-method test
profile for the developer's own app, with exact method signature and return-type
validation, debug/opt-in gating, hit counters, and a reset path. Do not infer an
authorization override from a field name or storage class alone.

Host JVM tests cover metadata identification and safe handling of null/unrelated
classes. Android device behavior has not yet been verified.
