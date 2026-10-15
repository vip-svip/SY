#!/system/bin/sh
# ============================================================
#  ctl.sh — 统一控制入口 (供 WebUI / action.sh / 命令行调用)
#  ctl.sh status | toggle <f> | restart <f> | apps | <sub> ...
# ============================================================
D="$(dirname "$0")"
. "$D/common.sh"

case "$1" in
  status)
    # 【性能】旧版一次 status 就 fork 五个子脚本（dns/mitm/splash/panel/notify），
    # 每个都是 shell 冷启动；面板首页每 6 秒轮询一次 → 每分钟 50+ 次进程创建，
    # 这曾是「面板卡顿」的最大来源。
    # 现在：
    #   ① 结果缓存 20 秒（status 数据本来就不需要秒级新鲜）；
    #   ② 传 --fast 时只返回缓存（面板轮询用），不触发子脚本；
    #   ③ top 结果缓存 60 秒（top -n1 在手机上很贵）。
    CACHEF="$CACHE/status.json"
    FAST="${2:-}"
    now=$(date +%s 2>/dev/null || echo 0)
    if [ -s "$CACHEF" ]; then
      age=$(( now - $(stat -c %Y "$CACHEF" 2>/dev/null || echo 0) ))
      if [ "$age" -lt 20 ]; then cat "$CACHEF"; exit 0; fi
    fi
    if [ "$FAST" = "--fast" ] && [ -s "$CACHEF" ]; then cat "$CACHEF"; exit 0; fi
    dns=$(sh "$D/dns.sh" status 2>/dev/null)
    mitm=$(sh "$D/mitm.sh" status 2>/dev/null)
    splash=$(sh "$D/splash.sh" status 2>/dev/null)
    panel=$(sh "$D/panel.sh" status 2>/dev/null)
    notify=$(sh "$D/notify.sh" status 2>/dev/null)
    mem=$(cat /proc/meminfo 2>/dev/null | awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{used=(t-a)/1024; printf "%.0f", used}')
    # CPU 单独缓存 60 秒：top -n1 在手机上开销最大
    CPUF="$CACHE/cpu.txt"
    cnow=$(date +%s 2>/dev/null || echo 0)
    cage=9999
    [ -s "$CPUF" ] && cage=$(( cnow - $(stat -c %Y "$CPUF" 2>/dev/null || echo 0) ))
    if [ "$cage" -gt 60 ]; then
      top -n1 -b 2>/dev/null | awk '/abserver/{sum+=$9}END{printf "%.1f", sum+0}' > "$CPUF" 2>/dev/null
    fi
    cpu=$(cat "$CPUF" 2>/dev/null); [ -z "$cpu" ] && cpu=0
    up=$(uptime 2>/dev/null | sed 's/.*up //;s/,.*//')
    upesc=$(json_escape "$up")
    OUT=$(printf '{"dns":%s,"mitm":%s,"splash":%s,"panel":%s,"notify":%s,"sys":{"mem_used_mb":%s,"cpu_pct":%s,"uptime":"%s"}}\n' \
      "$dns" "$mitm" "$splash" "$panel" "$notify" "$mem" "$cpu" "$upesc")
    printf '%s\n' "$OUT" | tee "$CACHEF" 2>/dev/null
    ;;
  toggle)
    f="$2"
    cur=$(cfg_get "$(echo "$f" | tr 'a-z' 'A-Z')_ENABLE 1")
    if [ "$cur" = "1" ]; then new=0; else new=1; fi
    cfg_set "$(echo "$f" | tr 'a-z' 'A-Z')_ENABLE" "$new"
    case "$f" in
      mitm)   [ "$new" = "1" ] && sh "$D/mitm.sh" up >/dev/null 2>&1 || sh "$D/mitm.sh" down >/dev/null 2>&1 ;;
      splash) [ "$new" = "1" ] && sh "$D/splash.sh" start >/dev/null 2>&1 || sh "$D/splash.sh" stop >/dev/null 2>&1 ;;
      panel)  [ "$new" = "1" ] && sh "$D/panel.sh" start >/dev/null 2>&1 || sh "$D/panel.sh" stop >/dev/null 2>&1 ;;
      notify) [ "$new" = "1" ] && sh "$D/notify.sh" start >/dev/null 2>&1 || sh "$D/notify.sh" stop >/dev/null 2>&1 ;;
      dns)    [ "$new" = "0" ] && { : > "$DNS_DIR/hosts"; mount --bind "$DNS_DIR/hosts" /system/etc/hosts 2>/dev/null; } || sh "$D/dns.sh" apply >/dev/null 2>&1 ;;
      privacy) [ "$new" = "1" ] && sh "$D/privacy_guard.sh" apply >/dev/null 2>&1 || sh "$D/privacy_guard.sh" remove >/dev/null 2>&1 ;;
      game)    [ "$new" = "1" ] && sh "$D/game_privacy.sh" apply >/dev/null 2>&1 || sh "$D/game_privacy.sh" remove >/dev/null 2>&1 ;;
      clipguard) [ "$new" = "1" ] && sh "$D/clip_guard.sh" apply >/dev/null 2>&1 || sh "$D/clip_guard.sh" remove >/dev/null 2>&1 ;;
      fxguard)   [ "$new" = "1" ] && sh "$D/fx_deepguard.sh" apply >/dev/null 2>&1 || sh "$D/fx_deepguard.sh" remove >/dev/null 2>&1 ;;
    esac
    echo "OK: $f -> $new"
    ;;
  restart)
    sh "$D/$2.sh" restart 2>/dev/null || { sh "$D/$2.sh" stop 2>/dev/null; sh "$D/$2.sh" start 2>/dev/null; }
    echo "OK: $2 restarted"
    ;;
  apps)
    # 列出已安装应用包名(供 MITM 生效应用 / 开屏规则选择)
    if command -v pm >/dev/null 2>&1; then
      pm list packages 2>/dev/null | sed 's/package://' | sort
    elif command -v cmd >/dev/null 2>&1; then
      cmd package list packages 2>/dev/null | sed 's/package://' | sort
    fi
    ;;
  appnames)
    # 包名|应用名 映射
    if command -v pm >/dev/null 2>&1; then
      pm list packages 2>/dev/null | sed 's/package://' | sort
    fi
    ;;
  settings)
    sub="$1"; shift
    sh "$D/settings.sh" "$@"
    ;;
  scripts)
    # 兼容别名: 脚本扩展中心的真实文件为 scripts_ext.sh
    shift
    sh "$D/scripts_ext.sh" "$@"
    ;;
  dns|mitm|splash|backup|notify|panel|dnssrv|netblock|proxynode|ruleset|kernel|leakguard|privacy_guard|game_privacy|clip_guard|privacy_check|privacy_ruleset|fx_deepguard|offline|oneclick|proxyrun|proxymgr|proxycfg|builtin_rules|kernel)
    sub="$1"; shift
    sh "$D/$sub.sh" "$@"
    ;;
  *)
    echo "usage: ctl.sh {status|toggle <f>|restart <f>|apps|dns|mitm|splash|scripts|backup|notify|panel|dnssrv|netblock|proxynode|ruleset|kernel|privacy_guard|game_privacy|clip_guard|privacy_check|privacy_ruleset|fx_deepguard|offline|oneclick|proxyrun|proxymgr|proxycfg|builtin_rules|kernel ...}"
    ;;
esac
