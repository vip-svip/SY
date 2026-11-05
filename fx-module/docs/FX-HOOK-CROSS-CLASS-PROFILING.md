# FX Hook 1.0.0 — Cross-class profiling

## What this adds

`MemberProfileGraph` builds a bounded index of direct class-to-class references
within a caller-supplied set of loaded classes. It records whether a reference
appears as a declared field type, method return type, or method parameter type.
It also attaches the existing metadata-only `MemberClassProfile` candidate
summary to each node.

This is useful for narrowing a developer-owned app's investigation from a
membership-looking state holder to adjacent session, account, repository, or
billing model classes. The graph is evidence of a type relationship only; it
does not infer authorization semantics or prove that one class controls another.

## Safety and bounds

- At most 512 supplied classes are indexed.
- At most 128 declared fields and 128 declared methods are inspected per class.
- Only types already present in the supplied class set become graph edges.
- No class is instantiated; no field value is read; no method is invoked.
- Synthetic and bridge methods are excluded.
- No token, account identifier, receipt, expiry value, or other runtime data is collected.
- No method hook, result replacement, network interception, billing manipulation,
  update suppression, or authorization mutation is performed.

## Next integration point

A developer-authored adapter may use this graph as a diagnostic aid, then bind
explicitly to documented test seams in the developer's own application. For
end-to-end entitlement tests, the application should consume a staging/test
authorization provider or dependency-injected fake; production builds must
continue to rely on server-verified entitlements and the official billing flow.

## Verification status

The JVM tests cover field, return-type, and parameter references, out-of-index
references, and null input. Passing host-side tests does not establish behavior
on a physical Android device.
