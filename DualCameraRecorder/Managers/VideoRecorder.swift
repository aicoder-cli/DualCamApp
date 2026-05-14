//
//  VideoRecorder.swift
//  DualCameraRecorder
//
//  视频录制引擎 - 负责合成双摄像头画面并录制视频
//

@preconcurrency import AVFoundation
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
    private var startTime: CMTime?
    private var lastFrameTime: CMTime?
    private var frameDuration = CMTime(value: 1, timescale: 30)
    private var nextVideoFrameTime: CMTime?
    private var frontFrameTime: CMTime?
    private var backFrameTime: CMTime?

    private var outputURL: URL?
    private let videoSize: CGSize
    private var frameRate: Int32 = 30
    private var latestLayoutIdentifier = LayoutType.pictureInPicture.rawValue
    var workCompletedHandler: ((RecordedWorkDraft) -> Void)?
    private let livePhotoFrameInterval = CMTime(value: 1, timescale: 30)
    private let ciContext = CIContext()
    private var livePhotoRecorder: LivePhotoRecorder?
    private var isCapturingLivePhoto = false
    private var lastLivePhotoFrameTime: CMTime?

    var outputVideoSize: CGSize { videoSize }
    
    // 视频帧缓存
    private var frontFrameBuffer: CVPixelBuffer?
    private var backFrameBuffer: CVPixelBuffer?
    private var latestLayoutSnapshot: RecordingLayoutSnapshot?
    private let frameStateLock = NSLock()

    private struct CurrentFrameState {
        let frontBuffer: CVPixelBuffer?
        let backBuffer: CVPixelBuffer?
        let snapshot: RecordingLayoutSnapshot?
    }

    // 帧处理队列
    private let processingQueue = DispatchQueue(label: "com.dualcamera.recording", qos: .userInteractive)
    private let mediaWritingQueue = DispatchQueue(label: "com.dualcamera.mediaWriting", qos: .userInitiated)
    private let processingSemaphore = DispatchSemaphore(value: 1)
    
    // MARK: - Initialization
    init() {
        // 默认视频尺寸 (720p portrait)
        videoSize = CGSize(width: 720, height: 1280)
    }
    
    // MARK: - Recording Control
    
    /// 开始录制
    @MainActor
    func startRecording(frameRate: Int32) async {
        guard recordingState == .idle else { return }

        self.frameRate = normalizedFrameRate(frameRate)
        self.frameDuration = CMTime(value: 1, timescale: self.frameRate)
        recordingState = .preparing

        do {
            try setupAssetWriter()
            prewarmCompositor()
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
    func stopRecording(saveToSystemPhotos: Bool = true) async {
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
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100.0,
            AVEncoderBitRateKey: 128000
        ]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        
        guard let assetWriter, let videoInput else {
            throw NSError(domain: "DualCameraRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.recorder.initializationFailed")])
        }

        guard assetWriter.canAdd(videoInput) else {
            throw NSError(domain: "DualCameraRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotAddInput")])
        }
        assetWriter.add(videoInput)

        if let audioInput, assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        }

        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? NSError(domain: "DualCameraRecorder", code: -3, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.video.cannotStartWriting")])
        }
    }
    
    private func prewarmCompositor() {
        processingQueue.sync { [weak self] in
            guard let self else { return }

            autoreleasepool {
                let state = self.currentFrameState()

                guard let frontBuffer = state.frontBuffer,
                      let backBuffer = state.backBuffer,
                      let snapshot = state.snapshot else {
                    _ = self.makeOutputPixelBuffer(size: self.videoSize)
                    return
                }

                _ = self.renderCompositePixelBuffer(
                    frontBuffer: frontBuffer,
                    backBuffer: backBuffer,
                    layoutSnapshot: snapshot
                )
            }
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
                    Task { @MainActor in
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
    }

    func updateWorkLayout(_ layout: LayoutType) {
        latestLayoutIdentifier = layout.rawValue
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
        let state = CurrentFrameState(
            frontBuffer: frontFrameBuffer ?? backFrameBuffer,
            backBuffer: backFrameBuffer ?? frontFrameBuffer,
            snapshot: latestLayoutSnapshot
        )
        frameStateLock.unlock()
        return state
    }

    private func currentFrameState() -> CurrentFrameState {
        frameStateLock.lock()
        let state = CurrentFrameState(
            frontBuffer: frontFrameBuffer ?? backFrameBuffer,
            backBuffer: backFrameBuffer ?? frontFrameBuffer,
            snapshot: latestLayoutSnapshot
        )
        frameStateLock.unlock()
        return state
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

                if self.isCapturingLivePhoto,
                   self.shouldAppendLivePhotoFrame(at: presentationTime),
                   let livePhotoRecorder = self.livePhotoRecorder,
                   let frontBuffer,
                   let backBuffer,
                   let image = self.composeImages(frontBuffer: frontBuffer, backBuffer: backBuffer, layoutSnapshot: snapshot),
                   let pixelBuffer = self.imageToPixelBuffer(image) {
                    self.lastLivePhotoFrameTime = presentationTime
                    livePhotoRecorder.appendVideoFrame(pixelBuffer, presentationTime: presentationTime)
                }

                guard self.isRecording,
                      let videoPresentationTime = self.nextVideoPresentationTime(for: presentationTime) else { return }

                if let frontBuffer, let backBuffer {
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
    func capturePhoto(livePhotoEnabled: Bool, livePhotoDuration: TimeInterval = 2.5, saveToSystemPhotos: Bool = true) async {
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
                    resolution: videoSize,
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
            let files = try await beginLivePhotoCapture()
            try await Task.sleep(nanoseconds: UInt64(captureDuration * 1_000_000_000))
            try await finishLivePhotoCapture()
            workCompletedHandler?(
                RecordedWorkDraft(
                    kind: .photo,
                    assetURL: files.photoURL,
                    pairedVideoURL: files.movieURL,
                    createdAt: Date(),
                    duration: captureDuration,
                    layout: latestLayoutIdentifier,
                    resolution: videoSize,
                    frameRate: Int(frameRate),
                    isLivePhoto: true
                )
            )
            if saveToSystemPhotos {
                await saveLivePhotoToPhotoLibrary(photoURL: files.photoURL, pairedVideoURL: files.movieURL)
            }
        } catch {
            await cancelLivePhotoCapture()
            errorMessage = L10n.string("error.livePhoto.saveFailed", error.localizedDescription)
        }

        resetRecordingState()
    }

    private func makeCurrentPhotoFile() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DualCameraRecorder", code: -20, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.photo.generatorReleased")]))
                    return
                }

                autoreleasepool {
                    let state = self.currentFrameState()

                    guard let frontBuffer = state.frontBuffer,
                          let backBuffer = state.backBuffer,
                          let snapshot = state.snapshot else {
                        continuation.resume(throwing: NSError(domain: "DualCameraRecorder", code: -21, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.camera.noFrameToSave")]))
                        return
                    }

                    guard let image = self.composeImages(frontBuffer: frontBuffer, backBuffer: backBuffer, layoutSnapshot: snapshot),
                          let imageData = image.jpegData(compressionQuality: 0.92) else {
                        continuation.resume(throwing: NSError(domain: "DualCameraRecorder", code: -22, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.photo.compositionFailed")]))
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

    private func beginLivePhotoCapture() async throws -> (photoURL: URL, movieURL: URL) {
        try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "DualCameraRecorder", code: -40, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.generatorReleased")]))
                    return
                }

                autoreleasepool {
                    let state = self.currentFrameState()

                    guard let frontBuffer = state.frontBuffer,
                          let backBuffer = state.backBuffer,
                          let snapshot = state.snapshot else {
                        continuation.resume(throwing: NSError(domain: "DualCameraRecorder", code: -41, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.camera.noFrameToSave")]))
                        return
                    }

                    guard let image = self.composeImages(frontBuffer: frontBuffer, backBuffer: backBuffer, layoutSnapshot: snapshot) else {
                        continuation.resume(throwing: NSError(domain: "DualCameraRecorder", code: -42, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.stillCompositionFailed")]))
                        return
                    }

                    do {
                        let assetIdentifier = UUID().uuidString
                        let photoURL = self.makeLivePhotoStillOutputURL()
                        let movieURL = self.makeLivePhotoMovieOutputURL()
                        try LivePhotoRecorder.writeStillImage(image, to: photoURL, assetIdentifier: assetIdentifier)
                        let recorder = try LivePhotoRecorder(
                            movieURL: movieURL,
                            videoSize: self.videoSize,
                            assetIdentifier: assetIdentifier
                        )
                        self.livePhotoRecorder = recorder
                        self.lastLivePhotoFrameTime = nil
                        self.isCapturingLivePhoto = true
                        continuation.resume(returning: (photoURL: photoURL, movieURL: movieURL))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func finishLivePhotoCapture() async throws {
        let recorder: LivePhotoRecorder = try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self, let recorder = self.livePhotoRecorder else {
                    continuation.resume(throwing: NSError(domain: "DualCameraRecorder", code: -43, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.recorderNotInitialized")]))
                    return
                }

                self.isCapturingLivePhoto = false
                self.livePhotoRecorder = nil
                self.lastLivePhotoFrameTime = nil
                continuation.resume(returning: recorder)
            }
        }

        try await recorder.finish()
    }

    private func cancelLivePhotoCapture() async {
        await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                self?.isCapturingLivePhoto = false
                self?.livePhotoRecorder = nil
                self?.lastLivePhotoFrameTime = nil
                continuation.resume()
            }
        }
    }

    func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        nonisolated(unsafe) let audioSampleBuffer = sampleBuffer

        mediaWritingQueue.async { [weak self] in
            guard let self,
                  self.isRecording,
                  let audioInput = self.audioInput,
                  self.ensureSessionStarted(at: presentationTime) else { return }

            guard audioInput.isReadyForMoreMediaData else { return }

            guard audioInput.append(audioSampleBuffer) else {
                self.reportWriterFailure(context: L10n.string("error.video.writeFailed", self.assetWriter?.error?.localizedDescription ?? "Audio append failed"))
                return
            }
        }
    }
    
    /// 合成并写入帧
    private func composeAndWriteFrame(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
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
        backBuffer: CVPixelBuffer,
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

        context.interpolationQuality = .high
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: outputSize))

        guard let frontImage = sourceCGImage(from: frontBuffer),
              let backImage = sourceCGImage(from: backBuffer) else { return nil }

        let layers = [
            (image: backImage, layout: layoutSnapshot.back),
            (image: frontImage, layout: layoutSnapshot.front)
        ].sorted { $0.layout.zIndex < $1.layout.zIndex }

        for layer in layers {
            draw(layer.image, sourceSize: CGSize(width: layer.image.width, height: layer.image.height), layout: layer.layout, in: context)
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

    private func draw(_ image: CGImage, sourceSize: CGSize, layout: CameraLayoutInfo, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        clip(layout, in: context)
        let drawRect = aspectFillRect(for: sourceSize, in: layout.frame)
        context.draw(image, in: drawRect)
    }

    /// 合成两个摄像头图像
    private func composeImages(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layoutSnapshot: RecordingLayoutSnapshot
    ) -> UIImage? {
        let frontImage = displayImage(from: frontBuffer)
        let backImage = displayImage(from: backBuffer)

        guard let front = frontImage, let back = backImage else { return nil }

        UIGraphicsBeginImageContextWithOptions(layoutSnapshot.outputSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: layoutSnapshot.outputSize))

        let layers = [
            (image: back, layout: layoutSnapshot.back),
            (image: front, layout: layoutSnapshot.front)
        ].sorted { $0.layout.zIndex < $1.layout.zIndex }

        for layer in layers {
            draw(layer.image, layout: layer.layout)
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func draw(_ image: UIImage, layout: CameraLayoutInfo) {
        let rect = layout.frame
        guard let context = UIGraphicsGetCurrentContext() else {
            image.draw(in: rect)
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

        let drawRect = aspectFillRect(for: image.size, in: rect)
        image.draw(in: drawRect)
        context.restoreGState()
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
        print(context)
        Task { @MainActor [weak self] in
            self?.errorMessage = context
        }
    }

    /// 启动时长计时器
    private func startDurationTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isRecording else {
                timer.invalidate()
                return
            }
            
            self.recordingDuration += 1
            let minutes = Int(self.recordingDuration) / 60
            let seconds = Int(self.recordingDuration) % 60
            self.recordedDurationString = String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    @MainActor
    private func resetRecordingState() {
        recordingState = .idle
        recordingDuration = 0
        recordedDurationString = "00:00"
    }

    private func makeOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "dual_camera_\(UUID().uuidString).mp4"
        return documentsPath.appendingPathComponent(fileName)
    }

    private func makePhotoOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "dual_camera_photo_\(UUID().uuidString).jpg"
        return documentsPath.appendingPathComponent(fileName)
    }

    private func makeLivePhotoStillOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "dual_camera_live_\(UUID().uuidString).jpg"
        return documentsPath.appendingPathComponent(fileName)
    }

    private func makeLivePhotoMovieOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "dual_camera_live_\(UUID().uuidString).mov"
        return documentsPath.appendingPathComponent(fileName)
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
