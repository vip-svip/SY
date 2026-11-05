#!/system/bin/sh
# certmgr.sh — 内置系统级 CA 管理（自签 CA，默认不信任，仅用于受控 MITM 检测实验）
# 模块只管理系统级信任区：两张内置 CA 以独立子模块进入 /system/etc/security/cacerts，
# Android 14+ 再用 bind mount 覆盖 /apex/com.android.conscrypt/cacerts（Conscrypt 实际读取处）。
# 用户证书区(/data/misc/user/0/cacerts-added)本模块从不主动写入 — 只有明确的
# `cleanup restore`（卸载时调用）才会把历史版本隔离区里用户原有的证书移回。
# 重要: cacerts 文件名必须等于证书 subject 哈希, 否则信任库直接忽略该 CA:
#   Android 4.2~6 用 subject_hash_old (MD5), Android 7+ 用 subject_hash (SHA1),
#   两者都要 <hash>.0 文件（certs/ca-index 字段5/6 即这两个哈希）。
# 用法:
#   builtin release [certs目录]   — 安装时把 certs/submodules/* 释放为独立子模块 /data/adb/modules/pg_*_ca
#   builtin list                 — 两张内置 CA 的 系统信任/禁用/挂载 状态（A14+ 以 APEX 视图为准）
#   builtin enable|disable <名>  — 启用/禁用子模块并同步本次开机信任
#   builtin remove <名>          — 删除子模块并解除信任（写 remove 标记, 升级不复活）
#   builtin purge                — 卸载清理(删两个子模块+解除挂载)
#   builtin sync                 — 对齐"本次开机"信任状态(/system 与 A14+ APEX 覆盖层; 幂等, 可重复调用)
#   cleanup [restore|purge]      — 清历史残留: 默认只保留隔离区(不写用户证书区); restore=移回用户证书区, purge=删除
SM=/data/adb/modules
SC=/system/etc/security/cacerts
# Android 14+ 应用/Conscrypt 实际读取的信任库在 APEX 内，magic mount 碰不到，
# 只写 /system/etc/security/cacerts 时内置 CA 等于没装（证书警告根因之一）
SC_APEX=$(ls -d /apex/com.android.conscrypt/cacerts 2>/dev/null | head -1)
PG=/data/adb/privacyguard
OVL=$PG/cacerts-overlay
MARK=$PG/cacerts-overlay.mounted
OVL_APEX=$PG/cacerts-overlay-apex
MARK_APEX=$PG/cacerts-overlay-apex.mounted
MARK_APEX_PARTIAL=$PG/cacerts-overlay-apex.partial
MIGRATION_PENDING=$PG/cacerts-skipmount-pending
# 模块内 certs/ 目录：真机路径 + 沙盒测试路径
MDIR_CERTS=/data/adb/modules/privacyguard/certs
[ -d "$MDIR_CERTS" ] || MDIR_CERTS=/data/mod/certs
. "$(dirname "$MDIR_CERTS")/scripts/certcopy.sh" 2>/dev/null || . "$(dirname "$0")/certcopy.sh"
. "$(dirname "$MDIR_CERTS")/scripts/certmarker.sh" 2>/dev/null || { echo "cert: ERROR certmarker.sh 缺失" >&2; exit 1; }
. "$(dirname "$0")/cert-apex-ns.sh" 2>/dev/null || { echo "cert: ERROR cert-apex-ns.sh 缺失" >&2; exit 1; }

