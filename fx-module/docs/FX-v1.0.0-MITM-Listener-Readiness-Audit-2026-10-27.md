# FX 1.0.0 — MITM listener readiness and VPN safety audit

Date: 2026-10-27

## Changes in this package

1. `scripts/mitm-listener-health.sh` validates the exact kernel TCP socket `127.0.0.1:18443` in LISTEN (`0100007F:4813`, state `0A`). The caller unsets the test-only proc path override before checking the real socket.
2. `scripts/mitm-engine.sh start` waits up to six seconds for both its own verified process and the socket. Existing process-without-listener state returns an error. A new process failing readiness is signalled only while its command line still proves ownership; the redirect is not installed on that failure path.
3. Both engine and redirect status now report a process without a bound listener as unhealthy/degraded instead of merely running.
4. `scripts/mitm-redirect.sh enable` refuses activation if interface inspection is unavailable, a recognized external VPN tunnel exists, CA system trust is unconfirmed, host synchronization fails, or the effective MITM host allowlist is empty.
5. `scripts/mitm-redirect-watch.sh` is started only after explicit redirect activation. It watches actual redirect status and disables only the FX-owned `PGMITM27` path if a recognized tunnel appears later, listener health degrades, or an owned chain is partial. It does not edit external firewall chains.
6. `scripts/mitm-audit.sh` distinguishes available-but-disabled, enabled/healthy, degraded, and unverifiable states.

## Host-side verification

- 31 focused regression scripts passed, including listener readiness, trust preflight, CA/MITM UI lifecycle, JS runtime/subscription tests, DNS fail-open, external VPN, and firewall rollback.
- `sh -n` passed for every shell file in the package.
- Node `--check` passed for every standalone `.js` file under `scripts` (6 files).
- Go `go test ./...` and `go vet ./...` passed in `mitm/`.

The listener test uses a simulated `/proc/net/tcp` fixture, and VPN detector tests use a stub `ip` command. These are host-side tests, not a OnePlus 12 runtime test.

## Limits and next blockers

- External VPN recognition relies on common tunnel names (`tun`, `wg`, `ppp`, `ipsec`, `tap`, `utun`, `tailscale`, `zt`). A nonstandard interface name may not be detected; this is not a guarantee that all third-party VPNs coexist with MITM.
- Real Android iptables behavior, CA/APEX/SELinux changes, VPN enable/disable races, and real HTTPS requests are not verified on device.
- The AdGuard Home v0.107.79 Linux ARM64 executable is not Android compatible by proof and is intentionally omitted from this installable ZIP. An Android-target workflow was committed to `vip-svip/SY` at `389fa47acd04526e59a31974a9fc55869a9affba`, but its CI result was not verified in this session. FX DNS traffic is therefore not yet wired to a verified AdGuard Home Android runtime.
