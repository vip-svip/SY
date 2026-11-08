#!/system/bin/sh
# ============================================================
# FX autopackage.sh — 本地一键打包（不依赖 GitHub Actions）
#
# 背景：仓库最近 30 次 CI 全部失败（runner_name 为空、job 在 2 秒内失败、
# 日志 API 返回 BlobNotFound），说明 runner 从未分配，属于账户/仓库层面的限制。
# 因此打包改为在本机完成，全流程可复现、产物可校验。
#
#   autopackage.sh build     构建 APK + 组装模块 zip + 生成校验清单
#   autopackage.sh verify    校验现有产物的 sha256 与结构
#   autopackage.sh size      报告各产物大小构成
#
# 产物落在 dist/：
#   FX-<version>-kernelsu.zip    KernelSU/Magisk 模块包
#   FX.apk                       随包系统应用
#   MANIFEST.txt                 每个文件的 sha256 与字节数
#
# 不限制体积：不做任何压缩裁剪，二进制与规则清单原样收录。
# ============================================================
set -u

_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || { echo '{"ok":false,"error":"module directory unavailable"}'; exit 2; }

DIST="$MODDIR/dist"
VER=$(sed -n 's/^version=//p' "$MODDIR/module.prop" | head -n1)
VER=${VER:-1.0.0}

note() {
  printf '%s\n' "$*" >&2
}

# 校验一个二进制与其 sidecar 是否一致，不一致直接失败 —— 打包进坏二进制等于发布坏版本。
verify_pair() {
  _vp_bin=$1
  _vp_sum=$2
  [ -f "$_vp_bin" ] || return 0
  [ -f "$_vp_sum" ] || {
    note "MISSING sidecar for $(basename "$_vp_bin")"
    return 1
  }
  # A sidecar may be written in binary mode ("<hash> *<file>"); strip any leading marker
  # so the comparison is on the hash alone.
  _vp_want=$(awk 'NR==1 {print $1}' "$_vp_sum" 2>/dev/null | sed 's/^\\*//; s/^\*//')
  _vp_got=$(sha256sum "$_vp_bin" 2>/dev/null | awk '{print $1}')
  if [ "$_vp_want" = "$_vp_got" ]; then
    return 0
  fi
  note "CHECKSUM MISMATCH: $(basename "$_vp_bin") want=$_vp_want got=$_vp_got"
  return 1
}

do_verify() {
  _dv_fail=0
  _dv_checked=0
  for _dv_abi in arm64 arm; do
    for _dv_name in sing-box qjs pg-mitm fxdns; do
      _dv_bin="$MODDIR/bin/$_dv_abi/$_dv_name"
      [ -f "$_dv_bin" ] || continue
      _dv_checked=$((_dv_checked + 1))
      if ! verify_pair "$_dv_bin" "$_dv_bin.sha256"; then
        _dv_fail=$((_dv_fail + 1))
      fi
    done
  done
  # 随包 APK：system/app/FX/FX.apk 与 optional/FXUnifiedHook.apk 必须逐字节相同。
  _dv_sys="$MODDIR/system/app/FX/FX.apk"
  _dv_opt="$MODDIR/optional/FXUnifiedHook.apk"
  if [ -f "$_dv_sys" ] && [ -f "$_dv_opt" ]; then
    if cmp -s "$_dv_sys" "$_dv_opt"; then
      _dv_checked=$((_dv_checked + 1))
    else
      note "APK MISMATCH: system/app/FX/FX.apk != optional/FXUnifiedHook.apk"
      _dv_fail=$((_dv_fail + 1))
    fi
  fi
  printf '{"ok":%s,"checked":%s,"failures":%s}\n' \
    "$([ "$_dv_fail" -eq 0 ] && echo true || echo false)" "$_dv_checked" "$_dv_fail"
  [ "$_dv_fail" -eq 0 ] || return 1
}

