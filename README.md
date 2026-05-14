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
  <a href="#技术架构">技术架构</a> •
  <a href="#国际化开发规范">国际化开发规范</a>
</p>

---

## ✨ 功能特性

| 特性 | 说明 |
|------|------|
| 📹 **双摄像头同步** | 同时录制前置和后置摄像头画面 |
| 🎨 **6种布局模式** | 画中画 / 左右分屏 / 上下分屏 / 对角 / 后置主屏 / 前置主屏 |
| ✋ **自由拖拽** | 前置摄像头窗口可任意调整位置 |
| ⚡ **录制中切换** | 录制过程中实时切换布局，不中断录制 |
| 🌐 **中英文国际化** | 支持应用内语言选择，默认跟随系统语言 |
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
    ├── Assets.xcassets/
    ├── en.lproj/                 # 英文文案与权限说明
    └── zh-Hans.lproj/            # 简体中文文案与权限说明
```

### 核心技术

- **SwiftUI** - 声明式 UI 框架
- **AVFoundation** - 摄像头和录制引擎
- **AVCaptureMultiCamSession** - 多摄像头同步捕获
- **AVAssetWriter** - 视频合成与导出

## 🌐 国际化开发规范

本项目把国际化作为功能开发的一部分，新增或修改功能时需要同步处理英文和简体中文文案。

- 新增用户可见文案时，不要在 SwiftUI 视图、管理器、弹窗、错误提示、设置页或引导页中硬编码显示字符串。
- SwiftUI 文案使用 `Resources/en.lproj/Localizable.strings` 和 `Resources/zh-Hans.lproj/Localizable.strings` 中的 key。
- 管理器、错误信息等非 SwiftUI 文案使用 `L10n.string(...)`，确保应用内语言切换后文案一致。
- `LayoutType`、`CaptureMode` 等枚举保留稳定的技术标识，展示标题、描述、调试文案使用独立 localization key。
- 新增隐私权限能力时，同时更新 `Info.plist` 默认英文说明，以及 `en.lproj/InfoPlist.strings`、`zh-Hans.lproj/InfoPlist.strings`。
- 提交涉及文案的改动前，使用 `plutil -lint` 校验变更过的 `.strings` 文件，并尽量检查中英文界面显示效果。

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
