#!/system/bin/sh
# ============================================================
#  广告拦截·内核增强版  —  模块安装脚本 (customize.sh)
#  KernelSU / Magisk 通用安装钩子
#  注意: customize.sh 会被安装器 source，$0 指向安装器，
#        模块目录必须用标准变量 $MODPATH。
# ============================================================
SKIPUNZIP=0

if [ -n "$MODPATH" ]; then
  MODDIR="$MODPATH"
else
  MODDIR="${0%/*}"
fi
DATA_DIR=/data/adb/SY
CERT_MOD=/data/adb/modules/SY_cert

[ -n "$API" ] || API=$(getprop ro.build.version.sdk 2>/dev/null)
[ -n "$API" ] || API=30

ui_print "- 模块目录: $MODDIR  (Android API $API)"

# ---------- ABI 检测 (多重回退) ----------
ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
[ -z "$ABI" ] && ABI=$(getprop ro.product.cpu.abilist 2>/dev/null | cut -d, -f1)
MACHINE=$(uname -m 2>/dev/null)
ui_print "- 设备架构: ABI=$ABI / machine=$MACHINE"

case "$ABI $MACHINE" in
  *arm64*|*aarch64*)            ARCH=arm64 ;;
  *armeabi*|*armv7*|*arm*)      ARCH=arm ;;
  *x86_64*|*amd64*|*x64*)       ARCH=amd64 ;;
  *i386*|*i686*|*x86*)          ARCH=amd64 ;;
  *)                            ARCH=arm64 ;;
esac
ui_print "- 选用架构: $ARCH"

BIN_SRC="$MODDIR/bin/abserver-$ARCH"
[ -f "$BIN_SRC" ] || BIN_SRC="$MODDIR/bin/abserver-arm64"
[ -f "$BIN_SRC" ] || BIN_SRC="$MODDIR/bin/abserver-amd64"

if [ -f "$BIN_SRC" ]; then
  cp -f "$BIN_SRC" "$MODDIR/bin/abserver"
  chmod 0755 "$MODDIR/bin/abserver"
  ui_print "- 已安装服务组件: $(basename "$BIN_SRC") -> bin/abserver"
else
  ui_print "! 未找到服务二进制，纯脚本功能仍可用"
fi

# ---------- 内置代理内核(sing-box): 随包, 按架构安装 ----------
KERNELS="$MODDIR/bin/kernels"
if [ -d "$KERNELS" ]; then
  KSRC="$KERNELS/sing-box-$ARCH"
  [ -f "$KSRC" ] || KSRC="$KERNELS/sing-box-arm64"
  if [ -f "$KSRC" ]; then
    cp -f "$KSRC" "$MODDIR/bin/sing-box"
    chmod 0755 "$MODDIR/bin/sing-box"
    ui_print "- 已安装内置内核 sing-box ($(basename "$KSRC")) -> bin/sing-box"
  fi
fi

unset __SY_MARK

# ---------- 初始化数据目录 (持久化) ----------
ui_print "- 初始化数据目录 $DATA_DIR"
mkdir -p "$DATA_DIR"/rules/dns "$DATA_DIR"/rules/mitm "$DATA_DIR"/rules/splash \
         "$DATA_DIR"/logs "$DATA_DIR"/config "$DATA_DIR"/backup "$DATA_DIR"/scripts \
         "$DATA_DIR"/cache "$DATA_DIR"/run "$DATA_DIR"/ca "$DATA_DIR"/config/script_meta

# 首次安装写入默认配置(不覆盖已有)
for c in sy.conf sources.conf splash_rules.conf mitm_rules.conf whitelist.conf notify_keywords.conf; do
  if [ -f "$MODDIR/config/$c" ] && [ ! -f "$DATA_DIR/config/$c" ]; then
    cp -f "$MODDIR/config/$c" "$DATA_DIR/config/$c"
  fi
done
if [ ! -f "$DATA_DIR/config/mitm_rules.conf" ] && [ -f "$MODDIR/config/mitm_rules.conf" ]; then
  cp -f "$MODDIR/config/mitm_rules.conf" "$DATA_DIR/config/mitm_rules.conf"
fi

# ============================================================
#  根证书: 生成主模块 overlay 证书 + 释放独立「根证书」子模块
# ============================================================
CERT_HASH=""
SYS_CACERTS_SRC="$MODDIR/system/etc/security/cacerts"
mkdir -p "$SYS_CACERTS_SRC"

if [ -x "$MODDIR/bin/abserver" ]; then
  ui_print "- 生成根证书 (RSA 2048, 有效期 10 年)"
  CA_OUT=$("$MODDIR/bin/abserver" ca -dir "$DATA_DIR/ca" -cn "SY Root CA" \
             -cacerts "$SYS_CACERTS_SRC" 2>/dev/null)
  CERT_HASH=$(echo "$CA_OUT" | sed -n 's/.*HASH=//p' | tr -d '\r' | tail -n1)
  ui_print "- $CA_OUT"
fi
# openssl 兜底
if [ -z "$CERT_HASH" ] && [ -f "$DATA_DIR/ca/ca.crt" ] && command -v openssl >/dev/null 2>&1; then
  H=$(openssl x509 -inform PEM -subject_hash_old -in "$DATA_DIR/ca/ca.crt" 2>/dev/null | head -n1)
  [ -n "$H" ] && { CERT_HASH="$H.0"; cp -f "$DATA_DIR/ca/ca.crt" "$SYS_CACERTS_SRC/$CERT_HASH"; }
