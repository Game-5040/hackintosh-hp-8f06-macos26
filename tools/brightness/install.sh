#!/bin/bash
# 安装亮度持久化：sudo bash install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "需要 root：sudo bash $0" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p /usr/local/bin

install -m 755 "$HERE/blp" /usr/local/bin/blp
install -m 755 "$HERE/bl" /usr/local/bin/bl
install -m 755 "$HERE/brightness-save.sh"    /usr/local/bin/brightness-save.sh
install -m 755 "$HERE/brightness-restore.sh" /usr/local/bin/brightness-restore.sh
install -m 644 "$HERE/com.local.brightness-save.plist"    /Library/LaunchDaemons/
install -m 644 "$HERE/com.local.brightness-restore.plist" /Library/LaunchDaemons/

launchctl bootout system /Library/LaunchDaemons/com.local.brightness-save.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.brightness-restore.plist 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.local.brightness-save.plist
launchctl bootstrap system /Library/LaunchDaemons/com.local.brightness-restore.plist
sleep 1
/usr/local/bin/brightness-save.sh
echo "已安装。当前保存的亮度: $(cat /var/db/brightness.level 2>/dev/null)"
launchctl list | grep brightness || true
