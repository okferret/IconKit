# IconKit (macOS)

一个轻量、可执行的 macOS（SwiftUI）图标工具集：

- **ScaleReducer**：将 `@3x/@2x` PNG 自动导出为 `@3x/@2x/1x` 三套资源；当输入为 `@2x` 时可选用 **Real-ESRGAN（realesrgan-ncnn-vulkan）** 提升放大质量（无需系统安装，首次使用自动下载）。
- **导出 Icon Sets**：从一张源图导出 Apple Asset Catalog（AppIcon.appiconset JSON）以及 Android mipmap/drawable 目录结构。

> 当前项目名与应用名：**IconKit**

---

## 功能概览

### 1) ScaleReducer（默认功能）

- **输入 @3x**：输出
  - `xxx@3x.png`（重新渲染一份）
  - `xxx@2x.png`（2/3 缩放）
  - `xxx.png`（1/3 缩放）
- **输入 @2x**：输出
  - `xxx@3x.png`（放大到 1.5x，优先走 Real-ESRGAN；失败则高质量插值）
  - `xxx@2x.png`（重新渲染一份）
  - `xxx.png`（1/2 缩放）
- **其他文件名**：输出
  - `xxx.png`

支持：
- 拖拽 PNG 到界面
- 或点击按钮选择文件
- 选择导出目录（同目录 / 指定目录）

### 2) 导出 Icon Sets

从一张源图导出：
- **Apple**：Asset Catalog 结构（含 `Contents.json`）
- **Android**：mipmap/drawable 结构

---

## Real-ESRGAN 集成说明（无需系统安装）

本项目通过 `RealESRGANManager.swift` 实现**按需下载**：

- 首次在 ScaleReducer 中开启“提升质量”并执行 `@2x → @3x` 放大时，会：
  1. 调用 GitHub API 获取 `xinntao/Real-ESRGAN-ncnn-vulkan` 最新 release
  2. 下载 macOS 对应 zip
  3. 解压到：
     
     `~/Library/Application Support/IconKit/realesrgan/`
  4. 之后直接复用本地缓存

如果下载/解压/执行失败，会自动回退到**高质量插值**放大，保证功能可用。

---

## 运行环境

- macOS（建议 13+）
- Xcode（建议 15+）
- SwiftUI

---

## 打开与运行

1. 解压项目
2. 打开 `IconKit.xcodeproj`
3. 选择 scheme：`IconKit`
4. 运行（⌘R）

---

## 项目结构

```
IconKit/
  IconKit.xcodeproj/
  IconKit/
    IconKitApp.swift
    RootView.swift
    ScaleReducerView.swift
    RealESRGANManager.swift
    ContentView.swift
    Exporter.swift
    AndroidExporter.swift
    ImageResizer.swift
    Assets.xcassets/
      AppIcon.appiconset/
```

---

## 说明与注意事项

- `realesrgan-ncnn-vulkan` 为第三方工具：
  - 本项目仅做“下载 + 调用”封装
  - 具体许可/分发条款请以其上游仓库为准：
    - https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan
- 若你需要“完全离线打包”（不联网也能用 Real-ESRGAN），可以把二进制与 models 直接放入 App Bundle（Resources）并改为优先读取 Bundle 内资源。

---

## 更新时间

- 2026-04-16
