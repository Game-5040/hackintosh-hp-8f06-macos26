#!/bin/bash
# 保存真实亮度（linear-brightness）到 /var/db/brightness.level
set -u
BLP=/usr/local/bin/blp
STATE=/var/db/brightness.level
[ -x "$BLP" ] || exit 0
cur=$("$BLP" linear-brightness 2>/dev/null | awk '{print $3}')
[ -n "$cur" ] || exit 0
if [ ! -f "$STATE" ] || [ "$(cat "$STATE" 2>/dev/null)" != "$cur" ]; then
  printf '%s\n' "$cur" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
fi
