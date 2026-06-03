# IconKit

一个轻量的 macOS（SwiftUI）图标工具集，帮助开发者快速生成多平台应用图标资源。

> **运行环境：** macOS 14.0+，Xcode 15.2+，Swift 5.9+

---

## 目录

- [功能概览](#功能概览)
- [应用图标导出](#-应用图标导出)
- [ScaleReducer 多倍图缩放](#-scalereducer多倍图缩放)
- [Real-ESRGAN AI 放大集成](#-real-esrgan-ai-放大集成)
- [GitHub Token 配置](#-github-token-配置)
- [快捷键](#-快捷键)
- [图像质量说明](#-图像质量说明)
- [项目结构](#-项目结构)
- [快速开始](#-快速开始)
- [注意事项](#-注意事项)
- [更新记录](#-更新记录)

---

## 功能概览

| 功能模块 | 描述 |
|---------|------|
| **应用图标导出** | 从单张源图一键生成 Apple 全平台 + Android 图标资源集 |
| **ScaleReducer** | 将 @1x/@2x/@3x 图片批量生成完整三套多倍图，支持 AI 超分辨率放大 |

---

## 🖼 应用图标导出

从一张源图（建议 **1024×1024 PNG，带透明通道**）一键导出所有平台图标。

### 使用步骤

1. 在侧边栏选择「**应用图标**」
2. 拖拽图片到预览区，或点击「选择图片…」（⌘O）
3. 在侧边栏勾选需要导出的平台
4. 点击「**导出到文件夹…**」（⇧⌘E），选择输出目录

### Apple 平台（Asset Catalog）

每个平台输出独立的 `.appiconset` 目录，包含 `Contents.json`，可直接拖入 Xcode Asset Catalog。

| 平台 | 输出目录 | 说明 |
|------|---------|------|
| **iOS / iPadOS** | `iOS.appiconset/` | iPhone + iPad 全尺寸（20/29/40/60/76/83.5pt）+ App Store 营销图（1024pt） |
| **macOS** | `macOS.appiconset/` | 16 / 32 / 128 / 256 / 512 pt，各含 @1x @2x |
| **watchOS** | `watchOS.appiconset/` | 通知中心（24/27.5/33pt）、伴侣设置（29pt）、App Launcher（40~54pt）、Quick Look（86~108pt）+ 营销图 |
| **tvOS** | `tvOS.appiconset/` | 400pt @1x @2x + 1280pt 营销图 |
| **CarPlay** | `carPlay.appiconset/` | 60pt @2x @3x |
| **iMessage** | `iMessage.appiconset/` | 消息扩展全套（29/60/67pt + 营销图） |
| **visionOS** | `visionOS.appiconset/` | 1024pt + 营销图 |

### Android 平台（mipmap）

输出结构：

```
Android/
├── mipmap-mdpi/
│   ├── ic_launcher.png          # 48×48 方形图标
│   └── ic_launcher_round.png    # 48×48 圆形图标（Android 7.1+）
├── mipmap-hdpi/                 # 72×72
├── mipmap-xhdpi/                # 96×96
├── mipmap-xxhdpi/               # 144×144
├── mipmap-xxxhdpi/              # 192×192
├── play_store_512.png           # 512×512 Google Play 商店图标
└── README.txt
```

将 `mipmap-*` 目录复制到 Android 项目的 `app/src/main/res/` 下即可。

---

## 📐 ScaleReducer（多倍图缩放）

将带有 `@1x`、`@2x` 或 `@3x` 后缀的 PNG/JPEG 自动生成完整的三套多倍图资源。

### 使用步骤

1. 在侧边栏选择「**缩放图片**」
2. 拖拽图片到拖拽区，或点击「选择图片」/「选择文件夹」
3. 在「导出目录」中选择输出位置（与原图同目录 或 统一导出目录）
4. 点击「**批量导出**」

### 输入/输出规则

| 输入文件名 | 生成文件 | 说明 |
|-----------|---------|------|
| `icon@3x.png` | `icon@3x.png`、`icon@2x.png`、`icon.png` | @3x 原图 + 缩小到 2/3（@2x）+ 缩小到 1/3（@1x） |
| `icon@2x.png` | `icon@3x.png`、`icon@2x.png`、`icon.png` | AI 放大 ×1.5（@3x）+ @2x 原图 + 缩小到 1/2（@1x） |
| `icon@1x.png` | `icon@3x.png`、`icon@2x.png`、`icon.png` | AI 放大 ×3（@3x）+ AI 放大 ×2（@2x）+ @1x 原图 |
| 其他文件名 | `icon.png` | 无 @scale 标记，仅输出原图 |

> **AI 放大策略（@1x 输入）：** AI 只跑一次 4x 放大，然后分别缩放到 2x（×0.5）和 3x（×0.75），避免重复调用。

### 功能特性

- ✅ 支持 PNG 和 JPEG 输入，输出统一为 PNG
- ✅ 支持批量处理（拖拽多张 / 选择文件夹）
- ✅ 文件夹扫描支持**递归模式**（开启「递归」开关）
- ✅ 左右分栏：左侧控制面板 + 右侧实时预览
- ✅ 批量处理进度条（显示当前/总数）
- ✅ 日志区自动滚动，支持文本选择复制
- ✅ 文件列表支持单独删除，拖拽追加不重复

---

## 🤖 Real-ESRGAN AI 放大集成

ScaleReducer 在处理放大任务时，可选用 **[Real-ESRGAN（realesrgan-ncnn-vulkan）](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan)** 提升放大质量，相比传统插值算法效果显著更好。

### AI 放大策略详解

| 场景 | AI 调用次数 | 处理方式 |
|------|-----------|---------|
| `@1x → @2x + @3x` | 1 次 | 4x 放大后，缩到 50%（@2x）和 75%（@3x） |
| `@2x → @3x` | 1 次 | 4x 放大后，缩到 37.5%（即原图 ×1.5） |
| `@3x → @2x + @1x` | 1 次（可选）| 直接插值缩小；若开启 AI，4x 放大后缩到 50%/@2x 和 25%/@1x |

> 若 AI 调用失败（未安装、网络问题、模型缺失），自动回退到高质量插值，功能不受影响。

### 安装方式

#### 方式一：自动下载（推荐）

1. 在「AI 放大」设置卡片中开启「优先使用 Real-ESRGAN 提升质量」
2. 点击「自动安装」，App 自动从 GitHub 下载最新 macOS release
3. 下载完成后缓存到本地，后续直接复用

**缓存目录：**
```
~/Library/Application Support/IconKit/realesrgan/
```

点击设置区右侧的 📁 按钮可直接在 Finder 中打开该目录。

#### 方式二：离线内嵌（适合分发）

将 `realesrgan-ncnn-vulkan` 二进制和 `models/` 目录放入 App Bundle：

```
IconKit.app/Contents/Resources/RealESRGAN/
├── realesrgan-ncnn-vulkan    # 可执行文件
├── models/                   # 模型文件目录
│   ├── realesrgan-x4plus.bin
│   ├── realesrgan-x4plus.param
│   └── ...
└── version.txt               # 版本号（可选，格式：v0.2.0）
```

App 优先使用内嵌版本，无需联网。

### 检查更新

点击「检查更新」按钮可查询 GitHub 是否有新版本，有新版时显示橙色徽章并提供「立即更新」按钮。

---

## 🔑 GitHub Token 配置

自动下载功能通过 GitHub API 获取最新 release 信息。匿名请求限速 **60 次/小时**，配置 Personal Access Token 后提升至 **5000 次/小时**。

### 配置步骤

1. 点击设置区右侧的 🔑 按钮展开 Token 输入区
2. 在 [GitHub Token 创建页面](https://github.com/settings/tokens/new?scopes=&description=IconKit) 创建一个无需任何权限的 Token
3. 将 Token 粘贴到输入框，点击「保存」
4. Token 存储于本地 `UserDefaults`，不会上传

> Token 格式：`ghp_xxxxxxxxxxxx`（classic）或 `github_pat_xxxxxxxxxxxx`（fine-grained）

---

## ⌨️ 快捷键

| 操作 | 快捷键 | 说明 |
|------|--------|------|
| 选择图片 | `⌘O` | 打开文件选择面板（应用图标模块） |
| 导出图标 | `⇧⌘E` | 触发导出（需已选图片且勾选平台） |

---

## 🎨 图像质量说明

| 项目 | 规格 |
|------|------|
| 色彩空间 | **sRGB**，保证跨设备颜色一致性 |
| 缩放算法 | **高质量插值**（`CGInterpolationQuality.high`） |
| PNG 输出 | 保留透明通道（`premultipliedLast` alpha） |
| JPEG 输出 | 白色背景填充，压缩质量 0.9 |
| 位深度 | 8 bits/channel |

---

## 📁 项目结构

```
IconKit/
├── IconKit.xcodeproj/
└── IconKit/
    ├── IconKitApp.swift            # App 入口，窗口配置，菜单命令
    ├── RootView.swift              # 导航分栏根视图（侧边栏 + 详情区）
    ├── ScaleReducerView.swift      # 多倍图缩放界面（批量处理、AI 放大）
    ├── Exporter.swift              # Apple 图标规格定义与导出逻辑
    ├── AndroidExporter.swift       # Android mipmap 图标导出逻辑
    ├── ImageResizer.swift          # 图像渲染核心（PNG/JPEG，sRGB，高质量插值）
    ├── RealESRGANManager.swift     # Real-ESRGAN 下载、安装、版本管理
    ├── RealESRGANInstallView.swift # Real-ESRGAN 安装状态 UI 组件
    ├── Info.plist                  # App 配置
    └── Assets.xcassets/            # 图标资源
```

### 核心模块说明

#### [`RealESRGANManager`](IconKit/RealESRGANManager.swift)

`@MainActor` 单例，负责：
- 检测内嵌/已下载二进制的可用性
- 从 GitHub API 获取最新 release 并下载 macOS 版 zip
- 解压、查找二进制、设置可执行权限
- 版本管理与更新检查
- 系统代理感知（`CFNetworkCopySystemProxySettings`）

#### [`ScaleReducerView`](IconKit/ScaleReducerView.swift)

主要处理流程：
1. 读取图片（后台线程，避免阻塞主线程）
2. 根据文件名后缀判断 @scale 类型
3. 调用 `aiUpscaleTo4x()` 进行 AI 放大（失败则回退插值）
4. 使用 `renderPNGExact()` 渲染目标尺寸 PNG

#### [`ImageResizer`](IconKit/ImageResizer.swift)

提供三个核心方法：
- `renderPNG(from:pixelSize:)` — 正方形 PNG，透明背景，aspect-fit
- `renderJPEG(from:pixelSize:quality:)` — 正方形 JPEG，白色背景
- `pixelSize(of:)` — 获取图片像素尺寸（支持多分辨率 TIFF、PDF/矢量图回退）

---

## 🚀 快速开始

```bash
# 1. 克隆项目
git clone <repo-url>
cd IconKit

# 2. 用 Xcode 打开
open IconKit.xcodeproj

# 3. 选择 scheme: IconKit，目标: My Mac
# 4. 运行 ⌘R

# 或直接命令行编译
xcodebuild -project IconKit.xcodeproj -scheme IconKit -configuration Debug build
```

**最低要求：**
- macOS 14.0 Sonoma 或更高
- Xcode 15.2 或更高
- 无第三方依赖（纯 Swift + AppKit/SwiftUI）

---

## ⚠️ 注意事项

1. **Real-ESRGAN 许可证**：`realesrgan-ncnn-vulkan` 为第三方开源工具，本项目仅做下载与调用封装，请遵守其 [BSD 3-Clause 许可证](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/blob/master/LICENSE)。

2. **沙盒环境**：若启用 App Sandbox，Real-ESRGAN 缓存目录会位于容器内：
   ```
   ~/Library/Containers/com.yourcompany.IconKit/Data/Library/Application Support/IconKit/realesrgan/
   ```

3. **Apple 图标文件名**：文件名包含 scale 标识（`1x`/`2x`/`3x`），不同 scale 的同尺寸图标不会互相覆盖。

4. **JPEG 输入**：ScaleReducer 支持 JPEG 输入，但输出统一为 PNG（保留透明通道）。

5. **@3x 源图的 AI 放大**：@3x 已是最高分辨率，AI 放大后再缩小与直接插值效果相近，主要用于保持代码路径一致性。

---

## 📋 更新记录

### 2026-06-03

**Bug 修复：**
- 🔴 修复 AI 放大参数错误：`-s 2` → `-s 4`，修复 @2x/@1x 输出尺寸错误（原来只放大了 2x，导致 @2x 输出缩小到原图 1x 大小）
- 🔴 修复 @3x 分支缺少 AI 放大逻辑，新增 `makeDownscaledFrom3x()` 函数，与 @2x/@1x 分支保持一致
- 🟠 修复内嵌版本号比较逻辑：去除 `"内嵌 "` 前缀后再与 GitHub tag 比较，防止每次启动都触发重复下载
- 🟠 修复 `@ObservedObject` 用法：`RealESRGANInstallView` 改为 `@StateObject`
- 🟠 修复同步 IO 阻塞主线程：`Data(contentsOf:)` 移至 `Task.detached` 后台执行
- 🟠 修复 `DispatchQueue.global` 混用：`RootView.runExport()` 改为 `Task + Task.detached`
- 🟡 修复并发检查竞争：新增 `currentCheckID` 防止 sleep 结束后错误清除反馈信息
- 🟡 修复 `leftPanel` 内 `VStack` 缩进不一致
- 🟡 删除 `AndroidExporter.swift` 重复注释
- 🟡 删除 `ContentView.swift` 死代码文件及 `project.pbxproj` 引用

### 2026-05-14

- **新增 `@1x` 放大支持**：`@1x` 图片可自动生成 `@2x` 和 `@3x`（AI 放大或插值）
- **优化 AI 调用**：`@1x` 放大时 AI 只跑一次，复用 4x 结果同时生成 2x 和 3x
- 修复 `AndroidExporter.swift` 函数闭合错误
- 修复 `RootView.swift` async/await 语法错误
- 清理 `RealESRGANManager.swift` 冗余代码

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
