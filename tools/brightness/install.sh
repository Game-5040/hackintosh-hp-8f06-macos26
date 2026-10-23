#!/bin/bash
# 亮度持久化（两阶段版）：sudo bash install.sh
# 阶段1 daemon：开机(登录前)把面板设成关机时的亮度
# 阶段2 agent ：进入系统后把控制中心滑块同步成该值
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "需要 root：sudo bash $0" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
U="${SUDO_USER:-$USER}"
UID_N="$(id -u "$U")"
UHOME="$(dscl . -read /Users/"$U" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -n "$UHOME" ] || UHOME="/Users/$U"
STATE=/Users/Shared/brightness.level

echo "用户: $U (uid=$UID_N)"

mkdir -p /usr/local/bin
install -m 755 "$HERE/ds"  /usr/local/bin/ds
install -m 755 "$HERE/blp" /usr/local/bin/blp
install -m 755 "$HERE/bl"  /usr/local/bin/bl
install -m 755 "$HERE/brightness-early.sh" /usr/local/bin/brightness-early.sh
install -m 755 "$HERE/brightness-ui.sh"    /usr/local/bin/brightness-ui.sh
install -m 755 "$HERE/brightness-save.sh"  /usr/local/bin/brightness-save.sh

# 清理旧任务（不碰状态文件）
for p in com.local.brightness-early com.local.brightness-ui com.local.brightness-save com.local.brightness-restore; do
  launchctl bootout system /Library/LaunchDaemons/$p.plist 2>/dev/null || true
  launchctl bootout gui/"$UID_N" "$UHOME/Library/LaunchAgents/$p.plist" 2>/dev/null || true
  rm -f /Library/LaunchDaemons/$p.plist "$UHOME/Library/LaunchAgents/$p.plist"
done

# 状态文件：不存在或为空/非法时才初始化，绝不覆盖有效值
valid=0
if [ -s "$STATE" ]; then
  v=$(tr -dc '0-9.' < "$STATE")
  [ -n "$v" ] && valid=1
fi
if [ "$valid" = 0 ]; then
  cur=$(/usr/local/bin/ds 2>/dev/null | head -1 | tr -dc '0-9.')
  [ -n "$cur" ] || cur=0.5
  printf '%s\n' "$cur" > "$STATE"
  echo "初始化状态文件为当前亮度: $cur"
else
  echo "保留已有状态文件: $(cat "$STATE")"
fi
chmod 644 "$STATE"

# 阶段1：系统级 daemon（登录前就能跑）
install -m 644 "$HERE/com.local.brightness-early.plist" /Library/LaunchDaemons/
launchctl bootstrap system /Library/LaunchDaemons/com.local.brightness-early.plist

# 阶段2 + 保存：用户级 agent
mkdir -p "$UHOME/Library/LaunchAgents"
install -m 644 -o "$U" "$HERE/com.local.brightness-ui.plist"   "$UHOME/Library/LaunchAgents/"
install -m 644 -o "$U" "$HERE/com.local.brightness-save.plist" "$UHOME/Library/LaunchAgents/"
launchctl bootstrap gui/"$UID_N" "$UHOME/Library/LaunchAgents/com.local.brightness-ui.plist"   2>/dev/null || true
launchctl bootstrap gui/"$UID_N" "$UHOME/Library/LaunchAgents/com.local.brightness-save.plist" 2>/dev/null || true

echo
echo "状态文件: $(cat "$STATE")"
echo "early(daemon): $(launchctl print system/com.local.brightness-early >/dev/null 2>&1 && echo 已加载 || echo 失败)"
echo "ui(agent):     $(launchctl print gui/"$UID_N"/com.local.brightness-ui >/dev/null 2>&1 && echo 已加载 || echo 失败)"
echo "save(agent):   $(launchctl print gui/"$UID_N"/com.local.brightness-save >/dev/null 2>&1 && echo 已加载 || echo 失败)"
echo
echo "设置亮度（会同步滑块）：/usr/local/bin/ds 0.4"
echo "立即保存：               /usr/local/bin/brightness-save.sh"
