# HP 笔记本（Ryzen 9 9955HX + RTX 5070）黑苹果 macOS 26 Tahoe 实战记录

> 在 HP 8F06 上**全新安装** macOS 26.7.1 (Tahoe) 并与 15.8.1 (Sequoia) 双系统共存，让显示、亮度、Wi-Fi、蓝牙、音频输出、电池全部可用。
> 除内置麦克风外，整机功能完整。

## 机器

| 项目 | 值 |
|---|---|
| 机型 | **HP OMEN 16-ap1xxx**（主板 ID `8F06`，ACP 的 `compatible` 报 `pci103c,8f06`） |
| CPU | AMD Ryzen 9 9955HX 16-Core（Zen 5, Fire Range） |
| 显卡 | NVIDIA GeForce RTX 5070 Laptop GPU 12 GB（device id `0x2D18`） |
| 屏幕 | 2560 × 1600 |
| 网卡 | MediaTek MT7925（Wi-Fi PCI `14C3:7925`，蓝牙 USB `0E8D:8C38`，ACP `1022:15E2` rev `0x62`） |
| 声卡 | Realtek ALC245（HDA `0x10EC0245`） |
| 系统 | macOS 26.7.1 (25G241) / Darwin 25.6.0 |
| SMBIOS | MacBookPro16,2 |
| 引导 | OpenCore（1401 生成，1.0.8） |

## 结果总览

| 功能 | 状态 | 方案 |
|---|---|---|
| 显示 / Metal 加速 | ✅ | NullMoth NVIDIA 驱动 2.5.2 |
| 硬件背光（亮度） | ✅ | `nvrmacpibl=1` |
| Wi-Fi | ✅ | watchthelight `MtkWlan` 0.11.3 + `MtkWlanNative` 0.4.11 |
| 蓝牙 | ✅ | `MtkBt` **0.2.4** + `BlueToolFixup` 2.7.2 + `LegionBtFix` 0.2.0 |
| 音频输出 | ✅ | `AppleALC` 1.9.9 + **`SimpleHDA` 1.0.0** + layout 11 |
| 电池 / 充电状态 | ✅ | `SSDT-AC` + `_PSR`/`_Q20` 重命名（26 上充电实时更新；"电源适配器已连接"指示不显示） |
| Windows 双系统引导 | ✅ | `LauncherOption = Full` + 自定义 `Entries` 图标 |
| USB 端口映射 | ✅ | `USBToolBox` + 手工修正的 `UTBMap`（9 个端口，内部 255） |
| 内置麦克风 | ❌ | 挂在 AMD ACP6x（非 HDA），macOS 无驱动 |
| 睡眠 | ❌ | 固件只声明 Modern Standby，无 S3 |
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

> 目标构建必须是 **26.7.1 (25G241)** —— 这是 `MtkWlanNative` 和 `LegionBtFix` 硬性要求的版本。
> 装成别的 26.x 小版本，这两个 kext 会直接拒绝加载。

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

- 2.5.2（`NVRM` / `NVRMFB` / `NVRMAGDC` 通用，`NVAccel` 按系统分构建：`kexts/15` 和 `kexts/26`）

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

---

# 四、Wi-Fi：`MtkWlan` + `MtkWlanNative`

项目：<https://github.com/watchthelight-labs/mt7925-hackintosh-wifi>（驱动）
前端：<https://github.com/watchthelight-labs/mt7925-hackintosh-wifi-native>（原生菜单）

## 版本要求（非常重要）

`MtkWlanNative` **只支持 macOS 26.7.1 build 25G241**，靠 `MtkNativeAbi` 硬匹配，其他构建直接拒绝加载（安全设计：加载失败会回退成以太网前端 `en1`）。

驱动本体 `MtkWlan` 0.11.3 是通用部分。

## 安装

```
1. MtkWlan.kext 和 MtkWlanNative.kext 放进 EFI/OC/Kexts/
2. Kernel → Add 加两条，MtkWlan 在前
3. boot-args 加：mtkfe=native mtknativeif=1
```

## 为什么不用原来的 itlmt7925

`itlmt7925`（GA403WM 那套）**只支持 macOS 15**，26 上不能用。两套驱动都驱动同一个 PCI 设备，不能共存。

验证：

```bash
ioreg -r -c MtkWlan -l -w0 | grep -E '"MtkFrontEndActive"|"MtkState"'
# 期望 MtkFrontEndActive = "native"，MtkState = "W6 pass: en1 passing traffic"
```

---

# 五、蓝牙：三件套 + 两个 NVRAM 键

项目：<https://github.com/watchthelight-labs/mt7925-hackintosh-bluetooth>（`MtkBt` 0.2.2）

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
| `MtkBt` 0.2.2 | 给 MT7925 灌蓝牙固件（支持 `0E8D:8C38`，我们的卡原生在列） |
| `LegionBtFix` 0.2.0 | 修 `bluetoothd` 的 LE 连接崩溃（**只匹配 26.7.1 25G241**） |

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

# 十、未解决：内置麦克风

## 现象

