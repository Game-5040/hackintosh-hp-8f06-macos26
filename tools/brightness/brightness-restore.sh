#!/bin/bash
# 开机恢复亮度：写 linear-brightness，等显示服务就绪，并在 20 秒后再校正一次
set -u
BLP=/usr/local/bin/blp
STATE=/var/db/brightness.level
[ -x "$BLP" ] || exit 0
[ -f "$STATE" ] || exit 0
val=$(cat "$STATE" 2>/dev/null)
[ -n "$val" ] || exit 0

apply() {
  "$BLP" linear-brightness "$val" >/dev/null 2>&1
}

# 等 AppleBacklightDisplay 出现
for i in $(seq 1 60); do
  if "$BLP" linear-brightness >/dev/null 2>&1; then
    apply
    break
  fi
  sleep 1
done

# 登录后 WindowServer 可能覆盖，再校正两次
sleep 20; apply
sleep 20; apply
exit 0
