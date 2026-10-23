#!/bin/bash
# 亮度持久化：sudo bash install.sh
#   daemon: 开机(登录前)写 linear-brightness
#   agent : 登录后同步滑块；显示器重新点亮时重新应用；用户改动时保存
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "需要 root：sudo bash $0" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
U="${SUDO_USER:-$USER}"
UID_N="$(id -u "$U")"
UHOME="$(dscl . -read /Users/"$U" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -n "$UHOME" ] || UHOME="/Users/$U"
STATE=/Users/Shared/brightness.level

# 如果没有预编译二进制，就地编译（需要 Command Line Tools）
if [ ! -x "$HERE/ds" ] || [ ! -x "$HERE/bl" ]; then
  echo "编译工具..."
  clang -O2 -o "$HERE/bl"  "$HERE/bl.c"  -framework IOKit -framework CoreFoundation
  clang -O2 -o "$HERE/blp" "$HERE/blp.c" -framework IOKit -framework CoreFoundation
  clang -O2 -o "$HERE/ds"  "$HERE/ds.c"  -framework CoreGraphics
  clang -O2 -o "$HERE/bw"  "$HERE/bw.c"  -framework CoreGraphics -framework IOKit -framework CoreFoundation
fi

mkdir -p /usr/local/bin
install -m 755 "$HERE/ds"  /usr/local/bin/ds
install -m 755 "$HERE/blp" /usr/local/bin/blp
install -m 755 "$HERE/bl"  /usr/local/bin/bl
install -m 755 "$HERE/brightness-early.sh" /usr/local/bin/brightness-early.sh
install -m 755 "$HERE/bw" /usr/local/bin/bw

# 清理旧任务
for p in com.local.brightness-early com.local.brightness-ui com.local.brightness-save com.local.brightness-restore com.local.brightness-watch; do
  launchctl bootout system /Library/LaunchDaemons/$p.plist 2>/dev/null || true
  launchctl bootout gui/"$UID_N" "$UHOME/Library/LaunchAgents/$p.plist" 2>/dev/null || true
  rm -f /Library/LaunchDaemons/$p.plist "$UHOME/Library/LaunchAgents/$p.plist"
done

# 状态文件：不存在/为空时才初始化
valid=0
if [ -s "$STATE" ]; then v=$(tr -dc '0-9.' < "$STATE"); [ -n "$v" ] && valid=1; fi
if [ "$valid" = 0 ]; then
  cur=$(/usr/local/bin/ds 2>/dev/null | head -1 | tr -dc '0-9.')
  [ -n "$cur" ] || cur=0.5
  printf '%s\n' "$cur" > "$STATE"
  echo "初始化状态文件: $cur"
else
  echo "保留状态文件: $(cat "$STATE")"
fi
# 交给登录用户，保证 agent 能读写（daemon 以 root 运行，读没问题）
touch /Users/Shared/brightness.wrangler /Users/Shared/brightness.log
chown "$U" "$STATE" /Users/Shared/brightness.wrangler /Users/Shared/brightness.log
chmod 644 "$STATE" /Users/Shared/brightness.wrangler /Users/Shared/brightness.log
rm -f "$STATE.tmp"

# daemon：开机尽早调暗
install -m 644 "$HERE/com.local.brightness-early.plist" /Library/LaunchDaemons/
launchctl bootstrap system /Library/LaunchDaemons/com.local.brightness-early.plist

# agent：看门狗（登录 + 每 3 秒）
mkdir -p "$UHOME/Library/LaunchAgents"
install -m 644 -o "$U" "$HERE/com.local.brightness-watch.plist" "$UHOME/Library/LaunchAgents/"
launchctl bootstrap gui/"$UID_N" "$UHOME/Library/LaunchAgents/com.local.brightness-watch.plist"

echo "状态: $(cat "$STATE")"
echo "early daemon: $(launchctl print system/com.local.brightness-early >/dev/null 2>&1 && echo OK || echo 失败)"
echo "watch agent:  $(launchctl print gui/"$UID_N"/com.local.brightness-watch >/dev/null 2>&1 && echo OK || echo 失败)"
