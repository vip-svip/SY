# FX 1.0.0 — AdGuard Home Android ARM64 integration status (2026-10-27)

## Verified build artifact

- Official upstream source: AdGuard Home v0.107.79.
- FX repository workflow: `.github/workflows/build-adguardhome-android-arm64.yml`.
- Workflow run: `40465966583` (run 2), conclusion `success`.
- Actions artifact ID: `12716706286`, archive SHA-256: `6004dba6e35cfabc1d91176ef7da5572a736ef7288470caf3083c8183aa948c0`.
- Upstream config validation: `check-adguardhome-config.yml` run `40480135241` (`success`; latest run after DoT hostname/bootstrap assertions); `.github/dns/AdGuardHome-FX-runtime-v1.0.0.yaml` is byte-identical to the manager output template and passed the official v0.107.79 `--check-config`.
- Binary SHA-256: `e122e73b2baed66fefa2d8337f1a8b2ed6067102c939043d73e6f7c3da11ef39`.
- Binary size: 31,567,112 bytes. ELF64 AArch64 PIE; Android API 24 target; interpreter `/system/bin/linker64`; dynamic dependencies are `liblog.so`, `libdl.so`, and `libc.so`.
- Stored in this package as `engines/adguardhome/AdGuardHome-android-arm64`, with build metadata and a checksum file.

## Activation boundary — automatic local recursive DNS when safe, device acceptance pending

This is an Android-target AdGuard Home binary with a separate Android ARM64 Unbound 1.26.2 recursive resolver. Both are wired through `scripts/adguardhome.sh` and `scripts/unbound.sh`, and is attempted automatically when safe prerequisites pass. It starts only when the protection master, DNS forwarding, FX direct mode and no detected external VPN are all satisfied, FX validates binary hashes/configuration, starts Unbound on loopback `127.0.0.1:5353`, requires a real unique uncached recursive DNS response, then starts AdGuard Home on loopback port 53 and validates a DNS answer before installing IPv4/IPv6 DNS redirects. AdGuard Home forwards only to `127.0.0.1:5353`; Unbound performs recursive queries to root/TLD/authoritative DNS and maintains its local cache. No Tencent/Alibaba/Cloudflare recursive forwarder is hard-coded in the runtime configuration. Root-owned DNS is exempted before FX DNS DNAT and `PGUARD` DNS lockdown to avoid recursive self-redirection. If startup, health, checksum or firewall prerequisite fails, FX does not install local DNS redirects and preserves the configured resolver/fail-open path.

Only domain entries explicitly marked REJECT from `fxrules/anti_fraud_96110.txt` are converted to AdGuard Home rules. Package-name and IP-CIDR rules remain in their existing FX rule path; no adblock/open-screen/watermark rules are imported. The Web UI admin interface is loopback-bound to an ephemeral port and authenticated with a bcrypt hash; pprof is disabled.

The Android ARM64 builds, official AdGuard Home config check and host-side lifecycle regression tests pass, but neither DNS binary has **been exercised on a OnePlus 12 device**. Therefore direct authoritative DNS reachability over UDP/TCP 53 on the user's mobile network, live DNSSEC validation, SELinux permissions, loopback DNAT behavior, Private DNS/DoH bypasses, real external-VPN coexistence, and automatic recovery under network loss remain unverified. A local recursive resolver still needs Internet access for uncached names; first queries may be slower than nearby recursive forwarders, while cached responses can be served locally. Unbound's RFC5011 auto-trust-anchor maintenance is enabled, and the packaged `unbound-anchor` can make a bounded refresh attempt after long offline periods.
## Separate script-trigger fix

The MITM hook parser now normalizes common `\/` URL-separator escaping used by proxy modules before compiling the Go regular expression. If a pattern arrives double-escaped from a config/string layer, the known escaped URL pattern is normalized as well. Regression tests cover Bilibili feed URLs and the Aloha profile endpoint. This fixes one reason an imported script could be present on disk but silently skipped at runtime. It does not make every third-party private API compatible, and it is not a real app traffic test.


## Audit154 continuation — local recursive DNS

The current FX package now includes a separate Android ARM64 Unbound 1.26.2 recursive resolver under `engines/unbound/`. AdGuard Home is configured only to query `127.0.0.1:5353`; the Unbound instance listens on loopback port 5353, uses bundled root hints and a local DNSSEC trust-anchor file, and performs root/TLD/authoritative recursion instead of forwarding cache misses to Tencent, Alibaba, or Cloudflare. Both layers have local caches.

The recursive resolver has SHA-256 sidecars for its executable, config checker, unique-query health probe, root hints, and trust-anchor seed. `unbound.sh ensure` validates all files, runs the pinned Android config checker, starts in foreground mode under PID identity validation, and requires a unique uncached recursive answer before FX allows DNS redirection. If this check fails, AdGuard Home is not brought up and DNS redirects remain disabled, preserving the pre-existing resolver or the established fail-open path.

The build was cross-compiled with Android NDK r26b/API 24 and passed the build pipeline's AArch64/linker checks and host config validation. Android runtime behavior, direct port-53 reachability on the user's mobile network, DNSSEC operation against live authoritative servers, and network-loss recovery still need OnePlus 12 device verification. A local recursive resolver cannot make DNS independent of the Internet: cache misses require reaching authoritative DNS servers, so the first lookup can be slower than a nearby public forwarder; cached lookups can be answered locally.

## Audit155 lifecycle hardening

The DNS owner exception is now narrow: only root-owned UDP/TCP traffic destined for port 53 bypasses FX DNS DNAT and the matching DNS-lockdown rules. The former blanket UID-0 `RETURN` behavior is explicitly rejected by regression tests because it could bypass unrelated proxy/filter rules. During uninstall, Unbound is stopped independently even if the AdGuard Home wrapper returns failure; if either service cannot be confirmed stopped, state files are preserved for retry. These are host-side code/test checks, not physical-device verification.
