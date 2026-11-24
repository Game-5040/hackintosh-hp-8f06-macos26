#!/bin/bash
# boot-verbose.sh — 开关 macOS/OpenCore 的启动跑码（-v）
#
# 用法:
#   ./boot-verbose.sh            # 查看当前状态
#   ./boot-verbose.sh on         # 开启跑码
#   ./boot-verbose.sh off        # 关闭跑码
#   ./boot-verbose.sh toggle     # 反转当前状态
#   ./boot-verbose.sh persist    # 把当前状态固化进 config.plist（需 sudo；会去掉 Delete 里的 boot-args）
#   ./boot-verbose.sh oc-log off # 关闭 OpenCore 自己的屏幕日志（保留文件日志）
#   ./boot-verbose.sh oc-log on  # 恢复 OpenCore 屏幕日志（调试用）
#
# 原理:
#   跑码有两层来源：
#   ① 内核跑码 —— NVRAM 里的 boot-args 带 -v。开跑码 = 加入 -v debug=0x100 keepsyms=1。
#      OpenCore 的 config.plist 只在 NVRAM 里没有 boot-args 时才写入它自己的值；
#      若 NVRAM → Delete 里有 boot-args，则每次启动先删再写，nvram 改动撑不过重启，
#      所以要用 persist 把值写进 config 并移除 Delete 项。
#   ② OpenCore 自己的屏幕日志 —— Misc → Debug → Target 的 bit1 (0x02)。
#      这层与 -v 无关，即使没有 -v 也会在开机时滚字。用 oc-log off 关掉（保留 bit6 文件日志）。

set -u

# ---------- 颜色 ----------
if [ -t 1 ]; then
  B=$'\033[1m'; D=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=; D=; R=; G=; Y=; N=
fi

VERBOSE_TOKENS=("-v" "debug=0x100" "keepsyms=1")
OC_CONFIG="/Volumes/SYSTEM/EFI/OC/config.plist"

# ---------- 读取/写入 ----------
get_args() {
  nvram boot-args 2>/dev/null | sed -n 's/^boot-args[[:space:]]*//p'
}

write_args() {
  local value="$1" err actual
  if [ -z "$value" ]; then
    err="$(sudo nvram -d boot-args 2>&1)"
  else
    err="$(sudo nvram boot-args="$value" 2>&1)"
  fi

  # 读回校验：某些固件上 nvram 会报
  #   "Error creating CFTypeRef for value IONVRAM-SYNCNOW-PROPERTY"
  # 但值其实已经写入。以读回结果为准，只有确实没写进去才算失败。
  actual="$(get_args)"
  if [ "$actual" = "$value" ] || { [ -z "$value" ] && [ -z "$actual" ]; }; then
    if printf '%s' "$err" | grep -q "IONVRAM-SYNCNOW-PROPERTY"; then
      echo "${D}（忽略 nvram 的 IONVRAM-SYNCNOW-PROPERTY 提示：已读回确认写入成功）${N}"
    fi
    return 0
  fi

  echo "${R}写入失败: ${err:-未知错误}${N}" >&2
  echo "${D}当前实际值: ${actual:-<空>}${N}" >&2
  return 1
}

has_token() {  # $1=整串 $2=目标
  local w
  for w in $1; do
    [ "$w" = "$2" ] && return 0
  done
  return 1
}

drop_tokens() {  # $1=整串，其余=要去掉的
  local out="" w t skip
  for w in $1; do
    skip=0
    shift_dummy=0
    for t in "${@:2}"; do
      if [ "$w" = "$t" ]; then skip=1; break; fi
    done
    [ $skip -eq 0 ] && out="$out $w"
  done
  echo "${out# }"
}

append_tokens() {  # $1=整串，其余=要加上的（已存在则跳过）
  local out="$1" t
  for t in "${@:2}"; do
    if has_token "$out" "$t"; then continue; fi
    if [ -z "$out" ]; then out="$t"; else out="$out $t"; fi
  done
  echo "$out"
}

