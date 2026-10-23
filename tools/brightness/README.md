# 亮度持久化（NVIDIA 笔记本面板）

macOS 上第三方显卡驱动**不保存**背光亮度，重启后回到最亮。这套工具分两段解决：

```
阶段 1（登录前，系统级 daemon）  → 写 linear-brightness（IOKit）   → 屏幕立刻恢复
阶段 2（进入系统后，用户 agent） → 写 DisplayServices（私有框架） → 滑块同步、按键从该值继续
```

## 为什么需要两个接口

同一块面板有三个"亮度"入口，行为各不相同：

| 接口 | 现象 |
|---|---|
| `IODisplayParameters.brightness` | 写了不生效（滑块占位值） |
| `IODisplayParameters.linear-brightness` | **真正控制面板**，但滑块不动 |
| `DisplayServicesSetBrightness` | 面板 + 滑块一起动（控制中心走的就是它） |

而 `DisplayServices` 需要 GUI 会话，**系统级 daemon 里调用会失败**；`linear-brightness` 没有这个限制，登录前就能写。所以两个阶段各用一个接口。

## 文件

| 文件 | 作用 |
|---|---|
| `bl.c` / `blp.c` | IOKit 读写 `linear-brightness`（`blp` 可指定参数名） |
| `ds.c` | DisplayServices 读写亮度：`ds` 读，`ds 0.4` 写 |
| `brightness-early.sh` | 阶段 1：开机等面板出现，写入保存值 |
| `brightness-ui.sh` | 阶段 2：登录后把滑块同步到该值 |
| `brightness-save.sh` | 每 60 秒保存当前值 |
| `com.local.brightness-*.plist` | 一个 daemon + 两个 agent |
| `install.sh` | 安装（需 sudo） |

## 安装

```bash
clang -O2 -o bl  bl.c  -framework IOKit -framework CoreFoundation
clang -O2 -o blp blp.c -framework IOKit -framework CoreFoundation
clang -O2 -o ds  ds.c  -framework CoreGraphics
sudo bash install.sh
```

## 使用

```bash
/usr/local/bin/ds 0.4            # 设 40%（面板 + 滑块同步）
/usr/local/bin/brightness-save.sh
cat /Users/Shared/brightness.level
```

## 验证

```bash
# 阶段 1：模拟开机时的最亮状态
/usr/local/bin/ds 1.0
sudo /usr/local/bin/brightness-early.sh
/usr/local/bin/blp linear-brightness     # 应回到保存值

# 阶段 2：同步滑块
/usr/local/bin/brightness-ui.sh
/usr/local/bin/ds                        # 应与保存值一致
```

## 已知限制与踩过的坑

- **状态文件必须非空**：安装脚本曾用 `: > file` 清空它，导致脚本读到空值直接退出
- **`save` 不能 RunAtLoad**：登录瞬间它会抢在 `ui` 之前把状态写成当前（最亮）值
- **`/usr/local/bin` 默认不存在**：安装脚本要 `mkdir -p`
- **恢复有 ~5 秒延迟**：驱动在 `publishBacklight()` 里固定用 NVKMS 的初始值，面板要等驱动注册后才可写
- **保存间隔 60 秒**：关机前最后一分钟的调整可能丢失，可改 `StartInterval`
