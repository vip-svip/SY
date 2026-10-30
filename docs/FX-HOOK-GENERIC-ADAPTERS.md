# FX Hook generic authorization adapters

`AuthorizationIntegrationAdapter` accepts only typed states already parsed by the host application's normal, verified code path. It maps session restore/refresh/logout, entitlement active/inactive/expired/revoked/pending, Billing purchased/pending/canceled/refunded/revoked, and update available/current/policy-skipped/error to diagnostic events.

This adapter is observation-only. It cannot create sessions, change entitlement, acknowledge or consume purchases, suppress server checks, or alter update policy. The application remains responsible for authenticating responses and enforcing entitlements. Never pass secrets, account identifiers, raw payloads, or purchase tokens as labels.

Network request timing remains the responsibility of `AuthorizationRequestTracker`; use its begin/complete methods around the real request boundary, then call this adapter with the business state produced by the application's ordinary parser.
