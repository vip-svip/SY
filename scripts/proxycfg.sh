#!/system/bin/sh
# ============================================================
#  proxycfg.sh — 配置事务（候选 → 校验 → 原子替换 → 可回滚）
#  ------------------------------------------------------------
#  为什么需要它（移植自 MagicNet 的配置激活契约）：
#    SY 旧版生成配置是 「} > $CFG」**直接覆盖**运行中的配置文件。
#    如果编译中途失败、或写盘被中断，留下的是**半截 JSON**；
#    内核下次读到坏配置会直接启动失败，而用户上一次能用的配置已经没了。
#    MagicNet 的做法是：先写候选文件 → sing-box check 校验 → 原子 rename；
#    任一步失败都保留上一次有效的配置。本脚本照这个契约实现。
#
#  事务步骤：
#    ① stage   生成候选（走 proxynode 的 gen-config 或 stdin 给内容）
#    ② check   用内核自身校验候选（check 通过才算）
#    ③ commit  校验通过才原子替换运行配置，旧配置留成 .prev
#    ④ rollback 一键回到上一次有效配置
# ============================================================
. $(dirname $0)/common.sh

PC_DIR="$DATA_DIR/rules/proxy"
PC_RUN="$PC_DIR/config.json"
PC_CAND="$PC_DIR/config.candidate.json"
PC_PREV="$PC_DIR/config.prev.json"
PC_LOG="$LOGS/proxy.log"
PC_STATE="$DATA_DIR/state/machines/config-txn.state"
mkdir -p "$PC_DIR" "$(dirname "$PC_STATE")" 2>/dev/null

pc_arch() {
  uname -m 2>/dev/null | sed 's/aarch64/arm64/;s/^armv8l$/arm64/;s/^armv7l$/armv7/;s/x86_64/amd64/'
}
pc_core() {
  a=$(pc_arch)
  for c in "$MODDIR/bin/kernels/sing-box-$a" "$MODDIR/bin/sing-box" "$MODDIR/bin/kernels/sing-box"; do
    [ -f "$c" ] && { echo "$c"; return; }
  done
  echo ""
}
pc_state() { # <phase>
  f="$PC_STATE"; tmp="$f.tmp.$"
  {
    echo schema=1
    echo domain=config-txn
    echo phase=$1
    echo updated=$(date +%s 2>/dev/null || echo 0)
    echo run_size=$( [ -s "$PC_RUN" ] && wc -c < "$PC_RUN" | tr -d " " || echo 0 )
    echo cand_size=$( [ -s "$PC_CAND" ] && wc -c < "$PC_CAND" | tr -d " " || echo 0 )
    echo prev_size=$( [ -s "$PC_PREV" ] && wc -c < "$PC_PREV" | tr -d " " || echo 0 )
  } > $tmp 2>/dev/null
  mv $tmp $f 2>/dev/null || rm -f $tmp 2>/dev/null
}

pc_stage_gen() {
  echo "== 1) 生成候选 =="
  sh "$(dirname "$0")/proxynode.sh" gen-config >/dev/null 2>&1
  if [ -s "$PC_RUN" ]; then
    cp -f "$PC_RUN" "$PC_CAND" 2>/dev/null && echo "  候选已就绪" || { echo "ERR: 复制失败"; return 1; }
    pc_state stage
    return 0
  fi
  echo "ERR: 生成失败（通常因为还没选节点）"
  return 1
}

pc_stage_stdin() {
  echo "== 1) 接收候选 =="
  cat > "$PC_CAND.tmp" 2>/dev/null
  if [ -s "$PC_CAND.tmp" ]; then
    mv -f "$PC_CAND.tmp" "$PC_CAND" 2>/dev/null
    echo "  候选已保存 ($(wc -c < "$PC_CAND" 2>/dev/null | tr -d " ") 字节)"
    pc_state stage
    return 0
  fi
  rm -f "$PC_CAND.tmp" 2>/dev/null
  echo "ERR: 输入为空"; return 1
}

