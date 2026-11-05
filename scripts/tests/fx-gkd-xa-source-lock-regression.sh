#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
gitmodules="$root/.gitmodules"
test -s "$gitmodules" || { echo "FAIL: GKD-XA submodule declaration missing"; exit 1; }
git config -f "$gitmodules" --get submodule.vendor/GKD-XA.path | grep -Fxq 'vendor/GKD-XA'
git config -f "$gitmodules" --get submodule.vendor/GKD-XA.url | grep -Fxq 'https://github.com/84593320z/GKD-XA.git'
gitlink="$(git -C "$root" ls-tree HEAD vendor/GKD-XA)"
[[ "$gitlink" == "160000 commit 8a6ce935da11671dac7e1a7595416ec99ee07436"$'\t'"vendor/GKD-XA" ]] || {
  echo "FAIL: GKD-XA is not pinned to the reviewed v1.4.8 commit"
  echo "$gitlink"
  exit 1
}
grep -Fq '尚未合并进 FX APK' "$root/docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md"
echo "PASS: GKD-XA v1.4.8 source pin and non-completion boundary are recorded."