- 录音只有底噪（"滋滋"声）
- 录音时扬声器跟着波形响（回环）
- Windows 下正常

## 排查过程（错误的方向）

花了两天在 ALC245 上折腾：

```
- 把 0x12 引脚改成 Mic at Int, Digital（0x90a60130）
- 试遍 0x19 / 0x1a / 0x1b / 0x1d 四个候选引脚
- 确认 mixer 0x23 有 5 个输入，第 5 个（索引 4）就是 0x12
- 开 alcverbs=1 调用 alc-verb 改引脚、改 mixer、改 amp
```

结论：**全部无效，因为麦克风根本不在 codec 上。**

## 真正的结论

三条证据：

1. **BIOS 没给 codec 配置 DMIC**
   AppleALC 的 layout 11/12/13 **都不写 `ConfigData`**（引脚配置），所以读到的 `0x12 = 0x411111f0`（未连接）就是 **BIOS 默认值**。
   对比有 DMIC 的机器（Minisforum / Acer），BIOS 值是 `0x90a60130`（启用）。

2. **DSDT 里有 AMD ACP**

```
Device (ACP) { Name (_HID, "AMDI0063") }
```

`AMDI0063` 是 AMD 音频协处理器（SoundWire/PDM）。

3. **Windows 设备管理器确认**：麦克风挂在 **AMD Audio CoProcessor** 下，不是 Realtek。

## 为什么没有 macOS 驱动

