#!/bin/bash
# 校准 OpenCore 配置：把 1401 每次更新后改掉的设置修回来
# 用法: sudo bash oc-picker-tidy.sh [--check]
set -uo pipefail
MNT=/Volumes/SYSTEM
CONFIG="$MNT/EFI/OC/config.plist"
LOG=/var/log/oc-picker-tidy.log
DRY=0; [ "${1:-}" = "--check" ] && DRY=1
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

we_mounted=0
if [ ! -f "$CONFIG" ]; then
  diskutil mount disk0s1 >/dev/null 2>&1 || true
  sleep 1
  [ -f "$CONFIG" ] && we_mounted=1
fi
if [ ! -f "$CONFIG" ]; then log "找不到 config.plist（ESP 挂载失败）"; exit 1; fi

suffix=""
[ "$DRY" = 1 ] && suffix="（预览）"
log "开始校准$suffix $CONFIG"
/usr/bin/python3 - "$CONFIG" "$DRY" <<'PY'
import plistlib, sys, shutil, datetime, os, re
path, dry = sys.argv[1], sys.argv[2] == "1"
d = plistlib.load(open(path, 'rb'))
changed = []
def note(m):
    changed.append(m); print("   *", m)

# 1. 辅助条目默认隐藏
b = d['Misc']['Boot']
if b.get('HideAuxiliary') is not True:
    b['HideAuxiliary'] = True
    note("Misc.Boot.HideAuxiliary = true")

# 2. 1401 的工具条目标记为辅助（按 Space 才显示）
for t in d['Misc'].get('Tools', []):
    name = t.get('Name', '') or ''
    p = t.get('Path', '') or ''
    if name.startswith('1401:') or 'NullMoth' in p:
        if t.get('Auxiliary') is not True:
            t['Auxiliary'] = True
            note(f"工具 {name!r}: Auxiliary = true")

# 3. boot-args 里补回 CPU 名称补丁
G = '7C436110-AB2A-4BBB-A880-FE41995C9F82'
nvr = d['NVRAM']['Add'].get(G, {})
ba = nvr.get('boot-args', '')
if ba:
    nba = re.sub(r'revpatch=([^\s]+)',
                 lambda m: 'revpatch=' + ','.join(
                     m.group(1).split(',') if 'cpuname' in m.group(1).split(',')
                     else m.group(1).split(',') + ['cpuname']),
                 ba) if 'revpatch=' in ba else ba + ' revpatch=cpuname'
    if 'revcpu=' not in nba:
        nba += ' revcpu=1'
    if nba != ba:
        nvr['boot-args'] = nba
        note("boot-args: 补回 revpatch=...,cpuname 与 revcpu=1")

# 4. 自定义 CPU 名称
L = '4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102'
want = 'AMD Ryzen 9 9955HX 16-Core Processor'
d['NVRAM']['Add'].setdefault(L, {})
if d['NVRAM']['Add'][L].get('revcpuname') != want:
    d['NVRAM']['Add'][L]['revcpuname'] = want
    note("NVRAM revcpuname 已恢复")

if not changed:
    print("   配置已符合预期，无需修改")
    sys.exit(0)
if dry:
    print("   （预览模式，未写入）")
    sys.exit(0)

bak = path + ".bak-tidy-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
shutil.copy2(path, bak)
print("   备份:", os.path.basename(bak))
plistlib.dump(d, open(path, 'wb'), fmt=plistlib.FMT_XML)
print("   已写入")
PY

# 只保留最近 5 个 tidy 备份
ls -t "$MNT/EFI/OC"/config.plist.bak-tidy-* 2>/dev/null | tail -n +6 | while read -r f; do rm -f "$f"; done

if [ "$we_mounted" = 1 ] && [ "$DRY" = 0 ]; then
  diskutil unmount disk0s1 >/dev/null 2>&1 || true
fi
log "完成"
