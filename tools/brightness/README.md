# 亮度持久化（NVIDIA 笔记本面板）

macOS 上第三方显卡驱动**不保存**背光亮度，重启后回到最亮。这套工具用两个 LaunchDaemon 解决。

## 关键：两个亮度参数

`AppleBacklightDisplay` 的 `IODisplayParameters` 里有两个相似参数：

| 参数 | 行为 |
|---|---|
| `brightness` | 滑块占位值，**写了不生效** |
| `linear-brightness` | **真正控制面板**，按亮度键改的是它 |

验证方法：按几下亮度键，看哪个参数跟着变。

```bash
ioreg -rc AppleBacklightDisplay -w0 | tr ',' '\n' | grep -E '"brightness"|linear-brightness'
```

## 文件

| 文件 | 作用 |
|---|---|
| `bl.c` | 读写 `linear-brightness`：`bl` 读，`bl 0.4` 写 |
| `blp.c` | 通用参数读写：`blp <参数> [值]` |
| `brightness-save.sh` | 每 60 秒保存当前亮度到 `/var/db/brightness.level` |
| `brightness-restore.sh` | 开机恢复，并在 20/40 秒后再校正 |
| `com.local.brightness-*.plist` | LaunchDaemon 定义 |
| `install.sh` | 安装（自动 `mkdir -p /usr/local/bin`） |

## 安装

```bash
clang -O2 -o bl  bl.c  -framework IOKit -framework CoreFoundation
clang -O2 -o blp blp.c -framework IOKit -framework CoreFoundation
sudo bash install.sh
```

## 验证

```bash
bl 0.25                          # 设成 25%
sudo /usr/local/bin/brightness-save.sh
cat /var/db/brightness.level     # 0.2500
bl 1.0                          # 改成最亮
sudo /usr/local/bin/brightness-restore.sh
bl                              # 应回到 0.2500，且屏幕真的变暗
```

最后重启一次，确认亮度自动恢复。

## 说明

- 最大误差是"关机前最后一分钟内的调整"（保存间隔 60 秒），可改 `StartInterval` 调整
- `/usr/local/bin` 在 macOS 默认不存在，安装脚本会创建
