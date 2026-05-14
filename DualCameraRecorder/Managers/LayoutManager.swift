//
//  LayoutManager.swift
//  DualCameraRecorder
//
//  布局管理器 - 负责管理双摄像头画面的布局方式
//

import SwiftUI

/// 预设布局类型
enum LayoutType: String, CaseIterable, Identifiable {
    case splitVertical
    case splitHorizontal
    case pictureInPicture
    case circleReaction
    case directorStack
    case diagonalCut

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .splitVertical: return "rectangle.split.2x1"
        case .splitHorizontal: return "rectangle.split.1x2"
        case .pictureInPicture: return "rectangle.on.rectangle"
        case .circleReaction: return "circle.inset.filled"
        case .directorStack: return "square.stack.3d.up.fill"
        case .diagonalCut: return "square.stack.3d.down.right"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .splitVertical: return "layout.splitVertical.title"
        case .splitHorizontal: return "layout.splitHorizontal.title"
        case .pictureInPicture: return "layout.pictureInPicture.title"
        case .circleReaction: return "layout.circleReaction.title"
        case .directorStack: return "layout.directorStack.title"
        case .diagonalCut: return "layout.diagonalCut.title"
        }
    }

    var shortTitleKey: LocalizedStringKey {
        switch self {
        case .splitVertical: return "layout.splitVertical.shortTitle"
        case .splitHorizontal: return "layout.splitHorizontal.shortTitle"
        case .pictureInPicture: return "layout.pictureInPicture.shortTitle"
        case .circleReaction: return "layout.circleReaction.shortTitle"
        case .directorStack: return "layout.directorStack.shortTitle"
        case .diagonalCut: return "layout.diagonalCut.shortTitle"
        }
    }

    var descriptionKey: LocalizedStringKey {
        switch self {
        case .splitVertical: return "layout.splitVertical.description"
        case .splitHorizontal: return "layout.splitHorizontal.description"
        case .pictureInPicture: return "layout.pictureInPicture.description"
        case .circleReaction: return "layout.circleReaction.description"
        case .directorStack: return "layout.directorStack.description"
        case .diagonalCut: return "layout.diagonalCut.description"
        }
    }

    static func from(_ rawValue: String) -> LayoutType {
        LayoutType(rawValue: rawValue) ?? .pictureInPicture
    }
}

/// 摄像头裁剪形状
enum CameraClipShape: String, CaseIterable, Identifiable {
    case rectangle
    case roundedRectangle
    case circle
    case diagonalLeading
    case diagonalTrailing

    var id: String { rawValue }

    var displayNameKey: LocalizedStringKey {
        switch self {
        case .rectangle: return "shape.square"
        case .roundedRectangle: return "shape.rounded"
        case .circle: return "shape.circle"
        case .diagonalLeading, .diagonalTrailing: return "shape.diagonal"
        }
    }
}

/// 单个摄像头视图的布局信息
struct CameraLayoutInfo {
    var frame: CGRect
    var zIndex: Double
    var cornerRadius: CGFloat
    var showBorder: Bool
    var clipShape: CameraClipShape
}

struct RecordingLayoutSnapshot {
    let front: CameraLayoutInfo
    let back: CameraLayoutInfo
    let outputSize: CGSize
}

/// 布局管理器
class LayoutManager: ObservableObject {

    // MARK: - Published Properties
    @Published var currentLayout: LayoutType = .pictureInPicture
    @Published var frontCameraOffset: CGSize = .zero
    @Published var backCameraOffset: CGSize = .zero
    @Published var frontCameraScale: CGFloat = 1.0
    @Published var backCameraScale: CGFloat = 1.0
    @Published var floatingHorizontalPosition: CGFloat = 0.76
    @Published var floatingVerticalPosition: CGFloat = 0.72
    @Published var floatingSize: CGFloat = 0.34
    @Published var floatingShape: CameraClipShape = .roundedRectangle

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
    let defaultPiPScale: CGFloat = 0.34

    // MARK: - Layout Calculations

    /// 获取前置摄像头的布局信息
    func getFrontCameraLayout() -> CameraLayoutInfo {
        let baseLayout = getBaseLayout(for: .front)
        let scaledFrame = scaleFrame(baseLayout.frame, scale: frontCameraScale)
        let offsetFrame = offsetFrame(scaledFrame, offset: frontCameraOffset)

        return CameraLayoutInfo(
            frame: offsetFrame,
            zIndex: baseLayout.zIndex,
            cornerRadius: baseLayout.cornerRadius,
            showBorder: baseLayout.showBorder,
            clipShape: baseLayout.clipShape
        )
    }

    /// 获取后置摄像头的布局信息
    func getBackCameraLayout() -> CameraLayoutInfo {
        let baseLayout = getBaseLayout(for: .back)
        let scaledFrame = scaleFrame(baseLayout.frame, scale: backCameraScale)
        let offsetFrame = offsetFrame(scaledFrame, offset: backCameraOffset)

        return CameraLayoutInfo(
            frame: offsetFrame,
            zIndex: baseLayout.zIndex,
            cornerRadius: baseLayout.cornerRadius,
            showBorder: baseLayout.showBorder,
            clipShape: baseLayout.clipShape
        )
    }

