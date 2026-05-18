//
//  ContentView.swift
//  DualCamApp
//
//  主视图 - 整合所有功能模块（清新风格）
//

import SwiftUI

// MARK: - 设计令牌
private enum Design {
    static let background = Color(red: 0.02, green: 0.024, blue: 0.032)
    static let panel = Color.white.opacity(0.09)
    static let panelStroke = Color.white.opacity(0.14)
    static let accent = Color(red: 0.84, green: 1.0, blue: 0.30)
    static let recordRed = Color(red: 0.95, green: 0.16, blue: 0.20)
    static let mutedText = Color.white.opacity(0.56)
    static let pillShadow = Color.black.opacity(0.24)
    static let radius: CGFloat = 30
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .photo: return "capture.photo"
        case .video: return "capture.video"
        }
    }
}

enum ShootingFrameRate: Int, CaseIterable, Identifiable {
    case cinematic = 24
    case standard = 30
    case smooth = 60

    var id: Int { rawValue }
    var title: String { "\(rawValue) fps" }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .cinematic:
            return "frameRate.cinematic.subtitle"
        case .standard:
            return "frameRate.standard.subtitle"
        case .smooth:
            return "frameRate.smooth.subtitle"
        }
    }
}

struct ContentView: View {

    // MARK: - State Objects
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var layoutManager = LayoutManager()
    @StateObject private var videoRecorder = VideoRecorder()
    @StateObject private var worksManager = WorksManager()
    @StateObject private var captureFeedback = CaptureFeedbackService()

    // MARK: - State Variables
    @State private var showSettings = false
    @State private var showWorks = false
    @State private var showCustomizePanel = false
    @State private var isFlashOn = false
    @State private var isLivePhotoEnabled = false
    @State private var captureMode: CaptureMode = .video
    @State private var hasAppliedInitialPreferences = false
    @State private var recordingControlsRevealed = false
    @State private var hasShownStartupMinimumDuration = false
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @AppStorage(SettingsKey.defaultLivePhotoDuration) private var defaultLivePhotoDuration: Double = 2.5
    @AppStorage(SettingsKey.shootingFrameRate) private var shootingFrameRate: Int = 30
    @AppStorage(SettingsKey.defaultCaptureMode) private var defaultCaptureModeRaw = DefaultCaptureMode.video.rawValue
    @AppStorage(SettingsKey.defaultLayout) private var defaultLayoutRaw = LayoutType.pictureInPicture.rawValue
    @AppStorage(SettingsKey.rememberLastLayout) private var rememberLastLayout = true
    @AppStorage(SettingsKey.lastLayout) private var lastLayoutRaw = LayoutType.pictureInPicture.rawValue
    @AppStorage(SettingsKey.immersiveRecording) private var immersiveRecording = true
    @AppStorage(SettingsKey.controlRevealSeconds) private var controlRevealSeconds = ControlRevealDuration.twoSeconds.rawValue
    @AppStorage(SettingsKey.soundAndHapticsEnabled) private var soundAndHapticsEnabled = true

    private var isVideoRecording: Bool {
        captureMode == .video && videoRecorder.recordingState == .recording
    }

    private var isImmersiveRecordingActive: Bool {
        immersiveRecording && isVideoRecording
    }

    private var showsRecordingChrome: Bool {
        !isImmersiveRecordingActive || recordingControlsRevealed
    }