- 唯一的 macOS ACP 麦克风驱动 [`AMDMicrophone`](https://github.com/qhuyduong/AMDMicrophone) **只支持 Renoir**（ACP3x）
- 它检查 PCI revision：`if (revisionId == 0x1)`，我们的 ACP 是 **`0x62`**，直接 `return NULL`
- 搜遍 15 个 forks，**没有一个扩展到新平台**
- [`acp6x-omen-dkms`](https://github.com/NevetScar/acp6x-omen-dkms) 是同款机器的 **Linux** 补丁（支持 board `8F06`），但那是 Linux 内核模块，macOS 无法加载

## 结论

内置麦克风需要写一个 **macOS ACP6x (Yellow Carp) 驱动**，工作量数周，参考实现是 Linux 的 `acp6x-pdm-dma.c`。

现实方案：**USB 麦克风** 或 **蓝牙耳机**。

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
-v debug=0x100 keepsyms=1 -amfipassbeta -vi2c-force-polling revpatch=sbvmm
nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80
ipc_control_port_options=0 gfxrst=4 mtkfe=native mtknativeif=1 nvrmacpibl=1
```

| 参数 | 作用 |
|---|---|
| `nvfb=1 nvaccel=1 nvfbheads=4` | NullMoth 显卡帧缓冲/加速 |
| `nvrmacpibl=1` | **硬件背光** |
| `gfxrst=4` | 关闭 WhateverGreen 的启动画面拷贝（防登录时 panic） |
| `amfi=0x80` | 关闭 AMFI（加载未签名 kext） |
| `mtkfe=native mtknativeif=1` | MediaTek Wi-Fi 走原生前端 |
| `keepsyms=1` | SimpleHDA 要求 |
| `revpatch=sbvmm` | RestrictEvents 相关 |

## kext（35 条，按加载顺序）

```
Lilu → AMFIPass → AppleMCEReporterDisabler → BrightnessKeys → ECEnabler
→ NVMeFix → RealtekRTL8111 → RestrictEvents → VirtualSMC → SMCBatteryManager
→ SMCLightSensor → USBToolBox → UTBDefault → VoodooI2C(+PlugIns) → VoodooI2CHID
→ VoodooPS2Controller(+PlugIns) → WhateverGreen → NVRM → NVRMFB → NVRMAGDC
→ NVAccel → MtkWlan → MtkWlanNative → BlueToolFixup → MtkBt → LegionBtFix
→ AppleALC → SimpleHDA
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
```

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
| 麦克风只有噪音 | 麦克风在 AMD ACP 上，不在 codec | 无解，用 USB 麦克风 |
| OC 菜单突然多出 Recovery / `1401:` 工具条目 | 1401 写配置时重置了 `HideAuxiliary`（且它会新装两个工具，默认非辅助） | `HideAuxiliary = true`，并把工具条目的 `Auxiliary` 设为 `true` |
| Wi-Fi 保存过的网络连不上（一直转圈后失败） | 旧的保存状态（密码/PMK/私有 MAC）与当前驱动不符 | 系统设置里**忘记此网络**后重新连接；必要时关闭「私有 Wi-Fi 地址」 |
| 蓝牙连一会儿自己关闭又打开 | MtkBt 0.2.2 的重置循环 bug（bluetoothd 反复 SIGBUS 崩溃） | 升级 MtkBt 到 **0.2.4**（0.2.3 修复自动关闭、0.2.4 修复重置循环） |
| iPhone 个人热点在 Wi-Fi 菜单里点了没反应 | 菜单那条是**连续互通热点**（Instant Hotspot），走 AWDL —— 驱动没有 AWDL 接口 | 用「其他…」手动加入，或 `networksetup -setairportnetwork en1 "iPhone 12 mini" "密码"`；iPhone 需开「最大化兼容性」（2.4GHz + WPA2） |
| Wi-Fi 扫描很慢 / 部分网络看不到 | `setCOUNTRY_CODE` 被驱动"只记录不执行"，区域码停在 `XZ`，DFS 频道只能被动扫描 | 路由器 5GHz 固定到 36–48 或 149–161（避开 52–144） |
| `Reset NVRAM` / `Recovery` 从菜单**彻底消失**，按空格也不出现 | 停用了 `ResetNvramEntry.efi` 驱动（这是彻底移除），而不是设 `HideAuxiliary` | 驱动改回 `Enabled=true`，用 `HideAuxiliary=true` 隐藏（按空格可见） |
| 1401 做 USB 映射后只剩一个 USB-A 能用 | 它用类名（`AppleUSB20XHCIPort`）当端口键，同控制器第二个端口被覆盖 | 手工改成 `HS01/SS01/HS02/SS02` 并补全端口（见第十五节） |

---

# 十四、参考项目

| 项目 | 用途 |
|---|---|
| [nullmoth/1401](https://github.com/nullmoth/1401) | NVIDIA 黑苹果一键工具（含 Tahoe 升级准备） |
| [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver) | NVIDIA Metal 驱动 |
| [watchthelight-labs/mt7925-hackintosh-wifi](https://github.com/watchthelight-labs/mt7925-hackintosh-wifi) | MT7925 Wi-Fi 驱动 |
| [watchthelight-labs/mt7925-hackintosh-wifi-native](https://github.com/watchthelight-labs/mt7925-hackintosh-wifi-native) | Wi-Fi 原生菜单 |
| [watchthelight-labs/mt7925-hackintosh-bluetooth](https://github.com/watchthelight-labs/mt7925-hackintosh-bluetooth) | MT7925 蓝牙固件加载器 |
| [watchthelight-labs/LegionBtFix](https://github.com/watchthelight-labs/LegionBtFix) | bluetoothd 补丁（26.7.1） |
| [laobamac/SimpleHDA](https://github.com/laobamac/SimpleHDA) | 在 Tahoe 上恢复 AppleHDA |
| [acidanthera/AppleALC](https://github.com/acidanthera/AppleALC) | 音频 layout |
| [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) | BlueToolFixup |
| [NevetScar/acp6x-omen-dkms](https://github.com/NevetScar/acp6x-omen-dkms) | 同款机器的 Linux ACP6x 麦克风补丁（macOS 无法使用，供参考） |

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
| NullMoth NVIDIA（NVRM/NVFB/NVAccel/NVRMAGDC） | 2.5.2 | `nullmoth/nvidia-macos-driver` |
| MtkWlan（核心） | 0.11.3 | `watchthelight-labs/mt7925-hackintosh-wifi` |
| MtkWlanNative（原生前端） | 0.4.11 | `watchthelight-labs/mt7925-hackintosh-wifi-native` |
| **MtkBt** | **0.2.4** | `watchthelight-labs/mt7925-hackintosh-bluetooth` |
| BlueToolFixup | 2.7.2 | Acidanthera |
| LegionBtFix | 0.2.0 | watchthelight-labs |

## 为什么要盯着版本

本机的蓝牙曾经"连一会儿自己关闭又打开"，崩溃报告显示 `bluetoothd` 反复 **SIGBUS**（`TxLoop` 线程），根因是 **MtkBt 0.2.2 的重置循环 bug**。而 0.2.3 / 0.2.4 的更新说明正是：

- 0.2.3 —「Fixes Bluetooth turning itself off after a restart」
- 0.2.4 —「Stops a reset loop that could freeze USB input」

**驱动的更新说明往往就是正在发生的 bug**，症状对上了就该升级。

## 检查更新（`github.com` 打不开时用 API）

```bash
for repo in \
  watchthelight-labs/mt7925-hackintosh-wifi \
  watchthelight-labs/mt7925-hackintosh-wifi-native \
  watchthelight-labs/mt7925-hackintosh-bluetooth \
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
| 应用图标渲染异常 | `nullmoth/nvidia-macos-driver` issue #89（`icons-test1` 测试插件未进正式版） |
| Wi-Fi 区域码停在 `XZ`，DFS 扫描慢 | 驱动 `setCOUNTRY_CODE` 只记录不执行，无 boot-arg 可设 |
| WPA3-SAE / 企业级 802.1X / AWDL | 驱动功能缺口 |

---

# 十七、后续计划

- [ ] 内置麦克风：需要 macOS 版 ACP6x 驱动（见第十节）
- [ ] AirDrop / AWDL：驱动无 `awdl0`；移植 Owly 的可行性、工作量与验证方法见 [docs/airdrop-feasibility.md](docs/airdrop-feasibility.md)

---

# 许可与免责

本文档仅为个人折腾记录，不提供任何 EFI 或驱动文件的分发。所有驱动请从各自官方仓库获取。

黑苹果涉及修改引导配置、降低系统安全设置（SIP/AMFI），请自行评估风险。
