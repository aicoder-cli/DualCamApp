//
//  CameraPreviewView.swift
//  DualCameraRecorder
//
//  摄像头预览视图 - 使用UIViewRepresentable包装AVCaptureVideoPreviewLayer（清新风格）
//

import SwiftUI
import AVFoundation

/// 摄像头预览视图
struct CameraPreviewView: UIViewRepresentable {
    
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
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
        GeometryReader { geometry in
            CameraPreviewView(previewLayer: previewLayer)
                .frame(width: layoutInfo.frame.width, height: layoutInfo.frame.height)
                .cornerRadius(layoutInfo.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: layoutInfo.cornerRadius)
                        .stroke(Color.white.opacity(0.2), lineWidth: layoutInfo.showBorder ? 1.5 : 0)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                .offset(
                    x: layoutInfo.frame.origin.x + offset.width,
                    y: layoutInfo.frame.origin.y + offset.height
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
                        }
                    : nil
                )
        }
    }
}

/// 双摄像头预览容器
struct DualCameraPreviewContainer: View {
    
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var layoutManager: LayoutManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 后置摄像头预览
                if cameraManager.backCameraReady {
                    CameraPreviewView(previewLayer: cameraManager.getBackPreviewLayer())
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    // 等待画面 — 深色渐变背景
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.08, blue: 0.12),
                            Color(red: 0.12, green: 0.12, blue: 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                                .scaleEffect(0.8)
                            Text("等待摄像头…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    )
                }
                
                // 前置摄像头预览（根据布局显示）
                if cameraManager.frontCameraReady {
                    FrontCameraOverlay(
                        previewLayer: cameraManager.getFrontPreviewLayer(),
                        layoutManager: layoutManager,
                        containerSize: geometry.size
                    )
                }
            }
            .onAppear {
                layoutManager.containerSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                layoutManager.containerSize = newSize
            }
        }
    }
}

/// 前置摄像头覆盖层 — 清新毛玻璃风格
struct FrontCameraOverlay: View {
    
    let previewLayer: AVCaptureVideoPreviewLayer
    @ObservedObject var layoutManager: LayoutManager
    let containerSize: CGSize
    
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        let layoutInfo = layoutManager.getFrontCameraLayout()
        
        CameraPreviewView(previewLayer: previewLayer)
            .frame(width: layoutInfo.frame.width, height: layoutInfo.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: layoutInfo.cornerRadius + 4))
            .overlay(
                // 柔和边框
                RoundedRectangle(cornerRadius: layoutInfo.cornerRadius + 4)
                    .stroke(
                        isDragging
                            ? Color.white.opacity(0.6)
                            : Color.white.opacity(0.2),
                        lineWidth: isDragging ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
            // 拖拽时额外发光
            .shadow(
                color: isDragging ? Color.white.opacity(0.12) : .clear,
                radius: 20, x: 0, y: 0
            )
            .offset(
                x: layoutInfo.frame.origin.x + dragOffset.width,
                y: layoutInfo.frame.origin.y + dragOffset.height
            )
            .zIndex(layoutInfo.zIndex)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        withAnimation(.interactiveSpring()) {
                            isDragging = true
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            isDragging = false
                            layoutManager.updateFrontCameraOffset(dragOffset)
                            dragOffset = .zero
                        }
                    }
            )
    }
}

/// 录制指示器 — 胶丸药丸风格
struct RecordingIndicator: View {
    
    let duration: String
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 脉冲红点
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.25, blue: 0.3))
                    .frame(width: 10, height: 10)
                
                Circle()
                    .fill(Color(red: 0.95, green: 0.25, blue: 0.3))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.8 : 1.0)
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
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
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
            Text("摄像头预览预览")
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}
