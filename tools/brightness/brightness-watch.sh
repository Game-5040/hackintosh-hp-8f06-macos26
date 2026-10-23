#!/bin/bash
# 看门狗（用户级，每 3 秒）
set -u
DS=/usr/local/bin/ds
BLP=/usr/local/bin/blp
STATE=/Users/Shared/brightness.level
WSTATE=/Users/Shared/brightness.wrangler
LOG=/Users/Shared/brightness.log
[ -x "$DS" ] || exit 0
[ -f "$STATE" ] || exit 0

val=$(cat "$STATE" 2>/dev/null | tr -dc '0-9.')
[ -n "$val" ] || exit 0

wrangler_state() {
  ioreg -c IODisplayWrangler -r -d1 2>/dev/null \
    | sed -n 's/.*"CurrentPowerState"=\([0-9][0-9]*\).*/\1/p' | head -1
}
now_brightness() { "$DS" 2>/dev/null | head -1 | tr -dc '0-9.'; }
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG" 2>/dev/null; }
apply() {
  "$BLP" linear-brightness "$val" >/dev/null 2>&1
  "$DS" "$val" >/dev/null 2>&1
}

cur_w=$(wrangler_state)
last_w=$(cat "$WSTATE" 2>/dev/null)

# 只在读到有效状态时更新记录
if [ -n "$cur_w" ]; then
  printf '%s\n' "$cur_w" > "$WSTATE" 2>/dev/null || true
  if [ "$cur_w" = "4" ] && [ "$last_w" != "4" ]; then
    apply
    log "wake: last=$last_w now=$cur_w -> applied $val"
    exit 0
  fi
fi

# 显示器亮着时：用户改动就保存
if [ "$cur_w" = "4" ]; then
  cur=$(now_brightness)
  if [ -n "$cur" ] && [ "$cur" != "$val" ]; then
    printf '%s\n' "$cur" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    log "save: $val -> $cur"
  fi
fi
exit 0
