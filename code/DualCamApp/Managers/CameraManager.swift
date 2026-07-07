//
//  CameraManager.swift
//  DualCamApp
//
//  多摄像头管理器 - 负责同时管理前后摄像头
//

@preconcurrency import AVFoundation
import Combine
import UIKit

/// 摄像头类型
enum CameraType: Hashable {
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
    var photoOutput: AVCapturePhotoOutput?
    var movieOutput: AVCaptureMovieFileOutput?
    var connection: AVCaptureConnection?
}

enum CameraDeviceSelection {
    static let frontDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .builtInTrueDepthCamera
    ]

    static func frontCameraDeviceTypeRank(_ deviceType: AVCaptureDevice.DeviceType) -> Int {
        switch deviceType {
        case .builtInWideAngleCamera:
            return 300
        case .builtInUltraWideCamera:
            return 200
        case .builtInTrueDepthCamera:
            return 100
        default:
            return 0
        }
    }

    static func isSupportedFrontCameraDeviceType(_ deviceType: AVCaptureDevice.DeviceType) -> Bool {
        frontCameraDeviceTypeRank(deviceType) > 0
    }

    static func isMultiCamCameraReady(hasOutputConnection: Bool, hasPreviewConnection: Bool) -> Bool {
        hasOutputConnection && hasPreviewConnection
    }

    static func isSingleSessionCameraReady(didAddInput: Bool, didAddOutput: Bool, hasVideoConnection: Bool) -> Bool {
        didAddInput && didAddOutput && hasVideoConnection
    }
}

nonisolated enum RearLensKind: String, CaseIterable {
    case ultra
    case wide
    case tele

    var titleKey: String {
        switch self {
        case .ultra: return "focal.lens.ultraWide"
        case .wide: return "focal.lens.wide"
        case .tele: return "focal.lens.telephoto"
        }
    }
}

enum NativeOutputStatus: Equatable {
    case pending
    case ready
    case fallback(String)
}

struct NativePhotoPair {
    let frontData: Data
    let backData: Data?
}

struct NativeLivePhotoCapture {
    let photoData: Data
    let movieURL: URL
    let photoDisplayTime: CMTime
}

struct NativeLivePhotoPair {
    let front: NativeLivePhotoCapture
    let back: NativeLivePhotoCapture?
}

struct NativeMoviePair {
    let frontURL: URL
    let backURL: URL?
}

enum NativeOutputError: LocalizedError {
    case photoOutputUnavailable
    case photoDataUnavailable
    case movieOutputUnavailable
    case movieRecordingNotActive
    case livePhotoOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .photoOutputUnavailable:
            return "Native photo output is unavailable."
        case .photoDataUnavailable:
            return "Native photo data is unavailable."
        case .movieOutputUnavailable:
            return "Native movie output is unavailable."
        case .movieRecordingNotActive:
            return "Native movie recording is not active."
        case .livePhotoOutputUnavailable:
            return "Native Live Photo output is unavailable."
        }
    }
}

nonisolated enum RearLensStatus: Equatable {
    case physical(RearLensKind)
    case digitalCrop

    var titleKey: String {
        switch self {
        case .physical(let kind): return kind.titleKey
        case .digitalCrop: return "focal.lens.digitalCrop"
        }
    }
}

nonisolated struct RearFocalCapability: Equatable {
    static let prototypeZoomFactors: [CGFloat] = [0.5, 1, 2, 3, 5]
    static let fallback = RearFocalCapability(
        minZoomFactor: 1,
        maxZoomFactor: 1,
        recommendedZoomFactors: [1],
        physicalLensByZoom: [1: .wide]
    )

    let minZoomFactor: CGFloat
    let maxZoomFactor: CGFloat
    let recommendedZoomFactors: [CGFloat]
    let physicalLensByZoom: [CGFloat: RearLensKind]

    init(minZoomFactor: CGFloat, maxZoomFactor: CGFloat, availableLensKinds: Set<RearLensKind>) {
        let lowerBound = max(0.5, minZoomFactor)
        let upperBound = max(lowerBound, maxZoomFactor)
        let supportedZooms = Self.prototypeZoomFactors.filter { zoom in
            lowerBound - 0.001 <= zoom && zoom <= upperBound + 0.001
        }
        let fallbackZoom = min(max(Self.nearestPrototypeZoom(to: min(max(1, lowerBound), upperBound)), lowerBound), upperBound)
        let recommendedZooms = supportedZooms.isEmpty ? [fallbackZoom] : supportedZooms
        var lensMap: [CGFloat: RearLensKind] = [:]

        for zoom in recommendedZooms {
            if zoom < 1, availableLensKinds.contains(.ultra) {
                lensMap[zoom] = .ultra
            } else if zoom >= 3, availableLensKinds.contains(.tele) {
                lensMap[zoom] = .tele
            } else if zoom == 2, upperBound < 3, availableLensKinds.contains(.tele) {
                lensMap[zoom] = .tele
            } else if availableLensKinds.contains(.wide) {
                lensMap[zoom] = .wide
            } else if let firstLens = availableLensKinds.sorted(by: { $0.rawValue < $1.rawValue }).first {
                lensMap[zoom] = firstLens
            }
        }

        self.init(
            minZoomFactor: lowerBound,
            maxZoomFactor: upperBound,
            recommendedZoomFactors: recommendedZooms,
            physicalLensByZoom: lensMap.isEmpty ? [recommendedZooms[0]: .wide] : lensMap
        )
    }

    init(
        minZoomFactor: CGFloat,
        maxZoomFactor: CGFloat,
        physicalLensByZoom: [CGFloat: RearLensKind]
    ) {
        let lowerBound = max(0.5, minZoomFactor)
        let upperBound = max(lowerBound, maxZoomFactor)
        let recommendedZooms = Self.recommendedZoomFactors(
            lowerBound: lowerBound,
            upperBound: upperBound,
            physicalLensByZoom: physicalLensByZoom
        )

        self.init(
            minZoomFactor: lowerBound,
            maxZoomFactor: upperBound,
            recommendedZoomFactors: recommendedZooms,
            physicalLensByZoom: physicalLensByZoom.isEmpty ? [recommendedZooms[0]: .wide] : physicalLensByZoom
        )
    }

    init(
        minZoomFactor: CGFloat,
        maxZoomFactor: CGFloat,
        recommendedZoomFactors: [CGFloat],
        physicalLensByZoom: [CGFloat: RearLensKind]
    ) {
        self.minZoomFactor = minZoomFactor
        self.maxZoomFactor = maxZoomFactor
        self.recommendedZoomFactors = recommendedZoomFactors
        self.physicalLensByZoom = physicalLensByZoom
    }

    func clampedZoomFactor(_ zoomFactor: CGFloat) -> CGFloat {
        min(max(zoomFactor, minZoomFactor), maxZoomFactor)
    }

    func lensStatus(for zoomFactor: CGFloat) -> RearLensStatus {
        let clampedZoom = clampedZoomFactor(zoomFactor)
        if let exactZoom = physicalLensByZoom.keys.first(where: { abs($0 - clampedZoom) < 0.01 }),
           let lensKind = physicalLensByZoom[exactZoom] {
            return .physical(lensKind)
        }
        return .digitalCrop
    }

    static func formattedZoomFactor(_ zoomFactor: CGFloat) -> String {
        let rounded = zoomFactor.rounded()
        if abs(zoomFactor - rounded) < 0.01 {
            return String(format: "%.0f×", rounded)
        }
        return String(format: "%.1f×", zoomFactor)
    }

    private static func recommendedZoomFactors(
        lowerBound: CGFloat,
        upperBound: CGFloat,
        physicalLensByZoom: [CGFloat: RearLensKind]
    ) -> [CGFloat] {
        var zooms = physicalLensByZoom.keys
            .filter { lowerBound - 0.001 <= $0 && $0 <= upperBound + 0.001 }
            .sorted()

        if !zooms.contains(where: { abs($0 - 1) < 0.01 }), lowerBound <= 1, 1 <= upperBound {
            zooms.append(1)
        }

        let highestPhysicalZoom = zooms.max() ?? 1
        if highestPhysicalZoom >= 5, lowerBound <= 2, 2 <= upperBound, !zooms.contains(where: { abs($0 - 2) < 0.01 }) {
            zooms.append(2)
        }

        if zooms.isEmpty {
            zooms = [min(max(1, lowerBound), upperBound)]
        }

        return zooms.sorted()
    }

    private static func nearestPrototypeZoom(to zoomFactor: CGFloat) -> CGFloat {
        prototypeZoomFactors.min { abs($0 - zoomFactor) < abs($1 - zoomFactor) } ?? 1
    }
}

