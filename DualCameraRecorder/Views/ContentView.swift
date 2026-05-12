//
//  ContentView.swift
//  DualCameraRecorder
//
//  主视图 - 整合所有功能模块（清新风格）
//

import SwiftUI

// MARK: - 设计令牌
private enum Design {
    static let accent = Color.blue.opacity(0.85)
    static let recordRed = Color(red: 0.95, green: 0.25, blue: 0.3)
    static let glass = Color.white.opacity(0.12)
    static let glassBorder = Color.white.opacity(0.25)
    static let pillShadow = Color.black.opacity(0.15)
    static let radius: CGFloat = 22
}

struct ContentView: View {
    
    // MARK: - State Objects
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var layoutManager = LayoutManager()
    @StateObject private var videoRecorder = VideoRecorder()
    
    // MARK: - State Variables
    @State private var showSettings = false
    @State private var isFlashOn = false
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 摄像头预览层
                DualCameraPreviewContainer(
                    cameraManager: cameraManager,
                    layoutManager: layoutManager
                )
                .ignoresSafeArea()
                
                // 顶部渐变遮罩 + 控制栏
                VStack {
                    TopControlBar(
                        isFlashOn: $isFlashOn,
                        showSettings: $showSettings,
                        onFlashToggle: { cameraManager.toggleFlash() }
                    )
                    Spacer()
                }
                
                // 录制指示器
                if videoRecorder.recordingState == .recording {
                    VStack {
                        Spacer()
                        RecordingIndicator(duration: videoRecorder.recordedDurationString)
                            .padding(.bottom, 160)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                // 底部控制面板
                VStack {
                    Spacer()
                    
                    if cameraManager.isSessionRunning {
                        LayoutToolbar(layoutManager: layoutManager)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    BottomControlBar(
                        recordingState: videoRecorder.recordingState,
                        onStartRecording: {
                            withAnimation(.spring(response: 0.3)) {
                                Task { await videoRecorder.startRecording() }
                            }
                        },
                        onStopRecording: {
                            withAnimation(.spring(response: 0.3)) {
                                Task { await videoRecorder.stopRecording() }
                            }
                        },
                        onSwitchCamera: {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                layoutManager.switchLayout(
                                    to: layoutManager.currentLayout == .focusFront ? .focusBack : .focusFront
                                )
                            }
                        }
                    )
                    .padding(.bottom, 20)
                }
                
                // 错误提示
                if let error = cameraManager.errorMessage ?? videoRecorder.errorMessage {
                    ErrorBanner(message: error) {
                        withAnimation { cameraManager.errorMessage = nil; videoRecorder.errorMessage = nil }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 加载指示器
                if !cameraManager.isSessionRunning && cameraManager.errorMessage == nil {
                    LoadingOverlay(message: "正在启动摄像头...")
                }
            }
        }
        .onAppear {
            Task { await cameraManager.startCapture() }
        }
        .onDisappear {
            cameraManager.stopCapture()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(cameraManager: cameraManager, layoutManager: layoutManager)
        }
    }
}

// MARK: - 顶部控制栏

private struct TopControlBar: View {
    
    @Binding var isFlashOn: Bool
    @Binding var showSettings: Bool
    let onFlashToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 渐变遮罩
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                HStack {
                    TopBarButton(icon: isFlashOn ? "bolt.fill" : "bolt.slash", isActive: isFlashOn) {
                        isFlashOn.toggle()
                        onFlashToggle()
                    }
                    
                    Spacer()
                    
                    TopBarButton(icon: "gearshape.fill", isActive: false) {
                        showSettings = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 52)
            }
        }
    }
}