fi
[ -z "$CERT_HASH" ] && [ -f "$DATA_DIR/ca/ca.crt" ] && { CERT_HASH="sy.0"; cp -f "$DATA_DIR/ca/ca.crt" "$SYS_CACERTS_SRC/$CERT_HASH" 2>/dev/null; }

if [ -f "$DATA_DIR/ca/ca.crt" ]; then
  ui_print "- 根证书已写入主模块 overlay: system/etc/security/cacerts/$CERT_HASH"

  # ---------- 释放独立「根证书」子模块 (处理 Android 14+ APEX + 独立展示) ----------
  ui_print "- 释放独立「根证书」子模块 -> $CERT_MOD"
  rm -rf "$CERT_MOD"
  mkdir -p "$CERT_MOD"
  # 版本号跟随主模块，避免两处硬编码造成版本漂移
  MV=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | tr -d '\r' | head -n1)
  MVC=$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | tr -d '\r' | head -n1)
  [ -n "$MV" ] || MV=v1.0.0
  [ -n "$MVC" ] || MVC=10000
  cat > "$CERT_MOD/module.prop" <<EOF
id=SY_cert
name=SY · 根证书
version=$MV
versionCode=$MVC
author=vip-svip
description=[自动生成] 由广告拦截模块安装时释放，负责将根证书注入系统信任区并兼容 Android 14+ APEX。请勿单独删除；随主模块卸载一并清理。
EOF

  mkdir -p "$CERT_MOD/system/etc/security/cacerts"
  cp -f "$DATA_DIR/ca/ca.crt" "$CERT_MOD/system/etc/security/cacerts/$CERT_HASH" 2>/dev/null

  cat > "$CERT_MOD/post-fs-data.sh" <<'CERTEOF'
#!/system/bin/sh
# 根证书注入 (含 Android 14+ conscrypt APEX 兼容)
MODDIR=${0%/*}
DATA_DIR=/data/adb/SY
[ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
SRC_LINK=/data/adb/modules/SY/system/etc/security/cacerts
LOG="$DATA_DIR/logs/cert.log"
mkdir -p "$DATA_DIR/logs" 2>/dev/null
exec >>"$LOG" 2>&1
echo "=== cert post-fs-data $(date) ==="

# 1. 主模块 overlay 证书
if [ -d "$SRC_LINK" ]; then
  chmod 0755 "$SRC_LINK" 2>/dev/null
  chmod 0644 "$SRC_LINK"/* 2>/dev/null
  chown 0:0 "$SRC_LINK"/* 2>/dev/null
fi

# 2. Android 14+ : conscrypt 证书位于只读 APEX，需 bind mount
APEX_CACERTS=/apex/com.android.conscrypt/cacerts
if [ -d "$APEX_CACERTS" ]; then
  STORE="$DATA_DIR/.apexcerts"
  rm -rf "$STORE"; mkdir -p "$STORE"
  cp -f "$APEX_CACERTS"/* "$STORE"/ 2>/dev/null
  if [ -d "$SRC_LINK" ]; then
    cp -f "$SRC_LINK"/*.0 "$STORE"/ 2>/dev/null
  fi
  chmod 0644 "$STORE"/* 2>/dev/null
  chown 0:0 "$STORE"/* 2>/dev/null
  # 卸载旧挂载后重挂
  umount "$APEX_CACERTS" 2>/dev/null
  mount --bind "$STORE" "$APEX_CACERTS" 2>/dev/null \
    && echo "apex cacerts bind ok" || echo "apex cacerts bind FAILED"
fi
echo "=== cert done ==="
CERTEOF
  chmod 0755 "$CERT_MOD/post-fs-data.sh"

  cat > "$CERT_MOD/service.sh" <<'SVC'
#!/system/bin/sh
# late_start 再兜底一次 (部分设备 APEX 在 post-fs-data 后重挂载)
mkdir -p /data/adb/SY/logs 2>/dev/null
APEX=/apex/com.android.conscrypt/cacerts
STORE=/data/adb/SY/.apexcerts
if [ -d "$APEX" ] && [ -d "$STORE" ]; then
  mount 2>/dev/null | grep -q "$APEX" || mount --bind "$STORE" "$APEX" 2>/dev/null
fi
SVC
  chmod 0755 "$CERT_MOD/service.sh"

  cat > "$CERT_MOD/uninstall.sh" <<'UNI'
#!/system/bin/sh
umount /apex/com.android.conscrypt/cacerts 2>/dev/null
echo "cert module removed"
UNI
  chmod 0755 "$CERT_MOD/uninstall.sh"

  ui_print "- 根证书子模块已释放，重启后系统全局信任"
else
  ui_print "! 根证书生成失败 (缺服务组件且无 openssl)，可重启后进面板重装"
fi

# ---------- 权限 ----------
ui_print "- 设置文件权限"
set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm_recursive "$DATA_DIR" 0 0 0755 0644
[ -f "$MODDIR/bin/abserver" ] && set_perm "$MODDIR/bin/abserver" 0 0 0755
for f in "$MODDIR"/*.sh "$MODDIR"/scripts/*.sh; do
  [ -f "$f" ] && set_perm "$f" 0 0 0755
done
if [ -d "$CERT_MOD" ]; then
  set_perm_recursive "$CERT_MOD" 0 0 0755 0644
  for f in "$CERT_MOD"/*.sh; do [ -f "$f" ] && set_perm "$f" 0 0 0755; done
fi

ui_print "- 安装完成，重启后生效"
ui_print "- 面板: KernelSU 管理器中点击本模块「打开」按钮"
ui_print "- 数据目录: $DATA_DIR"
ui_print "- 根证书: $CERT_MOD (独立子模块)"
