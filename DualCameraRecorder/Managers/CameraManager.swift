//
//  CameraManager.swift
//  DualCameraRecorder
//
//  多摄像头管理器 - 负责同时管理前后摄像头
//

@preconcurrency import AVFoundation
import UIKit

/// 摄像头类型
enum CameraType {
    case front
    case back
}

/// 摄像头配置
struct CameraConfiguration {
    let type: CameraType
    let position: AVCaptureDevice.Position
    let previewLayer: AVCaptureVideoPreviewLayer
    var device: AVCaptureDevice?
    var input: AVCaptureDeviceInput?
    var output: AVCaptureVideoDataOutput?
    var connection: AVCaptureConnection?
}

/// 多摄像头管理器
@MainActor
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSessionRunning = false
    @Published var frontCameraReady = false
    @Published var backCameraReady = false
    @Published var errorMessage: String?
    @Published var hasMultiCameraSupport = false
    @Published var preferredFrameRate: Int32 = 30
    @Published var effectiveFrameRate: Int32 = 30
    @Published var frameRateDebugInfo = L10n.string("debug.fps.waiting")

    // MARK: - Private Properties
    private let frontSession = AVCaptureSession()
    private let backSession = AVCaptureSession()
    private let multiCamSession = AVCaptureMultiCamSession()
    
    private var frontCamera: CameraConfiguration!
    private var backCamera: CameraConfiguration!
    
    private let frontVideoDataOutputQueue = DispatchQueue(label: "com.dualcamera.videoOutput.front", qos: .userInitiated)
    private let backVideoDataOutputQueue = DispatchQueue(label: "com.dualcamera.videoOutput.back", qos: .userInitiated)
    private let audioDataOutputQueue = DispatchQueue(label: "com.dualcamera.audioOutput", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "com.dualcamera.session", qos: .userInitiated)

    private var audioInput: AVCaptureDeviceInput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var isFrontCameraConfigured = false
    private var isBackCameraConfigured = false
    private var isAudioConfigured = false
    private var isMultiCamConfigured = false
    private var frameRateSelectionReason = L10n.string("debug.camera.waiting")
    private var measuredFrontFrameRate: Double?
    private var measuredBackFrameRate: Double?

    private struct FrameRateSelection {
        let frameRate: Int32
        let formats: [(device: AVCaptureDevice, format: AVCaptureDevice.Format)]
        let reason: String
    }

    // nonisolated 引用：供 delegate 回调中使用，避免跨 Actor 访问
    nonisolated(unsafe) private var _frontVideoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private var _backVideoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private var _audioOutput: AVCaptureAudioDataOutput?
    nonisolated(unsafe) private var frontFPSWindowStart: CMTime?
    nonisolated(unsafe) private var backFPSWindowStart: CMTime?
    nonisolated(unsafe) private var frontFPSFrameCount = 0
    nonisolated(unsafe) private var backFPSFrameCount = 0

    // 视频帧回调
    nonisolated(unsafe) var frontVideoFrameHandler: ((CMSampleBuffer) -> Void)?
    nonisolated(unsafe) var backVideoFrameHandler: ((CMSampleBuffer) -> Void)?
    nonisolated(unsafe) var audioSampleBufferHandler: ((CMSampleBuffer) -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupCameras()
    }
    
    // MARK: - Setup Methods
    
    /// 设置摄像头配置
    private func setupCameras() {
        // 检查多摄像头支持
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        let frontDevices = discoverySession.devices.filter { $0.position == .front }
        let backDevices = discoverySession.devices.filter { $0.position == .back }

        hasMultiCameraSupport = AVCaptureMultiCamSession.isMultiCamSupported && !frontDevices.isEmpty && !backDevices.isEmpty
        
        // 创建预览层
        let frontPreviewLayer: AVCaptureVideoPreviewLayer
        let backPreviewLayer: AVCaptureVideoPreviewLayer

        if AVCaptureMultiCamSession.isMultiCamSupported {
            frontPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: multiCamSession)
            backPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: multiCamSession)
        } else {
            frontPreviewLayer = AVCaptureVideoPreviewLayer(session: frontSession)
            backPreviewLayer = AVCaptureVideoPreviewLayer(session: backSession)
        }

        frontPreviewLayer.videoGravity = .resizeAspectFill
        backPreviewLayer.videoGravity = .resizeAspectFill
        
        // 配置前后摄像头
        frontCamera = CameraConfiguration(
            type: .front,
            position: .front,
            previewLayer: frontPreviewLayer
        )
        
        backCamera = CameraConfiguration(
            type: .back,
            position: .back,
            previewLayer: backPreviewLayer
        )
    }
    
    /// 请求摄像头权限
    func requestPermissions() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            errorMessage = L10n.string("error.camera.permissionDenied")
            return false
        @unknown default:
            return false
        }
    }
    
    /// 请求麦克风权限
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            errorMessage = L10n.string("error.microphone.permissionDenied")
            return false
        @unknown default:
            return false
        }
    }
    
    /// 启动摄像头会话
    func startCapture() async {
        guard await requestPermissions() else { return }
        guard await requestMicrophonePermission() else { return }

        if hasMultiCameraSupport {
            await setupMultiCamSession()

            let multiCamSession = multiCamSession
            await withCheckedContinuation { continuation in
                sessionQueue.async {
                    if !multiCamSession.isRunning {
                        multiCamSession.startRunning()
                    }
                    continuation.resume()
                }
            }
            refreshVideoOrientations()
            isSessionRunning = multiCamSession.isRunning
        } else {
            await setupFrontCamera()
            await setupBackCamera()
            await setupAudio()

            let frontSession = frontSession
            let backSession = backSession
            await withCheckedContinuation { continuation in
                sessionQueue.async {
                    if !frontSession.isRunning {
                        frontSession.startRunning()
                    }
                    if !backSession.isRunning {
                        backSession.startRunning()
                    }
                    continuation.resume()
                }
            }

            refreshVideoOrientations()
            isSessionRunning = frontSession.isRunning || backSession.isRunning
        }
    }

    /// 停止摄像头会话
    func stopCapture() {
        let frontSession = frontSession
        let backSession = backSession
        let multiCamSession = multiCamSession
        sessionQueue.async { [weak self] in
            if multiCamSession.isRunning {
                multiCamSession.stopRunning()
            }
            if frontSession.isRunning {
                frontSession.stopRunning()
            }
            if backSession.isRunning {
                backSession.stopRunning()
            }
            Task { @MainActor in
                self?.isSessionRunning = false
            }
        }
    }
    
    // MARK: - Camera Setup

    private func configureVideoConnection(_ connection: AVCaptureConnection?, cameraType: CameraType) {
        guard let connection else { return }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        if cameraType == .front, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func refreshVideoOrientations() {
        configureVideoConnection(frontCamera.connection, cameraType: .front)
        configureVideoConnection(frontCamera.output?.connection(with: .video), cameraType: .front)
        configureVideoConnection(frontCamera.previewLayer.connection, cameraType: .front)
        configureVideoConnection(backCamera.connection, cameraType: .back)
        configureVideoConnection(backCamera.output?.connection(with: .video), cameraType: .back)
        configureVideoConnection(backCamera.previewLayer.connection, cameraType: .back)
    }

    func setPreferredFrameRate(_ frameRate: Int32) async {
        preferredFrameRate = normalizedFrameRate(frameRate)
        applyPreferredFrameRateIfPossible()
    }

    private func normalizedFrameRate(_ frameRate: Int32) -> Int32 {
        [24, 30, 60].contains(frameRate) ? frameRate : 30
    }

    private func applyPreferredFrameRateIfPossible() {
        let devices = [frontCamera.device, backCamera.device].compactMap { $0 }
        guard !devices.isEmpty else {
            effectiveFrameRate = preferredFrameRate
            frameRateSelectionReason = L10n.string("debug.frameRate.waitingDevice", preferredFrameRate)
            updateFrameRateDebugInfo()
            return
        }

        let requiresMultiCam = hasMultiCameraSupport && devices.count > 1
        let selection = resolveFrameRateSelection(
            preferred: preferredFrameRate,
            devices: devices,
            requiresMultiCam: requiresMultiCam
        )

        var applyFailures: [String] = []
        for item in selection.formats {
            if let failure = applyFrameRate(selection.frameRate, format: item.format, to: item.device) {
                applyFailures.append(failure)
            }
        }

        if applyFailures.isEmpty {
            effectiveFrameRate = selection.frameRate
            frameRateSelectionReason = selection.reason
        } else if selection.frameRate != 30 {
            let fallback = resolveFrameRateSelection(
                preferred: 30,
                devices: devices,
                requiresMultiCam: requiresMultiCam
            )
            var fallbackFailures: [String] = []
            for item in fallback.formats {
                if let failure = applyFrameRate(fallback.frameRate, format: item.format, to: item.device) {
                    fallbackFailures.append(failure)
                }
            }
            effectiveFrameRate = fallbackFailures.isEmpty ? fallback.frameRate : 30
            frameRateSelectionReason = L10n.string("debug.frameRate.applyFailedFallback", preferredFrameRate, applyFailures.joined(separator: "; "), effectiveFrameRate)
        } else {
            effectiveFrameRate = selection.frameRate
            frameRateSelectionReason = L10n.string("debug.frameRate.applyFailed", preferredFrameRate, applyFailures.joined(separator: "; "))
        }

        updateFrameRateDebugInfo()
        print(frameRateDebugInfo)
    }

    private func resolveFrameRateSelection(
        preferred: Int32,
        devices: [AVCaptureDevice],
        requiresMultiCam: Bool
    ) -> FrameRateSelection {
        let candidates = [normalizedFrameRate(preferred), 30, 24].reduce(into: [Int32]()) { result, frameRate in
            if !result.contains(frameRate) {
                result.append(frameRate)
            }
        }
        var failureReasons: [String] = []

        for frameRate in candidates {
            var selectedFormats: [(device: AVCaptureDevice, format: AVCaptureDevice.Format)] = []
            var missingDevices: [String] = []

            for device in devices {
                if let format = bestFormat(on: device, for: frameRate, requiresMultiCam: requiresMultiCam) {
                    selectedFormats.append((device: device, format: format))
                } else {
                    missingDevices.append(L10n.string("debug.frameRate.missingDeviceFormat", deviceLabel(device), frameRate, requiresMultiCam ? "multi-cam " : ""))
                }
            }

            if missingDevices.isEmpty {
                let reason = frameRate == preferredFrameRate
                    ? L10n.string("debug.frameRate.selected", preferredFrameRate, frameRate)
                    : L10n.string("debug.frameRate.fallback", preferredFrameRate, failureReasons.joined(separator: "; "), frameRate)
                return FrameRateSelection(frameRate: frameRate, formats: selectedFormats, reason: reason)
            }

            failureReasons.append(L10n.string("debug.frameRate.unavailable", frameRate, missingDevices.joined(separator: ", ")))
        }

        let fallbackFormats = devices.map { ($0, $0.activeFormat) }
        let reason = L10n.string("debug.frameRate.noMatchingFormat", preferredFrameRate, failureReasons.joined(separator: "; "))
        return FrameRateSelection(frameRate: 30, formats: fallbackFormats, reason: reason)
    }

    private func bestFormat(
        on device: AVCaptureDevice,
        for frameRate: Int32,
        requiresMultiCam: Bool
    ) -> AVCaptureDevice.Format? {
        let matchingFormats = device.formats.filter { format in
            supportsFrameRate(frameRate, format: format) && (!requiresMultiCam || format.isMultiCamSupported)
        }

        return matchingFormats.sorted { lhs, rhs in
            formatRank(lhs) < formatRank(rhs)
        }.first
    }

    private func supportsFrameRate(_ frameRate: Int32, format: AVCaptureDevice.Format) -> Bool {
        let target = Double(frameRate)
        return format.videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= target && target <= range.maxFrameRate
        }
    }

    private func formatRank(_ format: AVCaptureDevice.Format) -> Int {
        let dimensions = formatDimensions(format)
        let width = Int(max(dimensions.width, dimensions.height))
        let height = Int(min(dimensions.width, dimensions.height))
        let pixels = width * height

        if width == 1280 && height == 720 {
            return pixels
        }

        let isSixteenByNine = abs(Double(width) / Double(height) - 16.0 / 9.0) < 0.02
        return (isSixteenByNine ? 10_000_000 : 20_000_000) + pixels
    }

    private func formatDimensions(_ format: AVCaptureDevice.Format) -> CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    }

    private func applyFrameRate(
        _ frameRate: Int32,
        format: AVCaptureDevice.Format,
        to device: AVCaptureDevice
    ) -> String? {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: frameRate)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            return nil
        } catch {
            return L10n.string("debug.frameRate.deviceApplyFailed", deviceLabel(device), frameRate, error.localizedDescription)
        }
    }

    private func deviceLabel(_ device: AVCaptureDevice) -> String {
        switch device.position {
        case .front:
            return L10n.string("debug.camera.front")
        case .back:
            return L10n.string("debug.camera.back")
        default:
            return device.localizedName
        }
    }

    private func updateFrameRateDebugInfo() {
        let frontInfo = frontCamera.device.map { formatSummary(for: $0) } ?? L10n.string("debug.camera.frontUnconfigured")
        let backInfo = backCamera.device.map { formatSummary(for: $0) } ?? L10n.string("debug.camera.backUnconfigured")
        let frontMeasured = measuredFrontFrameRate.map { String(format: "%.1f", $0) } ?? "--"
        let backMeasured = measuredBackFrameRate.map { String(format: "%.1f", $0) } ?? "--"

        let debugInfo = """
        \(frameRateSelectionReason)
        \(L10n.string("debug.frameRate.requestEffective", preferredFrameRate, effectiveFrameRate))
        \(L10n.string("debug.frameRate.measured", frontMeasured, backMeasured))
        \(frontInfo)
        \(backInfo)
        """
        frameRateDebugInfo = debugInfo
    }

    private func formatSummary(for device: AVCaptureDevice) -> String {
        let format = device.activeFormat
        let dimensions = formatDimensions(format)
        let maxFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let minDuration = device.activeVideoMinFrameDuration.seconds
        let maxDuration = device.activeVideoMaxFrameDuration.seconds
        return String(
            format: "%@：%@ %dx%d max %.0ffps multiCam %@ duration %.4f/%.4f",
            deviceLabel(device),
            device.localizedName,
            dimensions.width,
            dimensions.height,
            maxFrameRate,
            format.isMultiCamSupported ? "Y" : "N",
            minDuration,
            maxDuration
        )
    }

    private func setupMultiCamSession() async {
        guard !isMultiCamConfigured else { return }

        do {
            guard let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                errorMessage = L10n.string("error.camera.frontNotFound")
                return
            }
            guard let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                errorMessage = L10n.string("error.camera.backNotFound")
                return
            }

            multiCamSession.beginConfiguration()

            let frontInput = try AVCaptureDeviceInput(device: frontDevice)
            guard multiCamSession.canAddInput(frontInput) else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddFrontInput")
                return
            }
            multiCamSession.addInputWithNoConnections(frontInput)
            frontCamera.device = frontDevice
            frontCamera.input = frontInput

            let backInput = try AVCaptureDeviceInput(device: backDevice)
            guard multiCamSession.canAddInput(backInput) else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddBackInput")
                return
            }
            multiCamSession.addInputWithNoConnections(backInput)
            backCamera.device = backDevice
            backCamera.input = backInput
            applyPreferredFrameRateIfPossible()

            let frontOutput = AVCaptureVideoDataOutput()
            frontOutput.setSampleBufferDelegate(self, queue: frontVideoDataOutputQueue)
            frontOutput.alwaysDiscardsLateVideoFrames = true
            frontOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            guard multiCamSession.canAddOutput(frontOutput) else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddFrontOutput")
                return
            }
            multiCamSession.addOutputWithNoConnections(frontOutput)
            frontCamera.output = frontOutput
            _frontVideoOutput = frontOutput

            let backOutput = AVCaptureVideoDataOutput()
            backOutput.setSampleBufferDelegate(self, queue: backVideoDataOutputQueue)
            backOutput.alwaysDiscardsLateVideoFrames = true
            backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            guard multiCamSession.canAddOutput(backOutput) else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddBackOutput")
                return
            }
            multiCamSession.addOutputWithNoConnections(backOutput)
            backCamera.output = backOutput
            _backVideoOutput = backOutput

            guard let frontPort = frontInput.ports(for: .video, sourceDeviceType: frontDevice.deviceType, sourceDevicePosition: .front).first,
                  let backPort = backInput.ports(for: .video, sourceDeviceType: backDevice.deviceType, sourceDevicePosition: .back).first else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotConnect")
                return
            }

            let frontOutputConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
            if multiCamSession.canAddConnection(frontOutputConnection) {
                multiCamSession.addConnection(frontOutputConnection)
                frontCamera.connection = frontOutputConnection
                configureVideoConnection(frontOutputConnection, cameraType: .front)
            }

            let frontPreviewConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontCamera.previewLayer)
            if multiCamSession.canAddConnection(frontPreviewConnection) {
                multiCamSession.addConnection(frontPreviewConnection)
                configureVideoConnection(frontPreviewConnection, cameraType: .front)
            }

            let backOutputConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
            if multiCamSession.canAddConnection(backOutputConnection) {
                multiCamSession.addConnection(backOutputConnection)
                backCamera.connection = backOutputConnection
                configureVideoConnection(backOutputConnection, cameraType: .back)
            }

            let backPreviewConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backCamera.previewLayer)
            if multiCamSession.canAddConnection(backPreviewConnection) {
                multiCamSession.addConnection(backPreviewConnection)
                configureVideoConnection(backPreviewConnection, cameraType: .back)
            }

            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let input = try AVCaptureDeviceInput(device: audioDevice)
                if multiCamSession.canAddInput(input) {
                    multiCamSession.addInputWithNoConnections(input)
                    audioInput = input

                    let output = AVCaptureAudioDataOutput()
                    output.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
                    if multiCamSession.canAddOutput(output) {
                        multiCamSession.addOutputWithNoConnections(output)
                        audioOutput = output
                        _audioOutput = output

                        if let audioPort = input.ports.first {
                            let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: output)
                            if multiCamSession.canAddConnection(audioConnection) {
                                multiCamSession.addConnection(audioConnection)
                            }
                        }
                    }
                }
            }

            multiCamSession.commitConfiguration()
            isMultiCamConfigured = true
            isFrontCameraConfigured = true
            isBackCameraConfigured = true
            isAudioConfigured = audioOutput != nil
            frontCameraReady = true
            backCameraReady = true

        } catch {
            multiCamSession.commitConfiguration()
            errorMessage = L10n.string("error.camera.multiSetupFailed", error.localizedDescription)
        }
    }

    /// 设置前置摄像头
    private func setupFrontCamera() async {
        guard !isFrontCameraConfigured else { return }

        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                errorMessage = L10n.string("error.camera.frontNotFound")
                return
            }

            frontSession.beginConfiguration()
            frontSession.sessionPreset = .hd1280x720

            frontCamera.device = device
            applyPreferredFrameRateIfPossible()

            let input = try AVCaptureDeviceInput(device: device)
            frontCamera.input = input

            if frontSession.canAddInput(input) {
                frontSession.addInput(input)
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: frontVideoDataOutputQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            frontCamera.output = videoOutput
            _frontVideoOutput = videoOutput

            if frontSession.canAddOutput(videoOutput) {
                frontSession.addOutput(videoOutput)
            }

            if let connection = videoOutput.connection(with: .video) {
                frontCamera.connection = connection
                configureVideoConnection(connection, cameraType: .front)
            }

            frontSession.commitConfiguration()
            isFrontCameraConfigured = true
            frontCameraReady = true

        } catch {
            frontSession.commitConfiguration()
            errorMessage = L10n.string("error.camera.frontSetupFailed", error.localizedDescription)
        }
    }
    
    /// 设置后置摄像头
    private func setupBackCamera() async {
        guard !isBackCameraConfigured else { return }

        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                errorMessage = L10n.string("error.camera.backNotFound")
                return
            }

            backSession.beginConfiguration()
            backSession.sessionPreset = .hd1280x720

            backCamera.device = device
            applyPreferredFrameRateIfPossible()

            let input = try AVCaptureDeviceInput(device: device)
            backCamera.input = input

            if backSession.canAddInput(input) {
                backSession.addInput(input)
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: backVideoDataOutputQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            backCamera.output = videoOutput
            _backVideoOutput = videoOutput

            if backSession.canAddOutput(videoOutput) {
                backSession.addOutput(videoOutput)
            }

            if let connection = videoOutput.connection(with: .video) {
                backCamera.connection = connection
                configureVideoConnection(connection, cameraType: .back)
            }

            backSession.commitConfiguration()
            isBackCameraConfigured = true
            backCameraReady = true

        } catch {
            backSession.commitConfiguration()
            errorMessage = L10n.string("error.camera.backSetupFailed", error.localizedDescription)
        }
    }

    private func setupAudio() async {
        guard !isAudioConfigured else { return }

        do {
            guard let device = AVCaptureDevice.default(for: .audio) else {
                errorMessage = L10n.string("error.microphone.notFound")
                return
            }

            backSession.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: device)
            audioInput = input
            if backSession.canAddInput(input) {
                backSession.addInput(input)
            }

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
            audioOutput = output
            _audioOutput = output

            if backSession.canAddOutput(output) {
                backSession.addOutput(output)
            }

            backSession.commitConfiguration()
            isAudioConfigured = true

        } catch {
            backSession.commitConfiguration()
            errorMessage = L10n.string("error.microphone.setupFailed", error.localizedDescription)
        }
    }
    
    // MARK: - Preview Layers
    
    /// 获取前置摄像头预览层
    func getFrontPreviewLayer() -> AVCaptureVideoPreviewLayer {
        return frontCamera.previewLayer
    }
    
    /// 获取后置摄像头预览层
    func getBackPreviewLayer() -> AVCaptureVideoPreviewLayer {
        return backCamera.previewLayer
    }
    
    // MARK: - Camera Control
    
    /// 切换前后摄像头
    func switchCameras() {
        let tempSession = frontCamera.previewLayer.session
        frontCamera.previewLayer.session = backCamera.previewLayer.session
        backCamera.previewLayer.session = tempSession
    }
    
    /// 设置缩放倍数（仅后置摄像头支持）
    func setZoomFactor(_ factor: CGFloat) {
        guard let device = backCamera.device else { return }
        
        do {
            try device.lockForConfiguration()
            let maxZoom = device.activeFormat.videoMaxZoomFactor
            let zoomFactor = min(max(factor, 1.0), maxZoom)
            device.videoZoomFactor = zoomFactor
            device.unlockForConfiguration()
        } catch {
            print("设置缩放失败: \(error)")
        }
    }
    
    /// 设置对焦点
    func setFocusPoint(_ point: CGPoint, for cameraType: CameraType) {
        let camera = cameraType == .front ? frontCamera : backCamera
        guard let camera = camera, let device = camera.device else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
        } catch {
            print("设置对焦点失败: \(error)")
        }
    }
    
    /// 切换闪光灯模式
    func toggleFlash() {
        guard let device = backCamera.device,
              device.hasFlash else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.torchMode == .off {
                device.torchMode = .on
            } else {
                device.torchMode = .off
            }
            
            device.unlockForConfiguration()
        } catch {
            print("切换闪光灯失败: \(error)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    nonisolated private func trackMeasuredFrameRate(sampleBuffer: CMSampleBuffer, isFront: Bool) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid, timestamp.isNumeric else { return }

        if isFront {
            updateMeasuredFrameRate(
                timestamp: timestamp,
                windowStart: &frontFPSWindowStart,
                frameCount: &frontFPSFrameCount,
                publish: { measured in
                    Task { @MainActor [weak self] in
                        self?.measuredFrontFrameRate = measured
                        self?.updateFrameRateDebugInfo()
                    }
                }
            )
        } else {
            updateMeasuredFrameRate(
                timestamp: timestamp,
                windowStart: &backFPSWindowStart,
                frameCount: &backFPSFrameCount,
                publish: { measured in
                    Task { @MainActor [weak self] in
                        self?.measuredBackFrameRate = measured
                        self?.updateFrameRateDebugInfo()
                    }
                }
            )
        }
    }

    nonisolated private func updateMeasuredFrameRate(
        timestamp: CMTime,
        windowStart: inout CMTime?,
        frameCount: inout Int,
        publish: (Double) -> Void
    ) {
        guard let start = windowStart else {
            windowStart = timestamp
            frameCount = 1
            return
        }

        frameCount += 1
        let elapsed = CMTimeGetSeconds(timestamp - start)
        guard elapsed >= 1.0 else { return }

        publish(Double(frameCount - 1) / elapsed)
        windowStart = timestamp
        frameCount = 1
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        // 使用 nonisolated 引用进行比较，避免跨 Actor 访问
        let frontRef = _frontVideoOutput
        let backRef = _backVideoOutput
        let audioRef = _audioOutput

        if output === frontRef {
            trackMeasuredFrameRate(sampleBuffer: sampleBuffer, isFront: true)
            frontVideoFrameHandler?(sampleBuffer)
        } else if output === backRef {
            trackMeasuredFrameRate(sampleBuffer: sampleBuffer, isFront: false)
            backVideoFrameHandler?(sampleBuffer)
        } else if output === audioRef {
            audioSampleBufferHandler?(sampleBuffer)
        }
    }
}