private struct ActiveNativeMovieRecording {
    let frontOutput: AVCaptureMovieFileOutput
    let frontDelegate: NativeMovieCaptureDelegate
    let backOutput: AVCaptureMovieFileOutput?
    let backDelegate: NativeMovieCaptureDelegate?
}

private final class NativePhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(NativeOutputError.photoDataUnavailable))
            return
        }

        completion(.success(data))
    }
}

private final class NativeLivePhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let movieURL: URL
    private let completion: (Result<NativeLivePhotoCapture, Error>) -> Void
    private var photoData: Data?
    private var photoDisplayTime = CMTime.zero
    private var captureError: Error?

    init(movieURL: URL, completion: @escaping (Result<NativeLivePhotoCapture, Error>) -> Void) {
        self.movieURL = movieURL
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            captureError = error
            return
        }
        photoData = photo.fileDataRepresentation()
        if photoData == nil {
            captureError = NativeOutputError.photoDataUnavailable
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            captureError = error
            return
        }
        self.photoDisplayTime = photoDisplayTime.isValid && photoDisplayTime.isNumeric ? photoDisplayTime : .zero
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        if let captureError {
            completion(.failure(captureError))
            return
        }
        guard let photoData,
              FileManager.default.fileExists(atPath: movieURL.path) else {
            completion(.failure(NativeOutputError.livePhotoOutputUnavailable))
            return
        }
        completion(.success(NativeLivePhotoCapture(photoData: photoData, movieURL: movieURL, photoDisplayTime: photoDisplayTime)))
    }
}

private final class NativeMovieCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private var result: Result<URL, Error>?
    private var continuation: CheckedContinuation<URL, Error>?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        complete(error.map { .failure($0) } ?? .success(outputFileURL))
    }

    func waitForCompletion() async throws -> URL {
        if let result {
            return try result.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        if let continuation {
            continuation.resume(with: result)
            self.continuation = nil
        } else {
            self.result = result
        }
    }
}

