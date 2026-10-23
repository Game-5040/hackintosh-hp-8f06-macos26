# AirDrop / AWDL 在第三方网卡上的可行性分析

> 结论先行：**协议层可以直接复用，卡点在 macOS 的 raw 802.11 注入能力。移植可行，但要 4–6 个月工作量；短期建议用 LocalSend 或树莓派桥接。**

## 一、问题：缺 `awdl0` 接口

本机（MT7925 + `MtkWlanNative` 0.4.11）没有 `awdl0`：

```bash
$ ifconfig awdl0
ifconfig: interface awdl0 does not exist
```

驱动作者在 [issue #2](https://github.com/watchthelight-labs/mt7925-hackintosh-wifi-native/issues/2) 里说明：

> `ifconfig awdl0` finds no interface. … The feasibility spike for AWDL on the MT7925 is **phase C of the Wi-Fi plan**.

受影响的功能：

| 功能 | 依赖 AWDL |
|---|---|
| AirDrop | ✅ |
| AirPlay 直连 | ✅ |
| Sidecar（iPad 副屏） | ✅ |
| 连续互通相机 | ✅ |
| 通用控制 | ✅ |
| Handoff（接力） | ✅ |
| Apple Watch 解锁 | ✅ |
| iPhone 镜像 | ✅ |

## 二、AWDL 是什么

苹果私有的点对点 Wi-Fi 协议（Apple Wireless Direct Link）：

- 复用同一块网卡，在 **64 ms 时隙**内于「当前 AP 信道」和「社交信道（6 / 44 / 149）」之间来回切换
- 用 802.11 管理帧（Action frames）广播、同步时钟、选主节点
- 用户无感知，正常上网不受影响

苹果的 Broadcom 驱动内建这套逻辑；第三方驱动（`MtkWlan`、`itlwm`）只实现了「连 AP + 跑数据」。

协议已被逆向：[One Billion Apples' Secret Sauce: Apple Wireless Direct Link](https://arxiv.org/abs/1803.09088)，并开源了 Linux 实现 [OWL](https://github.com/seemoo-lab/owl)。

## 三、可参考的实现：Owly

[`t4t5/owly`](https://github.com/t4t5/owly)（原 `omdrop-owl`，Rust，2.9k 星）—— Linux 上给非 Apple 网卡做 AirDrop，**头号支持卡就是 MT7925**。

架构（6 个 crate）：

| crate | 作用 | 可移植性 |
|---|---|---|
| `owly-awdl` | AWDL 协议：帧、TLV、同步、选举、信道序列、数据面 | ✅ **完全可移植**（sans-IO、no-std、纯 Rust，零 Linux 依赖） |
| `owly-airdrop` | AirDrop 协议（TLS、证书、文件传输） | ✅ 基本可移植（tokio + rustls，`nix` 沙箱依赖需替换） |
| `owly-radio` | 无线后端 | ❌ **必须重写** |
| `owlyd` | 守护进程 | ⚠️ D-Bus 需换成 XPC |
| `owly-cli` / `omdrop-owl` | CLI / 状态栏插件 | ✅ 外围 |

### `owly-radio` 依赖的 Linux 能力

```
1. nl80211 + netlink   → 创建 monitor 虚拟接口、注入原始 802.11 帧、切信道
2. TAP 设备 (awdl0)     → 给 IP 层提供链路层接口
3. nmcli / ip / ping    → 管理 Wi-Fi 连接
4. CAP_NET_ADMIN/RAW    → 权限模型
```

macOS 这四样都没有：**没有 mac80211 框架**，第三方 kext 不提供 monitor 模式或帧注入。

## 四、macOS 上已有的积木

[`Network-Weather/mt76-usb-macos`](https://github.com/Network-Weather/mt76-usb-macos)（2026-09，研究级）：

- 纯用户态，走 libusb / IOKit，**不需要 kext、不需要 root、不影响 SIP**
- 支持 **MT7921U / MT7925U** USB 网卡
- **接收路径已工作**：2.4 / 5 / 6 GHz，160 MHz，输出 radiotap pcap
- **注入是实验性的**：C 版实现了 MT7921 的 TXWI 注入，「60 个间隔试探帧成功过」，未做发布验证

即：**帧接收已验证，帧注入有原型。**

## 五、两条移植路线

### 路线 A：USB 网卡 + 用户态 radio backend（不需要 kext）

```
硬件:  ALFA AWUS036AXML (MT7921U) 或 Netgear A9000 (MT7925U)   ~¥300–600
   ↓
底层:  mt76-usb-macos（monitor 收 + 注入）
   ↓
适配:  实现 owly-radio 的 Backend trait（up / down / recover）
        + 信道控制（6 / 44 / 149）+ 64 ms 时隙时序
   ↓
复用:  owly-awdl + owly-airdrop（原样编译到 macOS）
   ↓
数据面: macOS 无 TAP → utun + 用户态 ARP/ND，或在 Rust 内建 smoltcp
```

| 项 | 评估 |
|---|---|
| 协议层工作量 | 2–4 周（几乎白拿） |
| radio backend 工作量 | **2–3 个月**（时隙时序是难点） |
| 数据面桥接 | 3–4 周 |
| 总计 | **4–6 个月**（单人，熟悉 Rust + 802.11） |
| 主要风险 | USB 注入稳定性未验证；AWDL 时隙对时序极敏感 |

### 路线 B：等 `MtkWlan` 实现 phase C

作者把 AWDL 列为可行性研究的 phase C。等驱动内实现后，radio backend 只需调用驱动接口，工作量降到**几周**。缺点：**没有时间表**。

## 六、绕不过的限制

即使移植成功，也只是**独立 App / CLI**，**不会变成系统原生 AirDrop** —— 接不进 `sharingd`，Finder 右键、分享菜单、拖到 Dock 图标都不会有。体验是「打开窗口选文件发给 iPhone」。

## 七、务实建议

| 方案 | 成本 | 时间 | 体验 |
|---|---|---|---|
| **LocalSend** | 免费 | 5 分钟 | 90% 接近 AirDrop |
| **树莓派 + USB 网卡跑 Owly** | ~¥300 | 半天 | 真 AWDL，经 Pi 转发 |
| **自己移植（路线 A）** | ¥300–600 + 4–6 个月 | 长 | 独立 App |
| 等驱动 phase C | 0 | 未知 | 可能成为原生 |

## 八、如果要动手，先验证这一步

> **在 macOS 上用 mt76-usb-macos 的注入 demo，连续发 1000 个帧不崩**

这是整条路线的生死线：

- 注入稳定 → 剩下都是工程问题
- 注入不稳定 → 路线 A 作废，只能等 phase C

## 参考

- [MtkWlanNative issue #2 — No AWDL interface](https://github.com/watchthelight-labs/mt7925-hackintosh-wifi-native/issues/2)
- [Owly — AirDrop for non-Apple devices](https://github.com/t4t5/owly)
- [OWL — Open Wireless Link](https://github.com/seemoo-lab/owl)
- [One Billion Apples' Secret Sauce (论文)](https://arxiv.org/abs/1803.09088)
- [mt76-usb-macos — macOS 用户态 monitor 驱动](https://github.com/Network-Weather/mt76-usb-macos)
- [itlwm issue #292 — AWDL 不支持（Intel 卡同样受限）](https://github.com/OpenIntelWireless/itlwm/issues/292)