fp_of() {
  # Do not assume an openssl CLI exists on Android. Android/toybox normally has
  # base64 -d + sha256sum; ca_fp16 computes the same SHA-256 of DER as fallback.
  if command -v openssl >/dev/null 2>&1; then
    _fp_ossl=$(openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//;s/://g' | tr 'A-F' 'a-f' | cut -c1-16)
    [ -n "$_fp_ossl" ] && { printf '%s' "$_fp_ossl"; return 0; }
  fi
  ca_fp16 "$1"
}
# Full DER SHA-256 is required for trust decisions; the 16-char ca-index
# fingerprint is only a compact display/migration key, never proof of trust.
ca_fp256() {
  _cf256_f="$1"
  [ -f "$_cf256_f" ] || return 1
  grep -q -- '-----BEGIN CERTIFICATE-----' "$_cf256_f" 2>/dev/null || return 1
  grep -q -- '-----END CERTIFICATE-----' "$_cf256_f" 2>/dev/null || return 1
  command -v base64 >/dev/null 2>&1 || return 1
  command -v sha256sum >/dev/null 2>&1 || return 1
  _cf256_b64=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$_cf256_f" 2>/dev/null \
    | grep -v -- '-----' | tr -d '\r\n \t')
  [ -n "$_cf256_b64" ] || return 1
  # Stage DER only inside the module's root-controlled state directory. A
  # predictable file directly under /data/local/tmp would permit symlink races
  # when this function is executed as root by the WebUI bridge.
  [ -d "$PG" ] && [ -w "$PG" ] || return 1
  _cf256_workdir="$PG/.cert-fp256.$$"
  (umask 077; mkdir "$_cf256_workdir") 2>/dev/null || return 1
  chmod 700 "$_cf256_workdir" 2>/dev/null || { rm -rf "$_cf256_workdir" 2>/dev/null; return 1; }
  _cf256_tmp="$_cf256_workdir/der"
  if ! printf '%s' "$_cf256_b64" | base64 -d > "$_cf256_tmp" 2>/dev/null || [ ! -s "$_cf256_tmp" ]; then
    rm -rf "$_cf256_workdir" 2>/dev/null
    return 1
  fi
  _cf256_fp=$(sha256sum "$_cf256_tmp" 2>/dev/null | awk '{print tolower($1)}')
  rm -rf "$_cf256_workdir" 2>/dev/null
  case "$_cf256_fp" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#_cf256_fp}" -eq 64 ] || return 1
  printf '%s' "$_cf256_fp"
}
ca_file_matches256() {
  _cm256_file="$1"; _cm256_expected=$(printf '%s' "$2" | tr 'A-F' 'a-f')
  [ -f "$_cm256_file" ] && [ -n "$_cm256_expected" ] || return 1
  case "$_cm256_expected" in *[!0-9a-f]*) return 1 ;; esac
  [ "${#_cm256_expected}" -eq 64 ] || return 1
  _cm256_actual=$(ca_fp256 "$_cm256_file") || return 1
  [ "$_cm256_actual" = "$_cm256_expected" ]
}
# Resolve a source CA by its compact index prefix, then return its complete
# fingerprint. If no source matches the index, callers fail closed instead of
# comparing only a 64-bit prefix against a potentially colliding certificate.
ca_expected_fp256() {
  _cef_id="$1"; _cef_short=$(printf '%s' "$(idx "$_cef_id" 3)" | tr 'A-F' 'a-f')
  [ -n "$_cef_short" ] || return 1
  for _cef_dir in "$MDIR_CERTS/submodules/$_cef_id/system/etc/security/cacerts" \
                  "$SM/$_cef_id/system/etc/security/cacerts"; do
    [ -d "$_cef_dir" ] || continue
    for _cef_file in "$_cef_dir"/*.0; do
      [ -f "$_cef_file" ] || continue
      _cef_actual_short=$(fp_of "$_cef_file") || continue
      [ "$(printf '%s' "$_cef_actual_short" | tr 'A-F' 'a-f')" = "$_cef_short" ] || continue
      ca_fp256 "$_cef_file" && return 0
    done
  done
  echo "cert: ERROR unable to resolve indexed CA fingerprint for $_cef_id; refusing trust decision" >&2
  return 1
}
# Compatibility wrapper for older call sites that only need compact index checks.
ca_file_matches() {
  _cm_file="$1"; _cm_expected=$(printf '%s' "$2" | tr 'A-F' 'a-f')
  [ -f "$_cm_file" ] && [ -n "$_cm_expected" ] || return 1
  _cm_actual=$(fp_of "$_cm_file")
  [ -n "$_cm_actual" ] && [ "$_cm_actual" = "$_cm_expected" ]
}

# Search all Android hash collision slots, not only <hash>.0. A CA may safely
# occupy .1/.2 when another system certificate has the same subject hash.
ca_store_has_cert() {
  _csh_dir="$1"; _csh_h1="$2"; _csh_h2="$3"; _csh_fp256="$4"
  case "$_csh_fp256" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
  [ "${#_csh_fp256}" -eq 64 ] || return 1
  for _csh_hash in "$_csh_h1" "$_csh_h2"; do
    case "$_csh_hash" in ''|*[!0-9a-fA-F]*) continue ;; esac
    _csh_n=0
    while [ "$_csh_n" -le 99 ]; do
      if ca_file_matches256 "$_csh_dir/$_csh_hash.$_csh_n" "$_csh_fp256"; then return 0; fi
      _csh_n=$((_csh_n+1))
    done
  done
  return 1
}
subj_of() {
  openssl x509 -in "$1" -noout -subject 2>/dev/null | sed 's/^subject=//'
}

# ---- ca-index 辅助: idx <显示名或目录名> <字段号2-6> ----
idx() {
  KEY="$1"; F="$2"
  [ -f "$MDIR_CERTS/ca-index" ] || return 1
  LINE=$(grep -v '^#' "$MDIR_CERTS/ca-index" | grep "|$KEY|" | head -1)
  [ -z "$LINE" ] && LINE=$(grep -v '^#' "$MDIR_CERTS/ca-index" | grep "^$KEY|" | head -1)
  [ -z "$LINE" ] && return 1
  echo "$LINE" | awk -F'|' -v f="$F" '{print $f}'
}

# ---- 子模块目录名清单 ----
ca_ids() {
  [ -f "$MDIR_CERTS/ca-index" ] || return 0
  grep -v '^#' "$MDIR_CERTS/ca-index" | awk -F'|' '{print $2}'
}

# ---- 同步本次开机信任: 按需 bind mount 覆盖 /system/etc/security/cacerts ----
# 触发挂载的两种情况:
#   1) 启用的子模块文件不在当前视图 → 覆盖层把它带进来(即时启用)
#   2) 已禁用的子模块文件仍在当前视图(magic mount 未刷新) → 覆盖层把它藏掉(即时禁用)
# 稳态(重启后)两种情况都不成立 → 不挂覆盖层, 不干扰系统和其他模块
# 注意: 本函数变量一律 _cs_ 前缀 — POSIX sh 函数无局部变量, 防止覆盖调用方的 id 等变量
# ---- SELinux 标签: cacerts 必须带专用类型, 否则应用读不到(表现为"装了仍不受信任") ----
ca_chcon() {
  _cc_dir="$1"; _cc_ref="${2:-}"
  [ -d "$_cc_dir" ] || { echo "cert: ERROR SELinux label target missing: $_cc_dir" >&2; return 1; }
  command -v chcon >/dev/null 2>&1 || { echo "cert: ERROR chcon unavailable; refusing to publish CA trust overlay" >&2; return 1; }
  _cc_ref_label=""
  # Prefer the actual label of an existing stock certificate in the target trust
  # store. AOSP Conscrypt labels /cacerts entries system_security_cacerts_file.
  if [ -n "$_cc_ref" ] && [ -d "$_cc_ref" ] && command -v ls >/dev/null 2>&1; then
    _cc_ref_file=$(find "$_cc_ref" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | head -1)
    if [ -n "$_cc_ref_file" ]; then
      _cc_ref_label=$(ls -Z "$_cc_ref_file" 2>/dev/null | awk 'NR==1 {print $1}')
      case "$_cc_ref_label" in *:*) ;; *) _cc_ref_label="" ;; esac
    fi
  fi
  _cc_probe=$(find "$_cc_dir" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | head -1)
  [ -n "$_cc_probe" ] || { echo "cert: ERROR no numbered CA file to verify SELinux labeling in $_cc_dir" >&2; return 1; }
  # Try the target store's exact file label first, then known AOSP labels. A
  # successful chcon exit is not enough: verify the resulting label on a CA file.
  for _cc_ctx in "$_cc_ref_label" u:object_r:system_security_cacerts_file:s0; do
    [ -n "$_cc_ctx" ] || continue
    if chcon -R "$_cc_ctx" "$_cc_dir" 2>/dev/null; then
      _cc_actual=$(ls -Z "$_cc_probe" 2>/dev/null | awk 'NR==1 {print $1}')
      if [ "$_cc_actual" = "$_cc_ctx" ]; then return 0; fi
    fi
  done
  echo "cert: ERROR unable to apply and verify a readable SELinux context on CA overlay $_cc_dir; original trust store will be preserved" >&2
  return 1
}

# ---- 证书 PEM → SHA256 指纹前16位（用于校验证书与 ca-index 行是否对应）----
# Android toybox / busybox 一般自带 base64 与 sha256sum, 无需 openssl。
ca_fp16() {
  _cf16_fp=$(ca_fp256 "$1") || return 1
  printf '%s' "$_cf16_fp" | cut -c1-16
}

# ---- 兼容旧安装: 就地校正 cacerts 文件名与 ca-index 字段5/6 ----
# Android 信任库按证书 subject 哈希取名(<hash>.0): Android 4.2~6 用
# subject_hash_old(MD5), Android 7+ 用 subject_hash(SHA1)。文件名不对时该 CA
# 会被信任库忽略(Settings 的「信任的凭据」里也看不到) → 表现为「装了证书但
# 应用仍报证书不受信任/证书警告」。历史版本的哈希可能与当前证书不同；这里始终按随包 PEM 的实际 subject_hash / subject_hash_old 校正。
# 有 openssl 时直接算哈希(最权威, 并回写 ca-index); 没有 openssl(多数设备)时
# 用 ca-index 字段5/6 取名, 但先用证书 SHA256 前16位(字段3)校验对应关系,
# 避免把错名套到证书上。
ca_selfheal() {
  [ -f "$MDIR_CERTS/ca-index" ] || return 0
  _hs_ossl=0
  command -v openssl >/dev/null 2>&1 && _hs_ossl=1
  # 临时文件名必须带 PID：旧版固定用 $PG/ca-index.tmp，当 WebUI 轮询、apply.sh、
  # post-fs-data 同时各跑一次 certmgr 时，多个进程交错追加同一临时文件、再各自
  # `mv -f` 覆盖 ca-index，会把索引写坏甚至整行丢失（真机实测并发 2×sync ×6 组，
  # ca-index 行数出现 5/11/22/6/3，其中一轮 pg_mitm_ca 行整个消失，
  # 表现为 WebUI『内置 CA』里 MITM 证书凭空不见）。
  _hs_tmp="$PG/ca-index.$$.tmp"
  : > "$_hs_tmp" 2>/dev/null || return 0
  while IFS= read -r _hs_line; do
    case "$_hs_line" in
      ''|'#'*) printf '%s\n' "$_hs_line" >> "$_hs_tmp"; continue ;;
    esac
    _hs_id=$(printf '%s' "$_hs_line" | awk -F'|' '{print $2}')
    _hs_fp_idx=$(printf '%s' "$_hs_line" | awk -F'|' '{print $3}')
    _hs_sha1=""; _hs_md5=""
    # 取一个可读证书文件: 模板目录优先, 其次已释放子模块(开机真正生效的是后者)
    _hs_first=""
    for _hs_dir in "$MDIR_CERTS/submodules/$_hs_id/system/etc/security/cacerts" \
                   "$SM/$_hs_id/system/etc/security/cacerts"; do
      [ -d "$_hs_dir" ] || continue
      for _hs_f in "$_hs_dir"/*.0; do
        [ -f "$_hs_f" ] || continue
        _hs_first="$_hs_f"; break
      done
      [ -n "$_hs_first" ] && break
    done
    if [ -n "$_hs_first" ]; then
      if [ "$_hs_ossl" = 1 ]; then
        _hs_sha1=$(openssl x509 -in "$_hs_first" -noout -subject_hash 2>/dev/null)
        _hs_md5=$(openssl x509 -in "$_hs_first" -noout -subject_hash_old 2>/dev/null)
      fi
      if [ -z "$_hs_sha1" ] || [ -z "$_hs_md5" ]; then
        # 无 openssl: 用 ca-index 的字段5/6, 但必须确认这份证书就是该索引行
        _hs_fp=$(ca_fp16 "$_hs_first")
        if [ -n "$_hs_fp" ] && [ "$_hs_fp" = "$_hs_fp_idx" ]; then
          _hs_sha1=$(idx "$_hs_id" 6); _hs_md5=$(idx "$_hs_id" 5)
        fi
      fi
    fi
    # 两处都校正: 模板目录 + 已释放子模块
    if [ -n "$_hs_sha1" ] || [ -n "$_hs_md5" ]; then
      for _hs_dir in "$MDIR_CERTS/submodules/$_hs_id/system/etc/security/cacerts" \
                     "$SM/$_hs_id/system/etc/security/cacerts"; do
        [ -d "$_hs_dir" ] || continue
        for _hs_f in "$_hs_dir"/*.0; do
          [ -f "$_hs_f" ] || continue
          # 按目标名补齐(同一子模块只有一张证书)
          [ -n "$_hs_sha1" ] && [ ! -f "$_hs_dir/$_hs_sha1.0" ] && cp -f "$_hs_f" "$_hs_dir/$_hs_sha1.0" 2>/dev/null
          [ -n "$_hs_md5" ]  && [ ! -f "$_hs_dir/$_hs_md5.0" ]  && cp -f "$_hs_f" "$_hs_dir/$_hs_md5.0" 2>/dev/null
          # 删除不属于当前证书 subject_hash / subject_hash_old 的残留文件
          _hs_n=$(basename "$_hs_f" .0)
          if [ "$_hs_n" != "$_hs_sha1" ] && [ "$_hs_n" != "$_hs_md5" ]; then
            rm -f "$_hs_f" 2>/dev/null
          fi
        done
        chmod 644 "$_hs_dir"/*.0 2>/dev/null
        # These are stored templates/child-module files under /data, not active
        # trust-store files. SELinux trust-store labels are applied only to the
        # collision-safe live overlays in ca_sync/ca_sync_apex.
      done
    fi
    # 回写索引字段5/6（仅 openssl 算出的权威值; 无 openssl 时保持索引原样）
    if [ "$_hs_ossl" = 1 ] && [ -n "$_hs_sha1" ]; then
      printf '%s\n' "$_hs_line" | awk -F'|' -v m="$_hs_md5" -v s="$_hs_sha1" \
        'BEGIN{OFS="|"} {if(NF>=6){$5=m;$6=s}}1' >> "$_hs_tmp"
    else
      printf '%s\n' "$_hs_line" >> "$_hs_tmp"
    fi
  done < "$MDIR_CERTS/ca-index"
  # 内容未变就不写模块目录(避免每次 sync 都改文件)
  _hs_same=0
  if command -v cmp >/dev/null 2>&1; then
    cmp -s "$_hs_tmp" "$MDIR_CERTS/ca-index" 2>/dev/null && _hs_same=1
  fi
  if [ "$_hs_same" = 1 ]; then
    rm -f "$_hs_tmp" 2>/dev/null
  else
    mv -f "$_hs_tmp" "$MDIR_CERTS/ca-index" 2>/dev/null || rm -f "$_hs_tmp" 2>/dev/null
  fi
}

# ---- Android 14+ (Conscrypt APEX) 信任库覆盖 ----
# A14 起应用从 /apex/com.android.conscrypt/cacerts 读取根证书，magic mount 的
# /system/etc/security/cacerts 对它无效。这里合成一份并 bind mount 覆盖。
# 局限: 仅对之后启动的进程生效，已运行的应用需重启进程或整机重启。
ca_sync_apex() {
  [ -n "$SC_APEX" ] || return 0
  [ -d "$SC_APEX" ] || return 0
  # APEX overlays are mounted in several process mount namespaces. Detach every
  # marker-owned view before rebuilding/deleting the shared source directory.
  if ! ca_apex_ns_unmount_all "$SC_APEX" "$PG" "$MARK_APEX"; then
    echo "cert: ERROR unable to reconcile all Conscrypt APEX namespaces; preserving $OVL_APEX" >&2
    return 1
  fi
  if [ -e "$OVL_APEX" ] && ! rm -rf "$OVL_APEX"; then
    echo "cert: ERROR unable to remove detached APEX overlay source; preserving trust state for retry" >&2
    return 1
  fi
  rm -f "$MARK_APEX_PARTIAL" 2>/dev/null
  _ca_need=0
  for _ca_id in $(ca_ids); do
    _ca_dir="$SM/$_ca_id"
    _ca_src="$MDIR_CERTS/submodules/$_ca_id/system/etc/security/cacerts"
    [ -d "$_ca_src" ] || continue
    _ca_h1=$(idx "$_ca_id" 5); _ca_h2=$(idx "$_ca_id" 6)
    _ca_fp256=$(ca_expected_fp256 "$_ca_id") || { echo "cert: ERROR APEX sync cannot verify full fingerprint for $_ca_id" >&2; return 1; }
    _ca_enabled=1
    [ -d "$_ca_dir" ] || _ca_enabled=0
    [ -f "$_ca_dir/disable" ] && _ca_enabled=0
    [ -f "$_ca_dir/remove" ] && _ca_enabled=0
    if [ "$_ca_enabled" = 1 ]; then
      ca_store_has_cert "$SC_APEX" "$_ca_h1" "$_ca_h2" "$_ca_fp256" || _ca_need=1
    fi
  done
  [ "$_ca_need" = 1 ] || return 0
  # 就绪检查: 早期(post-fs-data)同步时 APEX 可能还没挂载/为空; 空覆盖层会把
  # 公共根证书全部隐藏, 反而让浏览器对所有 HTTPS 站点报证书错误 — 必须先确认
  # 存量信任库已就绪, 否则本次跳过(apply.sh 在 boot_completed 后还会再同步一次)。
  # Subject-hash collisions are represented as <hash>.1, .2, ... as well as .0.
  # Preserve every numbered CA file; counting only *.0 can silently omit valid roots.
  _ca_stock_n=$(find "$SC_APEX" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | wc -l | tr -d ' ')
  if [ -z "$_ca_stock_n" ] || [ "$_ca_stock_n" -lt 1 ]; then
    echo "cert: ERROR $SC_APEX 信任库未就绪，跳过本次挂载（稍后 sync 重试）" >&2
    return 1
  fi
  rm -rf "$OVL_APEX"; mkdir -p "$OVL_APEX" 2>/dev/null || { echo "cert: ERROR 无法创建 APEX 覆盖层目录" >&2; return 1; }
  find "$SC_APEX" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | while IFS= read -r _ca_src; do cp -p "$_ca_src" "$OVL_APEX/" 2>/dev/null || exit 1; done
  [ "$?" -eq 0 ] || { echo "cert: ERROR 复制 APEX 系统证书失败，拒绝挂载" >&2; rm -rf "$OVL_APEX"; return 1; }
  for _ca_id in $(ca_ids); do
    _ca_dir="$SM/$_ca_id"
    _ca_src="$MDIR_CERTS/submodules/$_ca_id/system/etc/security/cacerts"
    [ -d "$_ca_src" ] || continue
    _ca_enabled=1
    [ -d "$_ca_dir" ] || _ca_enabled=0
    [ -f "$_ca_dir/disable" ] && _ca_enabled=0
    [ -f "$_ca_dir/remove" ] && _ca_enabled=0
    if [ "$_ca_enabled" = 1 ]; then
      if ! ca_copy_submodule_certs "$_ca_src" "$OVL_APEX" "APEX"; then
        rm -rf "$OVL_APEX" 2>/dev/null
        return 1
      fi
    fi
  done
  # 完整性检查: 覆盖层必须包含全部存量证书, 缺一张公共根都会造成 TLS 校验失败
  _ca_ovl_n=$(find "$OVL_APEX" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | wc -l | tr -d ' ')
  if [ -z "$_ca_ovl_n" ] || [ "$_ca_ovl_n" -lt "$_ca_stock_n" ]; then
    echo "cert: WARN $SC_APEX 覆盖层不完整($_ca_ovl_n/$_ca_stock_n)，拒绝挂载以免破坏公共信任链" >&2
    rm -rf "$OVL_APEX" 2>/dev/null
    return 1
  fi
  find "$OVL_APEX" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | while IFS= read -r _ca_f; do chmod 644 "$_ca_f" 2>/dev/null; done
  if ! ca_chcon "$OVL_APEX" "$SC_APEX"; then
    rm -rf "$OVL_APEX" 2>/dev/null
    echo "cert: ERROR APEX overlay SELinux labeling failed; refusing to mount custom trust store" >&2
    return 1
  fi
  if ! ca_apex_ns_mount_all "$OVL_APEX" "$SC_APEX" "$PG"; then
    echo "cert: ERROR 无法在必需的 Conscrypt/zygote 命名空间验证 CA 覆盖层" >&2
    if ca_apex_ns_unmount_all "$SC_APEX" "$PG" "$MARK_APEX"; then
      rm -rf "$OVL_APEX" 2>/dev/null || echo "cert: WARN detached overlay cleanup failed; source retained at $OVL_APEX" >&2
    else
      echo "cert: CRITICAL partial namespace cleanup failed; preserving $OVL_APEX for safe recovery" >&2
    fi
    return 1
  fi
  _ca_apex_marker_tmp="$MARK_APEX.tmp.$$"
  if ! { printf '%s\n' "$SC_APEX" > "$_ca_apex_marker_tmp"; } 2>/dev/null || \
     ! chmod 600 "$_ca_apex_marker_tmp" 2>/dev/null || ! mv -f "$_ca_apex_marker_tmp" "$MARK_APEX" 2>/dev/null; then
    rm -f "$_ca_apex_marker_tmp" 2>/dev/null
    echo "cert: ERROR APEX global marker publication failed; attempting namespace rollback" >&2
    if ca_apex_ns_unmount_all "$SC_APEX" "$PG" "$MARK_APEX"; then
      rm -rf "$OVL_APEX" 2>/dev/null || echo "cert: WARN marker rollback complete but overlay cleanup failed" >&2
    else
      echo "cert: CRITICAL marker publication rollback incomplete; preserving overlay source" >&2
    fi
    return 1
  fi
  if [ "${CA_APEX_NS_PARTIAL:-0}" = 1 ]; then
    _ca_partial_tmp="$MARK_APEX_PARTIAL.tmp.$$"
    if { printf '1\n' > "$_ca_partial_tmp"; } 2>/dev/null && chmod 600 "$_ca_partial_tmp" 2>/dev/null && mv -f "$_ca_partial_tmp" "$MARK_APEX_PARTIAL" 2>/dev/null; then
      echo "cert: WARN some optional app namespaces could not be updated; current app trust is partial and may require app restart" >&2
    else
      rm -f "$_ca_partial_tmp" 2>/dev/null
      echo "cert: WARN optional namespace status could not be persisted" >&2
    fi
  else
    rm -f "$MARK_APEX_PARTIAL" 2>/dev/null
  fi
  echo "cert: live overlay mounted and verified in required namespaces on $SC_APEX (A14+ APEX)"

}

# ---- 同步本次开机信任: 按需 bind mount 覆盖 /system/etc/security/cacerts ----
ca_sync() {
  _cs_system_error=0
  _cs_apex_error=0
  # 先卸掉本模块历史 live 挂载（多层一并揭净，8 层保险上限）
  # 关键（v1.10.5 修复）：只有确认 umount 真的成功才允许删覆盖层源目录。
  # 旧写法 `while umount ...; do :; done` 会吞掉 EBUSY：若挂载点仍被占用
  # （有进程 cwd/打开句柄在里面，或并发 certmgr/apply 正在读），循环退出后
  # 紧接着 `rm -rf "$OVL"` 会删掉「仍在生效的 bind mount 的源文件」→
  # /system/etc/security/cacerts 立刻读成空（0 张证书）→ 全站 HTTPS 报
  # `unable to get local issuer certificate`。真机已 100% 复现。
  # Marker loss must not make us delete the source of a still-live bind mount.
  if [ ! -f "$MARK" ] && mount 2>/dev/null | grep -q " $SC "; then
    echo "cert: ERROR $SC 已挂载但标记缺失，保留 $OVL；本次同步未完成" >&2
    return 1
  fi
  if [ -f "$MARK" ]; then
    _cs_n=0
    while umount "$SC" 2>/dev/null; do
      _cs_n=$((_cs_n+1)); [ $_cs_n -ge 8 ] && break
    done
    if mount 2>/dev/null | grep -q " $SC "; then
      echo "cert: ERROR $SC 仍处于挂载状态(EBUSY)，保留 $OVL 但本次同步未完成" >&2
      return 1
    else
      rm -f "$MARK"; rm -rf "$OVL"
    fi
  fi
  # APEX namespaces are reconciled inside ca_sync_apex; never detach only this shell's view here.
  _cs_need=0
  for _cs_id in $(ca_ids); do
    _cs_dir="$SM/$_cs_id"
    _cs_src="$MDIR_CERTS/submodules/$_cs_id/system/etc/security/cacerts"
    [ -d "$_cs_src" ] || continue
    _cs_h1=$(idx "$_cs_id" 5); _cs_h2=$(idx "$_cs_id" 6)
    _cs_fp256=$(ca_expected_fp256 "$_cs_id") || { echo "cert: ERROR system sync cannot verify full fingerprint for $_cs_id" >&2; return 1; }
    _cs_enabled=1
    [ -d "$_cs_dir" ] || _cs_enabled=0
    [ -f "$_cs_dir/disable" ] && _cs_enabled=0
    [ -f "$_cs_dir/remove" ] && _cs_enabled=0
    _cs_found=0
    ca_store_has_cert "$SC" "$_cs_h1" "$_cs_h2" "$_cs_fp256" && _cs_found=1
    if [ "$_cs_enabled" = 1 ] && [ "$_cs_found" = 0 ]; then _cs_need=1; fi
    if [ "$_cs_enabled" != 1 ] && [ "$_cs_found" = 1 ]; then _cs_need=1; fi
  done
  if [ "$_cs_need" = 1 ]; then
    # Keep all numbered hash entries: .1/.2 are valid collision-chain certificates.
    _cs_stock_n=$(find "$SC" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | wc -l | tr -d ' ')
    if [ -z "$_cs_stock_n" ] || [ "$_cs_stock_n" -lt 1 ]; then
      echo "cert: ERROR $SC 信任库未就绪，跳过本次挂载（稍后 sync 重试）" >&2
      _cs_system_error=1
    else
      rm -rf "$OVL"; mkdir -p "$OVL"
      _cs_removed=0
      find "$SC" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | while IFS= read -r _cs_src; do cp -p "$_cs_src" "$OVL/" 2>/dev/null || exit 1; done
      if [ "$?" -ne 0 ]; then echo "cert: ERROR 复制系统证书失败，拒绝挂载" >&2; rm -rf "$OVL" 2>/dev/null; return 1; fi
      for _cs_id in $(ca_ids); do
        _cs_dir="$SM/$_cs_id"
        _cs_src="$MDIR_CERTS/submodules/$_cs_id/system/etc/security/cacerts"
        [ -d "$_cs_src" ] || continue
        _cs_enabled=1
        [ -d "$_cs_dir" ] || _cs_enabled=0
        [ -f "$_cs_dir/disable" ] && _cs_enabled=0
        [ -f "$_cs_dir/remove" ] && _cs_enabled=0
        if [ "$_cs_enabled" = 1 ]; then
          if ! ca_copy_submodule_certs "$_cs_src" "$OVL" "system"; then
            rm -rf "$OVL" 2>/dev/null
            return 1
          fi
        else
          if ! ca_remove_submodule_certs "$_cs_src" "$OVL" "system"; then
            rm -rf "$OVL" 2>/dev/null
            return 1
          fi
          _cs_removed=$((_cs_removed+${CA_REMOVED_CERT_COUNT:-0}))
        fi
      done
      _cs_ovl_n=$(find "$OVL" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | wc -l | tr -d ' ')
      _cs_effective_n=$((_cs_ovl_n+_cs_removed))
      if [ -z "$_cs_ovl_n" ] || [ "$_cs_effective_n" -lt "$_cs_stock_n" ]; then
        echo "cert: ERROR $SC 覆盖层不完整(实际 $_cs_ovl_n + 已移除本模块 CA $_cs_removed / 原视图 $_cs_stock_n)，拒绝挂载" >&2
        rm -rf "$OVL" 2>/dev/null
        return 1
      else
        find "$OVL" -maxdepth 1 -type f 2>/dev/null | grep -E '/[0-9a-fA-F]+\.[0-9]+$' | while IFS= read -r _cs_f; do chmod 644 "$_cs_f" 2>/dev/null; done
        if ! ca_chcon "$OVL" "$SC"; then
          echo "cert: ERROR system CA overlay SELinux labeling failed; refusing to mount custom trust store" >&2
          rm -rf "$OVL" 2>/dev/null
          _cs_system_error=1
          return 1
        fi
        if mount --bind "$OVL" "$SC" 2>/dev/null; then
          if ! ca_commit_mount_marker "$MARK" "$SC" "$OVL"; then
            echo "cert: ERROR /system 挂载成功但标记提交失败；已尝试卸载，源目录仅在确认卸载后清理" >&2
            return 1
          fi
          echo "cert: live overlay mounted on $SC"
        else
          echo "cert: ERROR bind mount $SC 失败 — 当前启动周期未生效"
          rm -rf "$OVL"
          return 1
        fi
      fi
    fi
  fi
  _cs_apex_rc=0
  ca_sync_apex || _cs_apex_rc=1
  [ "${_cs_system_error:-0}" = 0 ] || return 1
  [ "${_cs_apex_error:-0}" = 0 ] || return 1
  [ "$_cs_apex_rc" = 0 ] || return 1
  # This is the only general clear path: it runs after both trust views synced.
  pg_cert_clear_migration_pending_after_sync || :
  return 0
}

# ---- 全局互斥锁（POSIX sh，toybox 无 flock）----
# mkdir 提供原子创建；锁内记录 PID。绝不因固定等待时间到期就抢占仍存活进程的锁。
# 陈旧锁通过原子 rename 竞争清理；拿锁超时返回失败，避免并发写坏 ca-index。
PG_CERTLOCK="$PG/certmgr.lock"
pg_cert_lock() {
  mkdir -p "$PG" 2>/dev/null || return 1
  _lk_w=0
  while :; do
    if mkdir "$PG_CERTLOCK" 2>/dev/null; then
      printf '%s\n' "$$" > "$PG_CERTLOCK/pid" || { rmdir "$PG_CERTLOCK" 2>/dev/null; return 1; }
      return 0
    fi
    _lk_owner="$(cat "$PG_CERTLOCK/pid" 2>/dev/null)"
    case "$_lk_owner" in
      ''|*[!0-9]*)
        # mkdir 与写入 pid 之间存在极短窗口，先等待；超过 2 秒才视为损坏锁。
        if [ "$_lk_w" -ge 10 ]; then
          _lk_stale="$PG/certmgr.lock.stale.$$"
          if mv "$PG_CERTLOCK" "$_lk_stale" 2>/dev/null; then
            rm -rf "$_lk_stale" 2>/dev/null
            _lk_w=0
            continue
          fi
        fi
        ;;
      *)
        if ! kill -0 "$_lk_owner" 2>/dev/null; then
          _lk_stale="$PG/certmgr.lock.stale.$$"
          if mv "$PG_CERTLOCK" "$_lk_stale" 2>/dev/null; then
            rm -rf "$_lk_stale" 2>/dev/null
            _lk_w=0
            continue
          fi
        fi
        ;;
    esac
    _lk_w=$((_lk_w+1))
    if [ "$_lk_w" -ge 150 ]; then
      echo "cert: ERROR 证书锁被占用超过 30 秒，拒绝并发修改: $PG_CERTLOCK" >&2
      return 1
    fi
    sleep 0.2 2>/dev/null || sleep 1
  done
}
pg_cert_unlock() {
  _lk_owner="$(cat "$PG_CERTLOCK/pid" 2>/dev/null)"
  [ "$_lk_owner" = "$$" ] && rm -rf "$PG_CERTLOCK" 2>/dev/null
}

# Child CA modules are storage containers; certmgr, not KernelSU's raw filename
# overlay, publishes their certificates into the active trust store. This avoids
# overwriting a different stock root with the same subject hash. Migrate legacy
# child directories before any mutating action and before trust synchronization.
pg_cert_ensure_skip_mount() {
  _esm_failed=0; _esm_changed=0; _esm_active_changed=0; _esm_pending_reboot=0
  _esm_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  [ -n "$_esm_boot" ] || _esm_boot=unknown
  if [ -f "$MIGRATION_PENDING" ]; then
    _esm_pending_id=$(cat "$MIGRATION_PENDING" 2>/dev/null)
    # Never infer a reboot if the boot ID is unavailable or the marker is empty.
    if [ "$_esm_boot" = unknown ] || [ -z "$_esm_pending_id" ] || [ "$_esm_pending_id" = "$_esm_boot" ]; then
      _esm_pending_reboot=1
    fi
  fi
  for _esm_id in pg_mitm_ca pg_https_ca; do
    _esm_dir="$SM/$_esm_id"
    [ -d "$_esm_dir" ] && [ -f "$_esm_dir/module.prop" ] || continue
    if [ ! -f "$_esm_dir/skip_mount" ]; then
      if ! (umask 077; : > "$_esm_dir/skip_mount") || ! chmod 644 "$_esm_dir/skip_mount" 2>/dev/null; then
        echo "cert: ERROR unable to mark legacy child $_esm_id skip_mount; refusing trust mutation to prevent hash-slot overwrite" >&2
        _esm_failed=1
      else
        _esm_changed=1
        if [ ! -f "$_esm_dir/disable" ] && [ ! -f "$_esm_dir/remove" ]; then _esm_active_changed=1; fi
        echo "cert: migrated $_esm_id to certmgr-owned collision-safe trust publication" >&2
      fi
    fi
  done
  # If an active legacy child was mounted earlier this boot, adding skip_mount
  # cannot revoke the already-installed KernelSU mount. Do not mutate trust from
  # a possibly clobbered source store; require a reboot to let the marker take
  # effect before rebuilding the trust view.
  if [ "$_esm_active_changed" = 1 ]; then
    _esm_tmp="$MIGRATION_PENDING.tmp.$$"
    if ! (umask 077; printf '%s\n' "$_esm_boot" > "$_esm_tmp") || ! chmod 600 "$_esm_tmp" 2>/dev/null || ! mv -f "$_esm_tmp" "$MIGRATION_PENDING" 2>/dev/null; then
      rm -f "$_esm_tmp" 2>/dev/null
      echo "cert: ERROR unable to persist pending reboot marker for CA collision-safe migration" >&2
      _esm_failed=1
    fi
    echo "cert: ERROR legacy active CA mounts may still shadow stock roots this boot; restart is required before further trust changes" >&2
    return 1
  fi
  if [ "$_esm_pending_reboot" = 1 ]; then
    echo "cert: ERROR collision-safe CA mount migration is pending a full reboot; trust mutations are blocked until next boot" >&2
    return 1
  fi
  [ "$_esm_failed" = 0 ] || return 1
}

# Clear the legacy migration warning only after the previous boot's skip_mount
# state has taken effect AND a complete trust synchronization succeeded.
# A same-boot call must never clear the marker: those raw mounts may still live.
pg_cert_clear_migration_pending_after_sync() {
  [ -f "$MIGRATION_PENDING" ] || return 0
  _ecm_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  _ecm_pending=$(cat "$MIGRATION_PENDING" 2>/dev/null)
  [ -n "$_ecm_boot" ] && [ -n "$_ecm_pending" ] && [ "$_ecm_pending" != "$_ecm_boot" ] || return 0
  if rm -f "$MIGRATION_PENDING" 2>/dev/null; then
    echo "cert: completed previous-boot skip_mount migration after verified trust sync" >&2
    return 0
  fi
  echo "cert: WARN verified trust sync succeeded but migration warning marker could not be removed" >&2
  return 1
}

# Recover interrupted enable publication after SIGKILL/reboot. The old directory is
# authoritative until trust synchronization and cleanup finish; if a previous snapshot
# remains, restore it and quarantine the possibly-published replacement for inspection.
# This is idempotent and must run only while holding PG_CERTLOCK.
PG_CERT_RECOVERY_CHANGED=0
pg_cert_recover_enable_transactions() {
  _r_sm="$1"; _r_failed=0
  [ -d "$_r_sm" ] || return 0
  for _r_prev in "$_r_sm"/.*.enable-prev.*; do
    [ -d "$_r_prev" ] || continue
    _r_base=${_r_prev##*/}; _r_id=${_r_base#.}; _r_id=${_r_id%%.enable-prev.*}
    case "$_r_id" in pg_mitm_ca|pg_https_ca) ;; *) echo "cert: WARN unknown enable recovery directory retained: $_r_prev" >&2; continue ;; esac
    if [ ! -f "$_r_prev/module.prop" ] || ! grep -q "^id=$_r_id$" "$_r_prev/module.prop"; then
      echo "cert: ERROR invalid enable recovery snapshot retained: $_r_prev" >&2; _r_failed=1; continue
    fi
    _r_dest="$_r_sm/$_r_id"
    if [ -e "$_r_dest" ]; then
      _r_quarantine="$_r_sm/.$_r_id.enable-interrupted.$$"
      if ! mv "$_r_dest" "$_r_quarantine" 2>/dev/null; then
        echo "cert: ERROR cannot quarantine interrupted replacement; snapshot retained: $_r_prev" >&2; _r_failed=1; continue
      fi
      if ! mv "$_r_prev" "$_r_dest" 2>/dev/null; then
        mv "$_r_quarantine" "$_r_dest" 2>/dev/null || echo "cert: ERROR replacement and prior snapshot both require manual recovery" >&2
        echo "cert: ERROR cannot restore interrupted enable snapshot: $_r_prev" >&2; _r_failed=1; continue
      fi
      PG_CERT_RECOVERY_CHANGED=1
      echo "cert: WARN restored prior $_r_id snapshot; interrupted replacement quarantined at $_r_quarantine" >&2
    else
      if ! mv "$_r_prev" "$_r_dest" 2>/dev/null; then
        echo "cert: ERROR cannot restore missing submodule from $_r_prev" >&2; _r_failed=1; continue
      fi
      PG_CERT_RECOVERY_CHANGED=1
      echo "cert: WARN restored missing $_r_id from interrupted enable snapshot" >&2
    fi
  done
  # A stage directory was never published. Remove only known submodule staging names.
  for _r_stage in "$_r_sm"/.*.enable-stage.*; do
    [ -d "$_r_stage" ] || continue
    _r_base=${_r_stage##*/}; _r_id=${_r_base#.}; _r_id=${_r_id%%.enable-stage.*}
    case "$_r_id" in pg_mitm_ca|pg_https_ca) rm -rf "$_r_stage" 2>/dev/null || { echo "cert: WARN unable to remove abandoned stage $_r_stage" >&2; _r_failed=1; } ;; esac
  done
  return "$_r_failed"
}

