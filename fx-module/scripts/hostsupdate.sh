#!/system/bin/sh
# ============================================================
# FX hostsupdate.sh — 定时更新规则源（bindhosts 的 cron 能力移植）
#
# bindhosts 用 busybox crond + 自定义 cron 文件定时拉取 hosts 源；FX 之前没有定时能力，
# 用户要么手动点「应用」，要么等下次开机。这里补上：
#   hostsupdate.sh enable   [interval]   启用定时（默认 24 小时）
#   hostsupdate.sh disable              停用
#   hostsupdate.sh status               显示当前状态与上次结果
#   hostsupdate.sh run                  立即执行一次
#
# 实现说明：不依赖 crond（Android 上不保证存在），用「记录下次执行时间」+ 开机与
# 每次应用时检查的方式。这样只需系统自己的调度，不额外常驻进程，也不会因 OEM 杀后台
# 失效——这正是 FX 已有的 scheduler 模式。
# ============================================================
set -u

_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || { echo '{"ok":false,"error":"module directory unavailable"}'; exit 2; }

PG=${PG:-/data/adb/privacyguard}
STATE="$PG/hostsupdate"
CONF="$STATE/schedule"
LOG="$PG/apply.log"

mkdir -p "$STATE" 2>/dev/null || { echo '{"ok":false,"error":"state directory unavailable"}'; exit 73; }
chmod 700 "$STATE" 2>/dev/null || :

log_line() {
	( umask 077; echo "[$(date '+%m-%d %H:%M:%S')] hostsupdate: $*" >> "$LOG" )
	chmod 600 "$LOG" 2>/dev/null || :
}

# 读取调度配置：interval_secs、enabled、next_epoch、last_run_epoch、last_result
read_schedule() {
	_int=86400; _en=0; _next=0; _last=0; _res=""
	if [ -f "$CONF" ] && [ ! -L "$CONF" ]; then
		while IFS='=' read -r _k _v; do
			case "$_k" in
				interval_secs) case "$_v" in ''|*[!0-9]*) ;; *) _int=$_v ;; esac ;;
				enabled) case "$_v" in 0|1) _en=$_v ;; esac ;;
				next_epoch) case "$_v" in ''|*[!0-9]*) ;; *) _next=$_v ;; esac ;;
				last_run_epoch) case "$_v" in ''|*[!0-9]*) ;; *) _last=$_v ;; esac ;;
				last_result) _res=$_v ;;
			esac
		done < "$CONF"
	fi
}

write_schedule() {
	_tmp="$STATE/.schedule.$$"
	{
		echo "interval_secs=$_int"
		echo "enabled=$_en"
		echo "next_epoch=$_next"
		echo "last_run_epoch=$_last"
		echo "last_result=$_res"
	} > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
	chmod 600 "$_tmp" 2>/dev/null || :
	mv -f "$_tmp" "$CONF" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
}

now_epoch() { date +%s 2>/dev/null || echo 0; }

cmd=${1:-status}

case "$cmd" in
	enable)
		_interval=${2:-86400}
		case "$_interval" in ''|*[!0-9]*) echo '{"ok":false,"error":"interval must be a positive integer (seconds)"}'; exit 64 ;; esac
		# 下限 1 小时、上限 30 天：太频繁会被上游封，太久失去意义
		[ "$_interval" -ge 3600 ] || _interval=3600
		[ "$_interval" -le 2592000 ] || _interval=2592000
		read_schedule
		_int=$_interval; _en=1; _next=$(( $(now_epoch) + _interval ))
		write_schedule || { echo '{"ok":false,"error":"cannot persist schedule"}'; exit 73; }
		log_line "enabled interval=${_interval}s next=$_next"
		printf '{"ok":true,"enabled":1,"interval_secs":%s,"next_epoch":%s}\n' "$_interval" "$_next"
		;;
	disable)
		read_schedule
		_en=0; _next=0
		write_schedule || { echo '{"ok":false,"error":"cannot persist schedule"}'; exit 73; }
		log_line "disabled"
		echo '{"ok":true,"enabled":0}'
		;;
	status)
		read_schedule
		_now=$(now_epoch)
		_remaining=0
		[ "$_next" -gt "$_now" ] 2>/dev/null && _remaining=$(( _next - _now ))
		printf '{"ok":true,"enabled":%s,"interval_secs":%s,"next_epoch":%s,"remaining_secs":%s,"last_run_epoch":%s,"last_result":"%s"}\n' \
			"$_en" "$_int" "$_next" "$_remaining" "$_last" "$_res"
		;;
	due)
		# Called by the boot service and by apply: report whether a run is owed.
		read_schedule
		if [ "$_en" != 1 ]; then
			echo '{"ok":true,"due":false,"reason":"disabled"}'
			exit 0
	fi
		_now=$(now_epoch)
		if [ "$_next" -le "$_now" ] 2>/dev/null; then
			echo '{"ok":true,"due":true}'
		else
			printf '{"ok":true,"due":false,"remaining_secs":%s}\n' "$(( _next - _now ))"
		fi
		;;
	run)
		read_schedule
		_started=$(now_epoch)
		# The actual fetch/apply is the module's own entrypoint; reuse it rather than
		# re-implementing subscription handling here.
		if [ -f "$MODDIR/scripts/apply.sh" ]; then
			if sh "$MODDIR/scripts/apply.sh" >/dev/null 2>&1; then
				_res="ok"
			else
				_res="failed"
			fi
		else
			_res="no-apply-entrypoint"
		fi
		_last=$(now_epoch)
		_next=$(( _last + _int ))
		write_schedule || { echo '{"ok":false,"error":"cannot persist schedule"}'; exit 73; }
		log_line "run result=$_res elapsed=$(( _last - _started ))s next=$_next"
		printf '{"ok":true,"result":"%s","last_run_epoch":%s,"next_epoch":%s}\n' "$_res" "$_last" "$_next"
		;;
	*)
		echo '{"ok":false,"error":"usage: hostsupdate.sh enable [interval_secs] | disable | status | due | run"}'
		exit 64
		;;
esac
exit 0
