#!/bin/bash
# 双击运行：切换启动跑码（-v）与 OpenCore 屏幕日志
cd "$(dirname "$0")" || exit 1
S=./boot-verbose.sh

clear
echo "======================================"
echo "   OpenCore 启动跑码开关"
echo "======================================"
echo
"$S" status
echo "OpenCore 屏幕日志: $("$S" oc-log status)"
echo "--------------------------------------"
echo "  1) 关闭跑码（重启后生效）"
echo "  2) 开启跑码（重启后生效）"
echo "  3) 永久关闭跑码：关 -v + 写进 config.plist"
echo "  4) 关闭 OpenCore 屏幕日志（保留文件日志）"
echo "  5) 彻底静音：Target=0（不打印、不写日志）"
echo "  6) 恢复 OpenCore 默认（Target=67）"
echo "  7) 退出"
echo "--------------------------------------"
echo "  只选 1 的话，若 config.plist 仍带 -v，"
echo "  重启后会被写回来；要真正关掉选 3。"
echo "  选 4 可去掉 OpenCore 自己在屏幕上滚的日志。"
echo "  选 5 用于验证：若屏幕仍有字，说明是读 config 之前打的。"
echo "--------------------------------------"
printf "请选择 [1/2/3/4/5/6/7]: "
read -r choice

case "$choice" in
  1) "$S" off ;;
  2) "$S" on ;;
  3) "$S" off; echo; "$S" persist ;;
  4) "$S" oc-log off ;;
  5) "$S" oc-log silent ;;
  6) "$S" oc-log on ;;
  *) echo "已退出。"; exit 0 ;;
esac

echo
echo "按回车关闭窗口…"
read -r _
