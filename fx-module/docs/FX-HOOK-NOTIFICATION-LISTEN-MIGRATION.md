# FX Hook migration: active-notification reads

Date: 2026-10-30

Legacy switch: `block_notif_listen` (`notifHide`).

API-101 Remote Files keys:

- Global master: `notification_listen_enabled` (published from the legacy `block_notif_listen` setting).
- Per-app selection: `notification_listen_block` in the Hook target record.

Runtime behavior:

- Intercepts only zero-argument `getActiveNotifications()` methods whose return type is `StatusBarNotification[]` on `NotificationManager` and `NotificationListenerService`.
- Returns an empty typed array only when both the global master and the per-app target are enabled.
- Does not alter notification posting, notification shade rendering, listener registration, permission state, or system notification services.
- Shared-package processes, protected framework/FX/LSPosed packages, unknown target state, and failed hook registration fail open.
- Existing API-82 Hook remains installed separately until all legacy switches reach parity and one-APK consolidation is complete.

Host-side parser/serializer/policy compilation and Remote Files publication regressions pass. Android CI build is tracked separately; OnePlus 12/LSPosed runtime injection remains unverified.
