# FX Hook member diagnostics: independent target switch

The per-target `member_diag=1` option is independent of the global `ads_enabled`
master switch. It can activate read-only member/billing diagnostics while ad filtering
is disabled. The three ad feature flags (`ads_splash`, `ads_feed`, `ads_overlay`)
remain governed by `ads_enabled`.

This is diagnostic instrumentation only. It does not alter purchase results, client
entitlements, server authorization, billing tokens, or protected operations.

Regression coverage verifies that a target with member diagnostics enabled and all
ad flags disabled remains eligible for diagnostics while `isAdsEnabledFor` remains false.
