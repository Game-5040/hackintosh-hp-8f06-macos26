# 亮度持久化（NVIDIA 笔记本面板）

macOS 上第三方显卡驱动**不保存**背光亮度，重启后回到最亮。这套工具分两段解决：

```
daemon  brightness-early   开机(登录前)  写 linear-brightness（IOKit）      → 屏幕立刻恢复
agent   brightness-watch   登录 + 每 3 秒 写 DisplayServices（私有框架）    → 滑块同步
                                         显示器从休眠恢复时重新应用         → 防止唤醒后跳回最亮
                                         用户改动时保存新值                → 不覆盖手动调整
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
| `brightness-watch.sh` | 常驻看门狗（0.3 秒轮询）：启动/唤醒/时间跳变时恢复，用户改动时保存 |
| `com.local.brightness-*.plist` | 一个 daemon + 一个 agent |
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
- **恢复时机取决于驱动注册**：`publishBacklight()` 里固定用 NVKMS 的初始值，面板要等驱动注册后才可写；脚本用 0.1 秒轮询，注册完立即写入
- **状态文件属主**：`/Users/Shared/brightness.*` 必须是登录用户所有，否则 agent 写不进去（root 属主会让看门狗永远读不到休眠状态）
- **唤醒检测**：`IODisplayWrangler` 的 `CurrentPowerState` 在显示器休眠时从 4 变成 1，恢复时回到 4
- **整机睡眠**：进程会被挂起甚至杀掉，单靠状态变化检测不到；脚本额外用"启动即应用"和"时钟跳变 >2 秒"兜底
