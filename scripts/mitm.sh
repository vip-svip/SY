#!/system/bin/sh
# ============================================================
#  mitm.sh — 第二层：MITM 中间人透明代理
#  功能: 生成根 CA、注入系统证书(OverlayFS)、iptables 透明重定向、
#        启动/停止 Go MITM 代理、内容替换规则管理
#  用法: mitm.sh {up|down|status|ca-cert|ca-install|ca-status|stats|rules-count|rules-reload|apps-set|test}
# ============================================================
. "$(dirname "$0")/common.sh"

CA_DIR="$DATA_DIR/ca"
CA_KEY="$CA_DIR/ca.key"
CA_CRT="$CA_DIR/ca.crt"
CA_PEM="$CA_DIR/ca.pem"
SYS_CACERTS="$MODDIR/system/etc/security/cacerts"
# 独立「根证书」子模块 (由主模块安装时释放)
CERT_MOD="/data/adb/modules/SY_cert"
CERT_MOD_CACERTS="$CERT_MOD/system/etc/security/cacerts"
PROXY_PORT=$(cfg_get MITM_PORT 8443)
HTTP_PORT=$(cfg_get MITM_HTTP_PORT 8080)
mkdir -p "$CA_DIR" "$SYS_CACERTS"

# ---------- 生成根 CA ----------
gen_ca() {
  if [ -f "$CA_KEY" ] && [ -f "$CA_CRT" ]; then
    log "mitm: CA 已存在"
    return 0
  fi
  log "mitm: 生成根证书"
  if [ -x "$BIN" ]; then
    "$BIN" ca -dir "$CA_DIR" -cn "SY Root CA" >/dev/null 2>&1 && { install_ca; return 0; }
  fi
  # 降级: openssl
  if have openssl; then
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout "$CA_KEY" -out "$CA_CRT" \
      -subj "/C=CN/O=SY/CN=SY Root CA" >/dev/null 2>&1
    [ -f "$CA_CRT" ] && { install_ca; return 0; }
  fi
  log "mitm: CA 生成失败"
  return 1
}

# ---------- 注入系统证书区 (OverlayFS) ----------
install_ca() {
  # Android 证书文件名 = <subject_hash_old>.0，由服务组件直接计算并写入系统证书区
  cname=""
  if [ -x "$BIN" ]; then
    cname=$("$BIN" ca -dir "$CA_DIR" -cn "SY Root CA" -cacerts "$SYS_CACERTS" 2>/dev/null \
      | sed -n 's/.*HASH=//p' | tr -d '\r' | tail -n1)
  fi
  if [ -z "$cname" ] && have openssl; then
    h=$(openssl x509 -inform PEM -subject_hash_old -in "$CA_CRT" 2>/dev/null | head -n1)
    [ -n "$h" ] && cname="$h.0"
  fi
  [ -z "$cname" ] && cname="sy.0"
  mkdir -p "$SYS_CACERTS"
  # 若服务组件未写入，则用 shell 复制兜底
  [ -f "$SYS_CACERTS/$cname" ] || cp -f "$CA_CRT" "$SYS_CACERTS/$cname" 2>/dev/null
  cp -f "$CA_CRT" "$CA_PEM" 2>/dev/null
  chmod 0644 "$SYS_CACERTS/$cname" 2>/dev/null
  chown 0:0 "$SYS_CACERTS/$cname" 2>/dev/null
  echo "$cname" > "$CA_DIR/installed_hash" 2>/dev/null
  if [ -f "$SYS_CACERTS/$cname" ]; then
    log "mitm: 根证书已写入系统证书区 ($cname)"
    echo "OK: 根证书已安装到系统证书区 ($cname)，重启设备后全局信任"
  else
    log "mitm: 根证书写入失败"
    echo "ERR: 写入系统证书区失败，请确认已授予 root 权限"
  fi
}