# ---------- 状态 ----------
show_status() {
  local args
  args="$(get_args)"
  echo
  echo "${B}当前 boot-args${N}"
  if [ -z "$args" ]; then
    echo "  ${D}(空)${N}"
  else
    # 逐词着色，-v / debug / keepsyms 高亮
    local w line="  "
    for w in $args; do
      case "$w" in
        -v|debug=0x100|keepsyms=1) line="$line${G}${w}${N} " ;;
        *) line="$line$w " ;;
      esac
    done
    echo "$line"
  fi
  echo
  if has_token "$args" "-v"; then
    echo "跑码状态: ${G}已开启${N}  ${D}(-v 存在，下次启动显示内核日志)${N}"
  else
    echo "跑码状态: ${D}已关闭${N}  ${D}(正常白苹果/进度条)${N}"
  fi
  echo
  if [ -f "$OC_CONFIG" ]; then
    local oc
    oc="$(/usr/bin/plutil -extract 'NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args' raw -o - "$OC_CONFIG" 2>/dev/null)"
    echo "${D}config.plist 里的值（清 NVRAM 后会退回这里）:${N}"
    echo "  ${oc:-<空>}"
  else
    echo "${D}EFI 未挂载，跳过 config.plist 检查${N}"
  fi
  echo
}

# ---------- 动作 ----------
do_on() {
  local before after
  before="$(get_args)"
  after="$(append_tokens "$before" "${VERBOSE_TOKENS[@]}")"
  if [ "$before" = "$after" ]; then
    echo "${Y}已经是开启状态，无需改动。${N}"
    return 0
  fi
  write_args "$after" || { echo "${R}写入 NVRAM 失败。${N}"; return 1; }
  echo "${G}已开启跑码。${N}"
  echo "${D}新增: -v debug=0x100 keepsyms=1${N}"
  echo "重启后生效。"
}

do_off() {
  local before after
  before="$(get_args)"
  after="$(drop_tokens "$before" "${VERBOSE_TOKENS[@]}")"
  if [ "$before" = "$after" ]; then
    echo "${Y}已经是关闭状态，无需改动。${N}"
    return 0
  fi
  write_args "$after" || { echo "${R}写入 NVRAM 失败。${N}"; return 1; }
  echo "${G}已关闭跑码。${N}"
  echo "${D}移除: -v debug=0x100 keepsyms=1${N}"
  echo "重启后生效。"
}

do_toggle() {
  if has_token "$(get_args)" "-v"; then do_off; else do_on; fi
}

GUID_NVRAM="7C436110-AB2A-4BBB-A880-FE41995C9F82"

ensure_oc_mounted() {
  [ -f "$OC_CONFIG" ] && return 0
  echo "${D}挂载 EFI 分区（会提示输入密码）…${N}"
  sudo diskutil mount disk0s1 >/dev/null 2>&1 || sudo diskutil mount /dev/disk0s1 >/dev/null 2>&1
  sleep 1
  if [ ! -f "$OC_CONFIG" ]; then
    echo "${R}挂载失败。请手动执行：sudo diskutil mount disk0s1${N}"
    return 1
  fi
  return 0
}