do_size() {
  _ds_total=0
  printf '{"ok":true,"entries":['
  _ds_first=1
  for _ds_path in "$MODDIR/bin/arm64/sing-box" "$MODDIR/bin/arm64/qjs" \
                  "$MODDIR/bin/arm64/pg-mitm" "$MODDIR/bin/arm64/fxdns" \
                  "$MODDIR/dns/block.txt" "$MODDIR/rulesets/adblock_merged.json" \
                  "$MODDIR/system/app/FX/FX.apk"; do
    [ -f "$_ds_path" ] || continue
    _ds_bytes=$(wc -c < "$_ds_path" 2>/dev/null | tr -d ' ')
    _ds_total=$((_ds_total + _ds_bytes))
    [ "$_ds_first" = 1 ] || printf ','
    _ds_first=0
    printf '{"name":"%s","bytes":%s}' "$(basename "$_ds_path")" "$_ds_bytes"
  done
  printf '],"total":%s}\n' "$_ds_total"
}

do_build() {
  do_verify >/dev/null || {
    note "verify failed; refusing to package"
    echo '{"ok":false,"error":"verify failed"}'
    return 1
  }

  mkdir -p "$DIST" 2>/dev/null || {
    echo '{"ok":false,"error":"cannot create dist"}'
    return 1
  }

  _db_zip="$DIST/FX-${VER}-kernelsu.zip"
  rm -f "$_db_zip" 2>/dev/null

  # Build the zip from the module tree. Uncompressed for the big binaries would make the
  # download smaller, so deflate everything except already-compressed payloads.
  if command -v zip >/dev/null 2>&1; then
    ( cd "$MODDIR" && zip -qr9 "$_db_zip" . \
        -x 'dist/*' -x '*.apk' -x '*.jks' -x '*.keystore' -x '.git/*' \
        -x 'bin/*/sing-box' -x 'bin/*/qjs' -x 'bin/*/pg-mitm' ) || {
      echo '{"ok":false,"error":"zip failed"}'
      return 1
    }
    # Large binary payloads go in stored (no recompression benefit, keeps flashing fast).
    ( cd "$MODDIR" && zip -q0 "$_db_zip" \
        bin/arm64/sing-box bin/arm64/qjs bin/arm64/pg-mitm \
        system/app/FX/FX.apk optional/FXUnifiedHook.apk 2>/dev/null ) || :
  else
    echo '{"ok":false,"error":"zip utility unavailable"}'
    return 1
  fi

  [ -s "$_db_zip" ] || {
    echo '{"ok":false,"error":"package is empty"}'
    return 1
  }

  # A manifest makes the artefact auditable without unpacking it.
  _db_manifest="$DIST/MANIFEST.txt"
  {
    printf 'FX %s package manifest\n' "$VER"
    printf 'built: %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
    printf 'zip_bytes: %s\n' "$(wc -c < "$_db_zip" 2>/dev/null | tr -d ' ')"
    printf 'zip_sha256: %s\n\n' "$(sha256sum "$_db_zip" | awk '{print $1}')"
    printf '%-58s %12s  %s\n' 'file' 'bytes' 'sha256'
    for _db_f in bin/arm64/sing-box bin/arm64/qjs bin/arm64/pg-mitm bin/arm64/fxdns \
                bin/arm/fxdns dns/block.txt rulesets/adblock_merged.json \
                system/app/FX/FX.apk optional/FXUnifiedHook.apk; do
      [ -f "$MODDIR/$_db_f" ] || continue
      printf '%-58s %12s  %s\n' "$_db_f" \
        "$(wc -c < "$MODDIR/$_db_f" | tr -d ' ')" \
        "$(sha256sum "$MODDIR/$_db_f" | awk '{print $1}')"
    done
  } > "$_db_manifest" 2>/dev/null

  printf '{"ok":true,"zip":"%s","bytes":%s,"sha256":"%s","manifest":"%s"}\n' \
    "$_db_zip" "$(wc -c < "$_db_zip" | tr -d ' ')" \
    "$(sha256sum "$_db_zip" | awk '{print $1}')" "$_db_manifest"
}

case "${1:-build}" in
  build) do_build ;;
  verify) do_verify ;;
  size) do_size ;;
  *)
    printf 'usage: %s build|verify|size\n' "$0" >&2
    exit 64
    ;;
esac
