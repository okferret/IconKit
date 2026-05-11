# IconKit

一个轻量的 macOS（SwiftUI）图标工具集，帮助开发者快速生成多平台应用图标资源。

> 运行环境：macOS 13.5+，Xcode 15+

---

## 功能概览

### 🖼 应用图标导出

从一张源图（建议 **1024×1024 PNG，带透明通道**）一键导出：

#### Apple 平台（Asset Catalog）

| 平台 | 说明 |
|------|------|
| **iOS / iPadOS** | iPhone + iPad 全尺寸 + App Store 营销图（1024pt） |
| **macOS** | 16 / 32 / 128 / 256 / 512 pt @1x @2x |
| **watchOS** | 通知中心、伴侣设置、App Launcher、Quick Look 全套 |
| **tvOS** | 400pt @1x @2x + 1280pt 营销图 |
| **CarPlay** | 60pt @2x @3x |
| **iMessage** | 消息扩展全套 |
| **visionOS** | 1024pt |

每个平台输出独立的 `.appiconset` 目录，包含 `Contents.json`，可直接拖入 Xcode Asset Catalog。

#### Android 平台（mipmap）

| 密度 | 尺寸 |
|------|------|
| mdpi | 48×48 |
| hdpi | 72×72 |
| xhdpi | 96×96 |
| xxhdpi | 144×144 |
| xxxhdpi | 192×192 |

每个密度桶同时输出：
- `ic_launcher.png`（方形图标）
- `ic_launcher_round.png`（圆形裁剪，Android 7.1+）

另外输出 `play_store_512.png`（512×512，用于 Google Play 商店上传）。

---

### 📐 ScaleReducer（多倍图缩放）

将 `@3x` 或 `@2x` PNG/JPEG 自动生成完整的三套资源：

| 输入 | 输出 |
|------|------|
| `xxx@3x.png` | `@3x`（原图）、`@2x`（2/3）、`@1x`（1/3） |
| `xxx@2x.png` | `@3x`（AI 放大或插值）、`@2x`（原图）、`@1x`（1/2） |
| 其他文件名 | 原样输出 |

**特性：**
- 支持 PNG 和 JPEG 输入
- 支持批量处理（拖拽多张 / 选择文件夹，可递归扫描）
- 左右分栏：左侧控制面板 + 右侧实时预览
- 进度条显示批量处理进度
- 日志区自动滚动，支持文本选择

---

## Real-ESRGAN 集成（AI 放大）

ScaleReducer 在处理 `@2x → @3x` 时，可选用 **Real-ESRGAN（realesrgan-ncnn-vulkan）** 提升放大质量。

### 使用方式

1. 在「AI 放大」区域开启「优先使用 Real-ESRGAN 提升质量」
2. 首次使用时自动从 GitHub 下载最新 release（macOS 版）
3. 下载后缓存到本地，后续直接复用

### 缓存目录

```
~/Library/Application Support/IconKit/realesrgan/
```

> 若下载/执行失败，自动回退到高质量插值，功能不受影响。

### 离线内嵌（可选）

将 `realesrgan-ncnn-vulkan` 二进制和 `models/` 目录放入：

```
IconKit.app/Contents/Resources/RealESRGAN/
```

App 会优先使用内嵌版本，无需联网。

---

## 快捷键

| 操作 | 快捷键 |
|------|--------|
| 选择图片 | ⌘O |
| 导出图标 | ⇧⌘E |

---

## 图像质量

- 所有渲染使用 **sRGB 色彩空间**，保证颜色一致性
- 缩放使用 **高质量插值**（`CGInterpolationQuality.high`）
- PNG 输出保留透明通道；JPEG 输出使用白色背景

---

## 项目结构

```
IconKit/
├── IconKit.xcodeproj/
└── IconKit/
    ├── IconKitApp.swift          # App 入口，窗口配置，菜单命令
    ├── RootView.swift            # 导航分栏根视图
    ├── ContentView.swift         # 应用图标导出界面
    ├── ScaleReducerView.swift    # 多倍图缩放界面
    ├── Exporter.swift            # Apple 图标规格与导出逻辑
    ├── AndroidExporter.swift     # Android 图标导出逻辑
    ├── ImageResizer.swift        # 图像渲染核心（PNG/JPEG，sRGB）
    ├── RealESRGANManager.swift   # Real-ESRGAN 下载与调用管理
    └── Assets.xcassets/
```

---

## 快速开始

1. 克隆或解压项目
2. 打开 `IconKit.xcodeproj`
3. 选择 scheme `IconKit`，目标平台 `My Mac`
4. 运行（⌘R）

---

## 注意事项

- `realesrgan-ncnn-vulkan` 为第三方开源工具，本项目仅做下载与调用封装
  - 上游仓库：https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan
  - 请遵守其许可证条款
- 导出的 Apple Asset Catalog 文件名包含 scale 标识（`1x`/`2x`/`3x`），不同 scale 的同尺寸图标不会互相覆盖

---

## 更新记录

### 2026-05-11
- 新增 tvOS、visionOS 图标导出支持
- 新增 Android 圆形图标（`ic_launcher_round.png`）和 Play Store 图标（`play_store_512.png`）
- 修复 Apple 图标文件名冲突问题（同 id 不同 scale 会覆盖）
- ImageResizer 全面切换 sRGB 色彩空间，新增 JPEG 导出支持
- ScaleReducer 支持 JPEG 输入，改为左右分栏布局，新增实时预览
- 导出完成后自动在 Finder 中打开目标目录
- 添加菜单快捷键（⌘O 选图，⇧⌘E 导出）
- 改进错误提示和进度反馈

### 2026-04-16
- 初始版本
