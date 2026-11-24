#!/bin/bash
# wifi-hotspot-debug.sh — 抓 airportd 视角的扫描/加入过程，查「手机热点搜不到」
#
#   sudo ./wifi-hotspot-debug.sh "iPhone 12 mini"
#
# 做三件事：
#   1. 打开 airportd 的 WiFi 日志（wdutil log + wifi）
#   2. 用 networksetup 试着加入一次，触发 airportd 的扫描与加入流程
#   3. 把这一分钟里 airportd / wifid 的日志捞出来，重点看：
#        · 它解析到了多少条扫描结果（driver 交付了多少）
#        · 有没有提到目标 SSID（提到=看得见，没提到=没交付）
#        · 拒绝加入的具体 reason
#
# 只在内存里打日志，不改任何配置；跑完可用 `sudo wdutil log - wifi` 关掉。
set -u
export LC_ALL=C

SSID="${1:-}"
if [ -z "$SSID" ]; then echo "用法: sudo $0 \"SSID\""; exit 1; fi
if [ "$(id -u)" != 0 ]; then echo "需要 sudo：sudo $0 \"$SSID\""; exit 1; fi

IFACE=$(networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}')
OUT="/tmp/wifi-hotspot-debug-$(date +%Y%m%d-%H%M%S).txt"

{
  echo "=== 时间: $(date) 接口: $IFACE 目标 SSID: $SSID ==="
  echo
  echo "--- 驱动缓存里的这一项（有=驱动扫到了） ---"
  ioreg -rc WTLWireless -l -w0 2>/dev/null | tr ',' '\n' | grep -oE '"MtkScan" = ".*"' | tail -1 \
    | sed 's/"MtkScan" = "//; s/"$//' | tr ';' '\n' | grep -F "$SSID" || echo "  （驱动缓存里没有）"
  echo
  echo "--- 打开 airportd 日志 ---"
} > "$OUT" 2>&1

wdutil log + wifi >> "$OUT" 2>&1
sleep 1

echo "--- 尝试加入 ---" >> "$OUT"
networksetup -setairportnetwork "$IFACE" "$SSID" >> "$OUT" 2>&1
sleep 6

echo >> "$OUT"
echo "--- airportd / wifid 日志（最近 2 分钟） ---" >> "$OUT"
log show --last 2m --info --predicate 'process == "airportd" OR process == "wifid" OR process == "WiFiAgent"' --style compact 2>/dev/null \
  | grep -viE "verbose|throttl" >> "$OUT"

echo >> "$OUT"
echo "--- 关键行（扫描结果数、SSID、拒绝原因） ---" >> "$OUT"
grep -inE "scan|ssid|iphone|reject|unsupported|denied|fail|error|bss" "$OUT" \
  | grep -viE "^--- " | tail -60 > "${OUT%.txt}-key.txt" 2>/dev/null

echo "已保存: $OUT"
echo "摘要  : ${OUT%.txt}-key.txt"
echo
echo "===== 摘要 ====="
cat "${OUT%.txt}-key.txt" 2>/dev/null | head -60
