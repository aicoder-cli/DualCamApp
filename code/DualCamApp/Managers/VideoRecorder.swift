//
//  VideoRecorder.swift
//  DualCamApp
//
//  视频录制引擎 - 负责合成双摄像头画面并录制视频
//

@preconcurrency import AVFoundation
import Combine
import UIKit
import ImageIO
@preconcurrency import Photos
import VideoToolbox

/// 录制状态
enum RecordingState {
    case idle
    case preparing
    case recording
    case stopping
    case saving
}

/// 视频录制器
class VideoRecorder: ObservableObject {
    
    // MARK: - Published Properties
    @Published var recordingState: RecordingState = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordedDurationString: String = "00:00"
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var isRecording = false
    private var isNativeMovieRecordingActive = false
    private var nativeMovieRecordingStartedAt: Date?
    private var nativeMovieLayoutTimeline: [WorkLayoutTimelineEntry] = []
    private var startTime: CMTime?
    private var lastFrameTime: CMTime?
    private var frameDuration = CMTime(value: 1, timescale: 30)
    private var nextVideoFrameTime: CMTime?
    private var frontFrameTime: CMTime?
    private var backFrameTime: CMTime?
    private var latestFramePresentationTime: CMTime?

    private var outputURL: URL?
    private var photoSize: CGSize
    private var videoSize: CGSize
    private var frameRate: Int32 = 30
    private var latestLayoutIdentifier = LayoutType.pictureInPicture.rawValue
    var workCompletedHandler: ((RecordedWorkDraft) -> Void)?
    private let livePhotoFrameInterval = CMTime(value: 1, timescale: 30)
    private let ciContext = CIContext()
    private var livePhotoRecorder: LivePhotoRecorder?
    private var isCapturingLivePhoto = false
    private var isLivePhotoPrebufferingEnabled = false
    private var livePhotoPrebufferDuration = CMTime(seconds: 1.25, preferredTimescale: 600)
    private var lastLivePhotoFrameTime: CMTime?
    private var lastLivePhotoPrebufferFrameTime: CMTime?
    private var livePhotoPrebuffer: [LivePhotoBufferedFrame] = []
    private var isLivePhotoAudioPrebufferingEnabled = false
    private var livePhotoAudioPrebufferDuration = CMTime(seconds: 1.25, preferredTimescale: 600)
    private var livePhotoTimelineOrigin: CMTime?
    private var livePhotoCaptureEndTime: CMTime?
    private var livePhotoAudioPrebuffer: [LivePhotoBufferedAudioSample] = []

    var outputPhotoSize: CGSize { photoSize }
    var outputVideoSize: CGSize { videoSize }

    func applyOutputSpec(_ spec: MediaOutputSpec) {
        guard recordingState == .idle else { return }
        photoSize = spec.photoSize
        videoSize = spec.videoSize
        isCompositorPrewarmed = false
    }
    
    // 视频帧缓存
    private var frontFrameBuffer: CVPixelBuffer?
    private var backFrameBuffer: CVPixelBuffer?
    private var latestLayoutSnapshot: RecordingLayoutSnapshot?
    private var isCompositorPrewarmScheduled = false
    private var isCompositorPrewarmed = false
    private let frameStateLock = NSLock()

    private struct CurrentFrameState {
        let frontBuffer: CVPixelBuffer?
        let backBuffer: CVPixelBuffer?
        let snapshot: RecordingLayoutSnapshot?
        let presentationTime: CMTime?
    }

    private enum LayerContentMode {
        case aspectFill
        case aspectFit
    }

    private struct LivePhotoBufferedFrame {
        let pixelBuffer: CVPixelBuffer
        let presentationTime: CMTime
    }

    private struct LivePhotoBufferedAudioSample {
        let sampleBuffer: CMSampleBuffer
        let presentationTime: CMTime
        let endTime: CMTime
    }

    // 帧处理队列
    private let processingQueue = DispatchQueue(label: "com.dualcamera.recording", qos: .userInteractive)
    private let mediaWritingQueue = DispatchQueue(label: "com.dualcamera.mediaWriting", qos: .userInitiated)
    private let processingSemaphore = DispatchSemaphore(value: 1)
    
    // MARK: - Initialization
    init() {
        photoSize = PhotoAspectRatio.threeByFour.outputSize
        videoSize = VideoResolution.p1080.outputSize
    }
    
    // MARK: - Recording Control

    @MainActor
    func startNativeMovieRecordingSession(frameRate: Int32, initialLayoutSnapshot: RecordingLayoutSnapshot) -> Bool {
        guard recordingState == .idle else { return false }
        self.frameRate = normalizedFrameRate(frameRate)
        self.frameDuration = CMTime(value: 1, timescale: self.frameRate)
        recordingState = .preparing

        do {
            try setupAssetWriter()
            prewarmCompositorIfNeeded()
            nativeMovieRecordingStartedAt = Date()
            nativeMovieLayoutTimeline = [WorkLayoutTimelineEntry(time: .zero, snapshot: initialLayoutSnapshot)]
            recordingState = .recording
            isRecording = true
            isNativeMovieRecordingActive = true
            startTime = nil
            lastFrameTime = nil
            nextVideoFrameTime = nil
            recordingDuration = 0
            recordedDurationString = "00:00"
            startDurationTimer()
            return true
        } catch {
            errorMessage = L10n.string("error.recording.initializationFailed", error.localizedDescription)
            resetRecordingState()
            return false
        }
    }

    @MainActor
    func updateNativeMovieRecordingLayout(_ snapshot: RecordingLayoutSnapshot) {
        guard isNativeMovieRecordingActive,
              let nativeMovieRecordingStartedAt else { return }
        let elapsed = Date().timeIntervalSince(nativeMovieRecordingStartedAt)
        nativeMovieLayoutTimeline.append(
            WorkLayoutTimelineEntry(
                time: CMTime(seconds: max(0, elapsed), preferredTimescale: 600),
                snapshot: snapshot
            )
        )
    }