pc_check() {
  echo "== 2) 校验候选 =="
  [ -s "$PC_CAND" ] || { echo "ERR: 没有候选（先 stage）"; return 1; }
  head -c 1 "$PC_CAND" 2>/dev/null | grep -q "{" || { echo "ERR: 候选不是 JSON 对象"; pc_state check_failed; return 1; }
  core=$(pc_core)
  if [ -z $core ]; then
    echo "WARN: 找不到内核，无法做权威校验 —— 这不是通过，是没条件校验"
    pc_state check_skipped
    return 0
  fi
  chk=$("$core" check -c "$PC_CAND" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    echo "  [通过] 内核 check 通过"
    pc_state check_ok
    return 0
  fi
  case "$chk" in
    *"unknown command"*|*"invalid command"*|*"Usage:"*)
      echo "  [跳过] 该内核版本不支持 check"; pc_state check_skipped; return 0 ;;
  esac
  echo "  [不通过] 候选有错，已阻止生效："
  printf "%s" "$chk" | head -n 5 | sed "s/^/     /"
  pc_state check_failed
  return 1
}

pc_commit() {
  echo "== 3) 提交（原子替换）=="
  [ -s "$PC_CAND" ] || { echo "ERR: 没有候选"; return 1; }
  pc_check >/dev/null 2>&1 || { echo "ERR: 候选未通过校验，拒绝提交（运行配置保持不变）"; return 1; }
  if [ -s "$PC_RUN" ]; then
    cp -f "$PC_RUN" "$PC_PREV" 2>/dev/null && echo "  已备份上一个有效配置 -> config.prev.json"
  fi
  if cp -f "$PC_CAND" "$PC_RUN.tmp" 2>/dev/null && mv -f "$PC_RUN.tmp" "$PC_RUN" 2>/dev/null; then
    rm -f "$PC_CAND" 2>/dev/null
    echo "  [成功] 运行配置已原子替换"
    pc_state committed
    return 0
  fi
  rm -f "$PC_RUN.tmp" 2>/dev/null
  echo "ERR: 替换失败（上一份仍可用）"
  pc_state commit_failed
  return 1
}

pc_rollback() {
  echo "== 回滚 =="
  [ -s "$PC_PREV" ] || { echo "ERR: 没有可回滚的备份"; return 1; }
  if cp -f "$PC_PREV" "$PC_RUN.tmp" 2>/dev/null && mv -f "$PC_RUN.tmp" "$PC_RUN" 2>/dev/null; then
    echo "  [成功] 已回滚到上一次有效配置"
    pc_state rolled_back
    echo "  提示: 内核仍在用旧配置运行，需重启代理才生效"
    return 0
  fi
  rm -f "$PC_RUN.tmp" 2>/dev/null
  echo "ERR: 回滚失败"; return 1
}

pc_status() {
  rs=0; [ -s "$PC_RUN" ] && rs=$(wc -c < "$PC_RUN" | tr -d " ")
  cs=0; [ -s "$PC_CAND" ] && cs=$(wc -c < "$PC_CAND" | tr -d " ")
  ps=0; [ -s "$PC_PREV" ] && ps=$(wc -c < "$PC_PREV" | tr -d " ")
  phase=idle; [ -f "$PC_STATE" ] && phase=$(sed -n "s/^phase=//p" "$PC_STATE" 2>/dev/null | head -n1)
  hr=false; [ "$rs" != "0" ] && hr=true
  hc=false; [ "$cs" != "0" ] && hc=true
  hp=false; [ "$ps" != "0" ] && hp=true
  printf '{"schema":1,"ok":true,"command":"config.status","data":{"phase":"%s","run_bytes":%s,"candidate_bytes":%s,"prev_bytes":%s,"has_run":%s,"has_candidate":%s,"has_prev":%s}}\n' $phase $rs $cs $ps $hr $hc $hp
}

case "$1" in
  stage)
    case "$2" in
      --from-gen|"") pc_stage_gen ;;
      *) pc_stage_gen ;;
    esac ;;
  stage-stdin) pc_stage_stdin ;;
  check)    pc_check ;;
  commit)   pc_commit ;;
  rollback) pc_rollback ;;
  status)   pc_status ;;
  apply)    pc_stage_gen && pc_check && pc_commit ;;
  *) echo "usage: proxycfg.sh {stage [--from-gen]|stage-stdin|check|commit|rollback|status|apply}"; exit 2 ;;
esac
