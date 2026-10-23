#!/bin/bash
set -u
DS=/usr/local/bin/ds
STATE=/Users/Shared/brightness.level
[ -x "$DS" ] || exit 0
cur=$("$DS" 2>/dev/null | head -1 | tr -dc '0-9.')
[ -n "$cur" ] || exit 0
[ -f "$STATE" ] || : > "$STATE"
[ "$(cat "$STATE" 2>/dev/null)" = "$cur" ] && exit 0
printf '%s\n' "$cur" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
chmod 644 "$STATE" 2>/dev/null || true