# 把当前 NVRAM 值固化进 config.plist，并去掉 Delete 里的 boot-args，
# 这样重启/清 NVRAM 都不会再退回旧值。
do_persist() {
  ensure_oc_mounted || return 1

  local args backup tmp add_before del_has
  args="$(get_args)"
  add_before="$(/usr/bin/plutil -extract "NVRAM.Add.$GUID_NVRAM.boot-args" raw -o - "$OC_CONFIG" 2>/dev/null)"
  if /usr/bin/plutil -extract "NVRAM.Delete.$GUID_NVRAM" json -o - "$OC_CONFIG" 2>/dev/null | grep -q '"boot-args"'; then
    del_has="是"
  else
    del_has="否"
  fi

  echo
  echo "${B}诊断${N}"
  echo "  config.Add.boot-args : ${add_before:-<空>}"
  echo "  config.Delete 含 boot-args : ${del_has}"
  echo "  NVRAM 当前值 : ${args:-<空>}"
  echo
  if [ "$del_has" = "是" ]; then
    echo "${Y}说明：Delete 里有 boot-args → OpenCore 每次启动会先删再按 config 写回，${N}"
    echo "${Y}      所以你用 nvram 改的值撑不过一次重启。下面会把它从 Delete 里移除。${N}"
    echo
  fi

  backup="$OC_CONFIG.bak-bootargs-$(date +%Y%m%d-%H%M%S)-$$"
  sudo cp "$OC_CONFIG" "$backup" || { echo "${R}备份失败${N}"; return 1; }
  echo "${D}已备份: $backup${N}"

  tmp="$(mktemp /tmp/oc-config.XXXXXX.plist)"
  /usr/bin/python3 - "$OC_CONFIG" "$tmp" "$GUID_NVRAM" "$args" <<'PY' || { echo "${R}生成新配置失败${N}"; return 1; }
import plistlib, sys
src, dst, guid, value = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(src, 'rb') as f:
    cfg = plistlib.load(f)
nv = cfg.setdefault('NVRAM', {})
add = nv.setdefault('Add', {}).setdefault(guid, {})
if value:
    add['boot-args'] = value
else:
    add.pop('boot-args', None)
dele = nv.get('Delete', {}).get(guid, None)
if isinstance(dele, list) and 'boot-args' in dele:
    dele.remove('boot-args')
    print('  removed boot-args from NVRAM.Delete')
with open(dst, 'wb') as f:
    plistlib.dump(cfg, f, sort_keys=False)
PY

  sudo cp "$tmp" "$OC_CONFIG" || { echo "${R}写入 config.plist 失败${N}"; return 1; }
  rm -f "$tmp"

  if ! /usr/bin/plutil -lint "$OC_CONFIG" >/dev/null 2>&1; then
    echo "${R}语法校验失败，回滚…${N}"
    sudo cp "$backup" "$OC_CONFIG"
    return 1
  fi

  local add_after
  add_after="$(/usr/bin/plutil -extract "NVRAM.Add.$GUID_NVRAM.boot-args" raw -o - "$OC_CONFIG" 2>/dev/null)"
  echo "${G}config.plist 已更新并通过语法校验。${N}"
  echo "  Add.boot-args 现在 : ${add_after:-<空>}"
  if [ "$add_after" = "$args" ]; then
    echo "${G}✓ 与 NVRAM 当前值一致，重启后不会再被改写。${N}"
  else
    echo "${Y}⚠ 写回值与预期不同，请检查。${N}"
  fi
}

# ---------- OpenCore 自身的屏幕日志 ----------
# Misc → Debug → Target 位含义（见 Configuration.pdf）:
#   0x01 启用日志  0x02 屏幕(console)  0x04 DataHub  0x08 串口
#   0x10 UEFI变量  0x20 非易失变量    0x40 文件  0x80 快速文件
describe_target() {
  local t="$1" parts=""
  [ $((t & 0x01)) -ne 0 ] && parts="$parts 日志"
  [ $((t & 0x02)) -ne 0 ] && parts="$parts 屏幕"
  [ $((t & 0x04)) -ne 0 ] && parts="$parts DataHub"
  [ $((t & 0x08)) -ne 0 ] && parts="$parts 串口"
  [ $((t & 0x10)) -ne 0 ] && parts="$parts UEFI变量"
  [ $((t & 0x20)) -ne 0 ] && parts="$parts 非易失变量"
  [ $((t & 0x40)) -ne 0 ] && parts="$parts 文件"
  [ $((t & 0x80)) -ne 0 ] && parts="$parts 快速文件"
  echo "${parts:- 无}"
}

