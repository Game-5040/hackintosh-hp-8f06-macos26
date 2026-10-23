#!/bin/bash
# 阶段 1：开机尽早把面板设成关机时的亮度（不需要 GUI，用 IOKit）
set -u
BLP=/usr/local/bin/blp
STATE=/Users/Shared/brightness.level
[ -x "$BLP" ] || exit 0
[ -f "$STATE" ] || exit 0
val=$(cat "$STATE" 2>/dev/null | tr -dc '0-9.')
[ -n "$val" ] || exit 0

# 等 AppleBacklightDisplay 出现，最多 60 秒；成功一次就退出
for i in $(seq 1 300); do
  if "$BLP" linear-brightness "$val" >/dev/null 2>&1; then
    got=$("$BLP" linear-brightness 2>/dev/null | awk '{print $3}')
    [ "$got" = "$val" ] && exit 0
  fi
  sleep 0.1
done
exit 0
