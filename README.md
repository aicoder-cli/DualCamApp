# 双摄录像

<p align="center">
  <img src="promo-preview.gif" width="300" alt="App Preview">
</p>

<p align="center">
  <strong>iOS 双摄像头录像应用</strong><br>
  同时调用前后摄像头 · 6种布局模式 · 一键录制
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#系统要求">系统要求</a> •
  <a href="#安装使用">安装使用</a> •
  <a href="#技术架构">技术架构</a>
</p>

---

## ✨ 功能特性

| 特性 | 说明 |
|------|------|
| 📹 **双摄像头同步** | 同时录制前置和后置摄像头画面 |
| 🎨 **6种布局模式** | 画中画 / 左右分屏 / 上下分屏 / 对角 / 后置主屏 / 前置主屏 |
| ✋ **自由拖拽** | 前置摄像头窗口可任意调整位置 |
| ⚡ **录制中切换** | 录制过程中实时切换布局，不中断录制 |
| 💾 **自动保存** | 录制完成自动保存到系统相册 |

## 📱 系统要求

- **iOS**: 15.0+
- **设备**: iPhone（多摄像头功能需真机）
- **Xcode**: 15.0+

## 🚀 安装使用

### 方式一：Xcode 编译（推荐）

```bash
# 克隆仓库
git clone https://github.com/aicoder-cli/DualCameraRecorder.git
cd DualCameraRecorder

# 用 Xcode 打开
open DualCameraRecorder.xcodeproj
```

1. 在 Xcode 中选择你的 **Apple Developer Team**
2. 连接 iPhone 真机
3. 点击 **Build & Run** (⌘R)

### 方式二：TestFlight（即将上线）

等待 TestFlight 公测版本发布...

## 🎮 使用指南

### 基本录制流程

1. **选择布局** - 点击底部工具栏选择喜欢的布局模式
2. **调整位置** - 拖拽前置摄像头窗口到合适位置
3. **开始录制** - 点击红色录制按钮
4. **结束录制** - 再次点击按钮，视频自动保存到相册

### 布局模式说明

| 布局 | 预览 |
|------|------|
| **画中画** | 后置全屏，前置小窗 |
| **左右分屏** | 前后各占一半 |
| **上下分屏** | 后置在上，前置在下 |
| **对角** | 前后对角排列 |
| **后置主屏** | 后置全屏，前置小窗 |
| **前置主屏** | 前置全屏，后置小窗 |

## 🏗 技术架构

```
DualCameraRecorder/
├── App/                          # 应用入口
│   └── DualCameraRecorderApp.swift
├── Managers/                     # 核心管理器
│   ├── CameraManager.swift       # 双摄像头管理
│   ├── VideoRecorder.swift       # 视频录制引擎
│   └── LayoutManager.swift       # 布局系统
├── Views/                        # UI 视图
│   ├── ContentView.swift         # 主界面
│   ├── CameraPreviewView.swift   # 摄像头预览
│   └── LayoutSelectorView.swift  # 布局选择器
└── Resources/                    # 资源文件
    └── Assets.xcassets/
```

### 核心技术

- **SwiftUI** - 声明式 UI 框架
- **AVFoundation** - 摄像头和录制引擎
- **AVCaptureMultiCamSession** - 多摄像头同步捕获
- **AVAssetWriter** - 视频合成与导出

## 📸 截图预览

<p align="center">
  <img src="promo-preview.gif" width="250" />
</p>

## 📝 更新日志

### v1.0.0
- ✅ 双摄像头同步录制
- ✅ 6种布局模式
- ✅ 自由拖拽调整
- ✅ 录制中切换布局
- ✅ 清新毛玻璃 UI

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可

MIT License

---

<p align="center">
  Made with ❤️ by AI Coder
</p>
