//
//  CameraPreviewView.swift
//  DualCamApp
//
//  摄像头预览视图 - 使用UIViewRepresentable包装AVCaptureVideoPreviewLayer（清新风格）
//

import SwiftUI
import AVFoundation

/// 摄像头预览视图
struct CameraPreviewView: UIViewRepresentable {

    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewLayerHostView {
        let view = PreviewLayerHostView()
        view.setPreviewLayer(previewLayer)
        configurePreviewOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewLayerHostView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
        configurePreviewOrientation()
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }

    static func dismantleUIView(_ uiView: PreviewLayerHostView, coordinator: ()) {
        uiView.removePreviewLayer()
    }

    private func configurePreviewOrientation() {
        previewLayer.videoGravity = .resizeAspectFill

        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = .portrait
    }
}

final class PreviewLayerHostView: UIView {

    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        clipsToBounds = true
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        if previewLayer === layer, layer.superlayer === self.layer {
            updatePreviewLayerFrame()
            return
        }

        previewLayer?.removeFromSuperlayer()

        if layer.superlayer !== self.layer {
            layer.removeFromSuperlayer()
            self.layer.addSublayer(layer)
        }

        previewLayer = layer
        layer.videoGravity = .resizeAspectFill
        setNeedsLayout()
        layoutIfNeeded()
    }

    func removePreviewLayer() {
        guard previewLayer?.superlayer === layer else {
            previewLayer = nil
            return
        }

        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewLayerFrame()
    }

    private func updatePreviewLayerFrame() {
        guard let previewLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

/// 可拖拽的摄像头预览视图
struct DraggableCameraPreview: View {

    let previewLayer: AVCaptureVideoPreviewLayer
    let layoutInfo: CameraLayoutInfo
    let isDraggable: Bool
    let onDragChanged: ((CGSize) -> Void)?
    let onDragEnded: (() -> Void)?

    @State private var offset: CGSize = .zero

    var body: some View {
        CameraPreviewView(previewLayer: previewLayer)
            .frame(width: layoutInfo.frame.width, height: layoutInfo.frame.height)
            .demoClip(layoutInfo)
            .demoBorder(layoutInfo, isActive: offset != .zero)
            .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 10)
            .position(
                x: layoutInfo.frame.midX + offset.width,
                y: layoutInfo.frame.midY + offset.height
            )
            .zIndex(layoutInfo.zIndex)
            .gesture(
                isDraggable ?
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                        onDragChanged?(value.translation)
                    }
                    .onEnded { _ in
                        onDragEnded?()
                        offset = .zero
                    }
                : nil
            )
    }
}

/// 双摄像头预览容器
struct DualCameraPreviewContainer: View {

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var layoutManager: LayoutManager
    var didFinishStartupAttempt = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                previewBackdrop

                if cameraManager.backCameraReady {
                    DemoCameraLayer(
                        previewLayer: cameraManager.getBackPreviewLayer(),
                        layoutInfo: layoutManager.getBackCameraLayout(),
                        cameraType: .back,
                        layoutManager: layoutManager
                    )
                }

                if cameraManager.frontCameraReady {
                    DemoCameraLayer(
                        previewLayer: cameraManager.getFrontPreviewLayer(),
                        layoutInfo: layoutManager.getFrontCameraLayout(),
                        cameraType: .front,
                        layoutManager: layoutManager
                    )
                }