# ---------- 释放独立「根证书」子模块 (供运行时/面板一键修复) ----------
release_cert_mod() {
  # 需要现成 CA 证书
  [ -f "$CA_CRT" ] || gen_ca >/dev/null 2>&1
  if [ ! -f "$CA_CRT" ]; then echo "ERR: 根证书尚未生成，无法释放子模块"; return 1; fi
  # 计算 Android 证书文件名 <subject_hash_old>.0
  h=""
  if [ -x "$BIN" ]; then
    h=$("$BIN" ca -dir "$CA_DIR" -cn "SY Root CA" -cacerts "$SYS_CACERTS" 2>/dev/null \
      | sed -n 's/.*HASH=//p' | tr -d '\r' | tail -n1)
  fi
  if [ -z "$h" ] && have openssl; then
    hh=$(openssl x509 -inform PEM -subject_hash_old -in "$CA_CRT" 2>/dev/null | head -n1)
    [ -n "$hh" ] && h="$hh.0"
  fi
  [ -z "$h" ] && h="sy.0"
  echo "$h" > "$CA_DIR/installed_hash" 2>/dev/null
  mkdir -p "$CERT_MOD_CACERTS"
  cp -f "$CA_CRT" "$CERT_MOD_CACERTS/$h" 2>/dev/null
  chmod 0644 "$CERT_MOD_CACERTS/$h" 2>/dev/null
  chown 0:0 "$CERT_MOD_CACERTS/$h" 2>/dev/null
  # module.prop (若缺失)
  if [ ! -f "$CERT_MOD/module.prop" ]; then
    cat > "$CERT_MOD/module.prop" <<MEOF
id=SY_cert
name=SY
version=v1.0.0
versionCode=10000
author=vip-svip
description=[自动生成] 由广告拦截模块释放，负责将根证书注入系统信任区并兼容 Android 14+ APEX。
MEOF
  fi
  # post-fs-data.sh (APEX 兼容)
  cat > "$CERT_MOD/post-fs-data.sh" <<'CEOF'
#!/system/bin/sh
MODDIR=${0%/*}
DATA_DIR=/data/adb/SY
[ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
SRC_LINK=/data/adb/modules/SY/system/etc/security/cacerts
mkdir -p "$DATA_DIR/logs" 2>/dev/null
exec >>"$DATA_DIR/logs/cert.log" 2>&1
echo "=== cert post-fs-data $(date) ==="
if [ -d "$SRC_LINK" ]; then
  chmod 0755 "$SRC_LINK" 2>/dev/null
  chmod 0644 "$SRC_LINK"/* 2>/dev/null
  chown 0:0 "$SRC_LINK"/* 2>/dev/null
fi
APEX_CACERTS=/apex/com.android.conscrypt/cacerts
if [ -d "$APEX_CACERTS" ]; then
  STORE="$DATA_DIR/.apexcerts"
  rm -rf "$STORE"; mkdir -p "$STORE"
  cp -f "$APEX_CACERTS"/* "$STORE"/ 2>/dev/null
  [ -d "$SRC_LINK" ] && cp -f "$SRC_LINK"/*.0 "$STORE"/ 2>/dev/null
  chmod 0644 "$STORE"/* 2>/dev/null
  chown 0:0 "$STORE"/* 2>/dev/null
  umount "$APEX_CACERTS" 2>/dev/null
  mount --bind "$STORE" "$APEX_CACERTS" 2>/dev/null && echo "apex bind ok" || echo "apex bind FAILED"
fi
echo "=== cert done ==="
CEOF
  chmod 0755 "$CERT_MOD/post-fs-data.sh"
  cat > "$CERT_MOD/service.sh" <<'SEOF'
#!/system/bin/sh
mkdir -p /data/adb/SY/logs 2>/dev/null
APEX=/apex/com.android.conscrypt/cacerts
STORE=/data/adb/SY/.apexcerts
if [ -d "$APEX" ] && [ -d "$STORE" ]; then
  mount 2>/dev/null | grep -q "$APEX" || mount --bind "$STORE" "$APEX" 2>/dev/null
fi
SEOF
  chmod 0755 "$CERT_MOD/service.sh"
  cat > "$CERT_MOD/uninstall.sh" <<'UEOF'
#!/system/bin/sh
umount /apex/com.android.conscrypt/cacerts 2>/dev/null
echo "cert module removed"
UEOF
  chmod 0755 "$CERT_MOD/uninstall.sh"
  log "mitm: 根证书子模块已释放 ($CERT_MOD/$h)"
  echo "OK: 根证书子模块已释放并注入证书 ($h)，重启后系统全局信任"
}

# ---------- 删除根证书 (系统证书区 + 子模块 + CA 文件) ----------
uninstall_ca() {
  h=""
  [ -f "$CA_DIR/installed_hash" ] && h=$(cat "$CA_DIR/installed_hash" 2>/dev/null)
  # 1) 系统证书区: 删除记录的证书名与所有 .0 (仅删本模块写入的，避免误伤系统预置需靠 overlay)
  [ -n "$h" ] && rm -f "$SYS_CACERTS/$h" 2>/dev/null
  rm -f "$SYS_CACERTS"/*.0 2>/dev/null
  # 2) 独立子模块: 直接移除整个 SY_cert 模块目录
  rm -rf "$CERT_MOD" 2>/dev/null
  # 3) 释放 apex 绑定
  umount /apex/com.android.conscrypt/cacerts 2>/dev/null
  # 4) 删除 CA 私钥/证书本体
  rm -f "$CA_KEY" "$CA_CRT" "$CA_PEM" "$CA_DIR/installed_hash" 2>/dev/null
  log "mitm: 根证书已删除 (hash=${h:-无})"
  echo "OK: 根证书已从系统证书区与子模块移除并删除，重启后完全失效"
}

# ---------- 透明代理重定向 ----------
# 通过 KSU/per-app 精准处理；此处做透明重定向基础规则
apply_iptables() {
  apps=$(cfg_get MITM_APPS "")
  # 清理旧规则
  clear_iptables
  # 对指定应用(UID)的 80/443 流量重定向到本地代理
  uids=""
  if [ -n "$apps" ]; then
    for pkg in $(echo "$apps" | tr ',' ' '); do
      uid=$(pm list packages -U 2>/dev/null | grep "package:$pkg " | sed 's/.*uid://')
      [ -z "$uid" ] && uid=$(cmd package list packages -U 2>/dev/null | grep "package:$pkg " | sed 's/.*uid://')
      [ -n "$uid" ] && uids="$uids $uid"
    done
  fi
  if [ -z "$uids" ]; then
    # 未指定应用 -> 重定向全部(排除 root, 排除代理自身)
    iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner ! --uid-owner 0 -j REDIRECT --to-ports "$HTTP_PORT" 2>/dev/null
    iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner ! --uid-owner 0 -j REDIRECT --to-ports "$PROXY_PORT" 2>/dev/null
    log "mitm: iptables 全局透明重定向已应用"
  else
    for uid in $uids; do
      iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner "$uid" -j REDIRECT --to-ports "$HTTP_PORT" 2>/dev/null
      iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$uid" -j REDIRECT --to-ports "$PROXY_PORT" 2>/dev/null
    done
    log "mitm: iptables 按应用重定向已应用 uids=$uids"
  fi
}

clear_iptables() {
  iptables -t nat -D OUTPUT -p tcp --dport 80 -m owner ! --uid-owner 0 -j REDIRECT --to-ports "$HTTP_PORT" 2>/dev/null
  iptables -t nat -D OUTPUT -p tcp --dport 443 -m owner ! --uid-owner 0 -j REDIRECT --to-ports "$PROXY_PORT" 2>/dev/null
  # 按应用规则难以枚举删除，这里用循环清空 nat OUTPUT 中本模块标记
  iptables -t nat -S OUTPUT 2>/dev/null | grep -E "REDIRECT --to-ports ($HTTP_PORT|$PROXY_PORT)" | \
    sed 's/^-A/-D/' | while read -r r; do iptables -t nat $r 2>/dev/null; done
  log "mitm: iptables 规则已清理"
}

# ---------- 启动代理 ----------
start_proxy() {
  stop_proxy
  [ -x "$BIN" ] || { echo "ERR: 服务组件缺失"; return 1; }
  gen_ca
  reload_rules
  "$BIN" proxy \
    -http ":$HTTP_PORT" \
    -https ":$PROXY_PORT" \
    -ca-key "$CA_KEY" \
    -ca-crt "$CA_CRT" \
    -rules "$MITM_DIR/active.json" \
    -apps "$(cfg_get MITM_APPS '')" \
    -whitelist "$WHITELIST" \
    -stats "$DATA_DIR/stats_mitm.json" \
    > "$LOGS/mitm_proxy.log" 2>&1 &
  echo $! > "$RUN/proxy.pid"
  sleep 1
  apply_iptables
  log "mitm: 代理已启动 pid=$(cat "$RUN/proxy.pid")"
  echo "OK: MITM 代理已启动 (http:$HTTP_PORT https:$PROXY_PORT)"
}

stop_proxy() {
  if [ -f "$RUN/proxy.pid" ]; then
    kill "$(cat "$RUN/proxy.pid")" 2>/dev/null
    rm -f "$RUN/proxy.pid"
  fi
  pkill -f "abserver proxy" 2>/dev/null
  clear_iptables
  log "mitm: 代理已停止"
}

# ---------- 规则转换 (QX/Surge/Loon/Shadowrocket -> json) ----------
reload_rules() {
  out="$MITM_DIR/active.json"
  echo '{"rules":[' > "$out"
  first=1
  # 合并所有 mitm_rules/*.conf
  for f in "$MITM_RULES" "$MITM_DIR"/*.conf; do
    [ -f "$f" ] || continue
    awk -v first="$first" '
      BEGIN{ n=0 }
      /^[[:space:]]*[#;]/ { next }
      /^[[:space:]]*$/ { next }
      # Surge/QX: ^https?://... url-regex / 直接 url pattern
      {
        line=$0
        gsub(/\\/, "\\\\", line)
        gsub(/"/, "\\\"", line)
        printf "%s{\"raw\":\"%s\"}\n", (n>0?",":""), line
        n++
      }
    ' "$f" >> "$out"
    first=0
  done
  # 也解析 config/mitm_rules.conf
  echo ']}' >> "$out"
  log "mitm: 规则已重载"
}

case "$1" in
  up)      start_proxy ;;
  down)    stop_proxy ;;
  restart) stop_proxy; start_proxy ;;
  status)
    running="no"; pid=""
    if [ -f "$RUN/proxy.pid" ] && kill -0 "$(cat "$RUN/proxy.pid")" 2>/dev/null; then
      running="yes"; pid=$(cat "$RUN/proxy.pid")
    fi
    ca="no"; [ -f "$CA_CRT" ] && ca="yes"
    redirected=$(iptables -t nat -S OUTPUT 2>/dev/null | grep -c REDIRECT)
    echo "{\"running\":\"$running\",\"pid\":\"$pid\",\"ca_ready\":\"$ca\",\"iptables_rules\":$redirected,\"port\":$PROXY_PORT}"
    ;;
  ca-cert)
    [ -f "$CA_CRT" ] && cat "$CA_CRT" || echo "ERR: 证书未生成"
    ;;
  ca-install)
    gen_ca >/dev/null 2>&1
    install_ca
    # 联动: 若独立根证书子模块尚未释放，则一并释放，保证与 UI 状态一致
    if [ ! -d "$CERT_MOD" ] || [ -z "$(ls "$CERT_MOD_CACERTS"/*.0 2>/dev/null | head -n1)" ]; then
      release_cert_mod
    fi
    ;;
  ca-release)
    release_cert_mod
    ;;
  ca-uninstall)
    uninstall_ca
    ;;
  ca-status)
    gen="no"; [ -f "$CA_CRT" ] && gen="yes"
    # 主模块 overlay 中的系统证书
    ov="no"; [ -n "$(ls "$SYS_CACERTS"/*.0 2>/dev/null | head -n1)" ] && ov="yes"
    # 独立子模块是否存在且已释放证书
    sub="no"; [ -d "$CERT_MOD" ] && sub="yes"
    subca="no"; [ -n "$(ls "$CERT_MOD_CACERTS"/*.0 2>/dev/null | head -n1)" ] && subca="yes"
    # runtime: 子模块是否被 KSU 识别为启用 (未禁用)
    sub_enabled="no"
    if [ -d "$CERT_MOD" ] && [ ! -f "$CERT_MOD/disable" ] && [ ! -f "$CERT_MOD/remove" ]; then sub_enabled="yes"; fi
    # 系统证书区是否已实际生效 (运行时 /system 可见)
    live="no"; [ -n "$(ls /system/etc/security/cacerts/*.0 2>/dev/null | head -n1)" ] && live="yes"
    # 综合判定: 任一路径安装成功即视为已安装
    inst="no"; { [ "$ov" = "yes" ] || [ "$subca" = "yes" ]; } && inst="yes"
    h=""; [ -f "$CA_DIR/installed_hash" ] && h=$(cat "$CA_DIR/installed_hash" 2>/dev/null)
    printf '{"generated":"%s","installed":"%s","overlay":"%s","submodule":"%s","submodule_ca":"%s","submodule_enabled":"%s","live":"%s","hash":"%s","dir":"%s","subdir":"%s"}\n' \
      "$gen" "$inst" "$ov" "$sub" "$subca" "$sub_enabled" "$live" "$h" "$SYS_CACERTS" "$CERT_MOD"
    ;;
  stats)
    st="$DATA_DIR/stats_mitm.json"
    [ -f "$st" ] && cat "$st" || echo '{"requests":0,"https_decrypted":0,"blocked":0,"blank_images":0,"blocked_js":0,"fields_trimmed":0}'
    ;;
  rules-count)
    n=$(grep -cvE '^[[:space:]]*(#|$)' "$MITM_RULES" 2>/dev/null)
    printf '{"rules":%s}\n' "${n:-0}"
    ;;
  rules-reload)
    reload_rules; echo "OK: 规则已重载"
    ;;
  apps-set)
    cfg_set MITM_APPS "$2"
    log "mitm: 生效应用 = $2"
    if [ -f "$RUN/proxy.pid" ]; then apply_iptables; fi
    echo "OK: 生效应用已设为 $2"
    ;;
  rules-list)
    cat "$MITM_RULES" 2>/dev/null
    ;;
  rules-import)
    cat >> "$MITM_RULES"; reload_rules; echo "OK: 规则已导入"
    ;;
  rules-save-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d > "$MITM_RULES" 2>/dev/null; printf '\n' >> "$MITM_RULES"
    reload_rules; echo "OK: 规则已保存并重载"
    ;;
  apps-get)
    cfg_get MITM_APPS ""
    ;;
  rules-list-lines)
    # 带行号的规则列表，供前端删除：格式 "行号|内容"
    awk '{printf "%d|%s\n", NR, $0}' "$MITM_RULES" 2>/dev/null
    ;;
  rules-add-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d >> "$MITM_RULES" 2>/dev/null; printf '\n' >> "$MITM_RULES"
    reload_rules; echo "OK: 已添加规则"
    ;;
  rules-del)
    ln="$2"
    [ -z "$ln" ] && { echo "ERR: 缺少行号"; exit 1; }
    tmp="$MITM_RULES.tmp.$$"
    awk -v want="$ln" 'NR!=want' "$MITM_RULES" > "$tmp" 2>/dev/null && mv "$tmp" "$MITM_RULES"
    reload_rules; echo "OK: 已删除第 $ln 行规则"
    ;;
  rules-clear)
    : > "$MITM_RULES"; reload_rules; echo "OK: 已清空 MITM 规则"
    ;;
  *)
    echo "usage: mitm.sh {up|down|restart|status|ca-cert|ca-install|ca-release|ca-status|stats|rules-count|rules-reload|rules-list|rules-list-lines|rules-add-b64|rules-del|rules-clear|rules-import|rules-save-b64|apps-set|apps-get}"
    ;;
esac
