# HP 笔记本（Ryzen 9 9955HX + RTX 5070）黑苹果 macOS 26 Tahoe 实战记录

> 在 HP 8F06 上**全新安装** macOS 26，让显示、亮度、Wi-Fi、蓝牙、音频输出、**内置麦克风**、**Siri**、电池、USB、三系统引导全部可用。
> 当前系统：**macOS 26.7.3（25G342）**，驱动 NVIDIA **3.1** + **WTLWireless 0.15.0**（Wi-Fi 与蓝牙同一个包）+ BlueToolFixup 2.7.2 / LegionBtFix **0.3.0**。
> 内置麦克风不是"找到个驱动装上"，而是**自己写的**：kext（`ACPCapture`，ACP6x PDM DMA）+ HAL 插件（`ACPMicPlugin`，用户态 DSP）。独立仓库：<https://github.com/Game-5040/acp6x-pdm-macos>。
> 已知缺口：睡眠（无 S3）、AirDrop（无 AWDL）、关机断电（待查）、部分图标残影（3.1 仍有）、iPhone 5 GHz 热点。

## 机器

| 项目 | 值 |
|---|---|
| 机型 | **HP OMEN 16-ap1xxx**（主板 ID `8F06`，ACP 的 `compatible` 报 `pci103c,8f06`） |
| CPU | AMD Ryzen 9 9955HX 16-Core（Zen 5, Fire Range） |
| 显卡 | NVIDIA GeForce RTX 5070 Laptop GPU 12 GB（device id `0x2D18`） |
| 屏幕 | 2560 × 1600 |
| 网卡 | MediaTek MT7925（Wi-Fi PCI `14C3:7925`，蓝牙 USB `0E8D:8C38`，ACP `1022:15E2` rev `0x62`） |
| 声卡 | Realtek ALC245（HDA `0x10EC0245`） |
| 系统 | macOS 26.7.3 (25G342) / Darwin 25.6.0 |
| SMBIOS | MacBookPro16,2 |
| 引导 | OpenCore **1.0.8 官方 RELEASE**（已替换 1401 的 DEBUG 构建） |

## 结果总览

| 功能 | 状态 | 方案 |
|---|---|---|
| 显示 / Metal 加速 | ✅ | NullMoth NVIDIA 驱动 **3.1** |
| 硬件背光（亮度） | ✅ | `nvrmacpibl=1` + 自建 LaunchDaemon 记住亮度（PR #312 在本机未生效） |
| HiDPI 缩放 | ⚠️ | `nvfbhidpi=1` + 驱动的「看起来像」尺寸；非整倍 HiDPI 未暴露，只能整倍 2×（1280×800） |
| Wi-Fi | ✅ | watchthelight **`WTLWireless` 0.15.0**（核心 + 原生前端 + 蓝牙固件三合一） |
| 蓝牙 | ✅ | `WTLWireless.Bt` 0.15.0 + `BlueToolFixup` 2.7.2 + `LegionBtFix` **0.3.0** |
| 音频输出 | ✅ | `AppleALC` 1.9.9 + **`SimpleHDA` 1.0.0** + layout 11；驱动 2.7 起自带 `NMXAudio`，实测接管了 ALC245 输出 |
| 电池 / 充电状态 | ✅ | `SSDT-AC` + `_PSR`/`_Q20` 重命名（26 上充电实时更新；"电源适配器已连接"指示不显示） |
| Windows 双系统引导 | ✅ | `LauncherOption = Full` + 自定义 `Entries` 图标 |
| Ubuntu 三系统引导 | ✅ | `OpenLinuxBoot` + `Ext4Dxe`（OC 直接起内核，不经 GRUB/shim）；BLSpec 把名字改成 `Ubuntu` |
| USB 端口映射 | ✅ | `USBToolBox` + 手工修正的 `UTBMap`（9 个端口，内部 255） |
| 内置麦克风 | ✅ | **自研**：`ACPCapture.kext`（ACP6x PDM DMA）+ `ACPMicPlugin.driver`（HAL 输入，含高通/AGC/门限） |
| Siri / 听写 | ✅ | HAL 插件暴露 `'imic'` 数据源控件（Siri 只认这个，见第十节） |
| 睡眠 | ❌ | 固件只声明 Modern Standby，无 S3 |
| 关机断电 | ⚠️ | 关机变重启；已排除 WOL/USB 唤醒/PMEE/RTC，定位到**拔掉 USB 设备即可正常关机** |
| 图标渲染残影 | ❌ | 默认（玻璃）图标样式下部分系统图标串图层；3.1 仍存在（不是 #363） |
| AirDrop / 连续互通 | ❌ | 驱动无 `awdl0`（AWDL 未实现）；可行性分析见 [docs/airdrop-feasibility.md](docs/airdrop-feasibility.md) |

---

# 一、迁移路径：15.8.1 → 26.7.1（全新安装，不是升级）

## 先说结论

**这台机器无法通过软件更新升级到 26。** 我们试过官方推荐路径，全部失败，最后采用的是：

```
1. 保留 15.8.1 不动
2. 全新安装 26.7.1 到一个新的 APFS 卷（双系统）
3. 从 15 里把 NVIDIA 驱动"写进" 26（文件复制 + 开机自动安装）
```

## 试过但失败的路径：软件更新 + 1401 的 Tahoe 准备

