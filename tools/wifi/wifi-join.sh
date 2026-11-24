#!/bin/bash
# wifi-join.sh — 绕过 Wi-Fi 菜单，直接按 SSID 连接（MT7925 / WTLWireless）
#
#   ./wifi-join.sh list                 列出驱动最近一次扫描看到的网络
#   ./wifi-join.sh status               当前连接状态
#   ./wifi-join.sh join SSID [密码]     直接加入（密码省略则用钥匙串里保存的）
#   ./wifi-join.sh forget SSID          忘记该网络
#
# 为什么需要它：macOS 的 Wi-Fi 菜单里那条是「连续互通热点」(Instant Hotspot)，走 AWDL，
# 而 MtkWlan/WTLWireless 没有 AWDL 接口，所以菜单里点了没反应、或者干脆显示搜索不到。
# 驱动其实扫得到这个热点（ioreg 的 MtkScan 里就有），直接按 SSID 加入即可。
set -u
export LC_ALL=C

IFACE=$(networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}')
[ -n "${IFACE:-}" ] || { echo "找不到 Wi-Fi 接口"; exit 1; }

scan_list() {
  ioreg -rc WTLWireless -l -w0 2>/dev/null \
    | tr ',' '\n' | grep -oE '"MtkScan" = ".*"' | tail -1 \
    | sed 's/"MtkScan" = "//; s/"$//' | tr ';' '\n' \
    | sed 's/^ *//' | grep -v '^$' \
    | awk -F/ '{printf "%4s dBm  ch%-4s %-10s %s\n", $3, $2, $4, $1}' \
    | sort -t' ' -k1,1nr
}

scan_list_raw() {
  ioreg -rc WTLWireless -l -w0 2>/dev/null \
    | tr ',' '\n' | grep -oE '"MtkScan" = ".*"' | tail -1 \
    | sed 's/"MtkScan" = "//; s/"$//' | tr ';' '\n' | sed 's/^ *//' | grep -v '^$'
}

state() {
  ioreg -rc WTLWireless -l -w0 2>/dev/null | tr ',' '\n' \
    | grep -oE '"MtkState" = [^,}]+' | sed 's/"MtkState" = //; s/"//g'
}

ssid_now() {
  ioreg -rc WTLWireless -l -w0 2>/dev/null | tr ',' '\n' \
    | grep -oE '"MtkTargetSsid" = [^,}]+' | sed 's/.*= //; s/"//g'
}

show_status() {
  local st ip ssid
  st=$(state); ssid=$(ssid_now); ip=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
  echo "接口      : $IFACE"
  echo "驱动状态  : ${st:-未知}"
  if echo "$st" | grep -q disconnected; then
    echo "上次 SSID : ${ssid:-(无)}"
  else
    echo "当前 SSID : ${ssid:-(未连接)}"
  fi
  echo "IP 地址   : ${ip:-(无)}"
  local rssi
  rssi=$(scan_list_raw | grep -F "${ssid:+$ssid/}" 2>/dev/null | head -1 | awk -F/ '{print $3" dBm, ch"$2}')
  [ -n "${rssi:-}" ] && echo "信号      : $rssi"
}

power_on() {
  if ifconfig "$IFACE" 2>/dev/null | grep -q "status: inactive"; then
    echo "Wi-Fi 处于关闭状态，先打开…"
    networksetup -setairportpower "$IFACE" on 2>&1 | sed 's/^/  /'
    sleep 3
  fi
}

do_join() {
  local ssid="$1" pw="${2:-}"
  power_on
  echo "正在加入「$ssid」…"
  if [ -n "$pw" ]; then
    JOIN_OUT=$(networksetup -setairportnetwork "$IFACE" "$ssid" "$pw" 2>&1)
  else
    JOIN_OUT=$(networksetup -setairportnetwork "$IFACE" "$ssid" 2>&1)
  fi
  printf '%s\n' "$JOIN_OUT" | sed 's/^/  /' 
  local i ip
  # networksetup 在 airportd 的扫描缓存里找不到该 SSID 时会直接返回这句，连驱动都不会碰
  if [ -n "${JOIN_OUT:-}" ] && echo "$JOIN_OUT" | grep -q "Could not find network"; then
    echo
    echo "macOS 的扫描列表里没有这个 SSID（驱动自己扫到了，但没交给 airportd）。"
    echo "手机热点常见原因与对策："
    echo "  1) iPhone：设置 → 个人热点 → 打开「最大化兼容性」（强制 2.4 GHz），再跑一次"
    echo "  2) 菜单栏 Wi-Fi 里点「其他…」，手动输入 SSID 和密码（绕过扫描缓存）"
    echo "  3) 实在不行就用 USB 线共享网络：iPhone 插上后 设置 → 个人热点 → 允许其他人加入"
    return 0
  fi
  for i in $(seq 1 20); do
    sleep 1
    ip=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
    [ -n "${ip:-}" ] && break
  done
  echo
  show_status
  if [ -n "${ip:-}" ]; then
    echo
    echo "已连上，网关 $(ipconfig getoption "$IFACE" router 2>/dev/null || echo 未知)，测连通性…"
    if ping -c1 -t3 "$(ipconfig getoption "$IFACE" router 2>/dev/null || echo 223.5.5.5)" >/dev/null 2>&1; then
      echo "  网关可达 ✓"
    else
      echo "  网关不可达 ✗（可能只是还没拿到 DHCP，等几秒再看）"
    fi
  else
    echo
    echo "20 秒内没拿到 IP。可能的原因："
    echo "  · 密码不对（菜单里点「其他…」用同样的密码试试，能连上就说明密码没问题）"
    echo "  · iPhone 热点需要打开「最大化兼容性」（设置 → 个人热点）"
    echo "  · 这个网络是隐藏 SSID 或者驱动这次没扫到：./wifi-join.sh list 看列表里有没有它"
  fi
}

case "${1:-}" in
  list)   scan_list ;;
  status) show_status ;;
  join)
    [ -n "${2:-}" ] || { echo "用法: $0 join SSID [密码]"; exit 1; }
    do_join "$2" "${3:-}" ;;
  forget)
    [ -n "${2:-}" ] || { echo "用法: $0 forget SSID"; exit 1; }
    networksetup -removepreferredwirelessnetwork "$IFACE" "$2" 2>&1 | sed 's/^/  /' ;;
  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
