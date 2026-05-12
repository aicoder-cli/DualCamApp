//
//  LayoutManager.swift
//  DualCameraRecorder
//
//  布局管理器 - 负责管理双摄像头画面的布局方式
//

import SwiftUI

/// 预设布局类型
enum LayoutType: String, CaseIterable, Identifiable {
    case pictureInPicture = "画中画"
    case sideBySide = "左右分屏"
    case topBottom = "上下分屏"
    case diagonal = "对角布局"
    case focusBack = "后置主屏"
    case focusFront = "前置主屏"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .pictureInPicture: return "rectangle.on.rectangle"
        case .sideBySide: return "rectangle.split.3x3"
        case .topBottom: return "rectangle.split.3x1"
        case .diagonal: return "rectangle.on.rectangle.angle"
        case .focusBack: return "video.fill"
        case .focusFront: return "person.fill"
        }
    }
}

/// 单个摄像头视图的布局信息
struct CameraLayoutInfo {
    var frame: CGRect
    var zIndex: Double
    var cornerRadius: CGFloat
    var showBorder: Bool
}

/// 布局管理器
class LayoutManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentLayout: LayoutType = .pictureInPicture
    @Published var frontCameraOffset: CGSize = .zero
    @Published var backCameraOffset: CGSize = .zero
    @Published var frontCameraScale: CGFloat = 1.0
    @Published var backCameraScale: CGFloat = 1.0
    
    // 拖拽状态
    @Published var isDraggingFront = false
    @Published var isDraggingBack = false
    @Published var isResizingFront = false
    @Published var isResizingBack = false
    
    // 布局边界
    @Published var containerSize: CGSize = .zero
    
    // MARK: - Constants
    let minScale: CGFloat = 0.3
    let maxScale: CGFloat = 1.5
    let defaultPiPScale: CGFloat = 0.35
    
    // MARK: - Layout Calculations
    
    /// 获取前置摄像头的布局信息
    func getFrontCameraLayout() -> CameraLayoutInfo {
        let baseFrame = getBaseFrame(for: .front)
        let scaledFrame = scaleFrame(baseFrame, scale: frontCameraScale)
        let offsetFrame = offsetFrame(scaledFrame, offset: frontCameraOffset)
        
        return CameraLayoutInfo(
            frame: offsetFrame,
            zIndex: currentLayout == .focusFront ? 1 : 2,
            cornerRadius: currentLayout == .pictureInPicture ? 12 : 0,
            showBorder: currentLayout == .pictureInPicture
        )
    }
    
    /// 获取后置摄像头的布局信息
    func getBackCameraLayout() -> CameraLayoutInfo {
        let baseFrame = getBaseFrame(for: .back)
        let scaledFrame = scaleFrame(baseFrame, scale: backCameraScale)
        let offsetFrame = offsetFrame(scaledFrame, offset: backCameraOffset)
        
        return CameraLayoutInfo(
            frame: offsetFrame,
            zIndex: currentLayout == .focusBack ? 2 : 1,
            cornerRadius: 0,
            showBorder: false
        )
    }
    
    /// 获取基础帧（根据布局类型）
    private func getBaseFrame(for camera: CameraType) -> CGRect {
        guard containerSize.width > 0 && containerSize.height > 0 else {
            return .zero
        }
        
        let width = containerSize.width
        let height = containerSize.height
        
        switch currentLayout {
        case .pictureInPicture:
            if camera == .front {
                // 前置摄像头在右下角，小窗口
                let pipWidth = width * defaultPiPScale
                let pipHeight = height * defaultPiPScale
                let x = width - pipWidth - 20
                let y = height - pipHeight - 80
                return CGRect(x: x, y: y, width: pipWidth, height: pipHeight)
            } else {
                // 后置摄像头全屏
                return CGRect(x: 0, y: 0, width: width, height: height)
            }
            
        case .sideBySide:
            let halfWidth = width / 2
            if camera == .front {
                return CGRect(x: 0, y: 0, width: halfWidth, height: height)
            } else {
                return CGRect(x: halfWidth, y: 0, width: halfWidth, height: height)
            }
            
        case .topBottom:
            let halfHeight = height / 2
            if camera == .front {
                return CGRect(x: 0, y: halfHeight, width: width, height: halfHeight)
            } else {
                return CGRect(x: 0, y: 0, width: width, height: halfHeight)
            }
            
        case .diagonal:
            if camera == .front {
                let smallWidth = width * 0.4
                let smallHeight = height * 0.4
                return CGRect(x: 20, y: 60, width: smallWidth, height: smallHeight)
            } else {
                let smallWidth = width * 0.4
                let smallHeight = height * 0.4
                let x = width - smallWidth - 20
                let y = height - smallHeight - 80
                return CGRect(x: x, y: y, width: smallWidth, height: smallHeight)
            }
            
        case .focusBack:
            if camera == .front {
                let smallWidth = width * 0.3
                let smallHeight = height * 0.3
                return CGRect(x: 20, y: 60, width: smallWidth, height: smallHeight)
            } else {
                return CGRect(x: 0, y: 0, width: width, height: height)
            }
            
        case .focusFront:
            if camera == .front {
                return CGRect(x: 0, y: 0, width: width, height: height)
            } else {
                let smallWidth = width * 0.3
                let smallHeight = height * 0.3
                let x = width - smallWidth - 20
                let y = height - smallHeight - 80
                return CGRect(x: x, y: y, width: smallWidth, height: smallHeight)
            }
        }
    }
    
    /// 缩放帧
    private func scaleFrame(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let clampedScale = min(max(scale, minScale), maxScale)
        let newWidth = frame.width * clampedScale
        let newHeight = frame.height * clampedScale
        let newX = frame.midX - newWidth / 2
        let newY = frame.midY - newHeight / 2
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }
    
    /// 偏移帧
    private func offsetFrame(_ frame: CGRect, offset: CGSize) -> CGRect {
        return CGRect(
            x: frame.origin.x + offset.width,
            y: frame.origin.y + offset.height,
            width: frame.size.width,
            height: frame.size.height
        )
    }
    
    // MARK: - Layout Actions
    
    /// 切换布局
    func switchLayout(to layout: LayoutType) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentLayout = layout
            // 重置偏移和缩放
            resetTransforms()
        }
    }
    
    /// 重置变换
    func resetTransforms() {
        frontCameraOffset = .zero
        backCameraOffset = .zero
        frontCameraScale = currentLayout == .pictureInPicture ? defaultPiPScale : 1.0
        backCameraScale = 1.0
    }
    
    /// 更新前置摄像头偏移
    func updateFrontCameraOffset(_ translation: CGSize) {
        frontCameraOffset = CGSize(
            width: frontCameraOffset.width + translation.width,
            height: frontCameraOffset.height + translation.height
        )
    }
    
    /// 更新后置摄像头偏移
    func updateBackCameraOffset(_ translation: CGSize) {
        backCameraOffset = CGSize(
            width: backCameraOffset.width + translation.width,
            height: backCameraOffset.height + translation.height
        )
    }
    
    /// 更新前置摄像头缩放
    func updateFrontCameraScale(_ scale: CGFloat) {
        frontCameraScale = min(max(scale, minScale), maxScale)
    }
    
    /// 更新后置摄像头缩放
    func updateBackCameraScale(_ scale: CGFloat) {
        backCameraScale = min(max(scale, minScale), maxScale)
    }
    
    /// 检查点是否在指定摄像头区域内
    func isPointInCameraArea(_ point: CGPoint, for camera: CameraType) -> Bool {
        let layout = camera == .front ? getFrontCameraLayout() : getBackCameraLayout()
        return layout.frame.contains(point)
    }
    
    /// 获取当前布局的描述
    func getLayoutDescription() -> String {
        switch currentLayout {
        case .pictureInPicture:
            return "画中画模式：后置摄像头为主画面，前置摄像头为小窗口"
        case .sideBySide:
            return "左右分屏模式：前后摄像头各占一半屏幕"
        case .topBottom:
            return "上下分屏模式：后置在上，前置在下"
        case .diagonal:
            return "对角布局模式：前后摄像头对角显示"
        case .focusBack:
            return "后置主屏模式：后置摄像头全屏，前置小窗口"
        case .focusFront:
            return "前置主屏模式：前置摄像头全屏，后置小窗口"
        }
    }
}

// CameraType 定义在 CameraManager.swift 中，此处不再重复声明
