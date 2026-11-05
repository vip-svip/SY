# FX 1.0.0 — VPN subscription auto-update retry fix (2026-10-27)

## Bug

`service.sh` previously wrote `PG/vpn-sub-last` **before** calling `apply.sh vpn-sub`. A boot-time network failure or failed subscription/core reconciliation therefore advanced the interval timestamp despite a failed update. With the default 24-hour interval, the next automatic attempt could be suppressed for a full day.

## Fix

- Moved the scheduled update into `scripts/vpn-auto-update.sh` so it is independently testable.
- The success stamp is committed with a temp file + atomic rename only after `apply.sh vpn-sub` returns success.
- A failed update preserves the last successful timestamp, logs the return code, and remains eligible for retry on the next service invocation.
- Malformed or leading-zero interval values are normalized before arithmetic; interval is clamped to 1–8760 hours and oversized values are prevented from overflowing shell arithmetic.
- Future/overflow timestamp values are ignored rather than wedging the schedule.

## Regression coverage

`scripts/tests/v1.0.0-vpn-auto-update-success-stamp-regression.sh` simulates: first update failure without a stamp; retry at the same time; successful stamp commit; no duplicate update before due time; later failure preserving the previous successful stamp; and retry of that failed due update. The test also checks that service.sh delegates to this helper and no longer stamps before the transaction.

## Limits

This fixes scheduler retry semantics, not the separate requirement to validate AdGuard Home DNS activation or third-party VPN traffic coexistence on OnePlus 12. Those remain explicitly unverified on-device.
