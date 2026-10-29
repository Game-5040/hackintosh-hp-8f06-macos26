# 列出系统实际提供的显示模式（含 HiDPI）

macOS 的「显示器」列表容易误解：带「（低分辨率）」的是 1× 缩放，不带的才是 HiDPI。
这个小工具直接问 CoreGraphics 要完整模式列表，并标出 `像素宽 > 逻辑宽` 的 HiDPI 项。

```bash
clang -O2 -o modes modes.c -framework CoreGraphics -framework CoreFoundation
./modes
```

输出示例（2560×1600 面板，驱动 2.6.3 + `nvfbhidpi=1`）：

```
总模式: 36
  HiDPI 1280x800 (像素 2560x1600)
  HiDPI 1024x640 (像素 2048x1280)
  HiDPI 800x600 (像素 1600x1200)
  HiDPI 800x500 (像素 1600x1000)
HiDPI 数量: 9
```

只列出整倍 2× 的模式，说明驱动没有把 scaled（非整倍）HiDPI 暴露给 macOS ——
主机文档见仓库根的「HiDPI 与显示缩放」一节。