按 [NullMoth 1401](https://github.com/nullmoth/1401) 的文档，正确流程是：

1. 安装 `1401-Mac-*.dmg`
2. 点 **「Prepare this Mac for Tahoe」** —— 它会：
   - 把 NVIDIA 驱动升级到最新（自带 Tahoe 构建）
   - **停用（park）驱动**（安装期间不能有第三方显卡驱动占着 GPU）
   - **缩小 GPU BAR**（`ResizeAppleGpuBars 0` / `ResizeGpuBars -1`）
3. 走 **系统设置 → 通用 → 软件更新** 升级

**实际遇到两个失败：**

| 阶段 | 现象 |
|---|---|
| 准备阶段 | 弹窗「**未能准备软件更新。请重试。**」，`/Library/Updates` 里一个包都没下载 |
| 强行换完整安装器 | 安装器跑到「**剩不到一分钟**」卡死不动 |

可能的原因（未逐一验证）：

- 系统做过 SIP 定制（`csr-active-config 0x0A43`）+ AMFI 绕过（`amfi=0x80`）
- `/Library/Extensions` 里存在第三方驱动（NVIDIA），升级时要迁移它们
- 26 对 SMBIOS / 系统卷密封的要求更严

> 结论：**这台机器上，跨大版本"原地升级"走不通，别在这上面耗时间。**

## 实际采用的路径：全新安装到新卷

```
原盘布局（1 TB）
├── ESP              536 MB
├── Windows (NTFS)   214.8 GB
├── Data (NTFS)      674.7 GB
└── APFS 容器        ← 15.8.1

安装 26 之后
├── ESP
├── Windows
├── Data
├── APFS 容器 disk1   53.7 GB   ← 新装的 26.7.1
└── APFS 容器 disk2  134.2 GB   ← 原来的 15.8.1（完整保留）
```

**好处**：

- 15.8.1 原样保留，随时可以回退
- 26 装坏了删掉重来即可
- 两个系统独立，互不影响

**代价**：

- 26 里是**全新的系统**，没有驱动、没有音频、没有 Wi-Fi/蓝牙 —— 这些都要重装（见后续各节）
- 引导器要用能同时识别两个系统的 OpenCore

> 无线这套（`WTLWireless` + `LegionBtFix`）对系统构建是**白名单匹配**的：装成白名单外的小版本，
> 原生前端会拒绝加载（Wi-Fi 退回以太网端口、没有菜单），`bluetoothd` 也可能反复崩。
> 现在用 26.7.3（25G342）没问题，但每次升级小版本后都要回来确认一次（见第四、五节）。

## 关键：驱动要"从 15 写进 26"

新装的 26 里没有任何 NVIDIA 驱动，启动后只有一个鼠标光标（见下一节）。而看不到界面就进不了终端，
所以驱动是**在 15 里操作、由 26 自己完成安装**的：

```
在 15.8.1 里：
  1. 把驱动包完整解压到 26 的 /Users/Shared/nullmoth/
  2. 往 26 的 /Library/LaunchDaemons/ 放一个开机启动项
  3. 在 26 的 /Library/Extensions/ 里预先把 kext 放好

重启进 26：
  4. 开机时 LaunchDaemon 自动执行官方 install.sh
  5. install.sh 在 26 内部重建内核集合（这一步必须发生在 26 里）
  6. 脚本自动重启

第二次进 26：有画面了
```

详细原理与踩坑见下一节。

## 后续：回收 15.8.1 的空间

确认 26 稳定运行几天后，可以删除旧系统并把空间并入 26（**不可逆**，删前请确认个人文件已备份）：

```bash
# 1. 确认 disk2 是那个 134.2 GB 的旧系统容器
diskutil list disk2

# 2. 删除旧系统的整个 APFS 容器（含其中的 Time Machine 备份卷）
sudo diskutil apfs deleteContainer disk2

# 3. 把释放出来的连续空间并入 26 的容器（0 = 用满所有可用空间）
sudo diskutil apfs resizeContainer disk1 0

# 4. 验证
diskutil list && df -h /
```

本机结果：26 的容器从 **53.7 GB 扩到 187.9 GB**，可用空间从 14 GB 变成 138 GB。

> 注意：删除后就没有可回退的旧系统了，唯一救援介质是 1401 安装 U 盘和事先备份的 EFI。


---

# 二、显卡：NullMoth NVIDIA 驱动

驱动仓库：<https://github.com/nullmoth/nvidia-macos-driver>

## 为什么需要"开机自动安装"

macOS 26 全新安装完成后，这个卷里**没有任何 NVIDIA 驱动**。首次启动的表现为：

> **只有一个鼠标光标，屏幕全黑。**

这里有个容易误判的细节：**能看到鼠标光标，说明 WindowServer 已经在跑**（画光标就需要帧缓冲），
所以不是"完全没有显示驱动"，而是**帧缓冲接管了、但画面没有合成出来**。

对比 macOS 15：在同样没有驱动的情况下，15 能显示一个**完整的软件渲染桌面** ——
Dock、菜单栏都在，只是动态壁纸加载不出来，显示成白底。这说明 15 的基础帧缓冲 + WindowServer 软件渲染是能用的。

到了 26，这条回退路径失效了：只剩光标，桌面出不来。具体是驱动模型变化还是别的原因，尚未确认，
但这已经不是"没驱动"能解释的了 —— 更像是 26 在无硬件加速时放弃合成桌面。

无论原因如何，结果一样：**看不到界面，也就进不了终端**，只能让系统**自己**在开机时把驱动装上。

## 关键坑：内核集合必须在目标系统里构建

驱动装到 `/Library/Extensions` 后，需要进内核集合（`AuxiliaryKernelExtensions.kc`）才会加载。我们一开始想从 15 系统跨卷给 26 构建，**全部失败**：

| 尝试 | 结果 |
|---|---|
| 从 15 把 kext 拷进 26 的 `/Library/Extensions` | 内核集合没重建，驱动不加载 |
| `kmutil install -R "/Volumes/Mac OS 26 - Data"` | 静默无效（集合文件没变） |
| `kmutil install -R "/Volumes/Mac OS 26"` | 静默无效 |
| `kmutil create` 从 15 跨卷构建 | 集合里嵌入的是 `/Volumes/...` 临时路径，26 启动时找不到 |

官方文档 [docs/MULTI-GPU.md](https://github.com/nullmoth/nvidia-macos-driver/blob/main/docs/MULTI-GPU.md) 说得很清楚：

> an isolated preflight collection can embed `/var/tmp/.../repo/*.kext` in `_PrelinkBundlePath` … **The next boot found the temporary paths and loaded none of the NVIDIA components.**

**集合里的路径必须是永久路径**（`/Library/Extensions/...`），所以只能在 26 里面构建。

## 解决方案：开机自动安装

没有画面就进不了终端，于是用 **LaunchDaemon 在开机时跑官方 `install.sh`**：

1. 把官方驱动包（`nullmoth-nvidia-<版本>.tar.gz`，注意要**完整解压**，包含 `SHA256SUMS`）放到 `/Users/Shared/nullmoth/`
2. 装一个 LaunchDaemon，开机执行：

```bash
#!/bin/bash
exec >>/var/log/nullmoth-bootinstall.log 2>&1
rm -f /Library/LaunchDaemons/com.nullmoth.bootinstall.plist   # 只跑一次
cd /Users/Shared/nullmoth/pkgroot && ./install.sh
/sbin/shutdown -r now
```

3. 重启后 26 会自己装完并重启，第二次启动就有画面了

> **踩坑记录**：第一次失败是因为我只解压了 `Library/` 和 `Users/` 两个目录，
> 缺了 `SHA256SUMS`、`MANIFEST.txt`、`VERSION`，安装器第 2 步完整性校验直接拒绝：
> `STOP: SHA256SUMS mismatch: re-download the package`。
> **一定要整包解压。**

## 驱动版本

`NVRM` / `NVRMFB` / `NVRMAGDC` 是通用部分，`NVAccel` 按系统分构建（`kexts/15`、`kexts/26`）。一路升上来的版本：

| 版本 | 关键变化 |
|---|---|
| 2.5.2 | 我们最早用的一版，`kexts/15` + `kexts/26` 分目录 |
| 2.6.3 | HiDPI「看起来像」尺寸（#354）、Dock/控制中心模糊修复（#363）、屏幕旋转 |
| 2.7 | **自带 Tahoe HD Audio 驱动**（`NMXAudio`，Realtek + NVIDIA HDMI/DP）、ARM apps 翻译器、内核 panic 修复 |
| 2.8 | 开源内核模块换到 **620.70.06**、DLSS 4/4.5 走 MetalFX、Metal 4 对象模型 |
| 2.9 | 关机/重启前把 GPU 静默、BAR 还给固件（#488）；笔记本亮度启动时不再覆盖已保存值（#525）；240/300Hz 面板 |
| **3.1** | 当前使用中（26.7.3） |

版本之间不是只改 bug：2.7 把音频接管了，2.8 换的是内核模块本体，2.9 动的是关机路径 —— 升级前先看 release notes 再决定。

---

# 三、亮度：`nvrmacpibl=1`

DSDT 里本来就有背光设备（`\_SB.PCI0.GP17.VGA.LCD`，带 `_BCL`/`_BCM`），但 NVIDIA 驱动默认不去驱动它。

> **实际操作**：这个开关是 [1401](https://github.com/nullmoth/1401) 应用里的一个选项（「打开背光」）。
> 勾选后它会往 boot-args 写入 `nvrmacpibl=1`，不需要手动改配置。

在 boot-args 加 `nvrmacpibl=1` 后：

```bash
ioreg -c AppleBacklightDisplay -w0 | grep -c AppleBacklightDisplay   # 3
ioreg -c NVRMBacklightHandler -w0 | grep -c NVRMBacklightHandler     # 1
```

亮度就变成**硬件背光**（不再是软件 gamma 调光）。

## 持久化：重启后记住亮度

驱动**不保存**亮度：`publishBacklight()` 里固定用 NVKMS 的初始值（100%），重启后回到最亮。macOS 原生靠 SMC 记住亮度，我们这里没有。

### 关键：三个亮度接口，行为不同

| 接口 | 现象 |
|---|---|
| `IODisplayParameters.brightness` | 写了不生效（滑块占位值） |
| `IODisplayParameters.linear-brightness` | **真正控制面板**，但滑块不动 |
| `DisplayServicesSetBrightness`（私有框架） | **面板 + 滑块一起动**（控制中心走的就是它） |

判断哪个是真的：按几下亮度键，看哪个参数跟着变。

`DisplayServices` 需要 GUI 会话（系统级 daemon 里调用会失败），`linear-brightness` 没有这个限制 —— 所以分两段：

```
daemon  brightness-early   开机(登录前)   写 linear-brightness        → 屏幕恢复
agent   brightness-watch   常驻 C 进程    写 DisplayServices           → 滑块同步
              ├─ IODisplayWrangler 1→4   → 只关显示器后唤醒          → 重新应用（持续 5 秒）
              ├─ 时钟跳变 >2 秒          → 整机睡眠恢复              → 重新应用（持续 5 秒）
              ├─ 亮度突变到 100%         → 系统重置                  → 重新应用
              └─ 用户改动                → 保存新值
```

实测：OpenCore 结束后、系统启动早期屏幕就已恢复；登录后约 1 秒滑块同步；显示器休眠唤醒后 3 秒内恢复。

完整实现见 [`tools/brightness/`](tools/brightness/README.md)。

### 落地的五个坑

1. **状态文件不能被清空** —— 安装脚本里的 `: > file` 会清零，脚本读到空值直接退出
2. **状态文件属主必须是登录用户** —— 属主为 root 时 agent 写不进去，看门狗永远读不到休眠状态
3. **`save` 不能 `RunAtLoad`** —— 登录瞬间它会抢在同步之前把状态写成当前（最亮）值
4. **`/usr/local/bin` 默认不存在** —— 安装脚本要 `mkdir -p`
5. **首版用了错的参数** —— `brightness` 是占位值，写进去读回来都对，但屏幕不动

### 唤醒后跳回最亮怎么办

看门狗用 `IODisplayWrangler` 的 `CurrentPowerState` 判断显示器状态：

```
只关显示器:  4 → 1      唤醒 1 → 4   → 检测到状态变化，重新应用
整机睡眠:    进程被挂起  唤醒后时间跳变  → 检测到"时钟跳变 >2 秒"，重新应用
进程被杀:    KeepAlive 拉起  → 脚本启动即应用一次
```

它同时区分了两种情况：**唤醒**时恢复保存值，**用户改动**时保存新值 —— 所以不会和手动调节打架。

唤醒后不是只写一次：驱动可能在几百毫秒后**再次**把面板重置成最亮（表现为"滑块对、面板最亮"），所以检测到唤醒后会**持续 5 秒、每 0.3 秒重写一次**，把后置的重置压住。

看门狗是常驻 **C** 进程（0.3 秒轮询），直接调 `DisplayServices` 和 IOKit 属性，**零 fork**，CPU 占用 < 0.1%，唤醒后 0.3 秒内恢复。

---

# 四、Wi-Fi / 蓝牙：`WTLWireless` 0.15.0（三合一）

仓库：<https://github.com/watchthelight-labs/WTLWireless>

0.15.0 起，原来三个独立项目（`mt7925-hackintosh-wifi` 的 `MtkWlan`、`-native` 的 `MtkWlanNative`、`-bluetooth` 的 `MtkBt`）合并成**一个包**：

```
WTLWireless.kext
└── Contents/PlugIns/
    ├── WTLWirelessNative.kext   原生 Wi-Fi 前端（IO80211 菜单）
    └── WTLWirelessBt.kext       蓝牙固件加载器
```

旧仓库已归档或跳转到新仓库。三个 kext **不能与旧的 `MtkWlan` / `MtkWlanNative` / `MtkBt` 共存**，升级时要把旧的三条一起删掉。

## 安装

```
1. 从 EFI/OC/Kexts 移除 MtkWlan.kext、MtkWlanNative.kext、MtkBt.kext
2. 放入 WTLWireless.kext（两个插件在 Contents/PlugIns 里，跟着主体走）
3. Kernel → Add 删掉旧三条，按顺序加三条：
     WTLWireless         ← 主体
     WTLWireless.Native  ← 插件
     WTLWireless.Bt      ← 插件
4. boot-args 保持：mtkfe=native mtknativeif=1
5. BlueToolFixup 2.7.2、LegionBtFix 0.3.0 保持不动
```

> 主体必须排在插件之前。插件依赖主体里的符号，顺序反了会加载失败。

## 验证

```bash
kmutil showloaded | grep watchthelight
# org.watchthelight.WTLWireless (0.15.0)
# org.watchthelight.WTLWireless.Native (0.15.0)
# org.watchthelight.WTLWireless.Bt (0.15.0)

ioreg -r -c WTLWireless -l -w0 | grep -E '"MtkState"|"MtkFrontEndActive"|"MtkCountry"|"MtkChipName"'
# MtkState = "W6 pass: en1 passing traffic"
# MtkFrontEndActive = "native"
# MtkChipName = "MT7925"
```

`MtkScan` 是驱动自己的扫描缓存，一行一个网络：`SSID/信道/RSSI/加密`，末尾带 `!` 表示**不可加入**（比如企业级 `wpa2!`）。

## 版本与 ABI

原生前端靠 `MtkNativeAbi` 做**白名单硬匹配**：`MtkNativeAbi` 里的 `Builds` 列出它认的系统构建，不匹配就拒绝加载（回退成以太网前端 `en1`，菜单消失）。

本机 26.7.3（25G342）不在白名单里（只有 25G241 / 25G332 / 25G416），驱动会**回退到不高于当前系统的最新白名单构建 25G332** —— 实测照样能联网，只是这种跨版本组合官方没承诺。

### 0.15.0 是什么（2026-11-12）

- 把原来三个独立仓库（`mt7925-hackintosh-wifi` 的 `MtkWlan`、`-native` 的 `MtkWlanNative`、`-bluetooth` 的 `MtkBt`）合并成**一个包**：主体 `WTLWireless.kext` + 两个插件 `Contents/PlugIns/WTLWirelessNative.kext`、`WTLWirelessBt.kext`
- 驱动条目必须**主体在前、插件在后**，且新旧不能共存（`MtkWlan*` / `MtkBt` 必须先删干净）
- 芯片表扩展到 **MT7927**；`setCOUNTRY_CODE` 从 0.4.13 起真正下发（用 `ioreg -c WTLWireless -l | grep MtkCountry` 看）
- 装完的标志：`WTLWireless` / `.Native` / `.Bt` 三个都显示 `0.15.0`，`MtkState = "W6 pass: en1 passing traffic"`，`MtkFrontEndActive = native`

### 怎么知道有没有新版

`github.com` 经常连不上，用 API 查最新 tag：

```bash
T=ghp_xxx   # 有 rate limit，带个 token 更稳
for r in watchthelight-labs/WTLWireless watchthelight-labs/WTLLegionBtFix \
         acidanthera/BrcmPatchRAM nullmoth/nvidia-macos-driver; do
  printf '%-40s ' "$r"
  curl -s -H "Authorization: token $T" "https://api.github.com/repos/$r/releases/latest" \
    | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tag_name"),d.get("published_at","")[:10])'
done
```

截至 2026-11-26 的最新版：`WTLWireless 0.15.0` / `WTLLegionBtFix 0.3.0` / `BrcmPatchRAM 2.7.2` / NVIDIA 驱动 `3.1` —— 本机都已是这个版本。升级网卡驱动的活脚本在 `tools/wtl-upgrade/install.sh`（备份 config、逐二进制校验 SHA-256、失败回滚、生成 `rollback.sh`）。

## 已知缺口

| 缺口 | 表现 |
|---|---|
| WPA3-SAE / 企业级 802.1X | `MtkScan` 里标 `!`，点了也连不上 |
| AWDL | 没有 `awdl0`，AirDrop / 连续互通 / 隔空播放都不可用 |
| 区域码 | `setCOUNTRY_CODE` 只记录不执行，DFS 频道只能被动扫描 |
| **iPhone 5 GHz 热点** | 驱动缓存里有、标着可加入，但 airportd 拿不到，见下 |

## iPhone 热点：只有 2.4 GHz 能用

实测（2026-11，WTLWireless 0.15.0 / macOS 26.7.3）：

| 热点 | 驱动缓存 `MtkScan` | `networksetup` 返回 | 结果 |
|---|---|---|---|
| iPhone 5 GHz（ch44） | `iPhone 12 mini/44/-33/wpa2`（无 `!`） | `Could not find network` | macOS 看不见 |
| iPhone 2.4 GHz（ch6） | `iPhone 12 mini/6/-31/wpa2` | 加入成功 | `172.20.10.2`，能上网 |
| 安卓 5 GHz 热点（ch149） | 有 | 加入成功 | 正常 |

也就是说：**安卓的 5 GHz 热点能用，iPhone 的 5 GHz 热点不能**；iPhone 打开「最大化兼容性」降到 2.4 GHz 后就稳定了。

菜单里那条同名条目是「连续互通热点」（Instant Hotspot），走 AWDL，本来就用不了，要走命令行：

```bash
networksetup -setairportnetwork en1 "iPhone 12 mini" "密码"
```

封装好的脚本见 [`tools/wifi/wifi-join.sh`](tools/wifi/wifi-join.sh)（`list` / `status` / `join` / `forget`，连不上时会打印手机热点的三条对策）。

---

# 五、蓝牙：三件套 + 两个 NVRAM 键

加载器：<https://github.com/watchthelight-labs/WTLWireless>（蓝牙是包里的 `WTLWireless.Bt` 插件）
补丁：<https://github.com/watchthelight-labs/WTLLegionBtFix>（`LegionBtFix` 0.3.0，仓库已改名）

> `LegionBtFix` 0.2.0 用 SHA-1 校验 `bluetoothd` 的页面，**只对 26.7.1（25G241）有效**；
> 0.3.0 改成按指令窗口特征匹配，25G241 / 25G332 都能匹配（26.7.3 上实测正常）。升级系统后必须同步升级，否则 `bluetoothd` 会反复 SIGABRT 崩溃。

## 一个被推翻的误判

我们一开始以为"蓝牙设备的 USB 设备级 class 是 `0xEF`（复合设备），Apple 的传输层只认 `0xE0`，所以不可能支持"——**这个结论是错的**。

实际上 macOS 的蓝牙**不走内核传输层**，而是 `bluetoothd` 在用户态直接驱动这个 USB 设备。那个 `BCM_4350C2 / Transport: UART` 只是"还没接管"时的占位符。

## 真正缺的是两个 NVRAM 键

BlueToolFixup 2.7.0 起，`bluetoothd` 要求：

```
bluetoothExternalDongleFailed   = <00>                              1 字节
bluetoothInternalControllerInfo = <0000000000000000000000000000>   14 字节（不能多不能少）
```

**16 字节会让 `bluetoothd` 报 `CFDataGetLength != 14` 并退回 UART 占位符。**

## 三件套

| kext | 作用 |
|---|---|
| `BlueToolFixup` 2.7.2 | 让 `bluetoothd` 接受第三方控制器 |
| `WTLWireless.Bt` 0.15.0 | 给 MT7925 灌蓝牙固件（原 `MtkBt`；0.15.0 起并进 WTLWireless 包，支持 `0E8D:8C38`） |
| `LegionBtFix` 0.3.0 | 修 `bluetoothd` 的 LE 连接崩溃（按指令窗口匹配，不再锁单个系统构建） |

`LegionBtFix` 名字带 Legion 但不是联想专用：它补的是苹果 `bluetoothd` 的机器码（按页面哈希匹配），与笔记本品牌无关。

成功标志：

```
MtkBtState = ready
MtkBtSectionsSent = 3
MtkBtBytesSent = 447872
State: On, Chipset: THIRD_PARTY_DONGLE
```

---

# 六、音频：macOS 26 移除了 AppleHDA

## 病因

从 **Tahoe Beta 2 起，苹果删掉了 `AppleHDA.kext`**（所有支持 26 的 Mac 都有 T2 芯片，苹果认为不需要了）。

`AppleALC` 的补丁对象就是 AppleHDA —— 没有它，ALC245 自然没声音。

```
$ ls /System/Library/Extensions/AppleHDA.kext
不存在
$ kextstat | grep -i hda
（只有 AppleUSBAudio）
```

## 方案：SimpleHDA（OpenCore 注入，不碰系统分区）

项目：<https://github.com/laobamac/SimpleHDA>

另一条路是把 AppleHDA 重新装回 `/S/L/E`，但那会破坏系统卷密封、需要关 SIP，每次系统更新都可能失效。

**SimpleHDA 用 OpenCore 注入原版 AppleHDA 载荷**，系统分区不动。

> **后来的变化**：驱动 2.7 起，NullMoth 自己也带了一个 Tahoe 音频驱动（`NMXAudio.kext`），
> 实测它接管了 ALC245 的模拟输出（`system_profiler SPAudioDataType` 里 Manufacturer 是 `NullMoth`），
> SimpleHDA + AppleALC 仍然加载着、也能用。两套同时在，默认输出走 `Realtek ALC245 (Analog)`。

## 安装

```
1. SimpleHDA.kext 放进 EFI/OC/Kexts/
2. Kernel → Add 顺序：Lilu → AppleALC → SimpleHDA
3. DeviceProperties 加：
   PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x6) → layout-id = 11
4. boot-args 需要 keepsyms=1（本来就有）
```

要求：Lilu ≥ 1.7.1、AppleALC、有效的 `layout-id`。

## ALC245 的 layout

AppleALC 1.9.9 里 ALC245 只有 layout **11 / 12 / 13**：

- 11：能用（输出正常，引脚命名不完整）
- 12 / 13：在 macOS 15 上会破坏输出

---

# 七、电池 / 充电状态

HP 的 DSDT 里 `_PSR` 读的是一个永远不置位的 EC 字段（`R400`），所以要自己算。

## SSDT-AC

从 EC 的 `R830` bit15 推导交流电状态，并接管 `_Q20` 通知。

## ACPI 重命名

```
ACPI → Patch:
  _PSR → XPSR   （requires SSDT-AC.aml）
  _Q20 → XQ20   （requires SSDT-AC.aml）
ACPI → Add:
  SSDT-AC.aml
```

验证：

```bash
pmset -g batt
# Now drawing from 'AC Power'
# -InternalBattery-0  77%; charging; 0:31 remaining present: true
```

> **macOS 26 上的表现和 15 有差异：**
>
> - ✅ **充电状态实时更新**：插拔充电器后，电量与充电状态立刻变化（15 上有约 60 秒轮询延迟）
> - ⚠️ 但"**已连接电源适配器**"这个状态指示不再显示 —— `ioreg` 里 `ExternalConnected` 仍然是 `Yes`，只是系统 UI 不呈现
>
> 这是 26 上 `AppleSmartBattery` 行为变化带来的副作用，不影响实际充电。

---

# 八、Windows 双系统引导

## 原理

```
固件 → EFI/Microsoft/Boot/bootmgfw.efi   （被替换成 OpenCore 引导器，24576 字节）
     → OpenCore 菜单
     → Select Windows 时按 BlessOverride 跳到 bootmgfw-orig.efi（原版引导器，3086680 字节）
```

## 步骤

1. 把原版 `bootmgfw.efi` 备份成 `bootmgfw-orig.efi`
2. 用 OpenCore 的 `BOOTx64.efi`（24576 字节）替换 `bootmgfw.efi`
3. `config.plist → Misc → BlessOverride` 加一条：

```
\EFI\Microsoft\Boot\bootmgfw-orig.efi
```

## Ubuntu：不要用 GRUB，让 OpenCore 自己起内核

装 Ubuntu 之后会出现两个问题，其实同一个根因：

1. macOS 进不去了（卡 `Halting on critical error`）；
2. OC 里选 Ubuntu 还要过一道 GRUB 菜单，图标也不对。

**根因**：Ubuntu 安装器会把 `EFI/Boot/bootx64.efi` 换成自己的 shim（966,768 字节，和 `EFI/ubuntu/shimx64.efi` 一模一样），固件于是走 shim→GRUB，OpenCore 根本没被加载；而 macOS 的 `boot.efi` 由 GRUB 拉起时，`boot\System\Library\KernelCollections\...` 这个只有 OC 才有的卷前缀就不成立，于是 `LD.LKC|R.2` 之后直接 `Halting on critical error`。

**做法**（`UEFI → Drivers` 两条，顺序在前）：

```
Ext4Dxe.efi        40960 B   ← 读 ext4
OpenLinuxBoot.efi  69632 B   ← 直接发现内核 + initrd
```

然后删掉手工的 `Misc → Entries`（指向 `\EFI\ubuntu\grubx64.efi` 的那条），OC 就会自己扫出 Linux 内核。想改条目名和图标，在 **ext4 根**写 BLSpec：

```bash
# Ubuntu 里执行（/boot 在 ext4 根上）
sudo mkdir -p /loader/entries
cat <<EOF | sudo tee /loader/entries/ubuntu.conf
title Ubuntu
version 7.0.0-44-generic
linux /boot/vmlinuz-7.0.0-44-generic
initrd /boot/initrd.img-7.0.0-44-generic
options root=PARTUUID=<你的 root 分区 PARTUUID> ro quiet splash
EOF

sudo cp /boot/efi/EFI/OC/Resources/image/Acidanthera/GoldenGate/Ubuntu.icns /.VolumeIcon.icns
echo Ubuntu | sudo tee /.contentFlavour
```

四个坑：

- **驱动条目要克隆完整字段**：手写 `Path/Enabled/LoadEarly/Arguments` 会被 `ocvalidate` 判 `Missing key Comment` / `HideVerbose`，`Serialisation returns 5 errors`；
- **`RequestBootVarRouting` 在 1.0.8 里不存在**，写进 `Misc → Boot` 或 `Misc → Security` 都报 `No schema for ...`；
- **BLSpec 只能放 ext4 根，不能放 ESP**：放 ESP 上 OC 会先读它、再去 ext4 找内核，日志里是 `LNX: /boot/vmlinuz-... not found`，条目必废；
- **别动 `PickerAttributes` 的 `USE_VOLUME_ICON` 位**：macOS 条目的图标唯一来源就是 Preboot 里的 `.VolumeIcon.icns`，去掉这一位 macOS 图标会变回通用图标。

还有一个容易误判的现象：在 Ubuntu 里**改过刷新率**之后 warm reboot，macOS 会卡 Logo 或直接 `Halting on critical error`；不改刷新率、或者改完**关机**（ACPI S5 真断电）就没问题。刷新率是 GPU/面板的运行时状态，不落盘，warm reset 不会复位它。

## 两个坑

- **`Misc → Entries` 只接受 UEFI 设备路径**，写文件路径会报"路径无效"。文件路径要用 `BlessOverride`。
- 如果复制的 EFI 里 `BlessOverride` 是空的，Windows 就进不去（表现为 OC 菜单里没有 Windows 条目）。

---

# 九、两个通用 OpenCore 坑（这两个坑让我们浪费了很多时间）

## ① `NVRAM → Add` 不会覆盖已存在的变量

OpenCore 日志里会这样写：

```
OCVAR: Setting NVRAM 7C436110-...:boot-args - ignored, exists
```

**只写不存在的键。** 所以想让配置里的 `boot-args` 生效，必须在 `NVRAM → Delete` 里同时登记这个键：

```xml
<key>NVRAM</key>
<dict>
  <key>Add</key>    <dict> ... boot-args = "-v ... 你的参数" ... </dict>
  <key>Delete</key> <dict> ... <array><string>boot-args</string></array> ... </dict>
</dict>
```

否则内核拿到的永远是 NVRAM 里残留的旧值 —— 我们就是这样"明明改了配置却没生效"查了半天。

## ② `MinKernel` / `MaxKernel` 用的是 Darwin 内核版本，不是 macOS 版本

| macOS | Darwin |
|---|---|
| 15 Sequoia | 24.x |
| **26 Tahoe** | **25.x** |

所以限制"只在 macOS 26 加载"要写 `MinKernel = 25.0.0`，写 `26.0.0` 永远不会匹配。

---

# 十、内置麦克风：自研 ACP6x PDM 驱动（kext + HAL 插件）

> 代码与详细设计在独立仓库：<https://github.com/Game-5040/acp6x-pdm-macos>
> 这一节只记结论、关键数据和踩过的坑。

## 现象：麦克风不在声卡上

- 录音只有底噪、说话没声；录音时扬声器跟着波形响（那是把输出当成了输入）
- Windows 下正常
- ALC245 的输入节点在 macOS 里存在，但实测 peak = **0.000275**（就是噪声）

三条证据说明它挂在 AMD ACP6x 上，不在 Realtek codec 上：

1. **BIOS 没给 codec 配 DMIC**：AppleALC 的 layout 11/12/13 都不写 `ConfigData`，读到 `0x12 = 0x411111f0`（未连接）就是 BIOS 默认值；有 DMIC 的机器是 `0x90a60130`。
2. **DSDT 里有 AMD ACP**：`Device (ACP) { _HID "AMDI0063" }`，另有 `HID0`（`AMDI0063`，`_CRS` 给 `0xFEC13000/0x200`）。
3. **Windows 设备管理器**：麦克风挂在 **AMD Audio CoProcessor** 下。

## 为什么没有现成驱动

- [`AMDMicrophone`](https://github.com/qhuyduong/AMDMicrophone) 只支持 Renoir（ACP3x），代码里 `if (revisionId == 0x1)`，我们的 ACP 是 **`0x62`**，直接 `return NULL`
- 搜遍 15 个 fork，没有一个扩展到新平台
- [`acp6x-omen-dkms`](https://github.com/NevetScar/acp6x-omen-dkms) 是同款机器的 **Linux** 补丁（board `8F06`），macOS 加载不了 —— 但它是蓝本

## 先证明硬件能录（Phase 0）

在 Ubuntu 里装那个 DKMS 补丁，`arecord` 立刻能录到人声（开头有一声爆破音）。这一步很重要：**在写任何 macOS 代码之前，先确认"硬件 + 时钟 + 供电"这条链是通的**。

顺手纠正一个此前的误判：`acp6x_chip_offset_byte.h` 里的 `0x1242C04` 是**绝对地址**，Linux 的 `acp6x_readl(base + REG)` 会减掉 `ACP6x_PHY_BASE_ADDRESS (0x1240000)`，所以真实访问是 **BAR0 + 0x2C04**。256 KB 的 BAR 完全够用，之前"寄存器在 18 MB 外"的结论是读错了头文件。

## 探针：先只读，别写

`probe/ACPProbe.kext` 是分级只读探针（`stage 0` 只读 PCI 配置空间，`stage 1/2` 才碰 MMIO）。本机结果：

```
stage 0: revision=0x62  vendor=0x1022 device=0x15e2
         classcode=0x048000  barPhys=0xFC980000  barLen=0x40000
stage 1: pinConfig=4      pgfsmStatus=0
stage 2: PDM_CLKDIV=192   WOV_CLK_CTRL=1   DECIMATION=2
         NO_OF_CHANNELS=1 MISC_CTRL=0      PDM_ENABLE=0   DMA_ENABLE=0
         RINGBUFADDR/SIZE/WATERMARK=0  ATU_BASE/PAGE=0  SCRATCH_REG_0=0x427C00C3
```

两个结论：

- `pinConfig = 4` **不在** Linux 的 `ACP_CONFIG_{0,1,2,3,9,15}` 白名单里 → BIOS 已经把 ACP 配成 PDM/DMIC 模式，不需要我们改引脚；
- `pgfsmStatus = 0` = `ACP_POWERED_ON` → **ACP 已经上电，不需要任何电源序列**（Linux 那套 `acp_init()` 全砍）。

## 三道坎（都是"报错信息骗人"）

1. **`_kmod_info`**：没有 Xcode，`ld -kext` 不生成这个符号，OC 只报 `Prelinked injection ... - Invalid Parameter`（真实原因是 `Kext->Context.VirtualKmod == 0` → `EFI_UNSUPPORTED`，被上层折成了 `EFI_INVALID_PARAMETER`）。解法是按 `KMOD_INFO_64_V1` 的 196 字节布局手写一个：`pragma pack(4)`、`info_version=1`、`id=0xffffffff`、`name[64]`、`version[64]`、`reference_count=-1`、`start/stop` 指向桩函数；**源码里的变量名必须写 `kmod_info`**（写 `_kmod_info` 会变成 `__kmod_info`）。
2. **Info.plist 依赖**：缺 `com.apple.iokit.IOPCIFamily` 和 `com.apple.kpi.unsupported`（或 `kpi.*` 版本写成 `8.0.0`）时，OC 报的是**同一条** `Invalid Parameter`。最后是拿一个能正常注入的 kext 的 plist 当模板才拆开。
3. **`start()` 里写硬件 = 断电**：把 PTE 表写进 `start()`，开机在进度条处直接黑屏断电，**没有 panic 文件**（AMD 平台上是机器检查，不是软件崩溃）。最终 `start()` 只做 `IOService::start` + 取 BAR 长度 + `registerService()`，所有寄存器写入都由用户态方法触发。

## DMA 与采样

- 环 32 KB、周期 8 KB、4 MB 连续缓冲；PTE 表写在 `ACP_SCRATCH_REG_0`（`ATU_BASE_ADDR_GRP_1 = 0x03800000 | BIT(31)`、页大小 4 KB、每页 8 字节 low/high）
- **`ACP_WOV_PDM_NO_OF_CHANNELS` 要写 `0`（TWO_CH）**，`DECIMATION_FACTOR = 2`；本机固件留的是 `1`，于是硬件按 4×32bit 出帧（后两路恒 `0x80000000`）
- 使能前先 `FIFO_FLUSH` + 20 ms，再丢前 200 ms 样本，爆音就没了
- 数据是 **S32_LE / 2ch / 48 kHz**，但带巨大直流偏置（左 -0.138、右 -0.424 FS），必须高通；相邻样本差比绝对值平滑得多，说明确实是 32-bit 而不是 16/24-bit

## 用户态 DSP（HAL 插件）

`ACPMicPlugin.driver` 是 input-only 的 `AudioServerPlugIn`：2 通道 / 48 kHz / float32，按 `writeBytes` 增量从 4 MB 环取数。链路：

```
90/180 Hz 二阶高通 → 一阶 DC 阻断 → 3.5 kHz presence(+7 dB)
→ 语音包络 AGC(目标 0.10) → 门限(开门 2.5×、关门 1.4×、hangover 320 ms)
→ tanh 软限幅 → 音量
```

几个必须记住的坑：

- **一阶高通的 `1/(1-R)` 是 2000 倍**：把原始 `x` 存进上一级的历史变量，稳态会变成 `-2000 × 直流`，语音被整个压没（表现是"录不到音"，但 kext 的 `writeBytes` 在涨）；
- **逐块 AGC 会模糊**：音节之间反复上下，听感是"闷、不清楚"；改成语音包络（快的跟、慢的落）之后就干净了；
- **句尾被切是门限关门太快**：加迟滞 + 320 ms hangover；
- **硬件时钟**：`GetZeroTimeStamp` 必须用 kext 的 `writeBytes` 做 discipline，否则纯主机时钟与 PDM 时钟漂移，最后每个 IO 周期都 `kIOReturnIsoTooOld`。

实测（10 秒）：说话 **-18.7 dBFS**、静音 **-45.0 dBFS**、SNR **26.3 dB**、峰值 -5.0 dBFS、无削波。

## Siri 的门槛：一个叫 `'imic'` 的数据源

麦克风在系统里能录、浏览器能用、听写能用，但 Siri 一直显示"连接麦克风"。查 TCC 是白费：`corespeechd` 自带 `com.apple.private.tcc.allow`，日志里是 `Auth:Allowed (Entitled)`。

真正的原因写在 [LatSOFAudio](https://github.com/shubhambanekar/LatSOFAudio) 的 `ARCHITECTURE.md`「Siri's microphone gate」里：

- `+[AVVCAudioDeviceManager IsDeviceBuiltIn:]` 只在 transport 是 `'bltn'` **且输入作用域的 `kAudioDevicePropertyDataSources`（`'ssc#'`）第一项是 `'imic'`** 时返回真；
- CoreSpeech 按 transport 分类路由，`'bltn'` 设备必须报 `'imic'`/`'emic'`，否则路由为 nil —— 即使录音路径完全正常；
- `'usb '`、`'blue'`、`'line'` 不做这个检查（所以 USB/蓝牙麦一直能用）。

关键实现细节：**不能直接给设备回 `'ssc#'`**。coreaudiod 是从设备的 `kAudioObjectPropertyControlList` 里找 `'dsrc'`（`kAudioDataSourceControlClassID`）控件**合成**这两个属性的，直接答设备属性会一直返回 `'who?'`（`kAudioHardwareUnknownPropertyError` = 2003332927）。所以必须新增一个控件对象：

```
kObjectID_DataSource_Input = 6
  BaseClass     = 'slct'   (selector control)
  Class         = 'dsrc'   (data source)
  AvailableItems= ['imic']
  CurrentItem   = 'imic'
  ItemKind      = 'dsrc'
```

并且把设备的 `ControlList` 从 2 项改成 3 项（`ACPMic_ControlDataSize` 里那个 `2 * sizeof(AudioObjectID)` 也要改，只改 getter 不改 size 会出现 `size=8` 却返回 3 个）。改完之后 `DataSource('ssrc')` 返回 `'imic'`、`DataSources('ssc#')` 返回 1 项，**Siri 就认了**。

## 安装

```bash
# 1) kext（需要先在 config.plist 的 Kernel → Add 里加一条）
cd capture && ./build.sh
sudo ../tools/install-capture.sh install     # 备份 config、逐文件校验、ocvalidate，失败自动回滚
# 重启

# 2) HAL 插件（不需要重启）
cd ../plugin && ./build.sh
sudo ./install.sh                            # 拷到 /Library/Audio/Plug-Ins/HAL/ 并重启 coreaudiod
```

验证：

```bash
ioreg -rc ACPCapture -l | grep -E 'writeBytes|dmaEnable|ticks'
# 应该看到 writeBytes 在涨、dmaEnable=3、ticks 在涨；不动就说明 DMA 没起来

system_profiler SPAudioDataType | grep -A3 "AMD ACP PDM"
# 应该出现 AMD ACP PDM Microphone（2 通道 / 48000）

sudo ./tools/acpcap/acpcap 5 /tmp/test.wav   # 直接录 5 秒
```

---

# 十一、未解决：睡眠

- 固件 FADT 只声明 **Modern Standby**（`LOW_POWER_S0_IDLE_CAPABLE = 1`），没有 S3
- `pmset -g log` 显示 `Sleep/Wakes since boot = 0`
- BIOS 里没有 S3 选项

macOS 需要传统 S3 才能睡眠，无解。

---

# 十二、最终配置参考

## boot-args

```
-amfipassbeta -vi2c-force-polling revpatch=sbvmm,cpuname nvfb=1 nvaccel=1 nvfbheads=4
-nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 gfxrst=4
mtkfe=native mtknativeif=1 nvrmacpibl=1 revcpu=1 nvfbhidpi=1
```

| 参数 | 作用 |
|---|---|
| `nvfb=1 nvaccel=1 nvfbheads=4` | NullMoth 显卡帧缓冲/加速 |
| `nvrmacpibl=1` | **硬件背光** |
| `gfxrst=4` | 关闭 WhateverGreen 的启动画面拷贝（防登录时 panic） |
| `amfi=0x80` | 关闭 AMFI（加载未签名 kext） |
| `mtkfe=native mtknativeif=1` | MediaTek Wi-Fi 走原生前端 |
| `revpatch=sbvmm,cpuname` + `revcpu=1` | RestrictEvents：自定义 CPU 名称（见第十七节） |
| `nvfbhidpi=1` | HiDPI「看起来像」尺寸（见第十八节） |

> 跑码用的 `-v debug=0x100 keepsyms=1` 平时**不用**开。用 [`tools/boot-verbose/boot-verbose.sh`](tools/boot-verbose/boot-verbose.sh) 一句话开关：
> `./boot-verbose.sh on|off|status|persist`，其中 `persist` 会把当前值写进 config 并从 `NVRAM → Delete` 移除。

## kext（35 条，按加载顺序）

```
Lilu → AMFIPass → AppleMCEReporterDisabler → BrightnessKeys → ECEnabler
→ NVMeFix → RealtekRTL8111 → RestrictEvents → VirtualSMC → SMCBatteryManager
→ SMCLightSensor → USBToolBox → UTBDefault → VoodooI2C(+PlugIns) → VoodooI2CHID
→ VoodooPS2Controller(+PlugIns) → WhateverGreen → NVRM → NVRMFB → NVRMAGDC
→ NVAccel → WTLWireless → WTLWireless.Native → WTLWireless.Bt
→ BlueToolFixup → LegionBtFix → AppleALC → SimpleHDA
```

## ACPI

```
Add:    SSDT-EC.aml, SSDT-PLUG-ALT.aml, SSDT-USB-Reset.aml, SSDT-USBX.aml,
        SSDT-XOSI.aml, SSDT-AC.aml
Patch:  _OSI → XOSI, _PSR → XPSR, _Q20 → XQ20
```

## NVRAM（7C436110-AB2A-4BBB-A880-FE41995C9F82）

```
boot-args                          见上
bluetoothExternalDongleFailed      <00>
bluetoothInternalControllerInfo    <0000000000000000000000000000>
4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:revcpuname
                                   "AMD Ryzen 9 9955HX 16-Core Processor"
```

## 引导：把 1401 的 DEBUG 构建换成官方 RELEASE

1401 生成的 EFI 里，`OpenCore.efi` 是 **DEBUG 构建**（`872,448` 字节，版本串 `DBG-109-2026-10-19`）。它会在读 config **之前**先往屏幕上打十几行 `OC:` 横幅：

```
OC: Starting OpenCore...
OC: Loaded configuration of 62798 bytes
OCS: Missing key Base, context <Patch>!
OC: Watchdog status is 0
```

这些行来自 OpenCore 自己的初始化代码，**config 里的 `Misc → Debug → Target` 管不到**（`Target` 要等日志系统初始化后才生效，那已经是第 15 行之后的事了）。想彻底去掉只有换 RELEASE 构建：

```
1. 下载 OpenCore-1.0.8-RELEASE.zip，取 X64/EFI/OC/OpenCore.efi（626,688 字节）
2. 同版本的 BOOTx64.efi / OpenRuntime.efi / OpenCanopy.efi / ResetNvramEntry.efi 一起换
   （版本不一致会被拒载，这一组要整组换）
3. 换之前跑一遍 ocvalidate，把 config 修干净
```

`Misc → Debug → Target` 的位含义（顺带记一下）：

| 位 | 去哪 |
|---|---|
| `0x01` | 日志文件 |
| `0x02` | **屏幕 console** |
| `0x04` | DataHub |
| `0x08` | 串口 |
| `0x40` | 文件（非易失） |

本机用 `65`（`0x41` = 文件 + 日志，关掉屏幕）。换成 RELEASE 后，`opencore-*.txt` 里只剩下 boot.efi 自己写的 `AAPL:` 行。

整套替换脚本见 [`tools/oc-release-swap/install.sh`](tools/oc-release-swap/install.sh)（会先备份整个 `EFI` 再动手，并生成 `rollback.sh`）。

---

# 十三、踩坑清单（速查）

| 症状 | 原因 | 解决 |
|---|---|---|
| 软件更新"未能准备更新" | 显卡驱动没 park、GPU BAR 太大 | 1401 的「Prepare this Mac for Tahoe」 |
| 安装卡在"不到一分钟" | 同上 | 同上 |
| 26 有鼠标没画面 | NVIDIA 驱动没进内核集合 | 内核集合必须在 26 内部构建（见第二节） |
| 改配置里的 boot-args 不生效 | NVRAM Add 不覆盖已有值 | 同时在 `NVRAM → Delete` 登记 |
| kext 加了却不在 26 上加载 | `MinKernel` 写成了 26.x | 用 Darwin 版本 25.0.0 |
| Wi-Fi 只有 `en1` 以太网 | 缺 `mtkfe=native mtknativeif=1` | 加 boot-args |
| 蓝牙 5 秒后自动关 | 缺两个 NVRAM 键 / 缺 LegionBtFix | 见第五节 |
| OC 菜单里没有 Windows | `BlessOverride` 为空 | 加 `\EFI\Microsoft\Boot\bootmgfw-orig.efi` |
| `Misc → Entries` 报路径无效 | Entries 只收 UEFI 设备路径 | 改用 `BlessOverride` |
| 26 上没声音 | AppleHDA 被移除 | SimpleHDA + AppleALC + layout 11 |
| 麦克风只有噪音 | 麦克风在 AMD ACP6x 上，不在 ALC245 codec | 自研 ACP6x PDM 驱动（见第十节） |
| Ubuntu 装完后 macOS 卡在 `Halting on critical error` | `EFI/Boot/bootx64.efi` 被 Ubuntu 的 shim 覆盖，`boot.efi` 由 GRUB 拉起 | 把 `bootx64.efi` 换回 OC（24,576 B），并用 `OpenLinuxBoot` 直启 |
| OC 报 `Prelinked injection ... - Invalid Parameter` | ① kext 缺 `_kmod_info`；② `Info.plist` 缺 `com.apple.iokit.IOPCIFamily` / `com.apple.kpi.unsupported` | 手写 `_kmod_info`；依赖抄能正常注入的 kext |
| 装了自己的 kext 后开机直接断电（无 panic） | `start()` 里写 ACP 寄存器 / 写 PTE 表，ACP 未就绪时触发机器检查 | 硬件动作全部挪到用户态方法里触发 |
| OpenLinuxBoot 条目报 `LNX: ... not found` | BLSpec `.conf` 被放到了 ESP 上 | 只放 ext4 根（`/loader/entries/`） |
| Siri 显示"连接麦克风"，但录音/听写都正常 | Siri 只认 transport `'bltn'` 且数据源为 `'imic'` 的设备 | HAL 插件必须提供 `'dsrc'` 数据源控件（见第十节） |
| 处理器名称显示 `16-Core Intel Xeon W` 或 `Unknown` | 名字来自 Apple 的 SMBIOS 131 号表（无 AMD 条目） | 用 RestrictEvents：`revpatch=…,cpuname` + `revcpu=1` + NVRAM `revcpuname`（见第十七节） |
| 重启后亮度不恢复（面板总是最亮） | 驱动不保存亮度；且 `brightness` 参数写了不生效，真正生效的是 `linear-brightness` | 读写 `linear-brightness` + 两个 LaunchDaemon（见第三节「持久化」） |
| OC 菜单突然多出 Recovery / `1401:` 工具条目 | 1401 写配置时重置了 `HideAuxiliary`（且它会新装两个工具，默认非辅助） | `HideAuxiliary = true`，并把工具条目的 `Auxiliary` 设为 `true` |
| Wi-Fi 保存过的网络连不上（一直转圈后失败） | 旧的保存状态（密码/PMK/私有 MAC）与当前驱动不符 | 系统设置里**忘记此网络**后重新连接；必要时关闭「私有 Wi-Fi 地址」 |
| 蓝牙连一会儿自己关闭又打开 | 固件加载器 0.2.2 的重置循环 bug（bluetoothd 反复 SIGBUS 崩溃） | 升到 **0.2.4+**（0.2.3 修自动关闭、0.2.4 修重置循环；0.15.0 起并进 `WTLWireless.Bt`） |
| iPhone 个人热点在 Wi-Fi 菜单里点了没反应 / 报找不到网络 | 菜单那条是**连续互通热点**（Instant Hotspot），走 AWDL；而且 iPhone 的 **5 GHz** 热点驱动看不见（缓存里有、标可加入，airportd 仍报 `Could not find network`） | iPhone 打开「最大化兼容性」降到 2.4 GHz，再用「其他…」或 `networksetup -setairportnetwork en1 "iPhone 12 mini" "密码"`；脚本见 [`tools/wifi/wifi-join.sh`](tools/wifi/wifi-join.sh) |
| Wi-Fi 扫描很慢 / 部分网络看不到 | `setCOUNTRY_CODE` 被驱动"只记录不执行"，区域码停在 `XZ`，DFS 频道只能被动扫描 | 路由器 5GHz 固定到 36–48 或 149–161（避开 52–144） |
| 升级系统后 Wi-Fi 没菜单、蓝牙反复崩 | 前端 ABI 白名单没匹配当前构建；`LegionBtFix` 版本也没跟上 | 换 `WTLWireless` 0.15.0（三条 kext，主体在插件前）+ `LegionBtFix` 0.3.0 |
| 「显示器」里除了默认尺寸都很模糊 | 那些是 1× 缩放；HiDPI 需要整倍 2× 光栅 | 选不带宽「（低分辨率）」的条目，或装 BetterDisplay |
| 加了 `nvfbhidpi=1` 但没效果 | OpenCore 只写不存在的键，boot-args 被旧值占着 | 把 `boot-args` 加进 `NVRAM → Delete`，或用 `sudo nvram boot-args=...` |
| 关机变重启 | 已排除 WOL / USB 唤醒 / PMEE / RTC；**拔掉外接 USB 设备即可正常关机** | 待查（USB 设备在 S5 的远程唤醒）；驱动 2.9 修了 #488，待复测 |
| 开机前固定十几行 `OC:` 横幅，改 `Target` 无效 | 1401 的 `OpenCore.efi` 是 DEBUG 构建，横幅在日志系统初始化之前打印 | 换官方 1.0.8 RELEASE（见第十二节） |
| `Target` 改了屏幕还在打日志 | `0x02` 位才是屏幕输出；只改日志级别、或者改的是文件位都没用 | `Target = 65`（`0x41`：文件 + 日志，屏幕关） |
| `ocvalidate` 报 `Missing key Base, context <Patch>!` | `ACPI → Patch` 条目缺 `Base` / `BaseSkip` | 补两个键（值为空串 / 0） |
| `ocvalidate` 报注释含非法字符 | `Kernel → Add` 的 `Comment` 里有中文 | 注释改 ASCII，`ocvalidate` 要求 `No issues found` 再重启 |
| 默认图标样式下部分系统图标有残影 | 玻璃质感图标的图层/图集渲染错位；3.1 仍未修（不是 #363） | 图标与小组件样式切「透明」可绕过 |
| `Reset NVRAM` / `Recovery` 从菜单**彻底消失**，按空格也不出现 | 停用了 `ResetNvramEntry.efi` 驱动（这是彻底移除），而不是设 `HideAuxiliary` | 驱动改回 `Enabled=true`，用 `HideAuxiliary=true` 隐藏（按空格可见） |
| 1401 做 USB 映射后只剩一个 USB-A 能用 | 它用类名（`AppleUSB20XHCIPort`）当端口键，同控制器第二个端口被覆盖 | 手工改成 `HS01/SS01/HS02/SS02` 并补全端口（见第十五节） |

---

# 十四、参考项目

| 项目 | 用途 |
|---|---|
| [nullmoth/1401](https://github.com/nullmoth/1401) | NVIDIA 黑苹果一键工具（含 Tahoe 升级准备） |
| [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver) | NVIDIA Metal 驱动 |
| [watchthelight-labs/WTLWireless](https://github.com/watchthelight-labs/WTLWireless) | MT7925 Wi-Fi 驱动 + 原生菜单 + 蓝牙固件（0.15.0 三合一） |
| [watchthelight-labs/WTLLegionBtFix](https://github.com/watchthelight-labs/WTLLegionBtFix) | bluetoothd 补丁（0.3.0，按指令窗口匹配） |
| [laobamac/SimpleHDA](https://github.com/laobamac/SimpleHDA) | 在 Tahoe 上恢复 AppleHDA |
| [acidanthera/AppleALC](https://github.com/acidanthera/AppleALC) | 音频 layout |
| [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) | BlueToolFixup |
| [NevetScar/acp6x-omen-dkms](https://github.com/NevetScar/acp6x-omen-dkms) | 同款机器的 Linux ACP6x 麦克风补丁（macOS 用不了，但寄存器序列与 DMI 绕过是蓝本） |
| [Game-5040/acp6x-pdm-macos](https://github.com/Game-5040/acp6x-pdm-macos) | **本机内置麦克风的 macOS 驱动**（kext + HAL 插件，本文第十节的代码） |
| [shubhambanekar/LatSOFAudio](https://github.com/shubhambanekar/LatSOFAudio) | Intel SOF 版 HAL 插件；`ARCHITECTURE.md` 里「Siri's microphone gate」一节解释了 `'imic'` 门槛 |
| [DexterSLamb/CmlSOFAudio](https://github.com/DexterSLamb/CmlSOFAudio) | 同上（Comet Lake 版），kext 用 `IODMACommand` + 用户态 `IOConnectMapMemory64` 的写法可抄 |

---

---

# 十五、USB 端口映射

## 为什么需要

macOS 每个 XHCI 控制器最多识别 **15 个端口**，而且**内部设备的端口必须标记为 `255`**（Internal），否则系统会把它当成可移除设备，影响蓝牙、摄像头和睡眠。

本机三个控制器共 9 个端口，端口数不是问题，主要收益是内部端口标记正确 + 类型标注准确。

## 工具：1401 内置的「USB ports」

`1401.app` → **USB ports** 标签页：

1. 点 `Start` 开始监听
2. 逐个物理口插入 USB3 设备（USB-C 正反各一次），端口变绿表示已记录
3. 在列表里给每个口选类型，点 `Write the map`

它底层写的是 `USBToolBox.kext` + `UTBMap.kext`（`com.dhinakg.USBToolBox.kext`）。

> **不要用 USBMap（CorpNewt）**：macOS 26 上有已知问题 ——
> [USB 3.0 只跑 2.0 速度](https://github.com/corpnewt/USBMap/issues/69)、[端口定义未适配 26](https://github.com/corpnewt/USBMap/issues/66)。

## 1401 的一个 bug（必须手工修正）

1401 生成的映射用**类名**当端口键：

```
AppleUSB20XHCIPort  →  port 2
AppleUSB30XHCIPort  →  port 4
```

同一个控制器上的**第二个 USB2 端口会覆盖第一个**，所以它永远只能记录「1 个 USB2 + 1 个 USB3」，机器上另外的物理口全部失效（表现为只有一个 USB-A 能用）。

**修正方法**：把 `UTBMap.kext/Contents/Info.plist` 里的 ports 键改成唯一名字（`HS01`/`SS01`/`HS02`/`SS02`），并补全缺失的端口。

## 本机端口表（实测）

用插拔设备读 `locationID` 得到：

| 物理口 | 控制器 | USB3 端口 | USB2 端口 | 类型 |
|---|---|---|---|---|
| USB-C | XHC0（`15B6`） | 3 | 1 | `9` USB-C(带回转) |
| USB-A ② | XHC0（`15B6`） | 4 | 2 | `3` / `0` |
| USB-A ① | XHC1（`15B7`） | 3 | 1 | `3` / `0` |
| USB-A ③ | XHC1（`15B7`） | 4 | 2 | `3` / `0` |
| 内部 Hub（蓝牙/摄像头/键盘） | XHC2（`15B8`） | — | 1 | `255` Internal |

端口号与 `locationID` 的关系：

```
controller = locationID & 0xFF000000
port       = (locationID >> 20) & 0xF
```

## 类型码

| 值 | 含义 |
|---|---|
| `0` | USB 2.0 Type-A |
| `3` | USB 3 Type-A |
| `8` | USB-C（仅 USB2） |
| `9` | USB-C（带 switch，正反同端口） |
| `10` | USB-C（无 switch，正反不同端口） |
| `255` | Internal |

## 配套 kext

```
USBToolBox.kext   Enabled = true    ← 注入器，必须保留
UTBMap.kext       Enabled = true    ← 自定义映射
UTBDefault.kext   Enabled = false   ← 通用映射，停用
```

## 验证

仓库外的辅助脚本 `usb-test.py`（实时监控插拔）：

```bash
python3 usb-test.py          # 实时监控，插拔时报告控制器/端口/速度/映射
python3 usb-test.py --list   # 列出当前设备
python3 usb-test.py --map    # 打印映射表
```

输出示例：

```
[12:38:03] 插入  iPhone  XHC0  端口 1  HighSpeed(USB2 480M)  → 映射 USB-C(带回转) (HS01)
```

## 验收标准

| 检查 | 期望 |
|---|---|
| 3 个 USB-A 口 | 插 USB3 设备显示 `SuperSpeed(USB3 5G)` |
| USB-C 正反 | 都能识别，都映射到 `XHC0 端口 3/1` |
| 每个口的 USB2 通道 | 插 USB2 设备能识别 |
| 蓝牙 | `Chipset: THIRD_PARTY_DONGLE`，重启后正常 |
| 重启后 | 映射仍生效（`UTBMap.kext` 正常加载），蓝牙自动就绪 |

> 本机没有 S3（固件只支持 Modern Standby），因此不存在"睡眠唤醒"这一项测试。

---

# 十六、驱动版本管理

## 当前版本

| 驱动 | 版本 | 来源 |
|---|---|---|
| NullMoth NVIDIA（NVRM/NVRFB/NVAccel/NVRMAGDC） | **3.1** | `nullmoth/nvidia-macos-driver` |
| NMXAudio（驱动自带音频） | 1.0.0 | 同上 |
| WTLWireless（Wi-Fi 核心） | **0.15.0** | `watchthelight-labs/WTLWireless` |
| WTLWireless.Native（原生前端，插件） | **0.15.0** | 同上 |
| WTLWireless.Bt（蓝牙固件，插件） | **0.15.0** | 同上 |
| BlueToolFixup | 2.7.2 | Acidanthera（BrcmPatchRAM） |
| LegionBtFix | **0.3.0** | `watchthelight-labs/WTLLegionBtFix` |

## 为什么要盯着版本

本机的蓝牙曾经"连一会儿自己关闭又打开"，崩溃报告显示 `bluetoothd` 反复 **SIGBUS**（`TxLoop` 线程），根因是 **MtkBt 0.2.2 的重置循环 bug**。而 0.2.3 / 0.2.4 的更新说明正是：

- 0.2.3 —「Fixes Bluetooth turning itself off after a restart」
- 0.2.4 —「Stops a reset loop that could freeze USB input」

**驱动的更新说明往往就是正在发生的 bug**，症状对上了就该升级。

## 检查更新（`github.com` 打不开时用 API）

```bash
for repo in \
  watchthelight-labs/WTLWireless \
  watchthelight-labs/WTLLegionBtFix \
  nullmoth/nvidia-macos-driver ; do
  echo "== $repo"
  curl -s "https://api.github.com/repos/$repo/releases/latest" \
    | grep -E '"tag_name"|"published_at"' | head -2
done
```

## 更新方法（kext 类）

1. 下载新版本，解压出 `*.kext`
2. 备份旧版：`mv EFI/OC/Kexts/X.kext EFI/OC/Kexts/X.kext.bak-<旧版本>`
3. 复制新版到 `EFI/OC/Kexts/`
4. **`config.plist` 不用改** —— 只要 `BundlePath` 和 `ExecutablePath` 与之前一致
5. 重启验证

## 已知的"等上游"问题

| 问题 | 跟踪 |
|---|---|
| 应用图标渲染异常 | `nullmoth/nvidia-macos-driver` issue #89（`icons-test1` 测试插件未进正式版；3.1 仍复现） |
| GPU 温度读不到 | 驱动读 TSENS `0x20460`，本机 Blackwell 返回 `0xbadf1100` 哨兵值，被驱动拒绝发布；报告草稿在 `GPU温度报告.md` |
| Wi-Fi 区域码停在 `XZ`，DFS 扫描慢 | 驱动 `setCOUNTRY_CODE` 只记录不执行，无 boot-arg 可设 |
| WPA3-SAE / 企业级 802.1X / AWDL | 驱动功能缺口 |

---

# 十七、关于本机显示的名称：CPU

装好之后「系统报告 → 硬件 → 处理器名称」显示的是：

```
Processor Name: 16-Core Intel Xeon W
```

而真实 CPU 是 `AMD Ryzen 9 9955HX 16-Core Processor`。

## 原因：Apple 专有的 SMBIOS 131 号表

`PlatformInfo → Generic → ProcessorType` 对应的不是标准 SMBIOS 的处理器字符串，而是 **Apple 专有的 131 号表**。macOS 用「处理器类型 + 核心数」查这张表生成名字：

```
<0F01> 16 cores → "16-Core Intel Xeon W"
```

苹果从没用过 AMD CPU，所以表里**没有 AMD 名称**。而且：

- 设为 `0`（自动）时，OpenCore 对 AMD（family F）推断出的就是 `0x0F01`
- 设为表里没有的值（如 `65535`）→ 显示 `Unknown`
- 改 `UpdateSMBIOS = false` 风险太高（会丢机型身份）

所以**靠 SMBIOS 这条路走不通**。

## 解法：RestrictEvents 的 CPU 名称补丁

[RestrictEvents](https://github.com/acidanthera/RestrictEvents)（本机已装）支持运行时替换 CPU 品牌字符串：

| 参数 | 作用 |
|---|---|
| `revpatch=…,cpuname` | 允许自定义 CPU 名称 |
| `revcpu=1` | 启用品牌字符串补丁 |
| `revcpuname=<名称>` | 自定义名称（最多 48 字符） |

### 注意：名称带空格不能写进 boot-args

boot-args 用空格分隔，带空格的值会被截断。所以名称要走 **NVRAM 变量**：

```
NVRAM → Add → 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:revcpuname
                 = "AMD Ryzen 9 9955HX 16-Core Processor"
```

最终配置：

```
boot-args:  ... revpatch=sbvmm,cpuname revcpu=1
NVRAM:      4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:revcpuname
```

### 生效条件

OpenCore 的 `NVRAM → Add` **只写不存在的键**。如果 `boot-args` 已在 NVRAM 里，新的值不会写入 —— 要么把它加进 `NVRAM → Delete` 先删再写，要么手动清一次 NVRAM（本机用的是后者：开机时按空格 → Reset NVRAM）。

清 NVRAM 不影响 OpenCore 自己注册的启动项（`LauncherOption`），也不影响固件里的 Windows 启动项。

---

# 十八、HiDPI 与显示缩放

## 开启方法

两步（缺一不可）：

**① boot-arg `nvfbhidpi=1`**

```bash
# 写 NVRAM（立即生效）
cur=$(nvram boot-args | sed 's/^boot-args[[:space:]]*//')
sudo nvram boot-args="$cur nvfbhidpi=1"
```

同时要写进 config（`NVRAM → Add → boot-args`），并且把 `boot-args` 加进 `NVRAM → Delete` ——
否则 OpenCore 的"只写不存在的键"规则会让它下次启动就丢失。

**② 驱动要 2.6.3 或更新**

2.6.3 的 #354 把 scaled 模式标记为 `kDisplayModeValidForHiResFlag`，「看起来像」尺寸才出现在「显示器」里（现在用 3.1，照样生效）。

## 生效验证

```bash
sudo log show --last boot --predicate 'eventMessage CONTAINS "nvfbhidpi"' | head -3
```

正常输出：

```
NVRM-fb: nvfbhidpi: scaled desktops up to 5120x3200 on a 2560x1600 raster
```

## 本机能用的 HiDPI 尺寸（2560×1600 面板）

macOS 的 HiDPI 要求**像素 = 逻辑 × 2**，所以只有整倍光栅可用：

| 逻辑尺寸 | 像素 | 清晰度 |
|---|---|---|
| **1280×800** | 2560×1600 | ✅ 原生 2×，最清晰 |
| 1024×640 | 2048×1280 | ✅ 2× |
| 800×600 | 1600×1200 | ✅ 2× |
| 800×500 | 1600×1000 | ✅ 2× |
| 1440×900 / 1680×1050 | 需要 2880×1800 / 3360×2100 | ❌ 驱动尚未暴露 scaled 模式 |

## 列表里怎么分辨

「显示器」里的条目：

- 不带后缀的（如 `1280 × 800（默认）`）= **HiDPI，清晰**
- 带「（低分辨率）」的 = **1×，模糊**

可以用这个工具直接列出系统实际提供的 HiDPI 模式（源码见下）：

```bash
clang -O2 -o modes modes.c -framework CoreGraphics -framework CoreFoundation && ./modes
```

输出形如：

```
HiDPI 1280x800 (像素 2560x1600)
HiDPI 1024x640 (像素 2048x1280)
HiDPI 数量: 9
```

## 想要中间尺寸怎么办

| 方案 | 说明 |
|---|---|
| 用 1280×800 | 最清晰，UI 偏大 |
| **BetterDisplay**（免费） | 建虚拟屏实现任意缩放的 HiDPI，代价是轻微延迟 |
| 等驱动暴露 scaled 模式 | `nvfbhidpi` 已经允许 2× 桌面，但 macOS 列表里没有非整倍选项 |

---

# 十九、后续计划

- [x] 内置麦克风：自研 ACP6x PDM 驱动已完成（kext + HAL 插件，见第十节，代码单独成库）
- [ ] 麦克风进阶：双麦阵列波束成形/指向性（硬件是两只间距 2–3 cm 的 PDM 麦，互相关 0.96）、更稳的底噪估计
- [ ] 关机断电：已定位到"外接 USB 设备在 S5 保持唤醒"，尚未找到软件层解法
- [ ] 图标残影：默认（玻璃）图标样式的图层渲染错位，3.1 未修；上报材料已备
- [ ] 非整倍 HiDPI：`nvfbhidpi=1` 已允许 2× 桌面，但驱动未把 scaled 模式暴露给 macOS
- [ ] 亮度持久化：PR #312 在本机不生效，继续用自建 LaunchDaemon（见第三节）
- [ ] AirDrop / AWDL：驱动无 `awdl0`；移植 Owly 的可行性、工作量与验证方法见 [docs/airdrop-feasibility.md](docs/airdrop-feasibility.md)

---

# 许可与免责

本文档仅为个人折腾记录，不提供任何 EFI 或驱动文件的分发。所有驱动请从各自官方仓库获取。

黑苹果涉及修改引导配置、降低系统安全设置（SIP/AMFI），请自行评估风险。