    private var shouldShowStartupLoading: Bool {
        cameraManager.errorMessage == nil && (!hasShownStartupMinimumDuration || (!cameraManager.didFinishStartupAttempt && !cameraManager.isSessionRunning))
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background

                previewCard(size: geometry.size)
                    .ignoresSafeArea()

                cameraChromeGradients

                VStack(spacing: 0) {
                    DemoHeader(
                        isReady: cameraManager.isSessionRunning,
                        isRecording: isVideoRecording,
                        showsModeSwitch: showsRecordingChrome,
                        captureMode: $captureMode,
                        showSettings: $showSettings
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 54)

                    if videoRecorder.recordingState == .recording {
                        RecordingIndicator(duration: videoRecorder.recordedDurationString)
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()

                    if (cameraManager.isSessionRunning || cameraManager.didFinishStartupAttempt) && showsRecordingChrome {
                        LayoutToolbar(layoutManager: layoutManager)
                            .padding(.bottom, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    BottomControlBar(
                        recordingState: videoRecorder.recordingState,
                        captureMode: captureMode,
                        latestWork: worksManager.latestWork,
                        showsSideControls: showsRecordingChrome,
                        onStartRecording: {
                            if captureMode == .video {
                                let frameRate = shootingFrameRate
                                Task<Void, Never> {
                                    await cameraManager.setPreferredFrameRate(Int32(frameRate))
                                    updateRecordingLayoutSnapshot()
                                    await videoRecorder.startRecording(frameRate: cameraManager.effectiveFrameRate)
                                }
                            } else {
                                guard videoRecorder.recordingState == .idle else { return }
                                let livePhotoEnabled = isLivePhotoEnabled
                                let livePhotoDuration = min(max(defaultLivePhotoDuration, 1.0), 10.0)
                                captureFeedback.perform(livePhotoEnabled ? .livePhotoShutterAccepted : .photoCaptured, enabled: soundAndHapticsEnabled)
                                Task<Void, Never> {
                                    updateRecordingLayoutSnapshot()
                                    await videoRecorder.capturePhoto(
                                        livePhotoEnabled: livePhotoEnabled,
                                        livePhotoDuration: livePhotoDuration,
                                        saveToSystemPhotos: false
                                    )
                                }
                            }
                        },
                        onStopRecording: {
                            Task<Void, Never> { await videoRecorder.stopRecording(saveToSystemPhotos: false) }
                        },
                        onCustomize: {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                showCustomizePanel = true
                            }
                        },
                        onOpenAlbum: {
                            showWorks = true
                        }
                    )
                    .padding(.bottom, 22)
                }

                if let error = cameraManager.errorMessage ?? videoRecorder.errorMessage {
                    ErrorBanner(message: error) {
                        withAnimation { cameraManager.errorMessage = nil; videoRecorder.errorMessage = nil }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if shouldShowStartupLoading {
                    StartupLoadingView()
                        .transition(.opacity)
                }

                if showCustomizePanel {
                    CustomizationOverlay(
                        layoutManager: layoutManager,
                        isPresented: $showCustomizePanel
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            hasShownStartupMinimumDuration = false
            configureRecordingHandlers()
            applyInitialPreferencesIfNeeded()
            updateRecordingLayoutSnapshot()
            updateLivePhotoPrebuffering()
            let frameRate = shootingFrameRate
            Task<Void, Never> {
                await cameraManager.setPreferredFrameRate(Int32(frameRate))
                await cameraManager.startCapture()
            }
            Task<Void, Never> {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                hasShownStartupMinimumDuration = true
            }
        }
        .onChange(of: shootingFrameRate) { frameRate in
            guard videoRecorder.recordingState == .idle else { return }
            Task<Void, Never> { await cameraManager.setPreferredFrameRate(Int32(frameRate)) }
        }
        .onChange(of: videoRecorder.recordingState) { state in
            if state == .recording {
                captureFeedback.perform(.recordingStarted, enabled: soundAndHapticsEnabled)
                if isImmersiveRecordingActive {
                    hideRecordingControlsImmediately()
                }
            } else {
                resetRecordingControls()
            }
        }
        .onChange(of: videoRecorder.errorMessage) { errorMessage in
            guard errorMessage != nil else { return }
            captureFeedback.perform(.captureFailed, enabled: soundAndHapticsEnabled)
        }
        .onChange(of: captureMode) { _ in
            resetRecordingControls()
            updateLivePhotoPrebuffering()
        }
        .onChange(of: immersiveRecording) { enabled in
            if enabled && isVideoRecording {
                hideRecordingControlsImmediately()
            } else {
                resetRecordingControls()
            }
        }
        .onChange(of: isLivePhotoEnabled) { _ in
            updateLivePhotoPrebuffering()
        }
        .onChange(of: defaultLivePhotoDuration) { _ in
            updateLivePhotoPrebuffering()
        }
        .onChange(of: layoutManager.currentLayout) { layout in
            lastLayoutRaw = layout.rawValue
            updateRecordingLayoutSnapshot()
        }
        .onChange(of: layoutManager.frontCameraOffset) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.backCameraOffset) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.frontCameraScale) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.backCameraScale) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.floatingHorizontalPosition) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.floatingVerticalPosition) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.floatingSize) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.floatingShape) { _ in updateRecordingLayoutSnapshot() }
        .onChange(of: layoutManager.containerSize) { _ in updateRecordingLayoutSnapshot() }
        .onDisappear {
            resetRecordingControls()
            videoRecorder.setLivePhotoPrebufferingEnabled(false, duration: defaultLivePhotoDuration)
            clearRecordingHandlers()
            cameraManager.stopCapture()
            hasAppliedInitialPreferences = false
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                cameraManager: cameraManager,
                layoutManager: layoutManager,
                defaultLivePhotoDuration: $defaultLivePhotoDuration,
                shootingFrameRate: $shootingFrameRate
            )
        }
        .sheet(isPresented: $showWorks) {
            WorksView(manager: worksManager)
        }
    }

    private var background: some View {
        ZStack {
            Design.background
            RadialGradient(
                colors: [Design.accent.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 320
            )
            RadialGradient(
                colors: [Color.white.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    private var cameraChromeGradients: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Design.background.opacity(0.86), Design.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 156)

            Spacer()

            LinearGradient(
                colors: [Design.background.opacity(0), Design.background.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 250)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func previewCard(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            DualCameraPreviewContainer(
                cameraManager: cameraManager,
                layoutManager: layoutManager,
                didFinishStartupAttempt: cameraManager.didFinishStartupAttempt
            )
            .frame(width: size.width, height: size.height)

            if showsRecordingChrome {
                VStack(alignment: .leading, spacing: 4) {
                    Text(layoutManager.currentLayout.shortTitleKey)
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Design.accent))

                    Text(layoutManager.currentLayout.titleKey)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.84))
                }
                .padding(.horizontal, 18)
                .padding(.top, 118)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isImmersiveRecordingActive && !recordingControlsRevealed {
                Text("recording.tapToRevealControls")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.42)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }

            if captureMode == .photo {
                LivePhotoToggle(isEnabled: $isLivePhotoEnabled)
                    .padding(.top, 118)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { revealRecordingControls() })
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.18), value: showsRecordingChrome)
    }

    private func revealRecordingControls() {
        guard isImmersiveRecordingActive else { return }

        hideControlsWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            recordingControlsRevealed = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                recordingControlsRevealed = false
            }
        }
        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(controlRevealSeconds), execute: workItem)
    }

    private func hideRecordingControlsImmediately() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            recordingControlsRevealed = false
        }
    }

    private func resetRecordingControls() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            recordingControlsRevealed = false
        }
    }

    private func updateLivePhotoPrebuffering() {
        videoRecorder.setLivePhotoPrebufferingEnabled(
            captureMode == .photo && isLivePhotoEnabled,
            duration: min(max(defaultLivePhotoDuration, 1.0), 10.0)
        )
    }

    private func completionFeedbackEvent(for draft: RecordedWorkDraft) -> CaptureFeedbackService.Event? {
        draft.kind == .video ? .recordingStopped : nil
    }

    private func configureRecordingHandlers() {
        videoRecorder.workCompletedHandler = { draft in
            worksManager.add(draft)
            if let event = completionFeedbackEvent(for: draft) {
                captureFeedback.perform(event, enabled: soundAndHapticsEnabled)
            }
        }

        cameraManager.frontVideoFrameHandler = { sampleBuffer in
            videoRecorder.processFrame(sampleBuffer, isFront: true)
        }

        cameraManager.backVideoFrameHandler = { sampleBuffer in
            videoRecorder.processFrame(sampleBuffer, isFront: false)
        }

        cameraManager.audioSampleBufferHandler = { sampleBuffer in
            videoRecorder.processAudioSampleBuffer(sampleBuffer)
        }
    }

    private func applyInitialPreferencesIfNeeded() {
        guard !hasAppliedInitialPreferences else { return }
        hasAppliedInitialPreferences = true
        applyDefaultCaptureMode()
        applyInitialLayoutPreference()
    }

    private func applyDefaultCaptureMode() {
        switch DefaultCaptureMode.from(defaultCaptureModeRaw) {
        case .video:
            captureMode = .video
            isLivePhotoEnabled = false
        case .photo:
            captureMode = .photo
            isLivePhotoEnabled = false
        case .livePhoto:
            captureMode = .photo
            isLivePhotoEnabled = true
        }
    }

    private func applyInitialLayoutPreference() {
        let layoutRawValue = rememberLastLayout ? lastLayoutRaw : defaultLayoutRaw
        let layout = LayoutType.from(layoutRawValue)
        guard layoutManager.currentLayout != layout else { return }
        layoutManager.switchLayout(to: layout)
    }

    private func updateRecordingLayoutSnapshot() {
        let snapshot = layoutManager.makeRecordingLayoutSnapshot(outputSize: videoRecorder.outputVideoSize)
        videoRecorder.updateLayoutSnapshot(snapshot)
        videoRecorder.updateWorkLayout(layoutManager.currentLayout)
    }

    private func clearRecordingHandlers() {
        videoRecorder.workCompletedHandler = nil
        cameraManager.frontVideoFrameHandler = nil
        cameraManager.backVideoFrameHandler = nil
        cameraManager.audioSampleBufferHandler = nil
    }
}

