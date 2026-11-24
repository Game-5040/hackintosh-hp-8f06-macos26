#!/bin/bash
# 修复 OpenCore 启动菜单（双击运行，会要求输入管理员密码）
cd "$(dirname "$0")" || exit 1
clear
echo "==============================================="
echo "  修复 OpenCore 启动菜单"
echo "==============================================="
echo
echo "将校正以下内容："
echo "  1. 隐藏 Recovery / Reset NVRAM / 1401 工具条目"
echo "  2. 把它们标记为辅助条目（开机按空格才显示）"
echo "  3. 补回 CPU 名称补丁（revcpu / revpatch / revcpuname）"
echo
echo "请在弹出的提示里输入管理员密码。"
echo

if [ -x /usr/local/bin/oc-picker-tidy.sh ]; then
  T=/usr/local/bin/oc-picker-tidy.sh
else
  T="$(dirname "$0")/oc-picker-tidy.sh"
fi

if [ ! -f "$T" ]; then
  echo "✗ 找不到 oc-picker-tidy.sh（应在同目录或 /usr/local/bin）"
  echo
  read -n 1 -s -r -p "按任意键关闭..."; echo
  exit 1
fi

sudo /bin/bash "$T"
rc=$?

echo
if [ $rc -eq 0 ]; then
  echo "✅ 完成。重启后菜单应该只剩："
  echo "     Mac OS 26   /   Windows"
  echo "   （按空格可临时显示 Recovery 和 1401 工具）"
else
  echo "✗ 执行失败（退出码 $rc）"
  echo "   日志：/var/log/oc-picker-tidy.log"
fi
echo
read -n 1 -s -r -p "按任意键关闭窗口..."; echo
