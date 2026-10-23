#!/bin/bash
# 常驻看门狗（0.3 秒轮询）
#  - 进程启动/重启（含唤醒后）→ 应用一次
#  - 时间跳变（整机睡眠后恢复）→ 应用一次
#  - 显示器 1→4 → 应用一次
#  - 用户改动 → 保存新值
set -u
DS=/usr/local/bin/ds
BLP=/usr/local/bin/blp
STATE=/Users/Shared/brightness.level
WSTATE=/Users/Shared/brightness.wrangler
LOG=/Users/Shared/brightness.log
[ -x "$DS" ] || exit 1

wrangler_state() {
  ioreg -c IODisplayWrangler -r -d1 2>/dev/null \
    | sed -n 's/.*"CurrentPowerState"=\([0-9][0-9]*\).*/\1/p' | head -1
}
now_brightness() { "$DS" 2>/dev/null | head -1 | tr -dc '0-9.'; }
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG" 2>/dev/null; }
apply() {
  val=$(cat "$STATE" 2>/dev/null | tr -dc '0-9.')
  [ -n "$val" ] || return 0
  "$BLP" linear-brightness "$val" >/dev/null 2>&1
  "$DS" "$val" >/dev/null 2>&1
}

# 启动即应用（登录、或唤醒后 KeepAlive 拉起）
sleep 0.5
apply
log "start: applied $(cat "$STATE" 2>/dev/null)"
last_w=$(cat "$WSTATE" 2>/dev/null)
last_t=$(date +%s)

while true; do
  sleep 0.3
  t=$(date +%s)
  # 时间跳变超过 2 秒 → 刚从睡眠恢复
  if [ $((t - last_t)) -gt 2 ]; then
    apply
    log "resume: gap $((t - last_t))s, applied"
    last_t=$t
    last_w=$(cat "$WSTATE" 2>/dev/null)
    continue
  fi
  last_t=$t

  val=$(cat "$STATE" 2>/dev/null | tr -dc '0-9.')
  cur_w=$(wrangler_state)
  [ -n "$val" ] && [ -n "$cur_w" ] || continue

  if [ "$cur_w" != "$last_w" ]; then
    printf '%s\n' "$cur_w" > "$WSTATE" 2>/dev/null || true
    if [ "$cur_w" = "4" ]; then
      apply
      log "wake: applied $val"
    fi
    last_w="$cur_w"
  elif [ "$cur_w" = "4" ]; then
    cur=$(now_brightness)
    if [ -n "$cur" ] && [ "$cur" != "$val" ]; then
      printf '%s\n' "$cur" > "$STATE" 2>/dev/null || true
      log "save: $val -> $cur"
    fi
  fi
done