    @MainActor
    func finishNativeMovieRecording(
        frontURL: URL,
        backURL: URL?,
        layoutSnapshot: RecordingLayoutSnapshot,
        saveToSystemPhotos: Bool = false
    ) async {
        guard recordingState == .recording, isNativeMovieRecordingActive else { return }
        recordingState = .stopping
        isRecording = false
        isNativeMovieRecordingActive = false

        processingQueue.sync {}
        mediaWritingQueue.sync {}

        let layoutTimeline = nativeMovieLayoutTimeline.isEmpty
            ? [WorkLayoutTimelineEntry(time: .zero, snapshot: layoutSnapshot)]
            : nativeMovieLayoutTimeline
        let completedDuration = recordingDuration

        guard startTime != nil else {
            errorMessage = L10n.string("error.album.noRecordedVideo")
            resetRecordingState()
            return
        }

        guard assetWriter?.status == .writing else {
            errorMessage = L10n.string("error.video.writeFailed", assetWriter?.error?.localizedDescription ?? L10n.string("error.recorder.invalidState"))
            resetRecordingState()
            return
        }

        markInputsAsFinished()

        guard await finishWriting() else {
            resetRecordingState()
            return
        }

        recordingState = .saving

        do {
            guard let completedURL = outputURL,
                  FileManager.default.fileExists(atPath: completedURL.path) else {
                throw NSError(domain: "DualCamApp", code: -61, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.album.recordingFileMissing")])
            }

            let frontOriginalURL = try persistNativeOriginalMovie(from: frontURL, cameraName: "front")
            let backOriginalURL = try backURL.map { try persistNativeOriginalMovie(from: $0, cameraName: "back") }

            workCompletedHandler?(
                RecordedWorkDraft(
                    kind: .video,
                    assetURL: completedURL,
                    pairedVideoURL: nil,
                    frontOriginalURL: frontOriginalURL,
                    backOriginalURL: backOriginalURL,
                    highQualityRenderStatus: .notStarted,
                    layoutTimeline: layoutTimeline,
                    createdAt: Date(),
                    duration: completedDuration,
                    layout: latestLayoutIdentifier,
                    resolution: layoutSnapshot.outputSize,
                    frameRate: Int(frameRate),
                    isLivePhoto: false
                )
            )

            if saveToSystemPhotos {
                await saveToPhotoLibrary()
            }
        } catch {
            errorMessage = L10n.string("error.video.writeFailed", error.localizedDescription)
        }

        resetRecordingState()
    }

    @MainActor
    func cancelNativeMovieRecordingSession(error: Error) {
        guard isNativeMovieRecordingActive else { return }
        errorMessage = L10n.string("error.video.writeFailed", error.localizedDescription)
        resetRecordingState()
    }

    /// 开始录制
    @MainActor
    func startRecording(frameRate: Int32) async {
        guard recordingState == .idle else { return }

        self.frameRate = normalizedFrameRate(frameRate)
        self.frameDuration = CMTime(value: 1, timescale: self.frameRate)
        recordingState = .preparing

        do {
            try setupAssetWriter()
            prewarmCompositorIfNeeded()
            recordingState = .recording
            isRecording = true
            startTime = nil
            lastFrameTime = nil
            nextVideoFrameTime = nil

            // 启动计时器
            startDurationTimer()
            
        } catch {
            errorMessage = L10n.string("error.recording.initializationFailed", error.localizedDescription)
            recordingState = .idle
        }
    }
    
    /// 停止录制
    @MainActor
    func stopRecording(saveToSystemPhotos: Bool = false) async {
        guard recordingState == .recording else { return }
        
        recordingState = .stopping
        isRecording = false

        processingQueue.sync {}
        mediaWritingQueue.sync {}

        guard startTime != nil else {
            errorMessage = L10n.string("error.album.noRecordedVideo")
            resetRecordingState()
            return
        }

        guard assetWriter?.status == .writing else {
            errorMessage = L10n.string("error.video.writeFailed", assetWriter?.error?.localizedDescription ?? L10n.string("error.recorder.invalidState"))
            resetRecordingState()
            return
        }

        markInputsAsFinished()

        guard await finishWriting() else {
            resetRecordingState()
            return
        }

        recordingState = .saving

        if let completedURL = outputURL,
           FileManager.default.fileExists(atPath: completedURL.path) {
            workCompletedHandler?(
                RecordedWorkDraft(
                    kind: .video,
                    assetURL: completedURL,
                    pairedVideoURL: nil,
                    createdAt: Date(),
                    duration: recordingDuration,
                    layout: latestLayoutIdentifier,
                    resolution: videoSize,
                    frameRate: Int(frameRate),
                    isLivePhoto: false
                )
            )
        }

        if saveToSystemPhotos {
            await saveToPhotoLibrary()
        }

        resetRecordingState()
    }
    
    // MARK: - Setup Methods

    private func normalizedFrameRate(_ frameRate: Int32) -> Int32 {
        [24, 30, 60].contains(frameRate) ? frameRate : 30
    }

    private func videoBitRate(for frameRate: Int32) -> Int {
        frameRate >= 60 ? 8_000_000 : 4_000_000
    }

    /// 设置资源写入器
    private func setupAssetWriter() throws {
        let recordingURL = makeOutputURL()
        outputURL = recordingURL

        if FileManager.default.fileExists(atPath: recordingURL.path) {
            try FileManager.default.removeItem(at: recordingURL)
        }

        // 创建资源写入器
        assetWriter = try AVAssetWriter(url: recordingURL, fileType: .mp4)
        
        // 视频输入配置
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate(for: frameRate),
                AVVideoExpectedSourceFrameRateKey: Int(frameRate),
                AVVideoMaxKeyFrameIntervalKey: Int(frameRate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        // 像素缓冲适配器
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoSize.width,
            kCVPixelBufferHeightKey as String: videoSize.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        // 音频输入配置
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: CaptureAudioSettings.aac)
        audioInput?.expectsMediaDataInRealTime = true
        
        guard let assetWriter, let videoInput else {
            throw NSError(domain: "DualCamApp", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.recorder.initializationFailed")])
        }

        guard assetWriter.canAdd(videoInput) else {
            throw NSError(domain: "DualCamApp", code: -2, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotAddInput")])
        }
        assetWriter.add(videoInput)

        if let audioInput, assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        }

        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? NSError(domain: "DualCamApp", code: -3, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotStartWriting")])
        }
    }
    
    func prewarmCompositorIfNeeded() {
        guard recordingState == .idle || recordingState == .preparing else { return }
        guard !isCompositorPrewarmScheduled, !isCompositorPrewarmed else { return }
        isCompositorPrewarmScheduled = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            self.runCompositorPrewarm()
            DispatchQueue.main.async { [weak self] in
                self?.isCompositorPrewarmScheduled = false
                self?.isCompositorPrewarmed = true
            }
        }
    }

    private func runCompositorPrewarm() {
        autoreleasepool {
            let state = currentFrameState()

            guard let frontBuffer = state.frontBuffer,
                  let snapshot = state.snapshot else {
                _ = makeOutputPixelBuffer(size: videoSize)
                return
            }

            _ = renderCompositePixelBuffer(
                frontBuffer: frontBuffer,
                backBuffer: state.backBuffer,
                layoutSnapshot: snapshot
            )
        }
    }

    private func markInputsAsFinished() {
        guard let assetWriter else { return }

        if let videoInput, assetWriter.inputs.contains(where: { $0 === videoInput }) {
            videoInput.markAsFinished()
        }
        if let audioInput, assetWriter.inputs.contains(where: { $0 === audioInput }) {
            audioInput.markAsFinished()
        }
    }

    /// 完成写入
    @MainActor
    private func finishWriting() async -> Bool {
        guard let assetWriter else {
            errorMessage = L10n.string("error.album.recorderNotInitialized")
            return false
        }
        nonisolated(unsafe) let writer = assetWriter

        return await withCheckedContinuation { continuation in
            writer.finishWriting { [weak self] in
                let didComplete = writer.status == .completed
                if !didComplete {
                    let message = L10n.string("error.video.writeFailed", writer.error?.localizedDescription ?? String(describing: writer.status))
                    Task { @MainActor [weak self] in
                        self?.errorMessage = message
                    }
                }
                continuation.resume(returning: didComplete)
            }
        }
    }
    
    // MARK: - Frame Processing

    func updateLayoutSnapshot(_ snapshot: RecordingLayoutSnapshot) {
        frameStateLock.lock()
        latestLayoutSnapshot = snapshot
        frameStateLock.unlock()
        if recordingState == .idle {
            isCompositorPrewarmed = false
        }
    }

    func updateWorkLayout(_ layout: LayoutType) {
        latestLayoutIdentifier = layout.rawValue
    }

    func setLivePhotoPrebufferingEnabled(_ enabled: Bool, duration: TimeInterval) {
        let preDuration = min(max(duration, 1.0) / 2.0, 1.5)
        let prebufferDuration = CMTime(seconds: preDuration, preferredTimescale: 600)
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.isLivePhotoPrebufferingEnabled = enabled
            self.livePhotoPrebufferDuration = prebufferDuration
            if !enabled {
                self.livePhotoPrebuffer.removeAll(keepingCapacity: true)
                self.lastLivePhotoPrebufferFrameTime = nil
            }
        }
        mediaWritingQueue.async { [weak self] in
            guard let self else { return }
            self.isLivePhotoAudioPrebufferingEnabled = enabled
            self.livePhotoAudioPrebufferDuration = prebufferDuration
            if !enabled {
                self.livePhotoAudioPrebuffer.removeAll(keepingCapacity: true)
                self.livePhotoTimelineOrigin = nil
                self.livePhotoCaptureEndTime = nil
            }
        }
    }

    private func updateFrameState(pixelBuffer: CVPixelBuffer, isFront: Bool, presentationTime: CMTime) -> CurrentFrameState {
        frameStateLock.lock()
        if isFront {
            frontFrameBuffer = pixelBuffer
            frontFrameTime = presentationTime
        } else {
            backFrameBuffer = pixelBuffer
            backFrameTime = presentationTime
        }
        latestFramePresentationTime = presentationTime
        let state = CurrentFrameState(
            frontBuffer: frontFrameBuffer,
            backBuffer: backFrameBuffer,
            snapshot: latestLayoutSnapshot,
            presentationTime: latestFramePresentationTime
        )
        frameStateLock.unlock()
        return state
    }

    private func currentFrameState() -> CurrentFrameState {
        frameStateLock.lock()
        let state = CurrentFrameState(
            frontBuffer: frontFrameBuffer,
            backBuffer: backFrameBuffer,
            snapshot: latestLayoutSnapshot,
            presentationTime: latestFramePresentationTime
        )
        frameStateLock.unlock()
        return state
    }

    func clearBackFrameBuffer() {
        frameStateLock.lock()
        backFrameBuffer = nil
        backFrameTime = nil
        frameStateLock.unlock()
    }

    /// 处理视频帧
    func processFrame(_ sampleBuffer: CMSampleBuffer, isFront: Bool) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frameState = updateFrameState(pixelBuffer: pixelBuffer, isFront: isFront, presentationTime: presentationTime)

        guard processingSemaphore.wait(timeout: .now()) == .success else { return }

