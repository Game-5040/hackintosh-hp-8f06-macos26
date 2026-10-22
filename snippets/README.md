# 关键配置片段

直接复制到 `config.plist` 对应位置。**改之前先备份。**

## 1. NVRAM：boot-args 必须同时进 Delete

`config.plist → NVRAM`

```xml
<key>7C436110-AB2A-4BBB-A880-FE41995C9F82</key>
<dict>
    <key>boot-args</key>
    <string>-v debug=0x100 keepsyms=1 -amfipassbeta -vi2c-force-polling revpatch=sbvmm nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 gfxrst=4 mtkfe=native mtknativeif=1 nvrmacpibl=1</string>
    <key>bluetoothExternalDongleFailed</key>
    <data>AA==</data>
    <key>bluetoothInternalControllerInfo</key>
    <data>AAAAAAAAAAAAAAAAAAA=</data>
</dict>
```

`NVRAM → Delete → 7C436110-AB2A-4BBB-A880-FE41995C9F82`：

```xml
<array>
    <string>boot-args</string>
</array>
```

> **为什么**：OpenCore 的 `NVRAM → Add` 只写"不存在"的键。如果 NVRAM 里已经有旧值，
> 日志会出现 `OCVAR: Setting NVRAM ...:boot-args - ignored, exists`，你的新参数永远不生效。
> 必须在 `Delete` 里登记同名键，OC 才会先删再写。

## 2. DeviceProperties：音频 layout

```xml
<key>DeviceProperties</key>
<dict>
    <key>Add</key>
    <dict>
        <key>PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x6)</key>
        <dict>
            <key>layout-id</key>
            <integer>11</integer>
        </dict>
    </dict>
</dict>
```

> ALC245 可用的 layout 只有 11 / 12 / 13，本机 11 正常。

## 3. Kernel → Add：音频（顺序不能错）

`Lilu` 必须在前，`AppleALC` 在 `SimpleHDA` 之前。

```xml
<dict>
    <key>Arch</key>            <string>Any</string>
    <key>BundlePath</key>      <string>AppleALC.kext</string>
    <key>Comment</key>         <string>AppleALC 1.9.9: layout 11 (ALC245)</string>
    <key>Enabled</key>         <true/>
    <key>ExecutablePath</key>  <string>Contents/MacOS/AppleALC</string>
    <key>MaxKernel</key>       <string></string>
    <key>MinKernel</key>       <string></string>
    <key>PlistPath</key>       <string>Contents/Info.plist</string>
</dict>
<dict>
    <key>Arch</key>            <string>x86_64</string>
    <key>BundlePath</key>      <string>SimpleHDA.kext</string>
    <key>Comment</key>         <string>SimpleHDA 1.0.0: restore AppleHDA on Tahoe</string>
    <key>Enabled</key>         <true/>
    <key>ExecutablePath</key>  <string>Contents/MacOS/SimpleHDA</string>
    <key>MaxKernel</key>       <string>25.99.99</string>
    <key>MinKernel</key>       <string>25.0.0</string>
    <key>PlistPath</key>       <string>Contents/Info.plist</string>
</dict>
```

> `MinKernel 25.0.0` 是 **Darwin 内核版本**（macOS 26 = Darwin 25），不是 macOS 版本号。

## 4. 蓝牙三件套

```xml
<!-- Lilu → BlueToolFixup → MtkBt → LegionBtFix -->
<dict><key>Arch</key><string>Any</string>
<key>BundlePath</key><string>BlueToolFixup.kext</string>
<key>Enabled</key><true/>
<key>ExecutablePath</key><string>Contents/MacOS/BlueToolFixup</string>
<key>MaxKernel</key><string></string><key>MinKernel</key><string>21.0.0</string>
<key>PlistPath</key><string>Contents/Info.plist</string></dict>

<dict><key>Arch</key><string>Any</string>
<key>BundlePath</key><string>MtkBt.kext</string>
<key>Enabled</key><true/>
<key>ExecutablePath</key><string>Contents/MacOS/MtkBt</string>
<key>MaxKernel</key><string></string><key>MinKernel</key><string>21.0.0</string>
<key>PlistPath</key><string>Contents/Info.plist</string></dict>

<dict><key>Arch</key><string>Any</string>
<key>BundlePath</key><string>LegionBtFix.kext</string>
<key>Enabled</key><true/>
<key>ExecutablePath</key><string>Contents/MacOS/LegionBtFix</string>
<key>MaxKernel</key><string></string><key>MinKernel</key><string>25.0.0</string>
<key>PlistPath</key><string>Contents/Info.plist</string></dict>
```

## 5. Wi-Fi

```xml
<!-- 顺序：MtkWlan → MtkWlanNative -->
<dict><key>Arch</key><string>x86_64</string>
<key>BundlePath</key><string>MtkWlan.kext</string>
<key>Enabled</key><true/>
<key>ExecutablePath</key><string>Contents/MacOS/MtkWlan</string>
<key>MaxKernel</key><string></string><key>MinKernel</key><string></string>
<key>PlistPath</key><string>Contents/Info.plist</string></dict>

<dict><key>Arch</key><string>x86_64</string>
<key>BundlePath</key><string>MtkWlanNative.kext</string>
<key>Enabled</key><true/>
<key>ExecutablePath</key><string>Contents/MacOS/MtkWlanNative</string>
<key>MaxKernel</key><string></string><key>MinKernel</key><string></string>
<key>PlistPath</key><string>Contents/Info.plist</string></dict>
```

## 6. 电池：ACPI 补丁

```xml
<!-- ACPI → Add -->
<dict><key>Comment</key><string>SSDT-AC.aml</string>
<key>Enabled</key><true/><key>Path</key><string>SSDT-AC.aml</string></dict>

<!-- ACPI → Patch -->
<dict><key>Comment</key><string>_PSR to XPSR rename - requires SSDT-AC.aml</string>
<key>Enabled</key><true/><key>Count</key><integer>1</integer>
<key>Find</key><data>X1BTUg==</data>          <!-- "_PSR" -->
<key>Replace</key><data>WFBTUg==</data></dict>  <!-- "XPSR" -->

<dict><key>Comment</key><string>_Q20 to XQ20 rename - requires SSDT-AC.aml</string>
<key>Enabled</key><true/><key>Count</key><integer>1</integer>
<key>Find</key><data>X1EyMA==</data>          <!-- "_Q20" -->
<key>Replace</key><data>WFEyMA==</data></dict>  <!-- "XQ20" -->
```

## 7. Windows 引导

```xml
<!-- Misc → Entries 必须是空数组 -->
<key>Entries</key>
<array/>

<!-- Misc → BlessOverride -->
<key>BlessOverride</key>
<array>
    <string>\EFI\Microsoft\Boot\bootmgfw-orig.efi</string>
</array>
```

配合文件操作：

```
EFI/Microsoft/Boot/bootmgfw.efi        ← 替换成 OpenCore 的 BOOTx64.efi（24576 字节）
EFI/Microsoft/Boot/bootmgfw-orig.efi   ← 原版 Windows 引导器（约 3 MB）
```
