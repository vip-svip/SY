# FX Hook generic authorization lifecycle diagnostics

AuthorizationTrace is a generic, read-only instrumentation primitive for an application's own authentication, session, entitlement, billing, and update flows.

It records lifecycle stage, outcome, HTTP status, duration, and short sanitized diagnostic labels only. It has no API for credentials, cookies, raw response bodies, account identifiers, purchase tokens, entitlement mutation, or update suppression.

## Integration points

The owned app or its explicitly authored adapter should call record at real request/response boundaries:
- Login: LOGIN_REQUEST / LOGIN_RESULT
- Session: SESSION_RESTORE / TOKEN_REFRESH / TOKEN_REFRESH_RESULT / LOGOUT
- Entitlement: ENTITLEMENT_REQUEST / ENTITLEMENT_RESULT
- Billing: BILLING_RESULT
- Updates: UPDATE_CHECK / UPDATE_RESULT

Record server outcomes only after normal response verification and parsing. Protected operations must continue consuming the server-verified entitlement object. Update policy remains independent of login and entitlement validation.

The trace is bounded (default 256 events), in-memory, and clearable. It is diagnostic infrastructure; it does not claim that an application is logged in or VIP, and does not alter production authorization.