                if !cameraManager.frontCameraReady && !cameraManager.backCameraReady {
                    if didFinishStartupAttempt {
                        CameraUnavailableView()
                    } else {
                        WaitingCameraView()
                    }
                }
            }
            .clipped()
            .onAppear {
                layoutManager.containerSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                layoutManager.containerSize = newSize
            }
        }
    }

    private var previewBackdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.025, blue: 0.035),
                Color(red: 0.08, green: 0.09, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DemoCameraLayer: View {

    let previewLayer: AVCaptureVideoPreviewLayer
    let layoutInfo: CameraLayoutInfo
    let cameraType: CameraType
    @ObservedObject var layoutManager: LayoutManager

    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    private var isDraggable: Bool {
        cameraType == .front && [.pictureInPicture, .circleReaction, .directorStack].contains(layoutManager.currentLayout)
    }

    var body: some View {
        CameraPreviewView(previewLayer: previewLayer)
            .frame(width: layoutInfo.frame.width, height: layoutInfo.frame.height)
            .demoClip(layoutInfo)
            .demoBorder(layoutInfo, isActive: isDragging)
            .shadow(color: .black.opacity(layoutInfo.showBorder ? 0.35 : 0), radius: 18, x: 0, y: 10)
            .position(
                x: layoutInfo.frame.midX + dragOffset.width,
                y: layoutInfo.frame.midY + dragOffset.height
            )
            .zIndex(layoutInfo.zIndex)
            .gesture(isDraggable ? dragGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                withAnimation(.interactiveSpring()) {
                    isDragging = true
                    dragOffset = value.translation
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isDragging = false
                    layoutManager.updateFrontCameraOffset(dragOffset)
                    dragOffset = .zero
                }
            }
    }
}

private struct WaitingCameraView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.84, green: 1.0, blue: 0.30)))
                .scaleEffect(0.9)

            Text("camera.waiting")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
        }
    }
}

private struct CameraUnavailableView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.slash")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(Color(red: 0.84, green: 1.0, blue: 0.30))

            Text("camera.unavailable.title")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("camera.unavailable.body")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
    }
}

private struct DiagonalLeadingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DiagonalTrailingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension View {
    @ViewBuilder
    func demoClip(_ layoutInfo: CameraLayoutInfo) -> some View {
        switch layoutInfo.clipShape {
        case .rectangle:
            self.clipped()
        case .roundedRectangle:
            self.clipShape(RoundedRectangle(cornerRadius: layoutInfo.cornerRadius, style: .continuous))
        case .circle:
            self.clipShape(Circle())
        case .diagonalLeading:
            self.clipShape(DiagonalLeadingShape())
        case .diagonalTrailing:
            self.clipShape(DiagonalTrailingShape())
        }
    }

    @ViewBuilder
    func demoBorder(_ layoutInfo: CameraLayoutInfo, isActive: Bool) -> some View {
        let borderColor = isActive ? Color(red: 0.84, green: 1.0, blue: 0.30) : Color.white.opacity(0.22)
        let lineWidth: CGFloat = layoutInfo.showBorder ? (isActive ? 2 : 1) : 0

        switch layoutInfo.clipShape {
        case .rectangle:
            self.overlay(Rectangle().stroke(borderColor, lineWidth: lineWidth))
        case .roundedRectangle:
            self.overlay(RoundedRectangle(cornerRadius: layoutInfo.cornerRadius, style: .continuous).stroke(borderColor, lineWidth: lineWidth))
        case .circle:
            self.overlay(Circle().stroke(borderColor, lineWidth: lineWidth))
        case .diagonalLeading:
            self.overlay(DiagonalLeadingShape().stroke(Color.white.opacity(0.18), lineWidth: 1))
        case .diagonalTrailing:
            self.overlay(DiagonalTrailingShape().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }
}

/// 录制指示器 — 胶丸药丸风格
struct RecordingIndicator: View {

    let duration: String
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.16, blue: 0.20))
                    .frame(width: 10, height: 10)

                Circle()
                    .fill(Color(red: 0.95, green: 0.16, blue: 0.20))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.9 : 1.0)
                    .opacity(isPulsing ? 0 : 0.4)
            }

            Text(duration)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

/// 缩放控制视图
struct ZoomControlView: View {

    @Binding var zoomFactor: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.magnifyingglass")
                .foregroundColor(.white)

            Slider(value: $zoomFactor, in: minZoom...maxZoom)
                .accentColor(.white)
                .frame(width: 100)
                .rotationEffect(.degrees(-90))
                .frame(height: 100)

            Image(systemName: "minus.magnifyingglass")
                .foregroundColor(.white)

            Text(String(format: "%.1fx", zoomFactor))
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Text("preview.cameraPreview")
                .foregroundColor(.white)

            Spacer()
        }
    }
}
