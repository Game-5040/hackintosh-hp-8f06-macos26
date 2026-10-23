#!/bin/bash
# 阶段 2：登录后把滑块同步到保存的亮度（快速版，最多约 10 秒）
set -u
DS=/usr/local/bin/ds
STATE=/Users/Shared/brightness.level
[ -x "$DS" ] || exit 0
[ -f "$STATE" ] || exit 0
val=$(cat "$STATE" 2>/dev/null | tr -dc '0-9.')
[ -n "$val" ] || exit 0

now() { "$DS" 2>/dev/null | head -1 | tr -dc '0-9.'; }

# 最多尝试 20 次（每次 0.5 秒），值对上就退出
for i in $(seq 1 60); do
  "$DS" "$val" >/dev/null 2>&1
  sleep 0.1
  [ "$(now)" = "$val" ] && exit 0
done
exit 0