/// 多摄像头管理器
@MainActor
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSessionRunning = false
    @Published var frontCameraReady = false
    @Published var backCameraReady = false
    @Published var hasDeliveredFrontVideoFrame = false
    @Published var hasDeliveredBackVideoFrame = false
    @Published var errorMessage: String?
    @Published var didFinishStartupAttempt = false
    @Published var hasMultiCameraSupport = false
    @Published var preferredFrameRate: Int32 = 30
    @Published var effectiveFrameRate: Int32 = 30
    @Published var frameRateDebugInfo = L10n.string("debug.fps.waiting")
    @Published var nativeOutputStatus: NativeOutputStatus = .pending
    @Published var rearFocalCapability = RearFocalCapability.fallback
    @Published var rearZoomFactor: CGFloat = 1
    @Published var isSessionInterrupted = false
    @Published var sessionInterruptionReason: String?

    var rearLensStatus: RearLensStatus {
        rearFocalCapability.lensStatus(for: rearZoomFactor)
    }

    var hasDeliveredRequiredVideoFrames: Bool {
        guard isSessionRunning, hasDeliveredFrontVideoFrame else { return false }
        return !shouldWaitForBackVideoFrame || hasDeliveredBackVideoFrame
    }

    private var shouldWaitForBackVideoFrame: Bool {
        backCameraReady && _backVideoOutput != nil && (multiCamSession.isRunning || backSession.isRunning)
    }

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
    private var startupTimeoutTask: Task<Void, Never>?
    private var callRecoveryTask: Task<Void, Never>?
    private var hasAttemptedRuntimeErrorRecovery = false
    private var frameRateSelectionReason = L10n.string("debug.camera.waiting")
    private var measuredFrontFrameRate: Double?
    private var measuredBackFrameRate: Double?
    private var rearFocalDeviceZoomScale: CGFloat = 1

    private struct FrameRateSelection {
        let frameRate: Int32
        let formats: [(device: AVCaptureDevice, format: AVCaptureDevice.Format)]
        let reason: String
    }

    private let frontDeviceTypes: [AVCaptureDevice.DeviceType] = CameraDeviceSelection.frontDeviceTypes

    private let rearDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInWideAngleCamera,
        .builtInTelephotoCamera,
        .builtInUltraWideCamera
    ]

    // nonisolated 引用：供 delegate 回调中使用，避免跨 Actor 访问
    nonisolated(unsafe) private var _frontVideoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private var _backVideoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private var _audioOutput: AVCaptureAudioDataOutput?
    nonisolated(unsafe) private var frontFPSWindowStart: CMTime?
    nonisolated(unsafe) private var backFPSWindowStart: CMTime?
    nonisolated(unsafe) private var frontFPSFrameCount = 0
    nonisolated(unsafe) private var backFPSFrameCount = 0
    nonisolated(unsafe) private var isIPadDelayedRearStartupActive = false
    nonisolated(unsafe) private var iPadFrontFramesSinceStartup = 0
    nonisolated(unsafe) private var iPadLastFrontFrameTime: TimeInterval = 0
    nonisolated(unsafe) private var iPadRearStartupRequested = false
    nonisolated(unsafe) private var iPadRearFallbackTriggered = false
    private var activePhotoCaptureDelegates: [UUID: NativePhotoCaptureDelegate] = [:]
    private var activeLivePhotoCaptureDelegates: [UUID: NativeLivePhotoCaptureDelegate] = [:]
    private var activeNativeMovieRecording: ActiveNativeMovieRecording?

    // 视频帧回调
    nonisolated(unsafe) var frontVideoFrameHandler: ((CMSampleBuffer) -> Void)?
    nonisolated(unsafe) var backVideoFrameHandler: ((CMSampleBuffer) -> Void)?
    nonisolated(unsafe) var audioSampleBufferHandler: ((CMSampleBuffer) -> Void)?
    var sessionInterruptionHandler: (() -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupCameras()
    }
    
    // MARK: - Setup Methods
    
    /// 设置摄像头配置
    private func setupCameras() {
        // 检查多摄像头支持
        let frontDevices = availableFrontCameraDevices()
        let backDevices = availableBackCameraDevices()

        hasMultiCameraSupport = supportsMultiCamCapture && !frontDevices.isEmpty && !backDevices.isEmpty

        if hasMultiCameraSupport {
            configureMultiCamPreviewLayers()
        } else {
            configureSeparateSessionPreviewLayers()
        }
    }

    private func configureMultiCamPreviewLayers() {
        let frontPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: multiCamSession)
        let backPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: multiCamSession)
        configurePreviewLayers(frontPreviewLayer: frontPreviewLayer, backPreviewLayer: backPreviewLayer)
    }

    private func configureSeparateSessionPreviewLayers() {
        let frontPreviewLayer = AVCaptureVideoPreviewLayer(session: frontSession)
        let backPreviewLayer = AVCaptureVideoPreviewLayer(session: backSession)
        hasMultiCameraSupport = false
        frontCameraReady = false
        backCameraReady = false
        resetFirstFrameReadiness()
        isFrontCameraConfigured = false
        isBackCameraConfigured = false
        _frontVideoOutput = nil
        _backVideoOutput = nil
        nativeOutputStatus = .pending
        configurePreviewLayers(frontPreviewLayer: frontPreviewLayer, backPreviewLayer: backPreviewLayer)
    }

    private func configurePreviewLayers(frontPreviewLayer: AVCaptureVideoPreviewLayer, backPreviewLayer: AVCaptureVideoPreviewLayer) {
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
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted {
                errorMessage = L10n.string("error.camera.permissionDenied")
            }
            return granted
        case .denied, .restricted:
            errorMessage = L10n.string("error.camera.permissionDenied")
            return false
        @unknown default:
            errorMessage = L10n.string("error.camera.permissionDenied")
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
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted {
                errorMessage = L10n.string("error.microphone.permissionDenied")
            }
            return granted
        case .denied, .restricted:
            errorMessage = L10n.string("error.microphone.permissionDenied")
            return false
        @unknown default:
            errorMessage = L10n.string("error.microphone.permissionDenied")
            return false
        }
    }

    private func configureAudioSessionPolicy() {
        frontSession.automaticallyConfiguresApplicationAudioSession = false
        backSession.automaticallyConfiguresApplicationAudioSession = false
        multiCamSession.automaticallyConfiguresApplicationAudioSession = false

        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
        )
    }

    func prepareForRecording() async -> Bool {
        if sessionInterruptionReason == "error.camera.interrupted.inCall" {
            stopCallRecoveryPolling()
            isSessionInterrupted = false
            sessionInterruptionReason = nil
            await restartSession()
        }

        guard canUseAudioInput() else {
            markRecordingUnavailableDueToCall()
            return false
        }
        return true
    }

    func markRecordingUnavailableDueToCall() {
        markCaptureUnavailableDueToCall()
    }

    /// 启动摄像头会话
    func startCapture() async {
        didFinishStartupAttempt = false
        errorMessage = nil
        isSessionInterrupted = false
        sessionInterruptionReason = nil
        hasAttemptedRuntimeErrorRecovery = false
        resetFirstFrameReadiness()
        defer { didFinishStartupAttempt = true }

        guard await requestPermissions() else { return }
        guard await requestMicrophonePermission() else { return }

        configureAudioSessionPolicy()
        addSessionObservers()

        if hasMultiCameraSupport {
            await setupMultiCamSession()
            if isSessionInterrupted { return }

            if isMultiCamConfigured && frontCameraReady && backCameraReady {
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
                startStartupTimeout()
                return
            }

            configureSeparateSessionPreviewLayers()
            errorMessage = nil
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            await startIPadFrontFirstCapture()
            return
        }

        await setupFrontCamera()
        await setupBackCamera()
        await setupAudio()
        if isSessionInterrupted { return }

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
        isSessionRunning = (frontCameraReady && frontSession.isRunning) || (backCameraReady && backSession.isRunning)
        startStartupTimeout()
    }

    private func startIPadFrontFirstCapture() async {
        await setupFrontCamera()
        await setupAudio(on: frontSession)
        if isSessionInterrupted { return }

        resetIPadDelayedRearStartupState()

        let frontSession = frontSession
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !frontSession.isRunning {
                    frontSession.startRunning()
                }
                continuation.resume()
            }
        }

        backCameraReady = false
        refreshVideoOrientations()
        isSessionRunning = frontCameraReady && frontSession.isRunning
        startStartupTimeout()
    }

    private func resetIPadDelayedRearStartupState() {
        isIPadDelayedRearStartupActive = false
        iPadFrontFramesSinceStartup = 0
        iPadLastFrontFrameTime = 0
        iPadRearStartupRequested = false
        iPadRearFallbackTriggered = false
    }

    private func resetFirstFrameReadiness() {
        hasDeliveredFrontVideoFrame = false
        hasDeliveredBackVideoFrame = false
    }

    private func markFirstVideoFrame(isFront: Bool) {
        if isFront {
            guard !hasDeliveredFrontVideoFrame else { return }
            hasDeliveredFrontVideoFrame = true
        } else {
            guard !hasDeliveredBackVideoFrame else { return }
            hasDeliveredBackVideoFrame = true
        }

        if hasDeliveredRequiredVideoFrames {
            cancelStartupTimeout()
        }
    }

    private func startDelayedIPadRearCaptureIfNeeded() async {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              isIPadDelayedRearStartupActive,
              iPadRearStartupRequested,
              !iPadRearFallbackTriggered,
              frontCameraReady,
              frontSession.isRunning,
              !backSession.isRunning else { return }

        await setupBackCamera()

        let backSession = backSession
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !backSession.isRunning {
                    backSession.startRunning()
                }
                continuation.resume()
            }
        }

        let rearStartTime = Date.timeIntervalSinceReferenceDate
        backCameraReady = false
        hasDeliveredBackVideoFrame = false
        refreshVideoOrientations()
        isSessionRunning = frontCameraReady && frontSession.isRunning
        scheduleIPadRearStartupValidation(rearStartTime: rearStartTime, hasShownRearPreview: false)
    }

    private func scheduleIPadRearStartupValidation(rearStartTime: TimeInterval, hasShownRearPreview: Bool) {
        let delay: UInt64 = hasShownRearPreview ? 600_000_000 : 1_200_000_000
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            await self?.validateDelayedIPadRearStartup(rearStartTime: rearStartTime, hasShownRearPreview: hasShownRearPreview)
        }
    }

    private func validateDelayedIPadRearStartup(rearStartTime: TimeInterval, hasShownRearPreview: Bool) async {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              isIPadDelayedRearStartupActive,
              !iPadRearFallbackTriggered,
              backSession.isRunning else { return }

        guard iPadLastFrontFrameTime > rearStartTime else {
            await fallbackToIPadFrontOnlyAfterRearStartup()
            return
        }

        backCameraReady = false
        refreshVideoOrientations()
        isSessionRunning = frontCameraReady && frontSession.isRunning
    }

    private func fallbackToIPadFrontOnlyAfterRearStartup() async {
        guard !iPadRearFallbackTriggered else { return }

        iPadRearFallbackTriggered = true

        let backSession = backSession
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if backSession.isRunning {
                    backSession.stopRunning()
                }
                continuation.resume()
            }
        }

        backCameraReady = false
        frontCameraReady = frontSession.isRunning
        refreshVideoOrientations()
        isSessionRunning = frontCameraReady && frontSession.isRunning
    }

    /// 停止摄像头会话
    func stopCapture() {
        isIPadDelayedRearStartupActive = false
        iPadRearStartupRequested = false
        removeSessionObservers()
        cancelStartupTimeout()
        stopCallRecoveryPolling()
        resetFirstFrameReadiness()
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
            Task { @MainActor [weak self] in
                self?.isSessionRunning = false
            }
        }
    }

    /// 重启摄像头会话（供重试按钮调用）
    func restartSession() async {
        errorMessage = nil
        isSessionInterrupted = false
        sessionInterruptionReason = nil
        hasAttemptedRuntimeErrorRecovery = false
        stopCallRecoveryPolling()
        stopCapture()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await startCapture()
    }

    // MARK: - Session Interruption & Recovery

    private func addSessionObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleSessionWasInterrupted(_:)),
                       name: .AVCaptureSessionWasInterrupted, object: nil)
        nc.addObserver(self, selector: #selector(handleSessionInterruptionEnded(_:)),
                       name: .AVCaptureSessionInterruptionEnded, object: nil)
        nc.addObserver(self, selector: #selector(handleSessionRuntimeError(_:)),
                       name: .AVCaptureSessionRuntimeError, object: nil)
        nc.addObserver(self, selector: #selector(handleAudioSessionInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
    }

    private func removeSessionObservers() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    }

    private func startStartupTimeout() {
        cancelStartupTimeout()
        startupTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.hasDeliveredRequiredVideoFrames else { return }
            guard !self.isSessionInterrupted else {
                self.errorMessage = nil
                self.didFinishStartupAttempt = true
                return
            }
            self.errorMessage = L10n.string("error.camera.startupTimeout")
            self.didFinishStartupAttempt = true
        }
    }

    private func cancelStartupTimeout() {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
    }

    private func markCaptureUnavailableDueToCall() {
        cancelStartupTimeout()
        errorMessage = nil
        sessionInterruptionReason = "error.camera.interrupted.inCall"
        isSessionInterrupted = true
        didFinishStartupAttempt = true
        startCallRecoveryPolling()
    }

    private func startCallRecoveryPolling() {
        guard callRecoveryTask == nil else { return }
        callRecoveryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !Task.isCancelled else { break }
                guard self.isSessionInterrupted,
                      self.sessionInterruptionReason == "error.camera.interrupted.inCall" else { break }
                if !AVAudioSession.sharedInstance().isOtherAudioPlaying,
                   self.canUseAudioInput() {
                    self.stopCallRecoveryPolling()
                    self.isSessionInterrupted = false
                    self.sessionInterruptionReason = nil
                    if !self.isSessionRunning {
                        await self.restartSession()
                    }
                    break
                }
            }
        }
    }

    private func stopCallRecoveryPolling() {
        callRecoveryTask?.cancel()
        callRecoveryTask = nil
    }

    private func canUseAudioInput() -> Bool {
        configureAudioSessionPolicy()
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            return audioSession.isInputAvailable
        } catch {
            return false
        }
    }

    private func markCaptureInterrupted(reasonKey: String) {
        cancelStartupTimeout()
        errorMessage = nil
        sessionInterruptionReason = reasonKey
        isSessionInterrupted = true
        didFinishStartupAttempt = true
    }

    private func isCaptureDeviceUnavailableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == AVFoundationErrorDomain else { return false }
        let code = AVError.Code(rawValue: nsError.code)
        return code == .deviceAlreadyUsedByAnotherSession || code == .deviceInUseByAnotherApplication
    }

    @objc private func handleSessionWasInterrupted(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue),
              reason == .videoDeviceNotAvailableInBackground || reason == .videoDeviceNotAvailableDueToSystemPressure || reason == .videoDeviceInUseByAnotherClient else {
            return
        }

        let reasonKey: String
        switch reason {
        case .videoDeviceNotAvailableDueToSystemPressure:
            // Usually a phone call — both camera and mic are taken by the system
            reasonKey = "error.camera.interrupted.inCall"
        case .videoDeviceInUseByAnotherClient:
            reasonKey = "error.camera.interrupted.cameraInUse"
        case .videoDeviceNotAvailableInBackground:
            reasonKey = "error.camera.interrupted.inCall"
        default:
            reasonKey = "error.camera.interrupted.inCall"
        }

        let handler = sessionInterruptionHandler
        Task { @MainActor [weak self] in
            guard let self else { return }
            handler?()
            if reasonKey == "error.camera.interrupted.inCall" {
                self.markCaptureUnavailableDueToCall()
            } else {
                self.markCaptureInterrupted(reasonKey: reasonKey)
            }
        }
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        isSessionInterrupted = false
        sessionInterruptionReason = nil
        Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            self.resetFirstFrameReadiness()
            let frontSession = self.frontSession
            let backSession = self.backSession
            let multiCamSession = self.multiCamSession
            await withCheckedContinuation { continuation in
                self.sessionQueue.async {
                    if !frontSession.isRunning, self.isFrontCameraConfigured {
                        frontSession.startRunning()
                    }
                    if !backSession.isRunning, self.isBackCameraConfigured {
                        backSession.startRunning()
                    }
                    if !multiCamSession.isRunning, self.isMultiCamConfigured {
                        multiCamSession.startRunning()
                    }
                    continuation.resume()
                }
            }
            self.isSessionRunning = self.multiCamSession.isRunning || self.frontSession.isRunning || self.backSession.isRunning
        }
    }

    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        guard notification.userInfo?[AVCaptureSessionErrorKey] as? AVError != nil else { return }
        if !hasAttemptedRuntimeErrorRecovery {
            hasAttemptedRuntimeErrorRecovery = true
            Task<Void, Never> { @MainActor [weak self] in
                guard let self else { return }
                self.resetFirstFrameReadiness()
                let frontSession = self.frontSession
                let backSession = self.backSession
                let multiCamSession = self.multiCamSession
                await withCheckedContinuation { continuation in
                    self.sessionQueue.async {
                        if multiCamSession.isRunning { multiCamSession.stopRunning() }
                        if frontSession.isRunning { frontSession.stopRunning() }
                        if backSession.isRunning { backSession.stopRunning() }
                        Thread.sleep(forTimeInterval: 0.3)
                        if self.isMultiCamConfigured { multiCamSession.startRunning() }
                        if self.isFrontCameraConfigured { frontSession.startRunning() }
                        if self.isBackCameraConfigured { backSession.startRunning() }
                        continuation.resume()
                    }
                }
                self.isSessionRunning = self.multiCamSession.isRunning || self.frontSession.isRunning || self.backSession.isRunning
            }
        } else {
            errorMessage = L10n.string("error.camera.runtimeError")
            didFinishStartupAttempt = true
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .began {
            let handler = sessionInterruptionHandler
            Task { @MainActor [weak self] in
                handler?()
                self?.markCaptureUnavailableDueToCall()
            }
        } else if type == .ended {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopCallRecoveryPolling()
                self.isSessionInterrupted = false
                self.sessionInterruptionReason = nil
                if !self.isSessionRunning {
                    await self.restartSession()
                }
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
        configureVideoConnection(frontCamera.photoOutput?.connection(with: .video), cameraType: .front)
        configureVideoConnection(frontCamera.movieOutput?.connection(with: .video), cameraType: .front)
        configureVideoConnection(frontCamera.previewLayer.connection, cameraType: .front)
        configureVideoConnection(backCamera.connection, cameraType: .back)
        configureVideoConnection(backCamera.output?.connection(with: .video), cameraType: .back)
        configureVideoConnection(backCamera.photoOutput?.connection(with: .video), cameraType: .back)
        configureVideoConnection(backCamera.movieOutput?.connection(with: .video), cameraType: .back)
        configureVideoConnection(backCamera.previewLayer.connection, cameraType: .back)
    }

    private func installNativeOutputs(on session: AVCaptureSession, cameraType: CameraType) {
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            configurePhotoOutput(photoOutput)
            assignNativePhotoOutput(photoOutput, cameraType: cameraType)
            configureVideoConnection(photoOutput.connection(with: .video), cameraType: cameraType)
            if let device = cameraDevice(for: cameraType) {
                configurePhotoOutputDimensions(photoOutput, for: device)
            }
        }

        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            assignNativeMovieOutput(movieOutput, cameraType: cameraType)
            configureVideoConnection(movieOutput.connection(with: .video), cameraType: cameraType)
        }

        updateNativeOutputStatus()
    }

    private func assignNativePhotoOutput(_ output: AVCapturePhotoOutput, cameraType: CameraType) {
        switch cameraType {
        case .front:
            frontCamera.photoOutput = output
        case .back:
            backCamera.photoOutput = output
        }
    }

    private func cameraDevice(for cameraType: CameraType) -> AVCaptureDevice? {
        switch cameraType {
        case .front:
            return frontCamera.device
        case .back:
            return backCamera.device
        }
    }

    private func configurePhotoOutput(_ output: AVCapturePhotoOutput) {
        output.maxPhotoQualityPrioritization = .quality
        if output.isLivePhotoCaptureSupported {
            output.isLivePhotoCaptureEnabled = true
        }
    }

    private func configurePhotoOutputDimensions(_ output: AVCapturePhotoOutput, for device: AVCaptureDevice) {
        guard output.connection(with: .video) != nil else { return }
        if #available(iOS 16.0, *), let dimensions = preferredPhotoDimensions(for: device.activeFormat) {
            output.maxPhotoDimensions = dimensions
        } else {
            output.isHighResolutionCaptureEnabled = true
        }
    }

    private func configurePhotoSettings(_ settings: AVCapturePhotoSettings, for output: AVCapturePhotoOutput) {
        settings.photoQualityPrioritization = .quality
        if #available(iOS 16.0, *) {
            let dimensions = output.maxPhotoDimensions
            if dimensions.width > 0 && dimensions.height > 0 {
                settings.maxPhotoDimensions = dimensions
            }
        } else {
            settings.isHighResolutionPhotoEnabled = true
        }
    }

    @available(iOS 16.0, *)
    private func preferredPhotoDimensions(for format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        format.supportedMaxPhotoDimensions.sorted { lhs, rhs in
            photoDimensionsRank(lhs) < photoDimensionsRank(rhs)
        }.first
    }

    private func photoDimensionsRank(_ dimensions: CMVideoDimensions) -> Int {
        let width = Int(max(dimensions.width, dimensions.height))
        let height = Int(min(dimensions.width, dimensions.height))
        let pixels = width * height
        let aspectRatio = Double(width) / Double(height)
        let isFourByThree = abs(aspectRatio - 4.0 / 3.0) < 0.02
        return (isFourByThree ? 0 : 100_000_000) - pixels
    }

    private func assignNativeMovieOutput(_ output: AVCaptureMovieFileOutput, cameraType: CameraType) {
        switch cameraType {
        case .front:
            frontCamera.movieOutput = output
        case .back:
            backCamera.movieOutput = output
        }
    }

    private func updateNativeOutputStatus() {
        let hasPhotoOutputs = frontCamera.photoOutput != nil && backCamera.photoOutput != nil
        let hasMovieOutputs = frontCamera.movieOutput != nil && backCamera.movieOutput != nil
        if hasPhotoOutputs && hasMovieOutputs {
            nativeOutputStatus = .ready
        } else if frontCameraReady || backCameraReady {
            nativeOutputStatus = .fallback(L10n.string("settings.mediaOutput.fallback.usingFallback"))
        } else {
            nativeOutputStatus = .pending
        }
    }

    func captureNativePhotoPair() async throws -> NativePhotoPair {
        guard let frontOutput = frontCamera.photoOutput else {
            throw NativeOutputError.photoOutputUnavailable
        }

        async let frontData = captureNativePhotoData(from: frontOutput)
        if let backOutput = backCamera.photoOutput {
            async let backData = captureNativePhotoData(from: backOutput)
            return NativePhotoPair(frontData: try await frontData, backData: try? await backData)
        }
        return NativePhotoPair(frontData: try await frontData, backData: nil)
    }

    private func captureNativePhotoData(from output: AVCapturePhotoOutput) async throws -> Data {
        let settings = AVCapturePhotoSettings()
        configurePhotoSettings(settings, for: output)

        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = NativePhotoCaptureDelegate { [weak self] result in
                Task { @MainActor in
                    self?.activePhotoCaptureDelegates[id] = nil
                    continuation.resume(with: result)
                }
            }
            activePhotoCaptureDelegates[id] = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func captureNativeLivePhotoPair() async throws -> NativeLivePhotoPair {
        guard let frontOutput = frontCamera.photoOutput,
              frontOutput.isLivePhotoCaptureSupported,
              frontOutput.isLivePhotoCaptureEnabled else {
            throw NativeOutputError.livePhotoOutputUnavailable
        }

        async let frontCapture = captureNativeLivePhoto(from: frontOutput, cameraType: .front)
        if let backOutput = backCamera.photoOutput,
           backOutput.isLivePhotoCaptureSupported,
           backOutput.isLivePhotoCaptureEnabled {
            async let backCapture = captureNativeLivePhoto(from: backOutput, cameraType: .back)
            return NativeLivePhotoPair(front: try await frontCapture, back: try? await backCapture)
        }
        return NativeLivePhotoPair(front: try await frontCapture, back: nil)
    }

    private func captureNativeLivePhoto(from output: AVCapturePhotoOutput, cameraType: CameraType) async throws -> NativeLivePhotoCapture {
        let settings = AVCapturePhotoSettings()
        configurePhotoSettings(settings, for: output)
        let movieURL = makeNativeLivePhotoTemporaryURL(cameraType: cameraType)
        removeExistingFile(at: movieURL)
        settings.livePhotoMovieFileURL = movieURL

        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = NativeLivePhotoCaptureDelegate(movieURL: movieURL) { [weak self] result in
                Task { @MainActor in
                    self?.activeLivePhotoCaptureDelegates[id] = nil
                    continuation.resume(with: result)
                }
            }
            activeLivePhotoCaptureDelegates[id] = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func startNativeMovieRecording() throws {
        guard activeNativeMovieRecording == nil,
              let frontOutput = frontCamera.movieOutput else {
            throw NativeOutputError.movieOutputUnavailable
        }

        let frontDelegate = NativeMovieCaptureDelegate()
        let frontURL = makeNativeMovieTemporaryURL(cameraType: .front)
        removeExistingFile(at: frontURL)
        frontOutput.startRecording(to: frontURL, recordingDelegate: frontDelegate)

        var backOutput: AVCaptureMovieFileOutput?
        var backDelegate: NativeMovieCaptureDelegate?
        if let output = backCamera.movieOutput {
            let delegate = NativeMovieCaptureDelegate()
            let url = makeNativeMovieTemporaryURL(cameraType: .back)
            removeExistingFile(at: url)
            output.startRecording(to: url, recordingDelegate: delegate)
            backOutput = output
            backDelegate = delegate
        }

        activeNativeMovieRecording = ActiveNativeMovieRecording(
            frontOutput: frontOutput,
            frontDelegate: frontDelegate,
            backOutput: backOutput,
            backDelegate: backDelegate
        )
    }

    func stopNativeMovieRecording() async throws -> NativeMoviePair {
        guard let recording = activeNativeMovieRecording else {
            throw NativeOutputError.movieRecordingNotActive
        }
        activeNativeMovieRecording = nil

        if recording.frontOutput.isRecording {
            recording.frontOutput.stopRecording()
        }
        if recording.backOutput?.isRecording == true {
            recording.backOutput?.stopRecording()
        }

        let frontURL = try await recording.frontDelegate.waitForCompletion()
        let backURL = try await recording.backDelegate?.waitForCompletion()
        return NativeMoviePair(frontURL: frontURL, backURL: backURL)
    }

    private func makeNativeMovieTemporaryURL(cameraType: CameraType) -> URL {
        let name = cameraType == .front ? "front" : "back"
        return FileManager.default.temporaryDirectory.appendingPathComponent("dualcam_native_\(name)_\(UUID().uuidString).mov")
    }

    private func makeNativeLivePhotoTemporaryURL(cameraType: CameraType) -> URL {
        let name = cameraType == .front ? "front" : "back"
        return FileManager.default.temporaryDirectory.appendingPathComponent("dualcam_native_live_\(name)_\(UUID().uuidString).mov")
    }

    private func removeExistingFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func setPreferredFrameRate(_ frameRate: Int32) async {
        let normalizedFrameRate = normalizedFrameRate(frameRate)
        let devices = [frontCamera.device, backCamera.device].compactMap { $0 }
        if preferredFrameRate == normalizedFrameRate,
           effectiveFrameRate == normalizedFrameRate,
           !devices.isEmpty,
           devices.allSatisfy({ isFrameRateApplied(normalizedFrameRate, to: $0) }) {
            return
        }
        preferredFrameRate = normalizedFrameRate
        applyPreferredFrameRateIfPossible()
    }

    private func normalizedFrameRate(_ frameRate: Int32) -> Int32 {
        [24, 30, 60].contains(frameRate) ? frameRate : 30
    }

    private func isFrameRateApplied(_ frameRate: Int32, to device: AVCaptureDevice) -> Bool {
        let targetDuration = 1.0 / Double(frameRate)
        return abs(device.activeVideoMinFrameDuration.seconds - targetDuration) < 0.0005
            && abs(device.activeVideoMaxFrameDuration.seconds - targetDuration) < 0.0005
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

        configureNativePhotoOutputsForActiveFormats()
        updateFrameRateDebugInfo()
        refreshRearFocalCapability()
    }

    private func configureNativePhotoOutputsForActiveFormats() {
        if let output = frontCamera.photoOutput, let device = frontCamera.device {
            configurePhotoOutput(output)
            configurePhotoOutputDimensions(output, for: device)
        }
        if let output = backCamera.photoOutput, let device = backCamera.device {
            configurePhotoOutput(output)
            configurePhotoOutputDimensions(output, for: device)
        }
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
        let aspectRatio = Double(width) / Double(height)
        let isFourByThree = abs(aspectRatio - 4.0 / 3.0) < 0.02
        let isSixteenByNine = abs(aspectRatio - 16.0 / 9.0) < 0.02

        if isFourByThree {
            let targetPixels = 1920 * 1440
            let lowResolutionPenalty = pixels < 1280 * 960 ? 20_000_000 : 0
            return lowResolutionPenalty + abs(pixels - targetPixels)
        }

        return (isSixteenByNine ? 30_000_000 : 40_000_000) + pixels
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

    private func preferredFrontCameraDevices() -> [AVCaptureDevice] {
        availableFrontCameraDevices().sorted { frontCameraDeviceRank($0) > frontCameraDeviceRank($1) }
    }

    private func availableFrontCameraDevices() -> [AVCaptureDevice] {
        let defaults = frontDeviceTypes.compactMap { AVCaptureDevice.default($0, for: .video, position: .front) }
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: frontDeviceTypes,
            mediaType: .video,
            position: .front
        )
        return (defaults + discoverySession.devices).reduce(into: [AVCaptureDevice]()) { devices, device in
            if !devices.contains(where: { $0.uniqueID == device.uniqueID }) {
                devices.append(device)
            }
        }
    }

    private var supportsMultiCamCapture: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported && UIDevice.current.userInterfaceIdiom != .pad
    }

    private func frontCameraDeviceRank(_ device: AVCaptureDevice) -> Int {
        var rank = CameraDeviceSelection.frontCameraDeviceTypeRank(device.deviceType)
        if UIDevice.current.userInterfaceIdiom == .pad {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                rank += 200
            case .builtInTrueDepthCamera:
                rank += 100
            default:
                break
            }
        }
        return rank
    }

    private func preferredBackCameraDevices() -> [AVCaptureDevice] {
        availableBackCameraDevices().sorted { backCameraDeviceRank($0) > backCameraDeviceRank($1) }
    }

    private func availableBackCameraDevices() -> [AVCaptureDevice] {
        let defaults = rearDeviceTypes.compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: rearDeviceTypes,
            mediaType: .video,
            position: .back
        )
        return (defaults + discoverySession.devices).reduce(into: [AVCaptureDevice]()) { devices, device in
            if !devices.contains(where: { $0.uniqueID == device.uniqueID }) {
                devices.append(device)
            }
        }
    }

    private func backCameraDeviceRank(_ device: AVCaptureDevice) -> Int {
        let kinds = lensKinds(for: device)
        var rank = kinds.count * 100
        if kinds.contains(.ultra) { rank += 50 }
        if kinds.contains(.wide) { rank += 30 }
        if kinds.contains(.tele) { rank += 20 }
        if device.isVirtualDevice { rank += 10 }
        return rank
    }

    private func lensKinds(for device: AVCaptureDevice) -> Set<RearLensKind> {
        let sourceDevices = device.isVirtualDevice ? device.constituentDevices : [device]
        var kinds = Set<RearLensKind>()

        for sourceDevice in sourceDevices {
            switch sourceDevice.deviceType {
            case .builtInUltraWideCamera:
                kinds.insert(.ultra)
            case .builtInTelephotoCamera:
                kinds.insert(.tele)
            case .builtInWideAngleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera:
                kinds.insert(.wide)
            default:
                break
            }
        }

        if kinds.isEmpty {
            kinds.insert(.wide)
        }
        return kinds
    }

    private func refreshRearFocalCapability() {
        guard let device = backCamera.device else {
            rearFocalDeviceZoomScale = 1
            rearFocalCapability = .fallback
            rearZoomFactor = 1
            return
        }

        let lensKinds = lensKinds(for: device)
        rearFocalDeviceZoomScale = productZoomScale(for: device, lensKinds: lensKinds)
        let capability = rearFocalCapability(for: device, activeLensKinds: lensKinds)
        rearFocalCapability = capability
        rearZoomFactor = capability.clampedZoomFactor(device.videoZoomFactor / rearFocalDeviceZoomScale)
    }

    private func rearFocalCapability(for activeDevice: AVCaptureDevice, activeLensKinds: Set<RearLensKind>) -> RearFocalCapability {
        let allBackDevices = availableBackCameraDevices()
        var productMinZoom = activeDevice.minAvailableVideoZoomFactor / rearFocalDeviceZoomScale
        var productMaxZoom = activeDevice.maxAvailableVideoZoomFactor / rearFocalDeviceZoomScale
        var lensMap: [CGFloat: RearLensKind] = [:]

        for device in allBackDevices {
            let kinds = lensKinds(for: device)
            let scale = productZoomScale(for: device, lensKinds: kinds)
            productMinZoom = min(productMinZoom, device.minAvailableVideoZoomFactor / scale)
            productMaxZoom = max(productMaxZoom, device.maxAvailableVideoZoomFactor / scale)
            lensMap.merge(physicalLensByProductZoom(for: device, lensKinds: kinds, productZoomScale: scale)) { current, _ in current }
        }
        lensMap.merge(fieldOfViewLensByProductZoom(from: allBackDevices)) { current, _ in current }

        if lensMap.isEmpty {
            let fallbackZoom = min(max(1, productMinZoom), productMaxZoom)
            lensMap[fallbackZoom] = activeLensKinds.contains(.wide) ? .wide : (activeLensKinds.sorted { $0.rawValue < $1.rawValue }.first ?? .wide)
        }

        let nativeMaxZoom = min(productMaxZoom, nativeMaximumProductZoom(physicalLensByZoom: lensMap))
        return RearFocalCapability(
            minZoomFactor: productMinZoom,
            maxZoomFactor: nativeMaxZoom,
            physicalLensByZoom: lensMap
        )
    }

    private func physicalLensByProductZoom(
        for device: AVCaptureDevice,
        lensKinds: Set<RearLensKind>,
        productZoomScale: CGFloat
    ) -> [CGFloat: RearLensKind] {
        let productMinZoom = device.minAvailableVideoZoomFactor / productZoomScale
        let productMaxZoom = device.maxAvailableVideoZoomFactor / productZoomScale
        let switchOverZooms = device.virtualDeviceSwitchOverVideoZoomFactors
            .map { CGFloat(truncating: $0) / productZoomScale }
            .sorted()
        var lensMap: [CGFloat: RearLensKind] = [:]

        if lensKinds.contains(.ultra), productMinZoom < 1 {
            lensMap[productMinZoom] = .ultra
        }
        if lensKinds.contains(.wide), productMinZoom - 0.001 <= 1, 1 <= productMaxZoom + 0.001 {
            lensMap[1] = .wide
        }
        if lensKinds.contains(.tele) {
            for zoom in switchOverZooms where zoom > 1.01 {
                lensMap[zoom] = .tele
            }
        }

        return lensMap
    }

    private func fieldOfViewLensByProductZoom(from devices: [AVCaptureDevice]) -> [CGFloat: RearLensKind] {
        let physicalDevices = devices.flatMap { device in
            device.isVirtualDevice ? device.constituentDevices : [device]
        }.reduce(into: [AVCaptureDevice]()) { result, device in
            if device.position == .back, !result.contains(where: { $0.uniqueID == device.uniqueID }) {
                result.append(device)
            }
        }
        guard let wideDevice = physicalDevices.first(where: { $0.deviceType == .builtInWideAngleCamera }) else {
            return [:]
        }

        let wideFOV = CGFloat(wideDevice.activeFormat.videoFieldOfView) * .pi / 180
        guard wideFOV > 0 else { return [:] }
        var lensMap: [CGFloat: RearLensKind] = [1: .wide]

        for device in physicalDevices {
            let fov = CGFloat(device.activeFormat.videoFieldOfView) * .pi / 180
            guard fov > 0 else { continue }
            let productZoom = tan(wideFOV / 2) / tan(fov / 2)
            let roundedZoom = nativeRoundedZoom(productZoom)

            switch device.deviceType {
            case .builtInUltraWideCamera where roundedZoom < 1:
                lensMap[roundedZoom] = .ultra
            case .builtInTelephotoCamera where roundedZoom > 1:
                lensMap[roundedZoom] = .tele
            case .builtInWideAngleCamera:
                lensMap[1] = .wide
            default:
                break
            }
        }

        return lensMap
    }

    private func nativeMaximumProductZoom(physicalLensByZoom: [CGFloat: RearLensKind]) -> CGFloat {
        let teleZooms = physicalLensByZoom.compactMap { zoom, kind in
            kind == .tele ? zoom : nil
        }
        let highestTeleZoom = teleZooms.max() ?? 1

        if highestTeleZoom >= 4.5 {
            return 25
        }
        if highestTeleZoom >= 2.5 {
            return 15
        }
        if highestTeleZoom >= 1.5 {
            return 10
        }
        return physicalLensByZoom.keys.contains(where: { $0 < 1 }) ? 5 : 3
    }

    private func nativeRoundedZoom(_ zoomFactor: CGFloat) -> CGFloat {
        let nativeStops: [CGFloat] = [0.5, 1, 2, 3, 5]
        if let nearestStop = nativeStops.min(by: { abs($0 - zoomFactor) < abs($1 - zoomFactor) }),
           abs(nearestStop - zoomFactor) < 0.35 {
            return nearestStop
        }
        return (zoomFactor * 10).rounded() / 10
    }

    private func productZoomScale(for device: AVCaptureDevice, lensKinds: Set<RearLensKind>) -> CGFloat {
        guard device.isVirtualDevice, lensKinds.contains(.ultra) else { return 1 }
        let switchOverZooms = device.virtualDeviceSwitchOverVideoZoomFactors
            .map { CGFloat(truncating: $0) }
            .sorted()
        return switchOverZooms.first ?? 2
    }

    private func setupMultiCamSession() async {
        guard !isMultiCamConfigured else { return }

        do {
            guard !preferredFrontCameraDevices().isEmpty else {
                errorMessage = L10n.string("error.camera.frontNotFound")
                return
            }

            multiCamSession.beginConfiguration()

            var selectedFrontDevice: AVCaptureDevice?
            var selectedFrontInput: AVCaptureDeviceInput?
            for candidate in preferredFrontCameraDevices() {
                let input = try AVCaptureDeviceInput(device: candidate)
                if multiCamSession.canAddInput(input) {
                    selectedFrontDevice = candidate
                    selectedFrontInput = input
                    break
                }
            }

            guard let frontDevice = selectedFrontDevice, let frontInput = selectedFrontInput else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddFrontInput")
                return
            }

            multiCamSession.addInputWithNoConnections(frontInput)
            frontCamera.device = frontDevice
            frontCamera.input = frontInput

            var selectedBackDevice: AVCaptureDevice?
            var selectedBackInput: AVCaptureDeviceInput?
            for candidate in preferredBackCameraDevices() {
                let input = try AVCaptureDeviceInput(device: candidate)
                if multiCamSession.canAddInput(input) {
                    selectedBackDevice = candidate
                    selectedBackInput = input
                    break
                }
            }

            guard let backDevice = selectedBackDevice, let backInput = selectedBackInput else {
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

            let frontPhotoOutput = AVCapturePhotoOutput()
            if multiCamSession.canAddOutput(frontPhotoOutput) {
                multiCamSession.addOutputWithNoConnections(frontPhotoOutput)
                configurePhotoOutput(frontPhotoOutput)
                frontCamera.photoOutput = frontPhotoOutput
            }

            let backPhotoOutput = AVCapturePhotoOutput()
            if multiCamSession.canAddOutput(backPhotoOutput) {
                multiCamSession.addOutputWithNoConnections(backPhotoOutput)
                configurePhotoOutput(backPhotoOutput)
                backCamera.photoOutput = backPhotoOutput
            }

            let frontMovieOutput = AVCaptureMovieFileOutput()
            if multiCamSession.canAddOutput(frontMovieOutput) {
                multiCamSession.addOutputWithNoConnections(frontMovieOutput)
                frontCamera.movieOutput = frontMovieOutput
            }

            let backMovieOutput = AVCaptureMovieFileOutput()
            if multiCamSession.canAddOutput(backMovieOutput) {
                multiCamSession.addOutputWithNoConnections(backMovieOutput)
                backCamera.movieOutput = backMovieOutput
            }

            guard let frontPort = frontInput.ports(for: .video, sourceDeviceType: frontDevice.deviceType, sourceDevicePosition: .front).first,
                  let backPort = backInput.ports(for: .video, sourceDeviceType: backDevice.deviceType, sourceDevicePosition: .back).first else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotConnect")
                return
            }

            var didAddFrontOutputConnection = false
            var didAddFrontPreviewConnection = false
            var didAddBackOutputConnection = false
            var didAddBackPreviewConnection = false

            let frontOutputConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
            if multiCamSession.canAddConnection(frontOutputConnection) {
                multiCamSession.addConnection(frontOutputConnection)
                frontCamera.connection = frontOutputConnection
                configureVideoConnection(frontOutputConnection, cameraType: .front)
                didAddFrontOutputConnection = true
            }

            if let frontPhotoOutput = frontCamera.photoOutput {
                let connection = AVCaptureConnection(inputPorts: [frontPort], output: frontPhotoOutput)
                if multiCamSession.canAddConnection(connection) {
                    multiCamSession.addConnection(connection)
                    configureVideoConnection(connection, cameraType: .front)
                    configurePhotoOutputDimensions(frontPhotoOutput, for: frontDevice)
                }
            }

            if let frontMovieOutput = frontCamera.movieOutput {
                let connection = AVCaptureConnection(inputPorts: [frontPort], output: frontMovieOutput)
                if multiCamSession.canAddConnection(connection) {
                    multiCamSession.addConnection(connection)
                    configureVideoConnection(connection, cameraType: .front)
                }
            }

            let frontPreviewConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontCamera.previewLayer)
            if multiCamSession.canAddConnection(frontPreviewConnection) {
                multiCamSession.addConnection(frontPreviewConnection)
                configureVideoConnection(frontPreviewConnection, cameraType: .front)
                didAddFrontPreviewConnection = true
            }

            let backOutputConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
            if multiCamSession.canAddConnection(backOutputConnection) {
                multiCamSession.addConnection(backOutputConnection)
                backCamera.connection = backOutputConnection
                configureVideoConnection(backOutputConnection, cameraType: .back)
                didAddBackOutputConnection = true
            }

            if let backPhotoOutput = backCamera.photoOutput {
                let connection = AVCaptureConnection(inputPorts: [backPort], output: backPhotoOutput)
                if multiCamSession.canAddConnection(connection) {
                    multiCamSession.addConnection(connection)
                    configureVideoConnection(connection, cameraType: .back)
                    configurePhotoOutputDimensions(backPhotoOutput, for: backDevice)
                }
            }

            if let backMovieOutput = backCamera.movieOutput {
                let connection = AVCaptureConnection(inputPorts: [backPort], output: backMovieOutput)
                if multiCamSession.canAddConnection(connection) {
                    multiCamSession.addConnection(connection)
                    configureVideoConnection(connection, cameraType: .back)
                }
            }

            let backPreviewConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backCamera.previewLayer)
            if multiCamSession.canAddConnection(backPreviewConnection) {
                multiCamSession.addConnection(backPreviewConnection)
                configureVideoConnection(backPreviewConnection, cameraType: .back)
                didAddBackPreviewConnection = true
            }

            let frontReady = CameraDeviceSelection.isMultiCamCameraReady(
                hasOutputConnection: didAddFrontOutputConnection,
                hasPreviewConnection: didAddFrontPreviewConnection
            )
            let backReady = CameraDeviceSelection.isMultiCamCameraReady(
                hasOutputConnection: didAddBackOutputConnection,
                hasPreviewConnection: didAddBackPreviewConnection
            )
            guard frontReady && backReady else {
                multiCamSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotConnect")
                return
            }

            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
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
                } catch {
                    multiCamSession.commitConfiguration()
                    if isCaptureDeviceUnavailableError(error) {
                        markCaptureUnavailableDueToCall()
                        return
                    }
                    throw error
                }
            }

            multiCamSession.commitConfiguration()
            isMultiCamConfigured = true
            isFrontCameraConfigured = true
            isBackCameraConfigured = true
            isAudioConfigured = audioOutput != nil
            frontCameraReady = true
            backCameraReady = true
            updateNativeOutputStatus()

        } catch {
            multiCamSession.commitConfiguration()
            errorMessage = L10n.string("error.camera.multiSetupFailed", error.localizedDescription)
        }
    }

    /// 设置前置摄像头
    private func setupFrontCamera() async {
        guard !isFrontCameraConfigured else { return }

        do {
            guard !preferredFrontCameraDevices().isEmpty else {
                errorMessage = L10n.string("error.camera.frontNotFound")
                return
            }

            frontSession.beginConfiguration()
            frontSession.sessionPreset = .hd1280x720

            var selectedDevice: AVCaptureDevice?
            var selectedInput: AVCaptureDeviceInput?
            for candidate in preferredFrontCameraDevices() {
                let input = try AVCaptureDeviceInput(device: candidate)
                if frontSession.canAddInput(input) {
                    selectedDevice = candidate
                    selectedInput = input
                    break
                }
            }

            guard let device = selectedDevice, let input = selectedInput else {
                frontSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddFrontInput")
                return
            }

            frontSession.addInput(input)
            frontCamera.device = device
            frontCamera.input = input
            applyPreferredFrameRateIfPossible()

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: frontVideoDataOutputQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            guard frontSession.canAddOutput(videoOutput) else {
                frontSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddFrontOutput")
                return
            }
            frontSession.addOutput(videoOutput)
            frontCamera.output = videoOutput
            _frontVideoOutput = videoOutput

            guard let connection = videoOutput.connection(with: .video) else {
                frontSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotConnect")
                return
            }
            frontCamera.connection = connection
            configureVideoConnection(connection, cameraType: .front)
            installNativeOutputs(on: frontSession, cameraType: .front)

            frontSession.commitConfiguration()
            isFrontCameraConfigured = CameraDeviceSelection.isSingleSessionCameraReady(
                didAddInput: true,
                didAddOutput: true,
                hasVideoConnection: true
            )
            frontCameraReady = isFrontCameraConfigured
            updateNativeOutputStatus()

        } catch {
            frontSession.commitConfiguration()
            errorMessage = L10n.string("error.camera.frontSetupFailed", error.localizedDescription)
        }
    }
    
    /// 设置后置摄像头
    private func setupBackCamera() async {
        guard !isBackCameraConfigured else { return }

        do {
            backSession.beginConfiguration()
            backSession.sessionPreset = .hd1280x720

            var selectedDevice: AVCaptureDevice?
            var selectedInput: AVCaptureDeviceInput?
            for candidate in preferredBackCameraDevices() {
                let input = try AVCaptureDeviceInput(device: candidate)
                if backSession.canAddInput(input) {
                    selectedDevice = candidate
                    selectedInput = input
                    break
                }
            }

            guard let device = selectedDevice, let input = selectedInput else {
                backSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.backNotFound")
                return
            }

            backCamera.device = device
            applyPreferredFrameRateIfPossible()
            backCamera.input = input
            backSession.addInput(input)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: backVideoDataOutputQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            guard backSession.canAddOutput(videoOutput) else {
                backSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotAddBackOutput")
                return
            }
            backSession.addOutput(videoOutput)
            backCamera.output = videoOutput
            _backVideoOutput = videoOutput

            guard let connection = videoOutput.connection(with: .video) else {
                backSession.commitConfiguration()
                errorMessage = L10n.string("error.camera.cannotConnect")
                return
            }
            backCamera.connection = connection
            configureVideoConnection(connection, cameraType: .back)
            installNativeOutputs(on: backSession, cameraType: .back)

            backSession.commitConfiguration()
            isBackCameraConfigured = CameraDeviceSelection.isSingleSessionCameraReady(
                didAddInput: true,
                didAddOutput: true,
                hasVideoConnection: true
            )
            backCameraReady = isBackCameraConfigured
            updateNativeOutputStatus()

        } catch {
            backSession.commitConfiguration()
            errorMessage = L10n.string("error.camera.backSetupFailed", error.localizedDescription)
        }
    }

    private func setupAudio() async {
        await setupAudio(on: backSession)
    }

    private func setupAudio(on session: AVCaptureSession) async {
        guard !isAudioConfigured else { return }

        do {
            guard let device = AVCaptureDevice.default(for: .audio) else {
                errorMessage = L10n.string("error.microphone.notFound")
                return
            }

            session.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: device)
            audioInput = input
            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
            audioOutput = output
            _audioOutput = output

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            session.commitConfiguration()
            isAudioConfigured = true

        } catch {
            session.commitConfiguration()
            if isCaptureDeviceUnavailableError(error) {
                markCaptureUnavailableDueToCall()
            } else {
                errorMessage = L10n.string("error.microphone.setupFailed", error.localizedDescription)
            }
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
        setRearZoomFactor(factor)
    }

    func setRearZoomFactor(_ factor: CGFloat) {
        guard let device = backCamera.device else { return }
        let productZoomFactor = rearFocalCapability.clampedZoomFactor(factor)
        let rawZoomFactor = min(
            max(productZoomFactor * rearFocalDeviceZoomScale, device.minAvailableVideoZoomFactor),
            min(device.maxAvailableVideoZoomFactor, rearFocalCapability.maxZoomFactor * rearFocalDeviceZoomScale)
        )

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = rawZoomFactor
            device.unlockForConfiguration()
            rearZoomFactor = rearFocalCapability.clampedZoomFactor(rawZoomFactor / rearFocalDeviceZoomScale)
        } catch {
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

    nonisolated private func noteFirstVideoFrame(isFront: Bool) {
        Task { @MainActor [weak self] in
            self?.markFirstVideoFrame(isFront: isFront)
        }
    }

    nonisolated private func noteIPadFrontFrame() {
        guard isIPadDelayedRearStartupActive else { return }

        iPadLastFrontFrameTime = Date.timeIntervalSinceReferenceDate
        guard !iPadRearStartupRequested, !iPadRearFallbackTriggered else { return }

        iPadFrontFramesSinceStartup += 1
        guard iPadFrontFramesSinceStartup >= 3 else { return }

        iPadRearStartupRequested = true
        Task { @MainActor [weak self] in
            await self?.startDelayedIPadRearCaptureIfNeeded()
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
            noteFirstVideoFrame(isFront: true)
            noteIPadFrontFrame()
            frontVideoFrameHandler?(sampleBuffer)
        } else if output === backRef {
            trackMeasuredFrameRate(sampleBuffer: sampleBuffer, isFront: false)
            noteFirstVideoFrame(isFront: false)
            backVideoFrameHandler?(sampleBuffer)
        } else if output === audioRef {
            audioSampleBufferHandler?(sampleBuffer)
        }
    }
}
