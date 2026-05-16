# DualCam 双摄录像

<p align="center">
  <img src="promo-preview.gif" width="320" alt="DualCam promo preview">
</p>

<p align="center">
  <strong>前后双视角，同步录制。</strong><br>
  面向创作者的 iOS 双摄录像 App：六种构图模板、录制中切换布局、自动保存到系统相册。
</p>

<p align="center">
  <a href="#视觉预览">视觉预览</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#核心能力">核心能力</a> ·
  <a href="#技术架构">技术架构</a> ·
  <a href="#国际化开发规范">国际化开发规范</a>
</p>

---

## 视觉预览

<p align="center">
  <img src="assets/appstore-zh-01.png" width="220" alt="DualCam App Store preview 1">
  <img src="assets/appstore-zh-03.png" width="220" alt="DualCam App Store preview 2">
  <img src="assets/appstore-zh-06.png" width="220" alt="DualCam App Store preview 3">
</p>

- 交互原型：[`prototype.html`](prototype.html)
- 推荐视频源文件：[`promo-video.html`](promo-video.html)
- 操作说明：[`使用指南.md`](使用指南.md)

## 快速开始

### 系统要求

| 项目 | 要求 |
| --- | --- |
| iOS | 15.0+ |
| Xcode | 15.0+ |
| Swift | 5.0 |
| 设备 | 需要支持多摄的 iPhone 真机验证 |

### 打开工程

从 `DualCamApp/` 目录打开 Xcode 工程：

```bash
open code/DualCamApp.xcodeproj
```

在 Xcode 中选择 Apple Developer Team，连接 iPhone 真机后运行 `DualCamApp` scheme。

> Simulator 可以用于 UI 与编译检查，但不能验证双摄同步采集、闪光灯、麦克风和相册写入等硬件行为。

## 核心能力

| 能力 | 说明 |
| --- | --- |
| 前后双摄同步 | 同时预览并录制后置现场与前置反应 |
| 六种布局模板 | 画中画、左右分屏、上下分屏、对角、后置主屏、前置主屏 |
| 录制中切换 | 录制不中断，构图选择保持可见且可切换 |
| 自由调整前置窗口 | 画中画类布局支持拖拽与尺寸调整 |
| 自动保存 | 输出 H.264 MP4，并保存到系统相册 |
| 中英双语 | 支持应用内语言选择，默认跟随系统 |

## 产品结构

```
code/
├── DualCamApp/
│   ├── App/                 # 应用入口、语言和设置状态
│   ├── Managers/            # 相机、录制、布局、作品管理
│   ├── Views/               # SwiftUI 主界面、预览、设置、作品页
│   ├── Resources/           # Assets、Localizable.strings、InfoPlist.strings
│   └── Info.plist           # 隐私权限说明
├── DualCamAppTests/         # 单元测试
├── DualCamApp.xcodeproj
└── DualCamApp.xctestplan
```

## 技术架构

- `SwiftUI` 承载主界面、设置页、作品页与状态绑定。
- `AVFoundation` 管理前后摄像头、麦克风、预览层和采样回调。
- `AVCaptureMultiCamSession` 支撑前后摄像头同步采集。
- `AVAssetWriter` 负责 H.264 / AAC 合成输出。
- `PHPhotoLibrary` 负责录制完成后的相册保存。

关键实现文件：

| 文件 | 责任 |
| --- | --- |
| `code/DualCamApp/App/DualCamApp.swift` | SwiftUI app entry |
| `code/DualCamApp/Views/ContentView.swift` | 主界面状态组合与录制操作入口 |
| `code/DualCamApp/Managers/CameraManager.swift` | 前后摄像头 session、权限、预览层、采样回调 |
| `code/DualCamApp/Managers/LayoutManager.swift` | 六种布局模型和预览 frame 计算 |
| `code/DualCamApp/Managers/VideoRecorder.swift` | 双路画面合成、编码、相册保存 |
| `code/DualCamApp/Views/CameraPreviewView.swift` | `AVCaptureVideoPreviewLayer` 到 SwiftUI 的桥接 |

## 国际化开发规范

本项目把国际化作为功能开发的一部分，新增或修改功能时需要同步处理英文和简体中文文案。

- 用户可见文案不要硬编码在 SwiftUI 视图、管理器、弹窗、错误提示、设置页或引导页中。
- SwiftUI 文案使用 `code/DualCamApp/Resources/en.lproj/Localizable.strings` 和 `code/DualCamApp/Resources/zh-Hans.lproj/Localizable.strings` 中的 key。
- 管理器、错误信息等非 SwiftUI 文案使用 `L10n.string(...)`，确保应用内语言切换后文案一致。
- `LayoutType`、`CaptureMode` 等枚举保留稳定技术标识，展示标题和描述使用独立 localization key。
- 新增隐私权限能力时，同时更新 `Info.plist` 默认英文说明，以及 `en.lproj/InfoPlist.strings`、`zh-Hans.lproj/InfoPlist.strings`。
- 涉及文案的改动提交前，使用 `plutil -lint` 校验变更过的 `.strings` 文件，并尽量检查中英文界面显示效果。

## 本地文档资产

当前文档包复用了项目内已有设计资产，并集中复制到 `doc/assets/`：

- Split Capture app icon
- App Store 中文预览图
- 主交互原型 overview / flow
- 最大画框方案截图
- 官网首页与产品页截图

这些素材用于 README、使用指南、交互原型和推荐视频，避免文档与产品视觉系统脱节。