do_oclog() {
  local want="${1:-}" cur new
  case "$want" in
    ""|status)
      if [ ! -f "$OC_CONFIG" ]; then
        echo "EFI 未挂载，无法读取 OpenCore 日志设置"
        return 0
      fi
      ;;
    *) ensure_oc_mounted || return 1 ;;
  esac
  cur="$(/usr/bin/plutil -extract Misc.Debug.Target raw -o - "$OC_CONFIG" 2>/dev/null)"

  if [ -z "$cur" ]; then
    echo "${R}读不到 Misc.Debug.Target${N}"; return 1
  fi

  case "$want" in
    off|quiet) new=$(( (cur | 0x01 | 0x40) & ~0x02 )) ;;  # 日志+文件，无屏幕
    on|default) new=$(( cur | 0x01 | 0x02 | 0x40 )) ;;    # 加上屏幕
    silent|none) new=0 ;;                                 # 全关：无日志、无文件、无屏幕
    file) new=$(( (cur | 0x40) & ~0x02 )) ;;              # 只写文件
    ""|status) echo "Target = $cur (0x$(printf '%x' "$cur"))  →$(describe_target "$cur")"; return 0 ;;
    *[0-9]*) if [ "$want" -ge 0 ] 2>/dev/null; then new="$want"; else
               echo "用法: $0 oc-log off|on|silent|file|status|<十进制数>"; return 2; fi ;;
    *) echo "用法: $0 oc-log off|on|silent|file|status|<十进制数>"; return 2 ;;
  esac

  echo "${D}Target: $cur (0x$(printf '%x' "$cur")) →$(describe_target "$cur")${N}"
  echo "${D}Target: $new (0x$(printf '%x' "$new")) →$(describe_target "$new")${N}"

  local backup="$OC_CONFIG.bak-oclog-$(date +%Y%m%d-%H%M%S)-$$"
  sudo cp "$OC_CONFIG" "$backup" || { echo "${R}备份失败${N}"; return 1; }
  sudo /usr/bin/plutil -replace Misc.Debug.Target -integer "$new" "$OC_CONFIG" || {
    echo "${R}写入失败${N}"; return 1; }

  if ! /usr/bin/plutil -lint "$OC_CONFIG" >/dev/null 2>&1; then
    echo "${R}语法校验失败，回滚…${N}"; sudo cp "$backup" "$OC_CONFIG"; return 1
  fi

  local after
  after="$(/usr/bin/plutil -extract Misc.Debug.Target raw -o - "$OC_CONFIG" 2>/dev/null)"
  if [ "$after" = "$new" ]; then
    echo "${G}✓ 已写入 Target = $after${N}"
    case "$want" in
      off|quiet) echo "重启后 OpenCore 不再在屏幕上打印日志（opencore-*.txt 文件日志仍保留）。" ;;
      on|default) echo "重启后 OpenCore 会在屏幕上打印日志。" ;;
      silent|none) echo "重启后既不打印也不写 opencore-*.txt —— 出问题就没线索了，排完记得改回 off。" ;;
      file) echo "重启后只写 opencore-*.txt，屏幕上不打印。" ;;
    esac
  else
    echo "${Y}⚠ 读回值 $after 与预期 $new 不同${N}"
  fi
}

# ---------- 入口 ----------
action="${1:-status}"
case "$action" in
  status|"") show_status ;;
  on|enable)   do_on;  echo; show_status ;;
  off|disable) do_off; echo; show_status ;;
  toggle)      do_toggle; echo; show_status ;;
  persist|sync-oc) do_persist ;;
  oc-log|oclog) shift; do_oclog "${1:-status}" ;;
  -h|--help|help)
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
    ;;
  *)
    echo "${R}未知参数: $action${N}"
    echo "用法: $0 [status|on|off|toggle|persist|oc-log on|off]"
    exit 2
    ;;
esac