        processingQueue.async { [weak self] in
            defer { self?.processingSemaphore.signal() }
            guard let self = self else { return }

            autoreleasepool {
                let frontBuffer = frameState.frontBuffer
                let backBuffer = frameState.backBuffer

                guard let snapshot = frameState.snapshot else { return }

                var livePhotoPixelBuffer: CVPixelBuffer?
                if self.shouldAppendLivePhotoPrebufferFrame(at: presentationTime),
                   let frontBuffer,
                   let backBuffer,
                   let pixelBuffer = self.renderCompositePixelBuffer(frontBuffer: frontBuffer, backBuffer: backBuffer, layoutSnapshot: snapshot) {
                    livePhotoPixelBuffer = pixelBuffer
                    self.appendLivePhotoPrebufferFrame(pixelBuffer, presentationTime: presentationTime)
                }

                if self.isCapturingLivePhoto,
                   self.shouldAppendLivePhotoFrame(at: presentationTime),
                   let livePhotoRecorder = self.livePhotoRecorder,
                   let frontBuffer,
                   let backBuffer {
                    let pixelBuffer = livePhotoPixelBuffer ?? self.renderCompositePixelBuffer(frontBuffer: frontBuffer, backBuffer: backBuffer, layoutSnapshot: snapshot)
                    if let pixelBuffer {
                        self.lastLivePhotoFrameTime = presentationTime
                        nonisolated(unsafe) let livePhotoPixelBuffer = pixelBuffer
                        self.mediaWritingQueue.async {
                            livePhotoRecorder.appendVideoFrame(livePhotoPixelBuffer, presentationTime: presentationTime)
                        }
                    }
                }

                guard self.isRecording,
                      let videoPresentationTime = self.nextVideoPresentationTime(for: presentationTime) else { return }

                if let frontBuffer {
                    self.composeAndWriteFrame(
                        frontBuffer: frontBuffer,
                        backBuffer: backBuffer,
                        layoutSnapshot: snapshot,
                        presentationTime: videoPresentationTime
                    )
                }
            }
        }
    }

    private func shouldAppendLivePhotoPrebufferFrame(at presentationTime: CMTime) -> Bool {
        guard isLivePhotoPrebufferingEnabled else { return false }
        guard presentationTime.isValid, presentationTime.isNumeric else { return false }
        guard let lastLivePhotoPrebufferFrameTime else { return true }
        return presentationTime - lastLivePhotoPrebufferFrameTime >= livePhotoFrameInterval
    }

    private func appendLivePhotoPrebufferFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        livePhotoPrebuffer.append(LivePhotoBufferedFrame(pixelBuffer: pixelBuffer, presentationTime: presentationTime))
        lastLivePhotoPrebufferFrameTime = presentationTime
        pruneLivePhotoPrebuffer(relativeTo: presentationTime)
    }

    private func pruneLivePhotoPrebuffer(relativeTo presentationTime: CMTime) {
        let cutoff = presentationTime - livePhotoPrebufferDuration
        livePhotoPrebuffer.removeAll { frame in
            frame.presentationTime < cutoff
        }
    }

    private func shouldAppendLivePhotoFrame(at presentationTime: CMTime) -> Bool {
        guard presentationTime.isValid, presentationTime.isNumeric else { return false }
        guard let lastLivePhotoFrameTime else { return true }
        return presentationTime - lastLivePhotoFrameTime >= livePhotoFrameInterval
    }

    private func nextVideoPresentationTime(for presentationTime: CMTime) -> CMTime? {
        guard presentationTime.isValid, presentationTime.isNumeric else { return nil }

        guard let nextVideoFrameTime else {
            self.nextVideoFrameTime = presentationTime + frameDuration
            return presentationTime
        }

        guard presentationTime >= nextVideoFrameTime else { return nil }

        let maxLag = CMTimeMultiply(frameDuration, multiplier: 2)
        let writeTime = presentationTime - nextVideoFrameTime > maxLag ? presentationTime : nextVideoFrameTime
        self.nextVideoFrameTime = writeTime + frameDuration
        return writeTime
    }

    @MainActor
    func captureNativePhoto(
        frontData: Data,
        backData: Data?,
        layoutSnapshot: RecordingLayoutSnapshot,
        saveToSystemPhotos: Bool = false
    ) async {
        guard recordingState == .idle else { return }
        recordingState = .saving

        do {
            let capture = try await makeNativePhotoFile(frontData: frontData, backData: backData, layoutSnapshot: layoutSnapshot)
            workCompletedHandler?(
                RecordedWorkDraft(
                    kind: .photo,
                    assetURL: capture.photoURL,
                    pairedVideoURL: nil,
                    createdAt: Date(),
                    duration: nil,
                    layout: latestLayoutIdentifier,
                    resolution: capture.outputSize,
                    frameRate: Int(frameRate),
                    isLivePhoto: false
                )
            )
            if saveToSystemPhotos {
                await savePhotoToPhotoLibrary(capture.photoURL)
            }
        } catch {
            errorMessage = L10n.string("error.photo.saveFailed", error.localizedDescription)
        }

        resetRecordingState()
    }

    @MainActor
    func captureNativeLivePhoto(
        front: NativeLivePhotoCapture,
        back: NativeLivePhotoCapture?,
        layoutSnapshot: RecordingLayoutSnapshot,
        saveToSystemPhotos: Bool = false
    ) async {
        guard recordingState == .idle else { return }
        recordingState = .saving

        defer {
            try? FileManager.default.removeItem(at: front.movieURL)
            if let back { try? FileManager.default.removeItem(at: back.movieURL) }
        }

        do {
            let capture = try await makeNativeLivePhotoFiles(front: front, back: back, layoutSnapshot: layoutSnapshot)
            workCompletedHandler?(
                RecordedWorkDraft(
                    kind: .photo,
                    assetURL: capture.photoURL,
                    pairedVideoURL: capture.movieURL,
                    createdAt: Date(),
                    duration: nil,
                    layout: latestLayoutIdentifier,
                    resolution: layoutSnapshot.outputSize,
                    frameRate: Int(frameRate),
                    isLivePhoto: true
                )
            )
            if saveToSystemPhotos {
                await saveLivePhotoToPhotoLibrary(photoURL: capture.photoURL, pairedVideoURL: capture.movieURL)
            }
        } catch {
            errorMessage = L10n.string("error.livePhoto.saveFailed", error.localizedDescription)
        }

        resetRecordingState()
    }

    @MainActor
    func capturePhoto(livePhotoEnabled: Bool, livePhotoDuration: TimeInterval = 2.5, saveToSystemPhotos: Bool = false) async {
        guard recordingState == .idle else { return }

        if livePhotoEnabled {
            await captureLivePhoto(duration: livePhotoDuration, saveToSystemPhotos: saveToSystemPhotos)
            return
        }

        recordingState = .saving

        do {
            let photoURL = try await makeCurrentPhotoFile()
            workCompletedHandler?(
                RecordedWorkDraft(
                    kind: .photo,
                    assetURL: photoURL,
                    pairedVideoURL: nil,
                    createdAt: Date(),
                    duration: nil,
                    layout: latestLayoutIdentifier,
                    resolution: photoSize,
                    frameRate: Int(frameRate),
                    isLivePhoto: false
                )
            )
            if saveToSystemPhotos {
                await savePhotoToPhotoLibrary(photoURL)
            }
        } catch {
            errorMessage = L10n.string("error.photo.saveFailed", error.localizedDescription)
        }

        resetRecordingState()
    }

    @MainActor
    private func captureLivePhoto(duration: TimeInterval, saveToSystemPhotos: Bool) async {
        recordingState = .saving
        let captureDuration = min(max(duration, 1.0), 10.0)

        do {
            let capture = try await beginLivePhotoCapture(duration: captureDuration)
            try await Task.sleep(nanoseconds: UInt64(capture.postDuration * 1_000_000_000))
            try await finishLivePhotoCapture()
            workCompletedHandler?(
                RecordedWorkDraft(
                    kind: .photo,
                    assetURL: capture.photoURL,
                    pairedVideoURL: capture.movieURL,
                    createdAt: Date(),
                    duration: captureDuration,
                    layout: latestLayoutIdentifier,
                    resolution: photoSize,
                    frameRate: Int(frameRate),
                    isLivePhoto: true
                )
            )
            if saveToSystemPhotos {
                await saveLivePhotoToPhotoLibrary(photoURL: capture.photoURL, pairedVideoURL: capture.movieURL)
            }
        } catch {
            await cancelLivePhotoCapture()
            errorMessage = L10n.string("error.livePhoto.saveFailed", error.localizedDescription)
        }

        resetRecordingState()
    }

    private func makeNativePhotoFile(frontData: Data, backData: Data?, layoutSnapshot: RecordingLayoutSnapshot) async throws -> (photoURL: URL, outputSize: CGSize) {
        try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DualCamApp", code: -20, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.photo.generatorReleased")]))
                    return
                }

                autoreleasepool {
                    guard let frontImage = UIImage(data: frontData) else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -22, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.photo.compositionFailed")]))
                        return
                    }
                    let backImage = backData.flatMap { UIImage(data: $0) }
                    let outputSnapshot = self.nativePhotoLayoutSnapshot(from: layoutSnapshot, front: frontImage, back: backImage)

                    guard let image = self.composeImages(front: frontImage, back: backImage, layoutSnapshot: outputSnapshot),
                          let imageData = image.jpegData(compressionQuality: 0.96) else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -22, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.photo.compositionFailed")]))
                        return
                    }

                    do {
                        let photoURL = self.makePhotoOutputURL()
                        try imageData.write(to: photoURL, options: .atomic)
                        continuation.resume(returning: (photoURL: photoURL, outputSize: outputSnapshot.outputSize))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func makeNativeLivePhotoFiles(front: NativeLivePhotoCapture, back: NativeLivePhotoCapture?, layoutSnapshot: RecordingLayoutSnapshot) async throws -> (photoURL: URL, movieURL: URL) {
        try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DualCamApp", code: -40, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.generatorReleased")]))
                    return
                }

                autoreleasepool {
                    guard let frontImage = UIImage(data: front.photoData) else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -42, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.stillCompositionFailed")]))
                        return
                    }
                    let backImage = back.flatMap { UIImage(data: $0.photoData) }
                    guard let image = self.composeImages(front: frontImage, back: backImage, layoutSnapshot: layoutSnapshot) else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -42, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.stillCompositionFailed")]))
                        return
                    }

                    let assetIdentifier = UUID().uuidString
                    let photoURL = self.makeLivePhotoStillOutputURL()
                    let movieURL = self.makeLivePhotoMovieOutputURL()
                    let backMovieURL = back?.movieURL
                    let stillImageTime = front.photoDisplayTime.isValid && front.photoDisplayTime.isNumeric ? front.photoDisplayTime : .zero

                    self.mediaWritingQueue.async { [weak self] in
                        guard let self else { return }
                        do {
                            try LivePhotoRecorder.writeStillImage(image, to: photoURL, assetIdentifier: assetIdentifier)
                            try self.composeNativeLivePhotoMovieFile(
                                frontURL: front.movieURL,
                                backURL: backMovieURL,
                                outputURL: movieURL,
                                layoutSnapshot: layoutSnapshot,
                                assetIdentifier: assetIdentifier,
                                stillImageTime: stillImageTime
                            )
                            continuation.resume(returning: (photoURL: photoURL, movieURL: movieURL))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    private func makeCurrentPhotoFile() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DualCamApp", code: -20, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.photo.generatorReleased")]))
                    return
                }

                autoreleasepool {
                    let state = self.currentFrameState()

                    guard let frontBuffer = state.frontBuffer,
                          let snapshot = state.snapshot else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -21, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.camera.noFrameToSave")]))
                        return
                    }

                    guard let image = self.composeImages(frontBuffer: frontBuffer, backBuffer: state.backBuffer, layoutSnapshot: snapshot),
                          let imageData = image.jpegData(compressionQuality: 0.92) else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -22, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.photo.compositionFailed")]))
                        return
                    }

                    do {
                        let photoURL = self.makePhotoOutputURL()
                        try imageData.write(to: photoURL, options: .atomic)
                        continuation.resume(returning: photoURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func beginLivePhotoCapture(duration captureDuration: TimeInterval) async throws -> (photoURL: URL, movieURL: URL, postDuration: TimeInterval) {
        try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DualCamApp", code: -40, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.generatorReleased")]))
                    return
                }

                autoreleasepool {
                    let state = self.currentFrameState()
                    let requestedPreDuration = min(captureDuration / 2.0, 1.5)
                    let preDuration = CMTime(seconds: requestedPreDuration, preferredTimescale: 600)

                    guard let shutterTime = self.livePhotoPrebuffer.last?.presentationTime ?? state.presentationTime,
                          shutterTime.isValid,
                          shutterTime.isNumeric else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -41, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.camera.noFrameToSave")]))
                        return
                    }

                    let cutoff = shutterTime - preDuration
                    var preFrames = self.livePhotoPrebuffer.filter { frame in
                        frame.presentationTime >= cutoff && frame.presentationTime <= shutterTime
                    }

                    if preFrames.isEmpty,
                       let frontBuffer = state.frontBuffer,
                       let backBuffer = state.backBuffer,
                       let snapshot = state.snapshot,
                       let pixelBuffer = self.renderCompositePixelBuffer(frontBuffer: frontBuffer, backBuffer: backBuffer, layoutSnapshot: snapshot) {
                        preFrames = [LivePhotoBufferedFrame(pixelBuffer: pixelBuffer, presentationTime: shutterTime)]
                    }

                    guard !preFrames.isEmpty,
                          let shutterFrame = preFrames.min(by: { first, second in
                              abs((first.presentationTime - shutterTime).seconds) < abs((second.presentationTime - shutterTime).seconds)
                          }) else {
                        continuation.resume(throwing: NSError(domain: "DualCamApp", code: -42, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.stillCompositionFailed")]))
                        return
                    }

                    let firstFrameTime = preFrames[0].presentationTime
                    let rawStillImageTime = shutterFrame.presentationTime - firstFrameTime
                    let stillImageTime = rawStillImageTime >= .zero ? rawStillImageTime : .zero
                    let postDuration = max(0.25, captureDuration - stillImageTime.seconds)
                    let captureEndTime = firstFrameTime + CMTime(seconds: captureDuration, preferredTimescale: 600)
                    let assetIdentifier = UUID().uuidString
                    let photoURL = self.makeLivePhotoStillOutputURL()
                    let movieURL = self.makeLivePhotoMovieOutputURL()

                    self.livePhotoRecorder = nil
                    self.lastLivePhotoFrameTime = shutterTime
                    self.isCapturingLivePhoto = true

                    let bufferedFrames = preFrames
                    let stillFrame = shutterFrame
                    self.mediaWritingQueue.async { [weak self] in
                        guard let self else { return }

                        do {
                            guard let image = self.pixelBufferToImage(stillFrame.pixelBuffer) else {
                                throw NSError(domain: "DualCamApp", code: -42, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.stillCompositionFailed")])
                            }

                            try LivePhotoRecorder.writeStillImage(image, to: photoURL, assetIdentifier: assetIdentifier)
                            let livePhotoSize = CGSize(
                                width: CVPixelBufferGetWidth(stillFrame.pixelBuffer),
                                height: CVPixelBufferGetHeight(stillFrame.pixelBuffer)
                            )
                            let recorder = try LivePhotoRecorder(
                                movieURL: movieURL,
                                videoSize: livePhotoSize,
                                assetIdentifier: assetIdentifier,
                                stillImageTime: stillImageTime
                            )
                            self.livePhotoTimelineOrigin = firstFrameTime
                            self.livePhotoCaptureEndTime = captureEndTime
                            bufferedFrames.forEach { frame in
                                recorder.appendVideoFrame(frame.pixelBuffer, presentationTime: frame.presentationTime)
                            }
                            self.livePhotoAudioSamples(in: firstFrameTime...captureEndTime).forEach { sample in
                                guard let retimedSample = Self.retimedAudioSampleBuffer(sample.sampleBuffer, timelineOrigin: firstFrameTime) else { return }
                                recorder.appendAudioSampleBuffer(retimedSample)
                            }

                            self.processingQueue.async { [weak self] in
                                guard let self else { return }
                                self.livePhotoRecorder = recorder
                                continuation.resume(returning: (photoURL: photoURL, movieURL: movieURL, postDuration: postDuration))
                            }
                        } catch {
                            self.processingQueue.async { [weak self] in
                                self?.isCapturingLivePhoto = false
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        }
    }

    private func finishLivePhotoCapture() async throws {
        let recorder: LivePhotoRecorder = try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self, let recorder = self.livePhotoRecorder else {
                    continuation.resume(throwing: NSError(domain: "DualCamApp", code: -43, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.recorderNotInitialized")]))
                    return
                }

                self.isCapturingLivePhoto = false
                self.livePhotoRecorder = nil
                self.lastLivePhotoFrameTime = nil
                continuation.resume(returning: recorder)
            }
        }

        mediaWritingQueue.sync {
            livePhotoTimelineOrigin = nil
            livePhotoCaptureEndTime = nil
        }

        try await recorder.finish()
    }

    private func cancelLivePhotoCapture() async {
        await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                self?.isCapturingLivePhoto = false
                self?.livePhotoRecorder = nil
                self?.lastLivePhotoFrameTime = nil
                self?.mediaWritingQueue.async {
                    self?.livePhotoTimelineOrigin = nil
                    self?.livePhotoCaptureEndTime = nil
                }
                continuation.resume()
            }
        }
    }

    func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording || isLivePhotoPrebufferingEnabled || isCapturingLivePhoto else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime.isNumeric else { return }
        nonisolated(unsafe) let audioSampleBuffer = sampleBuffer

        mediaWritingQueue.async { [weak self] in
            guard let self else { return }

            self.handleLivePhotoAudioSample(audioSampleBuffer, presentationTime: presentationTime)

            guard self.isRecording,
                  let audioInput = self.audioInput,
                  self.ensureSessionStarted(at: presentationTime) else { return }

            guard audioInput.isReadyForMoreMediaData else { return }

            guard audioInput.append(audioSampleBuffer) else {
                self.reportWriterFailure(context: L10n.string("error.video.writeFailed", self.assetWriter?.error?.localizedDescription ?? "Audio append failed"))
                return
            }
        }
    }

    private func handleLivePhotoAudioSample(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) {
        if isLivePhotoAudioPrebufferingEnabled {
            livePhotoAudioPrebuffer.append(
                LivePhotoBufferedAudioSample(
                    sampleBuffer: sampleBuffer,
                    presentationTime: presentationTime,
                    endTime: Self.audioSampleEndTime(sampleBuffer, presentationTime: presentationTime)
                )
            )
            pruneLivePhotoAudioPrebuffer(relativeTo: presentationTime)
        }

        guard isCapturingLivePhoto,
              let livePhotoRecorder,
              let livePhotoTimelineOrigin,
              let livePhotoCaptureEndTime,
              Self.isAudioSample(presentationTime: presentationTime, within: livePhotoTimelineOrigin...livePhotoCaptureEndTime),
              let retimedSample = Self.retimedAudioSampleBuffer(sampleBuffer, timelineOrigin: livePhotoTimelineOrigin) else { return }

        livePhotoRecorder.appendAudioSampleBuffer(retimedSample)
    }

    private func pruneLivePhotoAudioPrebuffer(relativeTo presentationTime: CMTime) {
        let cutoff = presentationTime - livePhotoAudioPrebufferDuration
        livePhotoAudioPrebuffer.removeAll { sample in
            sample.endTime < cutoff
        }
    }

    private func livePhotoAudioSamples(in range: ClosedRange<CMTime>) -> [LivePhotoBufferedAudioSample] {
        livePhotoAudioPrebuffer.filter { sample in
            Self.isAudioSample(presentationTime: sample.presentationTime, within: range)
        }
    }

    static func isAudioSample(presentationTime: CMTime, within range: ClosedRange<CMTime>) -> Bool {
        presentationTime.isValid && presentationTime.isNumeric && range.contains(presentationTime)
    }

    static func audioSampleEndTime(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) -> CMTime {
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        guard duration.isValid, duration.isNumeric else { return presentationTime }
        return presentationTime + duration
    }

    static func retimedAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, timelineOrigin: CMTime) -> CMSampleBuffer? {
        guard timelineOrigin.isValid, timelineOrigin.isNumeric else { return nil }

        var timingCount = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        )
        guard status == noErr, timingCount > 0 else { return nil }

        var timing = Array(repeating: CMSampleTimingInfo(), count: timingCount)
        status = timing.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: timingCount,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: nil
            )
        }
        guard status == noErr else { return nil }

        for index in timing.indices {
            let presentationTime = timing[index].presentationTimeStamp
            guard presentationTime.isValid, presentationTime.isNumeric else { return nil }
            timing[index].presentationTimeStamp = presentationTime - timelineOrigin

            let decodeTime = timing[index].decodeTimeStamp
            if decodeTime.isValid, decodeTime.isNumeric {
                timing[index].decodeTimeStamp = decodeTime - timelineOrigin
            }
        }

        guard let firstPresentationTime = timing.first?.presentationTimeStamp,
              firstPresentationTime >= .zero else { return nil }

        var retimedSampleBuffer: CMSampleBuffer?
        status = timing.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: timingCount,
                sampleTimingArray: buffer.baseAddress,
                sampleBufferOut: &retimedSampleBuffer
            )
        }

        guard status == noErr else { return nil }
        return retimedSampleBuffer
    }
    
    /// 合成并写入帧
    private func composeNativeMovieFile(
        frontURL: URL,
        backURL: URL?,
        layoutTimeline: [WorkLayoutTimelineEntry],
        control: HighQualityRenderControl? = nil,
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            mediaWritingQueue.async { [weak self] in
                var outputURLToRemove: URL?
                var activeFrontReader: AVAssetReader?
                var activeBackReader: AVAssetReader?
                var activeWriter: AVAssetWriter?
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DualCamApp", code: -50, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.recorder.initializationFailed")]))
                    return
                }

                do {
                    let outputURL = self.makeOutputURL()
                    outputURLToRemove = outputURL
                    progress?(0.01, L10n.string("works.highQuality.phase.preparing"))
                    try control?.waitIfNeeded()
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }

                    let normalizedLayoutTimeline = layoutTimeline.sorted { $0.time < $1.time }
                    let initialLayoutSnapshot = normalizedLayoutTimeline.first?.snapshot
                    guard let initialLayoutSnapshot else {
                        throw NSError(domain: "DualCamApp", code: -50, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.recorder.initializationFailed")])
                    }

                    let frontAsset = AVAsset(url: frontURL)
                    guard let frontVideoTrack = frontAsset.tracks(withMediaType: .video).first else {
                        throw NSError(domain: "DualCamApp", code: -51, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.album.noRecordedVideo")])
                    }

                    let frontReader = try AVAssetReader(asset: frontAsset)
                    activeFrontReader = frontReader
                    let frontVideoOutput = self.makeOrientedVideoReaderOutput(asset: frontAsset, track: frontVideoTrack)
                    guard frontReader.canAdd(frontVideoOutput) else {
                        throw NSError(domain: "DualCamApp", code: -52, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotAddInput")])
                    }
                    frontReader.add(frontVideoOutput)

                    var backAsset: AVAsset?
                    var backReader: AVAssetReader?
                    var backVideoOutput: AVAssetReaderVideoCompositionOutput?
                    if let backURL {
                        let asset = AVAsset(url: backURL)
                        backAsset = asset
                        if let backVideoTrack = asset.tracks(withMediaType: .video).first {
                            let reader = try AVAssetReader(asset: asset)
                            activeBackReader = reader
                            let output = self.makeOrientedVideoReaderOutput(asset: asset, track: backVideoTrack)
                            if reader.canAdd(output) {
                                reader.add(output)
                                backReader = reader
                                backVideoOutput = output
                            }
                        }
                    }

                    let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)
                    activeWriter = writer
                    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: initialLayoutSnapshot.outputSize.width,
                        AVVideoHeightKey: initialLayoutSnapshot.outputSize.height,
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: self.videoBitRate(for: self.frameRate),
                            AVVideoExpectedSourceFrameRateKey: Int(self.frameRate),
                            AVVideoMaxKeyFrameIntervalKey: Int(self.frameRate),
                            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                        ]
                    ])
                    videoInput.expectsMediaDataInRealTime = false
                    guard writer.canAdd(videoInput) else {
                        throw NSError(domain: "DualCamApp", code: -53, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotAddInput")])
                    }
                    writer.add(videoInput)

                    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: initialLayoutSnapshot.outputSize.width,
                        kCVPixelBufferHeightKey as String: initialLayoutSnapshot.outputSize.height,
                        kCVPixelBufferCGImageCompatibilityKey as String: true,
                        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                    ])

                    let audioSourceAsset = [backAsset, frontAsset].compactMap { $0 }.first { !$0.tracks(withMediaType: .audio).isEmpty }
                    let audioSourceTrack = audioSourceAsset?.tracks(withMediaType: .audio).first
                    var audioInput: AVAssetWriterInput?
                    if audioSourceTrack != nil {
                        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: CaptureAudioSettings.aac)
                        input.expectsMediaDataInRealTime = false
                        if writer.canAdd(input) {
                            writer.add(input)
                            audioInput = input
                        }
                    }

                    guard frontReader.startReading() else {
                        throw frontReader.error ?? NSError(domain: "DualCamApp", code: -54, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", "Front reader failed")])
                    }
                    _ = backReader?.startReading()
                    guard writer.startWriting() else {
                        throw writer.error ?? NSError(domain: "DualCamApp", code: -55, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotStartWriting")])
                    }
                    writer.startSession(atSourceTime: .zero)

                    var firstVideoTime: CMTime?
                    var lastBackBuffer: CVPixelBuffer?
                    var nextBackSample = backVideoOutput?.copyNextSampleBuffer()
                    let totalVideoSeconds = max(CMTimeGetSeconds(frontAsset.duration), 0.001)
                    var lastProgressReport = Date.distantPast
                    var lastProgressValue = 0.0

                    while let frontSample = frontVideoOutput.copyNextSampleBuffer() {
                        try control?.waitIfNeeded()
                        guard let frontBuffer = CMSampleBufferGetImageBuffer(frontSample) else { continue }
                        let frontTime = CMSampleBufferGetPresentationTimeStamp(frontSample)
                        if firstVideoTime == nil { firstVideoTime = frontTime }
                        let timelineOrigin = firstVideoTime ?? .zero
                        let outputTime = frontTime - timelineOrigin

                        while let backSample = nextBackSample {
                            let backTime = CMSampleBufferGetPresentationTimeStamp(backSample)
                            guard backTime <= frontTime else { break }
                            lastBackBuffer = CMSampleBufferGetImageBuffer(backSample)
                            nextBackSample = backVideoOutput?.copyNextSampleBuffer()
                        }

                        let layoutSnapshot = self.layoutSnapshot(at: outputTime, in: normalizedLayoutTimeline)
                        guard let pixelBuffer = self.renderCompositePixelBuffer(frontBuffer: frontBuffer, backBuffer: lastBackBuffer, layoutSnapshot: layoutSnapshot) else { continue }
                        while !videoInput.isReadyForMoreMediaData {
                            try control?.waitIfNeeded()
                            Thread.sleep(forTimeInterval: 0.002)
                        }
                        guard adaptor.append(pixelBuffer, withPresentationTime: outputTime) else {
                            throw writer.error ?? NSError(domain: "DualCamApp", code: -56, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", "Video append failed")])
                        }

                        let currentProgress = min(max(CMTimeGetSeconds(outputTime) / totalVideoSeconds, 0), 1) * 0.92
                        if currentProgress - lastProgressValue >= 0.005 || Date().timeIntervalSince(lastProgressReport) >= 0.25 {
                            lastProgressValue = currentProgress
                            lastProgressReport = Date()
                            progress?(currentProgress, L10n.string("works.highQuality.phase.rendering"))
                        }
                    }

                    videoInput.markAsFinished()
                    guard frontReader.status == .completed || frontReader.status == .reading else {
                        throw frontReader.error ?? NSError(domain: "DualCamApp", code: -57, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", "Front reader incomplete")])
                    }

                    progress?(0.92, L10n.string("works.highQuality.phase.audio"))
                    if let audioSourceAsset, let audioSourceTrack, let audioInput {
                        try self.appendAudioTrack(from: audioSourceAsset, track: audioSourceTrack, to: audioInput, control: control)
                    }

                    try control?.waitIfNeeded()
                    progress?(0.98, L10n.string("works.highQuality.phase.finishing"))
                    let semaphore = DispatchSemaphore(value: 0)
                    writer.finishWriting { semaphore.signal() }
                    semaphore.wait()
                    guard writer.status == .completed else {
                        throw writer.error ?? NSError(domain: "DualCamApp", code: -58, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", String(describing: writer.status))])
                    }

                    outputURLToRemove = nil
                    progress?(1, L10n.string("works.highQuality.phase.completed"))
                    continuation.resume(returning: outputURL)
                } catch is CancellationError {
                    activeFrontReader?.cancelReading()
                    activeBackReader?.cancelReading()
                    activeWriter?.cancelWriting()
                    if let outputURLToRemove {
                        try? FileManager.default.removeItem(at: outputURLToRemove)
                    }
                    continuation.resume(throwing: CancellationError())
                } catch {
                    if let outputURLToRemove {
                        try? FileManager.default.removeItem(at: outputURLToRemove)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func renderHighQualityVideo(
        frontURL: URL,
        backURL: URL?,
        layoutTimeline: [WorkLayoutTimelineEntry],
        frameRate: Int,
        control: HighQualityRenderControl,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        let normalizedTimeline = layoutTimeline.sorted { $0.time < $1.time }
        guard !normalizedTimeline.isEmpty else {
            throw NSError(domain: "DualCamApp", code: -62, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.works.highQualityMissingTimeline")])
        }
        self.frameRate = normalizedFrameRate(Int32(frameRate))
        self.frameDuration = CMTime(value: 1, timescale: self.frameRate)
        return try await composeNativeMovieFile(frontURL: frontURL, backURL: backURL, layoutTimeline: normalizedTimeline, control: control, progress: progress)
    }

    private func composeNativeLivePhotoMovieFile(
        frontURL: URL,
        backURL: URL?,
        outputURL: URL,
        layoutSnapshot: RecordingLayoutSnapshot,
        assetIdentifier: String,
        stillImageTime: CMTime
    ) throws {
        let frontAsset = AVAsset(url: frontURL)
        guard let frontVideoTrack = frontAsset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "DualCamApp", code: -51, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.album.noRecordedVideo")])
        }

        let frontReader = try AVAssetReader(asset: frontAsset)
        let frontVideoOutput = makeOrientedVideoReaderOutput(asset: frontAsset, track: frontVideoTrack)
        guard frontReader.canAdd(frontVideoOutput) else {
            throw NSError(domain: "DualCamApp", code: -52, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotAddInput")])
        }
        frontReader.add(frontVideoOutput)

        var backAsset: AVAsset?
        var backReader: AVAssetReader?
        var backVideoOutput: AVAssetReaderVideoCompositionOutput?
        if let backURL {
            let asset = AVAsset(url: backURL)
            backAsset = asset
            if let backVideoTrack = asset.tracks(withMediaType: .video).first {
                let reader = try AVAssetReader(asset: asset)
                let output = makeOrientedVideoReaderOutput(asset: asset, track: backVideoTrack)
                if reader.canAdd(output) {
                    reader.add(output)
                    backReader = reader
                    backVideoOutput = output
                }
            }
        }

        guard frontReader.startReading() else {
            throw frontReader.error ?? NSError(domain: "DualCamApp", code: -54, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", "Front reader failed")])
        }
        _ = backReader?.startReading()

        guard let firstFrontSample = frontVideoOutput.copyNextSampleBuffer() else {
            throw NSError(domain: "DualCamApp", code: -31, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.noMotionFrames")])
        }

        let firstVideoTime = CMSampleBufferGetPresentationTimeStamp(firstFrontSample)
        let normalizedStillTime = stillImageTime.isValid && stillImageTime.isNumeric && stillImageTime >= firstVideoTime ? stillImageTime - firstVideoTime : stillImageTime
        let recorder = try LivePhotoRecorder(
            movieURL: outputURL,
            videoSize: layoutSnapshot.outputSize,
            assetIdentifier: assetIdentifier,
            stillImageTime: normalizedStillTime.isValid && normalizedStillTime.isNumeric ? normalizedStillTime : .zero
        )

        var lastBackBuffer: CVPixelBuffer?
        var nextBackSample = backVideoOutput?.copyNextSampleBuffer()
        var frontSample: CMSampleBuffer? = firstFrontSample
        while let currentFrontSample = frontSample {
            guard let frontBuffer = CMSampleBufferGetImageBuffer(currentFrontSample) else {
                frontSample = frontVideoOutput.copyNextSampleBuffer()
                continue
            }

            let frontTime = CMSampleBufferGetPresentationTimeStamp(currentFrontSample)
            while let backSample = nextBackSample {
                let backTime = CMSampleBufferGetPresentationTimeStamp(backSample)
                guard backTime <= frontTime else { break }
                lastBackBuffer = CMSampleBufferGetImageBuffer(backSample)
                nextBackSample = backVideoOutput?.copyNextSampleBuffer()
            }

            if let pixelBuffer = renderCompositePixelBuffer(frontBuffer: frontBuffer, backBuffer: lastBackBuffer, layoutSnapshot: layoutSnapshot) {
                recorder.appendVideoFrame(pixelBuffer, presentationTime: frontTime - firstVideoTime)
            }
            frontSample = frontVideoOutput.copyNextSampleBuffer()
        }

        let audioSourceAsset = [backAsset, frontAsset].compactMap { $0 }.first { !$0.tracks(withMediaType: .audio).isEmpty }
        if let audioSourceAsset,
           let audioTrack = audioSourceAsset.tracks(withMediaType: .audio).first {
            try appendAudioTrack(from: audioSourceAsset, track: audioTrack, to: recorder, timelineOrigin: firstVideoTime)
        }

        try recorder.finishSynchronously()
    }

    private func makeOrientedVideoReaderOutput(asset: AVAsset, track: AVAssetTrack) -> AVAssetReaderVideoCompositionOutput {
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        let renderRect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
        let renderSize = CGSize(width: abs(renderRect.width), height: abs(renderRect.height))
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: max(1, renderSize.width.rounded()), height: max(1, renderSize.height.rounded()))
        composition.frameDuration = CMTime(value: 1, timescale: frameRate)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        var transform = track.preferredTransform
        transform.tx -= renderRect.minX
        transform.ty -= renderRect.minY
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        output.videoComposition = composition
        return output
    }

    private func layoutSnapshot(at time: CMTime, in timeline: [WorkLayoutTimelineEntry]) -> RecordingLayoutSnapshot {
        var selected = timeline[0].snapshot
        for item in timeline where item.time <= time {
            selected = item.snapshot
        }
        return selected
    }

    private func appendAudioTrack(from asset: AVAsset, track: AVAssetTrack, to recorder: LivePhotoRecorder, timelineOrigin: CMTime) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "DualCamApp", code: -59, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", "Audio reader failed")])
        }

        while let sample = output.copyNextSampleBuffer() {
            guard let retimedSample = Self.retimedAudioSampleBuffer(sample, timelineOrigin: timelineOrigin) else { continue }
            recorder.appendAudioSampleBuffer(retimedSample)
        }
    }

    private func appendAudioTrack(from asset: AVAsset, track: AVAssetTrack, to audioInput: AVAssetWriterInput, control: HighQualityRenderControl? = nil) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "DualCamApp", code: -59, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", "Audio reader failed")])
        }

        var timelineOrigin: CMTime?
        while let sample = output.copyNextSampleBuffer() {
            try control?.waitIfNeeded()
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
            if timelineOrigin == nil { timelineOrigin = presentationTime }
            guard let origin = timelineOrigin,
                  let retimedSample = Self.retimedAudioSampleBuffer(sample, timelineOrigin: origin) else { continue }
            while !audioInput.isReadyForMoreMediaData {
                try control?.waitIfNeeded()
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard audioInput.append(retimedSample) else {
                throw NSError(domain: "DualCamApp", code: -60, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.writeFailed", "Audio append failed")])
            }
        }
        audioInput.markAsFinished()
    }

    /// 合成并写入帧
    private func composeAndWriteFrame(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer?,
        layoutSnapshot: RecordingLayoutSnapshot,
        presentationTime: CMTime
    ) {
        guard let pixelBuffer = renderCompositePixelBuffer(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layoutSnapshot: layoutSnapshot
        ) else { return }

        writeFrame(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }

    private func renderCompositePixelBuffer(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer?,
        layoutSnapshot: RecordingLayoutSnapshot
    ) -> CVPixelBuffer? {
        let outputSize = layoutSnapshot.outputSize
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        guard let outputPixelBuffer = makeOutputPixelBuffer(size: outputSize) else { return nil }

        CVPixelBufferLockBaseAddress(outputPixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputPixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(outputPixelBuffer) else { return nil }

        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputPixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = bitmapInfo(for: outputPixelBuffer)

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.translateBy(x: 0, y: outputSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: outputSize))

        guard let frontImage = sourceCGImage(from: frontBuffer) else { return nil }

        if let backBuffer,
           let backImage = sourceCGImage(from: backBuffer) {
            let layers = [
                (image: backImage, layout: outputVisibleLayout(layoutSnapshot.back, outputSize: outputSize), contentMode: LayerContentMode.aspectFit),
                (image: frontImage, layout: layoutSnapshot.front, contentMode: .aspectFill)
            ].sorted { $0.layout.zIndex < $1.layout.zIndex }

            for layer in layers {
                draw(layer.image, sourceSize: CGSize(width: layer.image.width, height: layer.image.height), layout: layer.layout, contentMode: layer.contentMode, in: context)
            }
        } else {
            let fullFrameLayout = CameraLayoutInfo(
                frame: CGRect(origin: .zero, size: outputSize),
                zIndex: 1,
                cornerRadius: 0,
                showBorder: false,
                clipShape: .rectangle
            )
            draw(frontImage, sourceSize: CGSize(width: frontImage.width, height: frontImage.height), layout: fullFrameLayout, in: context)
        }

        return outputPixelBuffer
    }

    private func makeOutputPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        if let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool {
            var pooledBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pooledBuffer)
            if status == kCVReturnSuccess, let pooledBuffer {
                return pooledBuffer
            }
        }

        var pixelBuffer: CVPixelBuffer?
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
        return pixelBuffer
    }

    private func sourceCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        if status == noErr, let cgImage {
            return cgImage
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private func bitmapInfo(for pixelBuffer: CVPixelBuffer) -> UInt32 {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_32BGRA:
            return CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        default:
            return CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        }
    }

    private func clip(_ layout: CameraLayoutInfo, in context: CGContext) {
        let rect = layout.frame

        switch layout.clipShape {
        case .rectangle:
            context.clip(to: rect)
        case .roundedRectangle:
            context.addPath(CGPath(roundedRect: rect, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil))
            context.clip()
        case .circle:
            context.addPath(CGPath(ellipseIn: rect, transform: nil))
            context.clip()
        case .diagonalLeading:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            context.addPath(path)
            context.clip()
        case .diagonalTrailing:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            context.addPath(path)
            context.clip()
        }
    }

    private func draw(_ image: CGImage, sourceSize: CGSize, layout: CameraLayoutInfo, contentMode: LayerContentMode = .aspectFill, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        clip(layout, in: context)
        let drawRect = aspectRect(for: sourceSize, in: layout.frame, contentMode: contentMode)
        context.translateBy(x: drawRect.minX, y: drawRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: drawRect.size))
    }

    /// 合成两个摄像头图像
    private func composeImages(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer?,
        layoutSnapshot: RecordingLayoutSnapshot
    ) -> UIImage? {
        guard let front = displayImage(from: frontBuffer) else { return nil }
        let back = backBuffer.flatMap { displayImage(from: $0) }
        return composeImages(front: front, back: back, layoutSnapshot: layoutSnapshot)
    }

    private func nativePhotoLayoutSnapshot(from layoutSnapshot: RecordingLayoutSnapshot, front: UIImage, back: UIImage?) -> RecordingLayoutSnapshot {
        guard let outputSize = nativePhotoOutputSize(from: back ?? front, matching: layoutSnapshot.outputSize) else {
            return layoutSnapshot
        }
        guard outputSize != layoutSnapshot.outputSize else { return layoutSnapshot }

        let scaleX = outputSize.width / layoutSnapshot.outputSize.width
        let scaleY = outputSize.height / layoutSnapshot.outputSize.height
        return RecordingLayoutSnapshot(
            front: scaledLayout(layoutSnapshot.front, scaleX: scaleX, scaleY: scaleY),
            back: scaledLayout(layoutSnapshot.back, scaleX: scaleX, scaleY: scaleY),
            outputSize: outputSize
        )
    }

    private func nativePhotoOutputSize(from image: UIImage, matching referenceSize: CGSize) -> CGSize? {
        guard referenceSize.width > 0, referenceSize.height > 0 else { return nil }
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let longEdge = max(pixelWidth, pixelHeight)
        let shortEdge = min(pixelWidth, pixelHeight)
        let referenceIsPortrait = referenceSize.height >= referenceSize.width
        return referenceIsPortrait
            ? CGSize(width: shortEdge, height: longEdge)
            : CGSize(width: longEdge, height: shortEdge)
    }

    private func scaledLayout(_ layout: CameraLayoutInfo, scaleX: CGFloat, scaleY: CGFloat) -> CameraLayoutInfo {
        CameraLayoutInfo(
            frame: CGRect(
                x: layout.frame.minX * scaleX,
                y: layout.frame.minY * scaleY,
                width: layout.frame.width * scaleX,
                height: layout.frame.height * scaleY
            ),
            zIndex: layout.zIndex,
            cornerRadius: layout.cornerRadius * min(scaleX, scaleY),
            showBorder: layout.showBorder,
            clipShape: layout.clipShape
        )
    }

    private func composeImages(front: UIImage, back: UIImage?, layoutSnapshot: RecordingLayoutSnapshot) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(layoutSnapshot.outputSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: layoutSnapshot.outputSize))

        if let back {
            let layers = [
                (image: back, layout: outputVisibleLayout(layoutSnapshot.back, outputSize: layoutSnapshot.outputSize), contentMode: LayerContentMode.aspectFit),
                (image: front, layout: layoutSnapshot.front, contentMode: .aspectFill)
            ].sorted { $0.layout.zIndex < $1.layout.zIndex }

            for layer in layers {
                draw(layer.image, layout: layer.layout, contentMode: layer.contentMode)
            }
        } else {
            front.draw(in: CGRect(origin: .zero, size: layoutSnapshot.outputSize))
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func draw(_ image: UIImage, layout: CameraLayoutInfo, contentMode: LayerContentMode = .aspectFill) {
        let rect = layout.frame
        guard let context = UIGraphicsGetCurrentContext() else {
            image.draw(in: aspectRect(for: image.size, in: rect, contentMode: contentMode))
            return
        }

        context.saveGState()

        switch layout.clipShape {
        case .rectangle:
            context.clip(to: rect)
        case .roundedRectangle:
            UIBezierPath(roundedRect: rect, cornerRadius: layout.cornerRadius).addClip()
        case .circle:
            UIBezierPath(ovalIn: rect).addClip()
        case .diagonalLeading:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            path.addClip()
        case .diagonalTrailing:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            path.addClip()
        }

        let drawRect = aspectRect(for: image.size, in: rect, contentMode: contentMode)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    private func outputVisibleLayout(_ layout: CameraLayoutInfo, outputSize: CGSize) -> CameraLayoutInfo {
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let visibleFrame = layout.frame.intersection(outputRect)
        guard !visibleFrame.isNull, visibleFrame.width > 0, visibleFrame.height > 0 else { return layout }

        return CameraLayoutInfo(
            frame: visibleFrame,
            zIndex: layout.zIndex,
            cornerRadius: layout.cornerRadius,
            showBorder: layout.showBorder,
            clipShape: layout.clipShape
        )
    }

    private func aspectRect(for imageSize: CGSize, in rect: CGRect, contentMode: LayerContentMode) -> CGRect {
        switch contentMode {
        case .aspectFill:
            return aspectFillRect(for: imageSize, in: rect)
        case .aspectFit:
            return aspectFitRect(for: imageSize, in: rect)
        }
    }

    private func aspectFillRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func aspectFitRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }

        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func displayImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Drawing Methods

    /// 画中画布局
    private func drawPictureInPicture(back: UIImage, front: UIImage) {
        // 后置全屏
        back.draw(in: CGRect(origin: .zero, size: videoSize))
        
        // 前置小窗口（右下角）
        let pipWidth = videoSize.width * 0.35
        let pipHeight = videoSize.height * 0.35
        let pipRect = CGRect(
            x: videoSize.width - pipWidth - 30,
            y: videoSize.height - pipHeight - 30,
            width: pipWidth,
            height: pipHeight
        )
        
        // 绘制圆角边框
        let path = UIBezierPath(roundedRect: pipRect, cornerRadius: 12)
        path.addClip()
        front.draw(in: pipRect)
    }
    
    /// 左右分屏布局
    private func drawSideBySide(back: UIImage, front: UIImage) {
        let halfWidth = videoSize.width / 2
        
        // 后置在右
        back.draw(in: CGRect(x: halfWidth, y: 0, width: halfWidth, height: videoSize.height))
        
        // 前置在左
        front.draw(in: CGRect(x: 0, y: 0, width: halfWidth, height: videoSize.height))
    }
    
    /// 上下分屏布局
    private func drawTopBottom(back: UIImage, front: UIImage) {
        let halfHeight = videoSize.height / 2
        
        // 后置在上
        back.draw(in: CGRect(x: 0, y: 0, width: videoSize.width, height: halfHeight))
        
        // 前置在下
        front.draw(in: CGRect(x: 0, y: halfHeight, width: videoSize.width, height: halfHeight))
    }
    
    /// 对角布局
    private func drawDiagonal(back: UIImage, front: UIImage) {
        let smallWidth = videoSize.width * 0.4
        let smallHeight = videoSize.height * 0.4
        
        // 后置在右下
        let backRect = CGRect(
            x: videoSize.width - smallWidth - 30,
            y: videoSize.height - smallHeight - 30,
            width: smallWidth,
            height: smallHeight
        )
        back.draw(in: backRect)
        
        // 前置在左上
        let frontRect = CGRect(x: 30, y: 30, width: smallWidth, height: smallHeight)
        front.draw(in: frontRect)
    }
    
    /// 后置主屏布局
    private func drawFocusBack(back: UIImage, front: UIImage) {
        // 后置全屏
        back.draw(in: CGRect(origin: .zero, size: videoSize))
        
        // 前置小窗口（左上角）
        let smallWidth = videoSize.width * 0.3
        let smallHeight = videoSize.height * 0.3
        let frontRect = CGRect(x: 30, y: 30, width: smallWidth, height: smallHeight)
        front.draw(in: frontRect)
    }
    
    /// 前置主屏布局
    private func drawFocusFront(back: UIImage, front: UIImage) {
        // 前置全屏
        front.draw(in: CGRect(origin: .zero, size: videoSize))
        
        // 后置小窗口（右下角）
        let smallWidth = videoSize.width * 0.3
        let smallHeight = videoSize.height * 0.3
        let backRect = CGRect(
            x: videoSize.width - smallWidth - 30,
            y: videoSize.height - smallHeight - 30,
            width: smallWidth,
            height: smallHeight
        )
        back.draw(in: backRect)
    }
    
    // MARK: - Helper Methods
    
    /// 像素缓冲转图像
    private func pixelBufferToImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    /// 图像转像素缓冲
    private func imageToPixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        let buffer: CVPixelBuffer

        if let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool {
            var pooledBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pooledBuffer)
            guard status == kCVReturnSuccess, let pooledBuffer else { return nil }
            buffer = pooledBuffer
        } else {
            var pixelBuffer: CVPixelBuffer?
            let options: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]

            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(videoSize.width),
                Int(videoSize.height),
                kCVPixelFormatType_32ARGB,
                options as CFDictionary,
                &pixelBuffer
            )

            guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
            buffer = pixelBuffer
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pixelData,
            width: Int(videoSize.width),
            height: Int(videoSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: bitmapInfo(for: buffer)
        ), let cgImage = image.cgImage else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }

        context.draw(cgImage, in: CGRect(origin: .zero, size: videoSize))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
    
    /// 写入帧
    private func writeFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        nonisolated(unsafe) let outputPixelBuffer = pixelBuffer

        mediaWritingQueue.async { [weak self] in
            guard let self,
                  self.isRecording,
                  let adaptor = self.pixelBufferAdaptor else { return }

            var writeTime = presentationTime
            if let startTime = self.startTime, writeTime < startTime {
                writeTime = startTime
            }
            if let lastFrameTime = self.lastFrameTime, writeTime <= lastFrameTime {
                writeTime = lastFrameTime + self.frameDuration
            }

            guard self.ensureSessionStarted(at: writeTime) else { return }

            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return }

            guard adaptor.append(outputPixelBuffer, withPresentationTime: writeTime) else {
                self.reportWriterFailure(context: L10n.string("error.video.writeFailed", self.assetWriter?.error?.localizedDescription ?? "Video append failed"))
                return
            }

            self.lastFrameTime = writeTime
        }
    }

    private func ensureSessionStarted(at presentationTime: CMTime) -> Bool {
        guard presentationTime.isValid,
              presentationTime.isNumeric,
              assetWriter?.status == .writing else { return false }

        if startTime == nil {
            startTime = presentationTime
            assetWriter?.startSession(atSourceTime: presentationTime)
        }

        return true
    }

    private func reportWriterFailure(context: String) {
        Task { @MainActor [weak self] in
            self?.errorMessage = context
        }
    }

    /// 启动时长计时器
    private func startDurationTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isRecording || self.isNativeMovieRecordingActive else {
                timer.invalidate()
                return
            }
            
            self.recordingDuration += 1
            let minutes = Int(self.recordingDuration) / 60
            let seconds = Int(self.recordingDuration) % 60
            self.recordedDurationString = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Session 中断时安全停止录制，不等待 finishWriting 完成
    func stopRecordingForInterruption() {
        guard recordingState == .recording else { return }
        recordingState = .stopping
        isRecording = false
        isNativeMovieRecordingActive = false

        processingQueue.sync {}
        mediaWritingQueue.sync {}

        guard let assetWriter, startTime != nil else {
            resetRecordingState()
            return
        }

        if let videoInput, assetWriter.inputs.contains(where: { $0 === videoInput }) {
            videoInput.markAsFinished()
        }
        if let audioInput, assetWriter.inputs.contains(where: { $0 === audioInput }) {
            audioInput.markAsFinished()
        }

        if assetWriter.status == .writing {
            assetWriter.finishWriting {}
        }

        resetRecordingState()
    }

    @MainActor
    private func resetRecordingState() {
        recordingState = .idle
        isRecording = false
        isNativeMovieRecordingActive = false
        nativeMovieRecordingStartedAt = nil
        nativeMovieLayoutTimeline = []
        recordingDuration = 0
        recordedDurationString = "00:00"
    }

    private func makeOutputURL() -> URL {
        outputURL(extension: "mp4")
    }

    private func persistNativeOriginalMovie(from temporaryURL: URL, cameraName: String) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent("dual_camera_original_\(cameraName)_\(UUID().uuidString).mov")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func makePhotoOutputURL() -> URL {
        outputURL(extension: "jpg", prefix: "photo")
    }

    private func makeLivePhotoStillOutputURL() -> URL {
        outputURL(extension: "jpg", prefix: "live")
    }

    private func makeLivePhotoMovieOutputURL() -> URL {
        outputURL(extension: "mov", prefix: "live")
    }

    private func outputURL(extension fileExtension: String, prefix: String? = nil) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stem = currentWorkNamingRule.fileNameStem(for: Date(), layout: latestLayoutIdentifier, prefix: prefix)
        return documentsPath.appendingPathComponent("\(stem).\(fileExtension)")
    }

    private var currentWorkNamingRule: WorkNamingRule {
        WorkNamingRule.from(UserDefaults.standard.string(forKey: SettingsKey.workNamingRule) ?? WorkNamingRule.dateLayout.rawValue)
    }

    private func savePhotoToPhotoLibrary(_ photoURL: URL) async {
        guard FileManager.default.fileExists(atPath: photoURL.path) else {
            errorMessage = L10n.string("error.photo.fileMissing")
            return
        }

        let authorizationStatus = await requestPhotoLibraryAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            errorMessage = L10n.string("error.photoLibrary.addPhotoDenied")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: photoURL)
            }
        } catch {
            errorMessage = L10n.string("error.photo.saveFailed", error.localizedDescription)
        }
    }

    private func saveLivePhotoToPhotoLibrary(photoURL: URL, pairedVideoURL: URL) async {
        guard FileManager.default.fileExists(atPath: photoURL.path),
              FileManager.default.fileExists(atPath: pairedVideoURL.path) else {
            errorMessage = L10n.string("error.livePhoto.pairedFilesMissing")
            return
        }

        let authorizationStatus = await requestPhotoLibraryAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            errorMessage = L10n.string("error.photoLibrary.addLivePhotoDenied")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: photoURL, options: nil)
                request.addResource(with: .pairedVideo, fileURL: pairedVideoURL, options: nil)
            }
        } catch {
            errorMessage = L10n.string("error.livePhoto.saveFailed", error.localizedDescription)
        }
    }

    private func saveToPhotoLibrary() async {
        guard let outputURL else {
            errorMessage = L10n.string("error.album.recordingURLMissing")
            return
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            errorMessage = L10n.string("error.album.recordingFileMissing")
            return
        }

        guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(outputURL.path) else {
            errorMessage = L10n.string("error.album.unsupportedVideoFormat")
            return
        }

        let authorizationStatus = await requestPhotoLibraryAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            errorMessage = L10n.string("error.photoLibrary.addVideoDenied")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
            }
        } catch {
            self.errorMessage = L10n.string("error.album.saveFailed", error.localizedDescription)
        }
    }

    private func requestPhotoLibraryAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return status
    }
}

extension VideoRecorder: @unchecked Sendable {}
