# FX Hook — Generic membership class profiling

`MemberClassProfile` adds bounded metadata-only candidate profiling. It scores class names, instance field names/types, and narrow getter signatures; recognizes obfuscated state-holder shape hints; and caps reflection scans at 128 fields and methods per class. It never constructs objects, reads field values, invokes methods, serializes application data, or changes return values. A positive profile is a discovery hint, not proof of membership semantics. App-owned adapters or staging integration are still needed to assign business meaning.