# 统一入口：所有会改 ca-index / 挂载状态的子命令先拿全局锁再进 case。
# `builtin list` 是只读，不进锁（WebUI 轮询频繁，避免互相等待）。
_pg_cm_needlock=1
case "$1/$2" in
  builtin/list) _pg_cm_needlock=0 ;;
  ''/*|*'') : ;;
esac
[ -z "$1" ] && _pg_cm_needlock=0
if [ "$_pg_cm_needlock" = 1 ]; then
  pg_cert_lock || exit 75
  trap 'pg_cert_unlock' 0
  pg_cert_recover_enable_transactions "$SM" || { echo "cert: ERROR interrupted enable recovery incomplete; refusing further mutation" >&2; exit 1; }
  pg_cert_ensure_skip_mount || { echo "cert: ERROR child CA modules cannot be safely migrated; refusing further mutation" >&2; exit 1; }
  if [ "$PG_CERT_RECOVERY_CHANGED" = 1 ]; then
    # Restoring module directories alone is insufficient: the live system/APEX CA
    # overlays may still reflect the interrupted replacement. Reconcile them before
    # any requested mutation; fail closed if trust-store synchronization cannot finish.
    ca_sync || { echo "cert: ERROR recovery restored certificate modules but trust-store resync failed; refusing further mutation" >&2; exit 1; }
  fi
fi

_pg_cm_rc=0
case "$1" in
  builtin)
    SUB="$2"
    case "$SUB" in
      release)
        # 安装时被 customize.sh 调用: certs/submodules/* → /data/adb/modules/pg_*_ca
        # 信任策略: 默认【不启用】。UI/README 一直写“默认不信任”, 且两张自签 CA 的
        # 私钥随模块公开分发, 安装即全系统信任会让安全软件/银行类 App 把设备判为
        # “存在自定义根证书/风险证书”, 这也是“装完模块就弹证书警告”的常见来源。
        # 用户只要在 WebUI『根证书管理』点过“启用”, 就写 $PG/ca-trust-optin;
        # 之后升级/重装保持启用; 其它情况一律释放为禁用状态(可一键启用)。
        CDIR="$3"
        { [ -z "$CDIR" ] || [ ! -d "$CDIR" ]; } && CDIR="$MDIR_CERTS"
        N=0; SKIP=0; FAIL=0
        for tmpl in "$CDIR/submodules"/*/; do
          [ -f "$tmpl/module.prop" ] || continue
          id=$(basename "$tmpl")
          dest="$SM/$id"
          # 用户曾用管理器删除该子模块 → 尊重，不复活
          if [ -f "$dest/remove" ]; then SKIP=$((SKIP+1)); continue; fi
          _rel_src="$tmpl/system/etc/security/cacerts"
          _rel_files=0
          for _rel_f in "$_rel_src"/*.0; do [ -f "$_rel_f" ] && _rel_files=$((_rel_files+1)); done
          if [ ! -d "$_rel_src" ] || [ "$_rel_files" -eq 0 ]; then
            FAIL=$((FAIL+1)); echo "cert: ERROR 子模块 $id 缺少 .0 证书文件" >&2; continue
          fi
          # 先在同一模块文件系统构建暂存目录；只有完整复制成功才替换旧目录。
          _rel_tmp="$SM/.${id}.release.$$"
          rm -rf "$_rel_tmp"
          if ! mkdir -p "$_rel_tmp/system/etc/security/cacerts" \
            || ! cp "$tmpl/module.prop" "$_rel_tmp/module.prop" 2>/dev/null \
            || ! cp "$_rel_src/"*.0 "$_rel_tmp/system/etc/security/cacerts/" 2>/dev/null; then
            rm -rf "$_rel_tmp"; FAIL=$((FAIL+1)); echo "cert: ERROR 释放 $id 复制失败" >&2; continue
          fi
          chmod 755 "$_rel_tmp" "$_rel_tmp/system" "$_rel_tmp/system/etc" "$_rel_tmp/system/etc/security" "$_rel_tmp/system/etc/security/cacerts" 2>/dev/null
          chmod 644 "$_rel_tmp/module.prop" "$_rel_tmp/system/etc/security/cacerts/"*.0 2>/dev/null
          # Keep the CA child module independent but do not let KernelSU's raw
          # system overlay blindly overwrite <hash>.0. certmgr composes the live
          # store collision-safely from the real system/Conscrypt trust store.
          : > "$_rel_tmp/skip_mount" || { rm -rf "$_rel_tmp"; FAIL=$((FAIL+1)); echo "cert: ERROR 无法写入 $id/skip_mount" >&2; continue; }
          chmod 644 "$_rel_tmp/skip_mount" 2>/dev/null
          # 默认禁用；仅在用户明确 opt-in 且原子替换成功后保留启用状态。
          DIS=1
          [ -f "$PG/ca-trust-optin" ] && [ ! -f "$dest/disable" ] && DIS=0
          rm -f "$_rel_tmp/disable"
          [ "$DIS" = 1 ] && : > "$_rel_tmp/disable"
          _rel_old="$SM/.${id}.old.$$"
          rm -rf "$_rel_old"
          if [ -d "$dest" ] && ! mv "$dest" "$_rel_old" 2>/dev/null; then
            rm -rf "$_rel_tmp"; FAIL=$((FAIL+1)); echo "cert: ERROR 无法备份旧子模块 $id" >&2; continue
          fi
          if mv "$_rel_tmp" "$dest" 2>/dev/null; then
            rm -rf "$_rel_old"; N=$((N+1))
          else
            [ -d "$_rel_old" ] && mv "$_rel_old" "$dest" 2>/dev/null
            rm -rf "$_rel_tmp"; FAIL=$((FAIL+1)); echo "cert: ERROR 无法安装子模块 $id" >&2
          fi
        done
        ca_selfheal
        if ! ca_sync; then
          FAIL=$((FAIL+1))
          echo "cert: ERROR 子模块已释放，但当前启动周期信任同步未完成" >&2
        fi
        if [ "$FAIL" -gt 0 ]; then
          _pg_cm_rc=1
          printf '{"ok":false,"detail":"已释放 %d 个，跳过 %d 个已删除，失败 %d 个；请检查错误日志"}\n' "$N" "$SKIP" "$FAIL"
        else
          printf '{"ok":true,"detail":"已释放 %d 个系统级 CA 子模块（默认未启用，需在“根证书管理”点启用；跳过 %d 个已删除的）"}\n' "$N" "$SKIP"
        fi
        ;;
      list)
        OUT=""
        # Android 14+ 应用/Conscrypt 实际读取 APEX 信任库: 有 APEX 时系统信任状态以
        # APEX 视图为准(避免 /system 覆盖层还在、APEX 里没有 → UI 误报“系统级信任中”)
        LIVE_APEX=0
        _ls_view="$SC"
        if [ -n "$SC_APEX" ] && [ -d "$SC_APEX" ]; then _ls_view="$SC_APEX"; LIVE_APEX=1; fi
        for id in $(ca_ids); do
          NAME=$(idx "$id" 1); FP=$(idx "$id" 3); SUBJ=$(idx "$id" 4)
          H1=$(idx "$id" 5); H2=$(idx "$id" 6)
          REL=0; DIS=0; SYS=0
          [ -d "$SM/$id" ] && [ ! -f "$SM/$id/remove" ] && REL=1
          [ -f "$SM/$id/disable" ] && DIS=1
          _ls_fp256=$(ca_expected_fp256 "$id" 2>/dev/null) || _ls_fp256=""
          if [ -n "$_ls_fp256" ]; then
            ca_store_has_cert "$_ls_view" "$H1" "$H2" "$_ls_fp256" && SYS=1
          fi
          APEX_NS=not-applicable
          if [ "$LIVE_APEX" = 1 ]; then
            if [ -n "$_ls_fp256" ] && ca_apex_ns_verify_zygote "$SC_APEX" "$_ls_fp256" "$H1" "$H2"; then APEX_NS=verified; else APEX_NS=unverified; fi
          fi
          OUT="$OUT{\"name\":\"$NAME\",\"id\":\"$id\",\"fp\":\"$FP\",\"subj\":\"$SUBJ\",\"system\":$SYS,\"released\":$REL,\"disabled\":$DIS,\"apex\":$LIVE_APEX,\"apex_ns\":\"$APEX_NS\"},"
        done
        OUT=$(printf '%s' "$OUT" | sed 's/,$//')
        LIVE=0; [ -f "$MARK" ] && LIVE=1
        LIVE_APEX_MOUNT=0; [ -f "$MARK_APEX" ] && LIVE_APEX_MOUNT=1
        LIVE_APEX_PARTIAL=0; [ -f "$MARK_APEX_PARTIAL" ] && LIVE_APEX_PARTIAL=1
        MIGRATION_PENDING_STATE=0; [ -f "$MIGRATION_PENDING" ] && MIGRATION_PENDING_STATE=1
        printf '{"ok":true,"certs":[%s],"live":%s,"live_apex":%s,"apex":%s,"apex_partial":%s,"migration_pending":%s}\n' "$OUT" "$LIVE" "$LIVE_APEX_MOUNT" "$LIVE_APEX" "$LIVE_APEX_PARTIAL" "$MIGRATION_PENDING_STATE"
        ;;
      enable)
        KEY="$3"
        id=$(idx "$KEY" 2); [ -z "$id" ] && { printf '{"ok":false,"detail":"无此内置 CA: %s"}\n' "$KEY"; exit 1; }
        # 用户明确启用 → 记录 opt-in 标记: 以后升级/重装保持启用；失败时恢复原标记。
        mkdir -p "$PG" 2>/dev/null
        _en_had_optin=0; [ -f "$PG/ca-trust-optin" ] && _en_had_optin=1
        : > "$PG/ca-trust-optin" 2>/dev/null
        _en_ok=1
        _en_had_dir=0; _en_had_disable=0; _en_replaced=0
        [ -d "$SM/$id" ] && _en_had_dir=1
        [ -f "$SM/$id/disable" ] && _en_had_disable=1
        _en_dest="$SM/$id"
        _en_stage="$SM/.$id.enable-stage.$$"
        _en_prev="$SM/.$id.enable-prev.$$"
        if [ ! -d "$_en_dest" ] || [ -f "$_en_dest/remove" ]; then
          # Build and validate in a sibling staging directory first. Never delete an
          # existing remove marker until the replacement is complete and publishable.
          _en_tmpl="$MDIR_CERTS/submodules/$id"
          rm -rf "$_en_stage" "$_en_prev" 2>/dev/null
          if [ ! -f "$_en_tmpl/module.prop" ] || [ ! -d "$_en_tmpl/system/etc/security/cacerts" ]; then
            _en_ok=0
            _pg_cm_rc=1
            printf '{"ok":false,"detail":"子模块模板缺失: %s"}\n' "$id"
          elif mkdir -p "$_en_stage/system/etc/security/cacerts" \
            && cp "$_en_tmpl/module.prop" "$_en_stage/module.prop" 2>/dev/null \
            && cp "$_en_tmpl/system/etc/security/cacerts/"*.0 "$_en_stage/system/etc/security/cacerts/" 2>/dev/null; then
            set -- "$_en_stage/system/etc/security/cacerts/"*.0
            if [ ! -f "$1" ] || ! grep -q '^version=' "$_en_stage/module.prop"; then
              _en_ok=0
              _pg_cm_rc=1
              rm -rf "$_en_stage" 2>/dev/null
              printf '{"ok":false,"detail":"子模块暂存校验失败: %s"}\n' "$id"
            else
              chmod 755 "$_en_stage" "$_en_stage/system" "$_en_stage/system/etc" "$_en_stage/system/etc/security" "$_en_stage/system/etc/security/cacerts" 2>/dev/null || _en_ok=0
              chmod 644 "$_en_stage/module.prop" "$_en_stage/system/etc/security/cacerts/"*.0 2>/dev/null || _en_ok=0
              : > "$_en_stage/skip_mount" 2>/dev/null || _en_ok=0
              chmod 644 "$_en_stage/skip_mount" 2>/dev/null || _en_ok=0
              if [ "$_en_ok" = 1 ]; then
                if [ -d "$_en_dest" ]; then
                  if ! mv "$_en_dest" "$_en_prev" 2>/dev/null; then
                    _en_ok=0
                  fi
                fi
                if [ "$_en_ok" = 1 ]; then
                  if mv "$_en_stage" "$_en_dest" 2>/dev/null; then
                    _en_replaced=1
                  else
                    _en_ok=0
                    [ -d "$_en_prev" ] && mv "$_en_prev" "$_en_dest" 2>/dev/null
                  fi
                fi
              fi
              if [ "$_en_ok" != 1 ]; then
                rm -rf "$_en_stage" 2>/dev/null
                _pg_cm_rc=1
                printf '{"ok":false,"detail":"发布证书子模块失败；原目录/移除标记已尽力保留: %s"}\n' "$id"
              fi
            fi
          else
            _en_ok=0
            _pg_cm_rc=1
            rm -rf "$_en_stage" 2>/dev/null
            printf '{"ok":false,"detail":"释放子模块暂存失败；原目录未主动删除: %s"}\n' "$id"
          fi
        fi
        if [ "$_en_ok" = 1 ]; then
          if ! rm -f "$SM/$id/disable"; then
            _pg_cm_rc=1
            if [ "$_en_replaced" = 1 ]; then
              rm -rf "$_en_dest" 2>/dev/null
              [ -d "$_en_prev" ] && mv "$_en_prev" "$_en_dest" 2>/dev/null || :
            fi
            [ "$_en_had_optin" = 1 ] || rm -f "$PG/ca-trust-optin" 2>/dev/null
            ca_sync >/dev/null 2>&1 || echo "cert: WARN enable-marker rollback resync still incomplete" >&2
            printf '{"ok":false,"detail":"无法清除 disable 标记: %s；已尝试恢复原子模块"}\n' "$id"
          elif ! ca_sync; then
            _pg_cm_rc=1
            if [ "$_en_replaced" = 1 ]; then
              rm -rf "$_en_dest" 2>/dev/null
              if [ -d "$_en_prev" ]; then
                mv "$_en_prev" "$_en_dest" 2>/dev/null || echo "cert: ERROR enable rollback could not restore previous submodule; backup retained at $_en_prev" >&2
              fi
            elif [ "$_en_had_dir" = 1 ]; then
              [ "$_en_had_disable" = 1 ] && : > "$_en_dest/disable" || rm -f "$_en_dest/disable"
            else
              rm -rf "$_en_dest"
            fi
            [ "$_en_had_optin" = 1 ] || rm -f "$PG/ca-trust-optin" 2>/dev/null
            ca_sync >/dev/null 2>&1 || echo "cert: WARN enable rollback resync still incomplete" >&2
            printf '{"ok":false,"detail":"信任库同步失败；已尝试恢复原子模块目录/标记，检查挂载状态后重试"}\n'
          else
            rm -rf "$_en_prev" 2>/dev/null
            printf '{"ok":true,"detail":"已启用 %s — 关键系统/Conscrypt 信任视图已同步并验证；个别应用命名空间可能需重启，证书固定应用不保证可用"}\n' "$(idx "$id" 1)"
          fi
        fi
        ;;
      disable)
        KEY="$3"
        id=$(idx "$KEY" 2); [ -z "$id" ] && { printf '{"ok":false,"detail":"无此内置 CA: %s"}\n' "$KEY"; exit 1; }
        if [ ! -d "$SM/$id" ]; then
          printf '{"ok":false,"detail":"%s 未释放(未安装?)"}\n' "$(idx "$id" 1)"
        else
          if ! : > "$SM/$id/disable"; then
            _pg_cm_rc=1
            printf '{"ok":false,"detail":"无法写入 disable 标记: %s"}\n' "$id"
          elif ! ca_sync; then
            _pg_cm_rc=1
            rm -f "$SM/$id/disable" 2>/dev/null
            ca_sync >/dev/null 2>&1 || echo "cert: WARN disable rollback resync still incomplete" >&2
            printf '{"ok":false,"detail":"信任库同步失败；已尝试恢复启用标记，实际挂载状态仍需检查"}\n'
          else
            printf '{"ok":true,"detail":"已禁用 %s — 本模块拥有的系统/Conscrypt 信任视图已同步；个别应用缓存需重启，系统原生同指纹 CA 不会被本模块删除"}\n' "$(idx "$id" 1)"
          fi
        fi
        ;;
      remove)
        KEY="$3"
        id=$(idx "$KEY" 2); [ -z "$id" ] && { printf '{"ok":false,"detail":"无此内置 CA: %s"}\n' "$KEY"; exit 1; }
        if [ -d "$SM/$id" ] && [ ! -f "$SM/$id/remove" ]; then
          _rm_backup="$PG/cert-remove-backup-$id-$$"
          rm -rf "$_rm_backup" 2>/dev/null
          if ! cp -R "$SM/$id" "$_rm_backup" 2>/dev/null; then
            _pg_cm_rc=1
            printf '{"ok":false,"detail":"无法创建移除回滚备份: %s"}\n' "$id"
            exit 1
          fi
          # 写 Magisk 的 remove 标记: 重启后管理器清除残留目录, 且 release/升级
          # 看到该标记不会再把 CA 复活(否则“移除”后一升级证书又回来了)
          mkdir -p "$SM/$id" 2>/dev/null
          if ! : > "$SM/$id/remove"; then
            _pg_cm_rc=1
            rm -rf "$_rm_backup" 2>/dev/null
            printf '{"ok":false,"detail":"无法写入 remove 标记: %s"}\n' "$id"
          elif ! rm -rf "$SM/$id/system" "$SM/$id/module.prop" "$SM/$id/disable" 2>/dev/null; then
            _pg_cm_rc=1
            _rm_restore="$SM/.$id.restore.$$"
            rm -rf "$_rm_restore" "$SM/$id" 2>/dev/null
            if cp -R "$_rm_backup" "$_rm_restore" 2>/dev/null && mv "$_rm_restore" "$SM/$id" 2>/dev/null; then
              ca_sync >/dev/null 2>&1 || echo "cert: WARN partial-remove rollback resync still incomplete" >&2
              rm -rf "$_rm_backup" 2>/dev/null
            else
              echo "cert: ERROR partial-remove rollback failed; backup retained at $_rm_backup" >&2
            fi
            printf '{"ok":false,"detail":"子模块文件清理失败；已尝试恢复原子模块目录"}\n' 
          elif ! ca_sync; then
            _pg_cm_rc=1
            _rm_restore="$SM/.$id.restore.$$"
            rm -rf "$_rm_restore" 2>/dev/null
            if cp -R "$_rm_backup" "$_rm_restore" 2>/dev/null; then
              rm -rf "$SM/$id" 2>/dev/null
              if mv "$_rm_restore" "$SM/$id" 2>/dev/null; then
                rm -rf "$_rm_backup" 2>/dev/null
                echo "cert: rollback restored $id after trust sync failure" >&2
              else
                echo "cert: ERROR rollback publish failed; backup retained at $_rm_backup" >&2
                _pg_cm_rc=1
              fi
            else
              echo "cert: ERROR rollback failed; backup retained at $_rm_backup" >&2
              _pg_cm_rc=1
            fi
            ca_sync >/dev/null 2>&1 || echo "cert: WARN remove rollback resync still incomplete" >&2
            printf '{"ok":false,"detail":"信任库同步失败；已尝试恢复子模块文件，检查证书挂载状态后重试"}\n'
          else
            rm -rf "$_rm_backup" 2>/dev/null
            printf '{"ok":true,"detail":"已移除子模块 %s — 系统信任已即时摘除, 升级不会自动复活(重启后管理器清理残留目录)"}\n' "$id"
          fi
        else
          _pg_cm_rc=1
          printf '{"ok":false,"detail":"%s 未释放"}\n' "$id"
        fi
        ;;
      purge)
        N=0
        for id in $(ca_ids); do
          [ -n "$SM" ] && [ -n "$id" ] && [ -d "$SM/$id" ] && { rm -rf "${SM:?}/$id"; N=$((N+1)); }
        done
        if ca_sync; then
          printf '{"ok":true,"detail":"已移除 %d 个 CA 子模块；信任同步流程完成，仍需核实实际挂载状态"}\n' "$N"
        else
          _pg_cm_rc=1
          printf '{"ok":false,"detail":"已清理子模块目录，但信任同步未完成；请检查挂载状态并重试"}\n'
        fi
        ;;
      sync)
        ca_selfheal
        if ca_sync; then
          printf '{"ok":true,"detail":"证书信任同步流程完成；请以 list/实际挂载状态核实系统信任"}\n'
        else
          _pg_cm_rc=1
          printf '{"ok":false,"detail":"证书信任同步未完成或因安全保护跳过；未宣称已生效，请检查 certmgr 日志与挂载状态"}\n'
        fi
        ;;
      *)
        _pg_cm_rc=2
        printf '{"ok":false,"detail":"用法: certmgr.sh builtin release|list|enable|disable|remove|purge|sync"}\n'
        ;;
    esac
    ;;
  cleanup)
    # 清理本模块历史版本(≤v1.7)残留的用户证书操作数据:
    #   certs-quarantine — 当年 disable 把用户 CA 移进去的隔离区
    #   certs-staging    — 当年 release 流程的暂存区
    #   cacerts-overlay* — 当年 ca_sync 的 live 覆盖层挂载
    # 隔离区的处理（默认绝不写用户证书区 — 写用户区会让系统弹出
    # “用户证书/网络可能被监控”类警告）:
    #     cleanup            — 默认: 保留隔离区文件原样, 只卸覆盖层/清暂存区
    #     cleanup restore    — 明确要求: 把隔离区证书移回 /data/misc/user/0/cacerts-added
    #                          (卸载时由 uninstall.sh 显式调用, 恢复用户原有状态)
    #     cleanup purge      — 明确要求: 直接删除隔离区(等同旧版 restore=0)
    UDIR=/data/misc/user/0/cacerts-added
    QDIR=$PG/certs-quarantine
    SDIR=$PG/certs-staging
    ACTION="$2"
    RESTORE=0; PURGE=0
    case "$ACTION" in
      restore|1)      RESTORE=1 ;;
      purge|delete|0) PURGE=1 ;;
      *)              RESTORE=0 ;;
    esac
    MSG=""
    # 1) 卸 live 覆盖层挂载(多层一并揭净, 8 层上限)
    #    同 ca_sync 的护栏：umount 失败(EBUSY)时绝不删源目录，否则信任库变空。
    if [ -f "$MARK" ] || mount 2>/dev/null | grep -q " $SC "; then
      _cl_n=0
      while umount "$SC" 2>/dev/null; do
        _cl_n=$((_cl_n+1)); [ $_cl_n -ge 8 ] && break
      done
      if mount 2>/dev/null | grep -q " $SC "; then
        MSG="$MSG live 覆盖层仍被占用(EBUSY)，已保留源目录未删"
      else
        rm -f "$MARK"; rm -rf "$OVL"
        MSG="$MSG live 覆盖层已卸载"
      fi
    fi
    # 1b) A14+ Conscrypt APEX overlay: unmount every owned mount namespace before
    # deleting shared source data; incomplete teardown is a cleanup failure.
    _cl_apex_present=0
    [ -f "$MARK_APEX" ] && _cl_apex_present=1
    for _cl_ns_mark in "$PG"/cacerts-overlay-apex.ns.*; do [ -f "$_cl_ns_mark" ] && _cl_apex_present=1; done
    if [ "$_cl_apex_present" = 1 ]; then
      if ca_apex_ns_unmount_all "$SC_APEX" "$PG" "$MARK_APEX"; then
        if rm -rf "$OVL_APEX" 2>/dev/null; then
          rm -f "$MARK_APEX_PARTIAL" 2>/dev/null
          MSG="$MSG APEX 覆盖层已从所有可见的 FX 命名空间卸载"
        else
          MSG="$MSG APEX 覆盖层已卸载但源目录清理失败（保留以便重试）"
          _cl_fail=1
        fi
      else
        MSG="$MSG APEX 命名空间挂载无法全部确认卸载，已保留源目录"
        _cl_fail=1
      fi
    fi
    # 2) 隔离区: 默认原样保留(不写用户证书区)
    if [ -d "$QDIR" ]; then
      _cl_n=0
      for f in "$QDIR"/*.0; do
        [ -f "$f" ] || continue
        _cl_n=$((_cl_n+1))
      done
      if [ "$RESTORE" = 1 ]; then
        _cl_mv=0
        for f in "$QDIR"/*.0; do
          [ -f "$f" ] || continue
          mkdir -p "$UDIR" 2>/dev/null
          mv "$f" "$UDIR/" 2>/dev/null && _cl_mv=$((_cl_mv+1))
        done
        rm -rf "$QDIR"
        MSG="$MSG; 隔离区 $_cl_mv/$_cl_n 张历史用户证书已按请求移回用户 CA 目录(会重新出现在“用户”凭据列表)"
      elif [ "$PURGE" = 1 ]; then
        rm -rf "$QDIR"
        MSG="$MSG; 隔离区 $_cl_n 张历史用户证书已按请求删除"
      else
        MSG="$MSG; 隔离区 $_cl_n 张历史用户证书已保留在 $QDIR(未写用户证书区; 恢复请执行 cleanup restore)"
      fi
    fi
    # 3) 暂存区
    [ -d "$SDIR" ] && { rm -rf "$SDIR"; MSG="$MSG; 暂存区已清理"; }
    if [ "${_cl_fail:-0}" = 1 ]; then
      _pg_cm_rc=1
      printf '{"ok":false,"detail":"%s"}\n' "${MSG# ; }"
    else
      printf '{"ok":true,"detail":"%s"}\n' "${MSG# ; }"
    fi
    ;;
  *)
    _pg_cm_rc=2
    printf '{"ok":false,"detail":"用法: certmgr.sh builtin release|list|enable|disable|remove|purge|sync | cleanup [restore|purge]"}\n'
    ;;
esac
# 释放全局锁（所有分支走到这里；尽早释放避免阻塞后续 certmgr 调用）
[ "$_pg_cm_needlock" = 1 ] && pg_cert_unlock
exit "$_pg_cm_rc"
