#!/system/bin/sh
# ============================================================
#  intecheck.sh — 厂商内核完整性检测（inte.ko 类）情报透明工具
#
#  为什么要做这个：
#    一加/OPPO（ColorOS）内核里有 inte.ko，会在「系统启动完成后」检查
#    新加载的内核模块是否在白名单、每小时哈希 sys_call_table 查劫持，
#    并把结果（最多 10 条）暴露在 /proc/inte_ko 供用户态与游戏反作弊读取。
#
#    它不拦断任何东西，只记录。用户对自己被记了什么毫不知情 ——
#    本工具的作用是**把这件事变透明**：有没有这套机制、记了什么。
#
#  能力边界（如实说明）：
#    · 本工具**只读不写**，不做任何绕过、不做对抗、不修改内核；
#    · 它读 /proc/inte_ko 需要 root，普通 App 读不到（这是系统设计）；
#    · 「被记录」本身不等于被处罚，是否上报/判罚由用户态与游戏服务器决定。
#  用法: intecheck.sh {status|report|watch}
# ============================================================
. "$(dirname "$0")/common.sh"

INTE_PROC="/proc/inte_ko"
INTE_STATUS="/proc/inte_status"
KOHASH_BIN="/system/system_ext/bin/oplus_kohashprocess"
KOHASH_DATA="/data/oplus/persist_hash"
AC_CHAIN="SY_INTE"

# 是否 ColorOS/OPPO 系（决定这套机制是否存在）
ic_is_oplus() {
  [ -f /system/system_ext/bin/oplus_kohashprocess ] && return 0
  case "$(getprop ro.build.version.opporom 2>/dev/null)$(getprop ro.oplus.version 2>/dev/null)" in
    "") ;;
    *) return 0 ;;
  esac
  return 1
}

ic_has_inte() { [ -e "$INTE_PROC" ] || [ -e "$INTE_STATUS" ] || [ -f "$KOHASH_BIN" ]; }

ic_status() {
  has=no; ic_has_inte && has=yes
  oplus=no; ic_is_oplus && oplus=yes
  # 【真机缺陷修复】mksh 下 `wc -l < 不存在的文件 2>/dev/null` 仍会把
  # "can't open ..." 打到 stderr。先判可读再读，彻底消除噪音。
  recs=-1
  if [ -r "$INTE_PROC" ]; then
    recs=$(wc -l < "$INTE_PROC" 2>/dev/null | head -n1)
    [ -n "$recs" ] || recs=-1
  fi
  cache=no; [ -f "$KOHASH_DATA/kh_value_sys.bin" ] && cache=yes
  printf '{"mechanism":"%s","oplus":"%s","proc_records":%s,"hash_cache":"%s","bin":"%s"}\n' \
    "$has" "$oplus" "${recs:--1}" "$cache" "$KOHASH_BIN"
}

ic_report() {
  echo "=========== 内核完整性检测（inte.ko 类）情报 ==========="
  if ic_has_inte; then
    echo "[存在] 本机有厂商内核完整性检测机制"
  else
    echo "[未检测到] 本机没有 /proc/inte_ko 与 /proc/inte_status"
    echo "            （非 ColorOS 系，或内核未编入该模块）"
    echo ""
    echo "它是什么（供参考）："
    echo "  · 挂在 load_module 出口，哈希**内存中的模块镜像**（不读磁盘文件）；"
    echo "  · 每小时哈希 sys_call_table，比对加载时的快照，查系统调用劫持；"
    echo "  · 只记录（内存最多 10 条），不阻断、不卸载、不杀进程；"
    echo "  · 结果经 /proc/inte_ko 暴露，由用户态与游戏反作弊读取。"
    return 0
  fi
  echo ""
  echo "--- 机制组成 ---"
  [ -e "$INTE_PROC" ]   && echo "  [有] $INTE_PROC   （结果读取口，权限 root）" || echo "  [无] $INTE_PROC"
  [ -e "$INTE_STATUS" ] && echo "  [有] $INTE_STATUS （用户态写 1 表示启动完成）" || echo "  [无] $INTE_STATUS"
  [ -f "$KOHASH_BIN" ]  && echo "  [有] $KOHASH_BIN （算白名单哈希的用户态程序）" || echo "  [无] $KOHASH_BIN"
  [ -f "$KOHASH_DATA/kh_value_sys.bin" ] && echo "  [有] $KOHASH_DATA/kh_value_sys.bin （哈希缓存，仅首启/OTA 重建）" || echo "  [无] 哈希缓存"
  echo ""
  echo "--- 它读了什么（来自公开代码分析）---"
  echo "  唯一读取的目录: /system_dlkm/lib/modules/  （系统内核模块目录）"
  echo "  写入的目录:     /data/oplus/persist_hash/  （几百字节的哈希缓存）"
  echo "  **不读** /data、照片、聊天记录、应用数据 —— 内核侧零文件操作。"
  echo ""
  echo "--- 当前记录（/proc/inte_ko）---"
  if [ -r "$INTE_PROC" ]; then
    _n=$(wc -l < "$INTE_PROC" 2>/dev/null | head -n1)
    [ -n "$_n" ] || _n=0
    if [ "$_n" = "0" ]; then
      echo "  (空) —— 没有未知模块或劫持记录"
    else
      echo "  共 $_n 条："
      head -10 "$INTE_PROC" 2>/dev/null | sed "s/^/    /"
    fi
  else
    echo "  (读不到，需要 root)"
  fi
  echo ""
  echo "--- 本模块自身是否会被它记录 ---"
  echo "  SY 是**纯用户态 overlay**（文件替换 + 脚本），不在启动后加载任何 .ko，"
  echo "  也不修改 sys_call_table —— 按该机制的判定条件，不会产生记录。"
  echo "  （这是设计事实，不是"绕过手法"：我们本来就没有它要检测的行为。）"
}

TAB=$(printf '\t')

if [ "$(basename "$0")" = "intecheck.sh" ]; then
case "$1" in
  status) ic_status ;;
  report) ic_report ;;
  *) echo "usage: intecheck.sh {status|report}"; exit 2 ;;
esac
fi