/// 顶部栏按钮 — 胶丸毛玻璃风格
private struct TopBarButton: View {
    
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isActive ? .yellow : .white)
                .frame(width: 42, height: 42)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    Capsule()
                        .stroke(Design.glassBorder, lineWidth: 0.5)
                )
                .shadow(color: Design.pillShadow, radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - 底部控制栏

struct BottomControlBar: View {
    
    let recordingState: RecordingState
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onSwitchCamera: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 左侧：切换摄像头
            SideActionButton(icon: "camera.rotate.fill") {
                onSwitchCamera()
            }
            
            Spacer()
            
            // 中间：录制按钮
            RecordButton(
                recordingState: recordingState,
                onStart: onStartRecording,
                onStop: onStopRecording
            )
            
            Spacer()
            
            // 右侧：相册
            SideActionButton(icon: "photo.on.rectangle") {
                // 打开相册
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .stroke(Design.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: Design.pillShadow, radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
    }
}

/// 侧边操作按钮 — 圆角方形毛玻璃
private struct SideActionButton: View {
    
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - 录制按钮

struct RecordButton: View {
    
    let recordingState: RecordingState
    let onStart: () -> Void
    let onStop: () -> Void
    
    @State private var isPressed = false
    
    private var isRecording: Bool { recordingState == .recording }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                isRecording ? onStop() : onStart()
            }
        }) {
            ZStack {
                // 外圈光晕
                Circle()
                    .stroke(
                        isRecording
                            ? Design.recordRed.opacity(0.3)
                            : Color.white.opacity(0.15),
                        lineWidth: 2
                    )
                    .frame(width: 72, height: 72)
                
                // 录制中脉冲光环
                if isRecording {
                    Circle()
                        .stroke(Design.recordRed.opacity(0.15), lineWidth: 1)
                        .frame(width: 88, height: 88)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                }
                
                // 内部按钮
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Design.recordRed)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Design.recordRed)
                            .frame(width: 58, height: 58)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }
                }
                .scaleEffect(isPressed ? 0.88 : 1.0)
            }
        }
        .pressAction(onPress: { withAnimation(.easeInOut(duration: 0.12)) { isPressed = true } },
                      onRelease: { withAnimation(.easeInOut(duration: 0.12)) { isPressed = false } })
    }
    
    // 脉冲动画
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    var body_inner: some View {
        EmptyView()
            .onAppear {
                guard isRecording else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulseScale = 1.35
                    pulseOpacity = 0
                }
            }
            .onChange(of: isRecording) { _, recording in
                if recording {
                    pulseScale = 1.0
                    pulseOpacity = 0.6
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        pulseScale = 1.35
                        pulseOpacity = 0
                    }
                } else {
                    pulseScale = 1.0
                    pulseOpacity = 0
                }
            }
    }
}

// MARK: - 错误提示

struct ErrorBanner: View {
    
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 20)
            .padding(.top, 60)
            
            Spacer()
        }
    }
}

// MARK: - 加载遮罩

struct LoadingOverlay: View {
    
    let message: String
    @State private var isRotating = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            
            VStack(spacing: 18) {
                // 自定义加载动画
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                        .frame(width: 48, height: 48)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                colors: [Color.white.opacity(0.1), Color.white, Color.white.opacity(0.1)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(isRotating ? 360 : 0))
                }
                
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .onAppear { withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { isRotating = true } }
    }
}

// MARK: - 设置页

struct SettingsView: View {
    
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var layoutManager: LayoutManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    InfoRow(title: "前置摄像头", status: cameraManager.frontCameraReady)
                    InfoRow(title: "后置摄像头", status: cameraManager.backCameraReady)
                    InfoRow(title: "多摄像头支持", status: cameraManager.hasMultiCameraSupport)
                } header: {
                    Text("摄像头信息")
                }
                
                Section {
                    Text(layoutManager.getLayoutDescription())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text("当前布局")
                }
                
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct InfoRow: View {
    let title: String
    let status: Bool
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(status ? Color.green : Color.red.opacity(0.8))
                    .frame(width: 8, height: 8)
                Text(status ? "就绪" : "未就绪")
                    .foregroundColor(status ? .green : .secondary)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - 按压手势修饰器

extension View {
    func pressAction(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

#Preview {
    ContentView()
}
