# FX 1.0.0 root-side Hook configuration status

Date: 2026-10-30

This audit was performed against the extracted working FX source tree at `/mnt/data/fx-recovery/work`. The full root module source is not yet part of the isolated GitHub validation branch; these hashes identify the exact files audited in the working tree and must be rechecked when the root tree is imported.

## Verified source files

| File | SHA-256 |
|---|---|
| `scripts/gen_xposed_conf.sh` | `99416a257f0f4936484399de68c4cc6e2052a7456aacd106e06f8596f00413aa` |
| `webroot/index.html` | `70d8f80f2b9dd89ef8e4facc2d5bcf875dcb76f35571d976c32fa2820d12ef9e` |
| `scripts/tests/v1.0.0-lsposed-remote-file-config-regression.sh` | `3c0072d3508626b5c5c945598fb345703fc4c7e4da0b2200bc637c2ca4d7a6eb` |
| `scripts/tests/v1.0.0-hook-ui-api101-flags-regression.sh` | `75cc9c336da17660387d8a55370da77e7150ddbeabf028108444d2215805a70d` |
| `scripts/tests/v1.0.0-lsposed-ad-hook-target-scope-regression.sh` | `47ba9579a2202dbf23e746f8409a2ec67fd486b8976483043f144a5c70b89d67` |

## Confirmed behavior

- The per-app Hook editor exposes and persists the API101 flags: `clipboard_isolate`, `mic_hw_hide`, `audio_fp_block`, `block_notif_listen`, `hide_notif_perm`, `usagestats_off`, `a11y_hide`, `hide_fingerprint_hw`, and `hide_face_hw`.
- The Remote Files publisher validates these fields as strict boolean values, defaults omitted fields to `0`, and emits the complete schema to each Android user profile.
- The API82 legacy `xposed.conf` target format intentionally excludes modern-only fields. The Remote Files target count is calculated from the generated modern payload, not from the legacy mirror.
- Multi-user publication remains atomic/fail-closed: a user-profile publication failure removes all payloads written in that pass and reports failure.
- The legacy and modern configuration paths remain separate: the legacy file is not treated as proof that the API101 Remote Files payload was published.

## Host regression results

- `v1.0.0-lsposed-remote-file-config-regression.sh`: PASS
- `v1.0.0-hook-ui-api101-flags-regression.sh`: PASS
- `v1.0.0-lsposed-ad-hook-target-scope-regression.sh`: PASS

These are host-side tests only. They do not prove that LSPosed loaded the module or that any Hook works on a OnePlus 12. The root source still needs to be imported into the same GitHub source/build pipeline before the complete KernelSU package can be considered integrated.
