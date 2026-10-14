#!/system/bin/sh
# ============================================================
#  fetch_data.sh — 抓取「离线隐私数据包」到 data/
#
#  为让模块在完全离线 / 断网环境下仍具备 IP 归属地判定、域名分类、
#  广告与追踪拦截能力，本脚本预先抓取并落地一批**可再分发**的数据：
#
#    data/geo/    —— 地理/IP 归属数据库（供 route.sh / netblock.sh 离线判定）
#    data/lists/  —— 广告 / 追踪 / 恶意域名清单（供 engine.sh 融合引擎编译）
#
#  许可说明（重要）：
#    · DB-IP Lite  ——  CC BY 4.0，允许再分发（需保留署名，见 data/geo/NOTICE.txt）
#    · sing-geoip / sing-geosite（SagerNet）—— GPL-3.0 / 数据来源公开
#    · v2ray geoip/geosite（MetaCubeX）—— 见其仓库许可
#    为规避授权风险，本脚本**刻意不下载 MaxMind GeoLite2**（其许可禁止再分发）。
#
#  用法: sh scripts/fetch_data.sh [geo|lists|all]
# ============================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
GEO="$ROOT/data/geo"
LISTS="$ROOT/data/lists"
mkdir -p "$GEO" "$LISTS"

dl() { # url out
  url="$1"; out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 --max-time 600 -o "$out" "$url" && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$out" "$url" && return 0
  fi
  return 1
}

YEAR_MONTH=$(date +%Y-%m)
# DB-IP 每月更新；若当月不存在则回退到近两月
dbip_get() { # kind(free/dbip-xxx-lite) -> file
  kind="$1"
  for ym in "$YEAR_MONTH" "$(date -d '-1 month' +%Y-%m 2>/dev/null)" "$(date -d '-2 month' +%Y-%m 2>/dev/null)"; do
    [ -n "$ym" ] || continue
    for ext in mmdb.gz csv.gz; do
      u="https://download.db-ip.com/free/${kind}-${ym}.${ext}"
      if dl "$u" "$GEO/${kind}.${ext}"; then echo "$GEO/${kind}.${ext}"; return 0; fi
    done
  done
  return 1
}

fetch_geo() {
  echo "== 抓取 geo 数据库 =="
  dbip_get dbip-city-lite    | while read -r f; do [ -n "$f" ] && echo "  ok $(basename "$f")"; done
  dbip_get dbip-asn-lite     | while read -r f; do [ -n "$f" ] && echo "  ok $(basename "$f")"; done
  dbip_get dbip-country-lite | while read -r f; do [ -n "$f" ] && echo "  ok $(basename "$f")"; done

  # 解压 .gz（模块运行期需要 .mmdb 原生格式）
  for g in "$GEO"/*.gz; do
    [ -f "$g" ] || continue
    case "$g" in
      *.mmdb.gz) gunzip -kf "$g" 2>/dev/null ;;
      *.csv.gz)  gunzip -kf "$g" 2>/dev/null ;;
    esac
  done
  # 解压成功的删掉 .gz 省体积
  for g in "$GEO"/*.gz; do [ -f "${g%.gz}" ] && rm -f "$g"; done

  # sing-box 生态的 geoip/geosite（二进制 db）
  dl "https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db"   "$GEO/sing-geoip.db"   && echo "  ok sing-geoip.db"
  dl "https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db" "$GEO/sing-geosite.db" && echo "  ok sing-geosite.db"
  # v2ray 生态（供 route import / ruleset 使用）
  dl "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"   "$GEO/geoip.dat"   && echo "  ok geoip.dat"
  dl "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" "$GEO/geosite.dat" && echo "  ok geosite.dat"

  cat > "$GEO/NOTICE.txt" <<'EOS'
离线地理/IP 数据包 —— 来源与许可
=================================
dbip-*-lite-*.mmdb   : DB-IP Lite, 许可 CC BY 4.0, https://db-ip.com
                       允许再分发，须保留署名 "IP Geolocation by DB-IP (https://db-ip.com)"。
sing-geoip.db        : SagerNet/sing-geoip (GPL-3.0)
sing-geosite.db      : SagerNet/sing-geosite (GPL-3.0)
geoip.dat/geosite.dat: MetaCubeX/meta-rules-dat
本包**不包含** MaxMind GeoLite2（其许可禁止再分发）。
EOS
  echo "  已生成 NOTICE.txt"
}

fetch_lists() {
  echo "== 抓取拦截清单 =="
  # 每行一个 URL -> 目标文件名
  while IFS= read -r line; do
    case "$line" in \#*|"") continue ;; esac
    url=${line%% *}; name=${line##* }
    if dl "$url" "$LISTS/$name"; then
      echo "  ok $name ($(wc -c < "$LISTS/$name" 2>/dev/null | tr -d ' ') B)"
    else
      echo "  -- 跳过 $name"
    fi
  done <<'EOL'
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt hagezi-pro.txt
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/tif.txt hagezi-tif.txt
https://raw.githubusercontent.com/AdguardTeam/cname-trackers/master/data/combined_disguised_trackers.txt adguard-cname-trackers.txt
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking_servers.txt adguard-tracking-servers.txt
https://easylist.to/easylist/easyprivacy.txt easyprivacy.txt
https://easylist.to/easylist/easylist.txt easylist.txt
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts stevenblack-hosts.txt
https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt kadhosts.txt
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/ChineseFilter/sections/adservers.txt adguard-cn-adservers.txt
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/MobileFilter/sections/adservers.txt adguard-mobile-adservers.txt
https://raw.githubusercontent.com/1Hosts/Lite/master/adblock.txt 1hosts-lite.txt
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/native.tiktok.txt hagezi-tiktok.txt
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/native.amazon.txt hagezi-amazon.txt
EOL
  echo "  清单目录: $(du -sh "$LISTS" 2>/dev/null | cut -f1)"
}

case "${1:-all}" in
  geo)   fetch_geo ;;
  lists) fetch_lists ;;
  all)   fetch_geo; fetch_lists ;;
  *) echo "usage: fetch_data.sh [geo|lists|all]" ;;
esac
echo "== 完成，data/ 总大小: $(du -sh "$ROOT/data" 2>/dev/null | cut -f1) =="
