#!/system/bin/sh
# ============================================================
#  广告拦截·内核增强版 — post-fs-data 阶段 (最早，早于 App 联网)
#  负责: 首启生成 hosts、绑定挂载 hosts、准备证书目录
# ============================================================
MODDIR=${0%/*}
DATA_DIR=/data/adb/SY
[ -d "$DATA_DIR" ] || DATA_DIR=/data/SY
MODDIR_REAL=/data/adb/modules/SY
LOG="$DATA_DIR/logs/post-fs.log"
mkdir -p "$DATA_DIR/logs" 2>/dev/null
exec >>"$LOG" 2>&1
echo "=== post-fs-data $(date) ==="

DNS_DIR="$DATA_DIR/rules/dns"
HOSTS_SRC="$DNS_DIR/hosts"
mkdir -p "$DNS_DIR" 2>/dev/null

# ---------- 1. 首启若 hosts 不存在: 用规则库缓存生成(不再内置规则) ----------
if [ ! -s "$HOSTS_SRC" ]; then
  echo "hosts 不存在，尝试用规则库缓存生成"
  BLK="$DATA_DIR/rules/remote/block.txt"
  AD="$DATA_DIR/rules/dns/all_domains.txt"
  {
    echo "# 广告拦截 — 首启自动生成 $(date)"
    echo "127.0.0.1 localhost"
    echo "::1 localhost"
    if [ -s "$AD" ]; then
      awk '{print "0.0.0.0 "$0; print "0.0.0.0 www."$0}' "$AD" 2>/dev/null
    elif [ -f "$BLK" ]; then
      sed -e 's/#.*$//' -e 's/[[:space:]]//g' "$BLK" 2>/dev/null | \
      grep -v '^||.*/' | \
      sed -e 's/^||//' -e 's/[\^*|].*$//' | \
      grep -E '^[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}$' | sort -u | \
      while IFS= read -r d; do
        echo "0.0.0.0 $d"
        echo "0.0.0.0 www.$d"
      done
    fi
  } > "$HOSTS_SRC.tmp" 2>/dev/null
  mv -f "$HOSTS_SRC.tmp" "$HOSTS_SRC" 2>/dev/null
  chmod 0644 "$HOSTS_SRC" 2>/dev/null
  echo "hosts 生成: $(wc -l < "$HOSTS_SRC" 2>/dev/null) 行 (规则库缓存)"
fi

# ---------- 2. 绑定挂载 hosts (DNS级拦截核心) ----------
if [ -s "$HOSTS_SRC" ]; then
  TARGET=/system/etc/hosts
  [ -f "$TARGET" ] || TARGET=/etc/hosts
  # 先卸载可能存在的旧挂载避免 EBUSY
  umount "$TARGET" 2>/dev/null
  if mount --bind "$HOSTS_SRC" "$TARGET" 2>/dev/null; then
    chmod 0644 "$TARGET" 2>/dev/null
    echo "hosts bind-mount ok -> $TARGET"
  else
    echo "hosts bind-mount FAILED -> $TARGET"
  fi
fi

# ---------- 3. 证书目录权限 ----------
CACERTS="$MODDIR_REAL/system/etc/security/cacerts"
if [ -d "$CACERTS" ]; then
  chmod 0755 "$CACERTS" 2>/dev/null
  chmod 0644 "$CACERTS"/* 2>/dev/null
  chown 0:0 "$CACERTS"/* 2>/dev/null
  echo "cacerts overlay ready"
fi

echo "=== post-fs-data done ==="