private struct DemoHeader: View {
    let isReady: Bool
    let isRecording: Bool
    let showsModeSwitch: Bool
    @Binding var captureMode: CaptureMode
    @Binding var showSettings: Bool

    private var statusKey: LocalizedStringKey {
        if isRecording { return "status.recording" }
        return isReady ? "status.ready" : "status.starting"
    }

    private var statusColor: Color {
        if isRecording { return Design.recordRed }
        return isReady ? Design.accent : Color.orange
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DualCam")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(statusKey)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.14))
                    )
            }

            Spacer()

            if showsModeSwitch {
                ModeSegmentedControl(selection: $captureMode)
                    .opacity(isRecording ? 0.72 : 1)
                    .allowsHitTesting(!isRecording)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                    .overlay(Circle().stroke(Design.panelStroke, lineWidth: 0.8))
            }
        }
    }
}

private struct LivePhotoToggle: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isEnabled.toggle()
            }
        }) {
            Image(systemName: isEnabled ? "livephoto" : "livephoto.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isEnabled ? Design.accent : .white.opacity(0.46))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isEnabled ? Color(red: 0.07, green: 0.09, blue: 0.04).opacity(0.76) : Color.black.opacity(0.34))
                )
                .overlay(
                    Circle()
                        .stroke(isEnabled ? Design.accent.opacity(0.5) : Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: isEnabled ? Design.accent.opacity(0.14) : .clear, radius: 22, x: 0, y: 0)
        }
        .accessibilityLabel(Text("livePhoto.title"))
        .accessibilityValue(Text(isEnabled ? "status.readyValue" : "status.notReady"))
    }
}

