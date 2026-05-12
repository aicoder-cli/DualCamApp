# DualCameraRecorder - 双摄像头录像应用

一个支持同时调用前后摄像头进行录像的iOS应用，支持自定义布局。

## 功能特性

### 📹 双摄像头录像
- 同时调用前置和后置摄像头
- 实时预览两个摄像头画面
- 支持录制时切换布局

### 🎨 自定义布局
- **画中画模式**：后置摄像头全屏，前置摄像头小窗口
- **左右分屏**：前后摄像头各占一半屏幕
- **上下分屏**：后置在上，前置在下
- **对角布局**：前后摄像头对角显示
- **后置主屏**：后置摄像头全屏，前置小窗口
- **前置主屏**：前置摄像头全屏，后置小窗口

### 🖐️ 交互功能
- 支持拖拽调整小窗口位置
- 录制中可实时切换布局
- 支持缩放后置摄像头
- 支持闪光灯控制

## 系统要求

- iOS 15.0+
- Xcode 15.0+
- Swift 5.0+
- 支持多摄像头的iOS设备（iPhone 7及以上）

## 项目结构

```
DualCameraRecorder/
├── DualCameraRecorder.xcodeproj/    # Xcode项目文件
├── DualCameraRecorder/
│   ├── App/
│   │   └── DualCameraRecorderApp.swift    # 应用入口
│   ├── Managers/
│   │   ├── CameraManager.swift     # 多摄像头管理器
│   │   ├── VideoRecorder.swift     # 视频录制引擎
│   │   └── LayoutManager.swift     # 布局管理器
│   ├── Views/
│   │   ├── ContentView.swift       # 主视图
│   │   ├── CameraPreviewView.swift # 摄像头预览视图
│   │   └── LayoutSelectorView.swift # 布局选择器
│   ├── Resources/
│   │   └── Assets.xcassets/        # 资源文件
│   └── Info.plist                  # 应用配置
└── README.md
```

## 核心模块说明

### CameraManager
负责管理前后摄像头会话：
- 初始化和配置AVCaptureSession
- 处理摄像头权限请求
- 提供预览层
- 管理摄像头控制（缩放、对焦、闪光灯）

### LayoutManager
负责管理双摄像头画面布局：
- 提供6种预设布局模板
- 支持自定义偏移和缩放
- 计算每个摄像头的布局信息

### VideoRecorder
负责视频录制和合成：
- 使用AVAssetWriter进行视频写入
- 实时合成双摄像头画面
- 根据布局类型生成最终视频
- 自动保存到相册

## 使用方法

1. 用Xcode打开 `DualCameraRecorder.xcodeproj`
2. 选择目标设备或模拟器
3. 点击运行按钮启动应用
4. 授权摄像头和麦克风权限
5. 选择喜欢的布局模式
6. 点击录制按钮开始录制
7. 再次点击停止录制，视频自动保存到相册

## 注意事项

- 多摄像头功能需要真机测试，模拟器不支持
- 首次使用需要授权摄像头、麦克风和相册权限
- 录制时建议使用画中画或分屏模式以获得最佳效果
- 视频分辨率为1080p (1920x1080)

## 技术栈

- **UI框架**: SwiftUI
- **摄像头**: AVFoundation (AVCaptureSession)
- **视频录制**: AVAssetWriter
- **布局**: 自定义布局管理器
- **最低支持版本**: iOS 15.0

## License

MIT License