    /// 获取基础布局（根据布局类型）
    private func getBaseLayout(for camera: CameraType) -> CameraLayoutInfo {
        guard containerSize.width > 0 && containerSize.height > 0 else {
            return CameraLayoutInfo(frame: .zero, zIndex: 0, cornerRadius: 0, showBorder: false, clipShape: .rectangle)
        }

        let width = containerSize.width
        let height = containerSize.height

        switch currentLayout {
        case .splitVertical:
            let halfWidth = width / 2
            let frame = camera == .front
                ? CGRect(x: 0, y: 0, width: halfWidth, height: height)
                : CGRect(x: halfWidth, y: 0, width: halfWidth, height: height)
            return CameraLayoutInfo(frame: frame, zIndex: camera == .front ? 2 : 1, cornerRadius: 0, showBorder: false, clipShape: .rectangle)

        case .splitHorizontal:
            let halfHeight = height / 2
            let frame = camera == .front
                ? CGRect(x: 0, y: halfHeight, width: width, height: halfHeight)
                : CGRect(x: 0, y: 0, width: width, height: halfHeight)
            return CameraLayoutInfo(frame: frame, zIndex: camera == .front ? 2 : 1, cornerRadius: 0, showBorder: false, clipShape: .rectangle)

        case .pictureInPicture:
            if camera == .front {
                return floatingLayout(clipShape: floatingShape)
            }
            return CameraLayoutInfo(frame: CGRect(x: 0, y: 0, width: width, height: height), zIndex: 1, cornerRadius: 0, showBorder: false, clipShape: .rectangle)

        case .circleReaction:
            if camera == .front {
                return floatingLayout(clipShape: .circle)
            }
            return CameraLayoutInfo(frame: CGRect(x: 0, y: 0, width: width, height: height), zIndex: 1, cornerRadius: 0, showBorder: false, clipShape: .rectangle)

        case .directorStack:
            if camera == .front {
                return CameraLayoutInfo(
                    frame: CGRect(x: width * 0.24, y: height * 0.16, width: width * 0.72, height: height * 0.68),
                    zIndex: 2,
                    cornerRadius: 28,
                    showBorder: true,
                    clipShape: .roundedRectangle
                )
            }
            return CameraLayoutInfo(
                frame: CGRect(x: width * 0.04, y: height * 0.06, width: width * 0.72, height: height * 0.68),
                zIndex: 1,
                cornerRadius: 28,
                showBorder: true,
                clipShape: .roundedRectangle
            )

        case .diagonalCut:
            let shape: CameraClipShape = camera == .front ? .diagonalTrailing : .diagonalLeading
            return CameraLayoutInfo(
                frame: CGRect(x: 0, y: 0, width: width, height: height),
                zIndex: camera == .front ? 2 : 1,
                cornerRadius: 0,
                showBorder: false,
                clipShape: shape
            )
        }
    }

    private func floatingLayout(clipShape: CameraClipShape) -> CameraLayoutInfo {
        let width = containerSize.width
        let height = containerSize.height
        let clampedSize = min(max(floatingSize, 0.22), 0.56)
        let viewWidth = width * clampedSize
        let viewHeight = clipShape == .circle ? viewWidth : height * clampedSize
        let x = width * floatingHorizontalPosition - viewWidth / 2
        let y = height * floatingVerticalPosition - viewHeight / 2
        let radius = clipShape == .rectangle ? 0 : 24

        return CameraLayoutInfo(
            frame: CGRect(x: x, y: y, width: viewWidth, height: viewHeight),
            zIndex: 2,
            cornerRadius: CGFloat(radius),
            showBorder: true,
            clipShape: clipShape
        )
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
            resetTransforms()
        }
    }

    /// 重置变换
    func resetTransforms() {
        frontCameraOffset = .zero
        backCameraOffset = .zero
        frontCameraScale = 1.0
        backCameraScale = 1.0
        if currentLayout == .pictureInPicture || currentLayout == .circleReaction {
            floatingSize = defaultPiPScale
        }
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

    func makeRecordingLayoutSnapshot(outputSize: CGSize) -> RecordingLayoutSnapshot {
        let sourceSize = containerSize == .zero ? outputSize : containerSize
        let scale = min(outputSize.width / sourceSize.width, outputSize.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (outputSize.width - scaledSize.width) / 2,
            y: (outputSize.height - scaledSize.height) / 2
        )

        return RecordingLayoutSnapshot(
            front: scaledLayout(getFrontCameraLayout(), scale: scale, origin: origin),
            back: scaledLayout(getBackCameraLayout(), scale: scale, origin: origin),
            outputSize: outputSize
        )
    }

    private func scaledLayout(_ layout: CameraLayoutInfo, scale: CGFloat, origin: CGPoint) -> CameraLayoutInfo {
        CameraLayoutInfo(
            frame: CGRect(
                x: origin.x + layout.frame.origin.x * scale,
                y: origin.y + layout.frame.origin.y * scale,
                width: layout.frame.width * scale,
                height: layout.frame.height * scale
            ),
            zIndex: layout.zIndex,
            cornerRadius: layout.cornerRadius * scale,
            showBorder: layout.showBorder,
            clipShape: layout.clipShape
        )
    }

    var currentLayoutDescriptionKey: LocalizedStringKey {
        currentLayout.descriptionKey
    }
}

// CameraType 定义在 CameraManager.swift 中，此处不再重复声明