private struct ModeSegmentedControl: View {
    @Binding var selection: CaptureMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureMode.allCases) { mode in
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        selection = mode
                    }
                }) {
                    Text(mode.titleKey)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selection == mode ? .black : .white.opacity(0.62))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(selection == mode ? Design.accent : Color.clear)
                        )
                }
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(Design.panelStroke, lineWidth: 0.8))
    }
}

// MARK: - 底部控制栏

struct BottomControlBar: View {

    let recordingState: RecordingState
    let captureMode: CaptureMode
    let latestWork: WorkItem?
    let showsSideControls: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCustomize: () -> Void
    let onOpenAlbum: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            SideActionButton(icon: "slider.horizontal.3") {
                onCustomize()
            }
            .opacity(showsSideControls ? 1 : 0)
            .allowsHitTesting(showsSideControls)

            Spacer()

            RecordButton(
                recordingState: recordingState,
                captureMode: captureMode,
                onStart: onStartRecording,
                onStop: onStopRecording
            )

            Spacer()

            WorksEntryButton(latestWork: latestWork) {
                onOpenAlbum()
            }
            .opacity(showsSideControls ? 1 : 0)
            .allowsHitTesting(showsSideControls)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .stroke(Design.panelStroke, lineWidth: 0.8)
        )
        .shadow(color: Design.pillShadow, radius: 16, x: 0, y: 8)
        .padding(.horizontal, 18)
        .animation(.easeInOut(duration: 0.18), value: showsSideControls)
    }
}

/// 侧边操作按钮 — 圆角方形毛玻璃
private struct SideActionButton: View {

    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                )
        }
    }
}

// MARK: - 录制按钮

struct RecordButton: View {

    let recordingState: RecordingState
    let captureMode: CaptureMode
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    private var isRecording: Bool { recordingState == .recording }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                isRecording ? onStop() : onStart()
            }
        }) {
            ZStack {
                Circle()
                    .stroke(captureMode == .video ? Design.recordRed.opacity(0.42) : Color.white.opacity(0.85), lineWidth: 4)
                    .frame(width: 76, height: 76)

                if isRecording {
                    Circle()
                        .stroke(Design.recordRed.opacity(0.18), lineWidth: 2)
                        .frame(width: 94, height: 94)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                }

                if isRecording {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Design.recordRed)
                        .frame(width: 30, height: 30)
                } else if captureMode == .video {
                    Circle()
                        .fill(Design.recordRed)
                        .frame(width: 55, height: 55)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 55, height: 55)
                        .overlay(Circle().fill(Design.accent).frame(width: 13, height: 13))
                }
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .pressAction(onPress: { withAnimation(.easeInOut(duration: 0.12)) { isPressed = true } },
                      onRelease: { withAnimation(.easeInOut(duration: 0.12)) { isPressed = false } })
        .onAppear { updatePulseAnimation(isRecording: isRecording) }
        .onChange(of: isRecording) { recording in
            updatePulseAnimation(isRecording: recording)
        }
    }

    private func updatePulseAnimation(isRecording: Bool) {
        if isRecording {
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

private struct CustomizationOverlay: View {
    @ObservedObject var layoutManager: LayoutManager
    @Binding var isPresented: Bool

    private let shapes: [CameraClipShape] = [.roundedRectangle, .circle, .rectangle]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isPresented = false
                    }
                }

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("customize.title")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("customize.subtitle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Design.mutedText)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                }

                CustomSlider(title: "X", value: $layoutManager.floatingHorizontalPosition, range: 0.18...0.86)
                CustomSlider(title: "Y", value: $layoutManager.floatingVerticalPosition, range: 0.18...0.84)
                CustomSlider(title: "customize.size", value: $layoutManager.floatingSize, range: 0.22...0.56)

                HStack(spacing: 10) {
                    ForEach(shapes) { shape in
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                layoutManager.floatingShape = shape
                                if layoutManager.currentLayout == .circleReaction && shape != .circle {
                                    layoutManager.switchLayout(to: .pictureInPicture)
                                }
                            }
                        }) {
                            Text(shape.displayNameKey)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(layoutManager.floatingShape == shape ? .black : .white.opacity(0.72))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(layoutManager.floatingShape == shape ? Design.accent : Color.white.opacity(0.08))
                                )
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.7))
                        }
                    }
                }
            }
            .padding(22)
            .padding(.bottom, 24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Design.panelStroke, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 214)
        }
    }
}

private struct CustomSlider: View {
    let title: LocalizedStringKey
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.0f", value * 100))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Design.accent)
            }

            Slider(value: $value, in: range)
                .accentColor(Design.accent)
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

// MARK: - 启动等待页

struct StartupLoadingView: View {
    @State private var isRotating = false

    var body: some View {
        ZStack {
            Design.background.ignoresSafeArea()

            RadialGradient(
                colors: [Design.accent.opacity(0.26), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 460
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 24)

                VStack(spacing: 14) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Design.accent.opacity(0.20), radius: 20, x: 0, y: 8)

                    VStack(spacing: 8) {
                        Text("DualCam")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .kerning(-1.8)
                            .foregroundColor(.white)

                        Text("startup.hero.title")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))

                        Text("startup.hero.subtitle")
                            .font(.system(size: 13, weight: .medium))
                            .lineSpacing(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Design.mutedText)
                            .frame(maxWidth: 300)
                    }
                }

                VStack(spacing: 10) {
                    StartupFeatureRow(
                        iconName: "rectangle.on.rectangle.angled",
                        titleKey: "startup.feature.dualCapture.title",
                        bodyKey: "startup.feature.dualCapture.body"
                    )
                    StartupFeatureRow(
                        iconName: "square.grid.2x2",
                        titleKey: "startup.feature.layouts.title",
                        bodyKey: "startup.feature.layouts.body"
                    )
                    StartupFeatureRow(
                        iconName: "record.circle",
                        titleKey: "startup.feature.quickRecord.title",
                        bodyKey: "startup.feature.quickRecord.body"
                    )
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                Spacer(minLength: 18)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 3)
                            .frame(width: 30, height: 30)

                        Circle()
                            .trim(from: 0, to: 0.68)
                            .stroke(
                                AngularGradient(
                                    colors: [Design.accent.opacity(0.1), Design.accent, Design.accent.opacity(0.1)],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 30, height: 30)
                            .rotationEffect(.degrees(isRotating ? 360 : 0))
                    }

                    Text("camera.starting")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
            .padding(.bottom, 42)
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { isRotating = true } }
    }
}

private struct StartupFeatureRow: View {
    let iconName: String
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Design.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Design.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(bodyKey)
                    .font(.system(size: 11, weight: .medium))
                    .lineSpacing(1)
                    .foregroundColor(Design.mutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
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
