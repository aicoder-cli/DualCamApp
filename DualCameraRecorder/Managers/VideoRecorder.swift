//
//  VideoRecorder.swift
//  DualCameraRecorder
//
//  视频录制引擎 - 负责合成双摄像头画面并录制视频
//

import AVFoundation
import UIKit
import Photos

/// 录制状态
enum RecordingState {
    case idle
    case preparing
    case recording
    case stopping
    case saving
}

/// 视频录制器
@MainActor
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
    
    private let outputURL: URL
    private let videoSize: CGSize
    private let frameRate: Int32 = 30
    
    // 视频帧缓存
    private var frontFrameBuffer: CVPixelBuffer?
    private var backFrameBuffer: CVPixelBuffer?
    
    // 帧处理队列
    private let processingQueue = DispatchQueue(label: "com.dualcamera.recording", qos: .userInteractive)
    
    // MARK: - Initialization
    init() {
        // 设置输出路径
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "dual_camera_\(Date().timeIntervalSince1970).mp4"
        outputURL = documentsPath.appendingPathComponent(fileName)
        
        // 默认视频尺寸 (1080p)
        videoSize = CGSize(width: 1920, height: 1080)
    }
    
    // MARK: - Recording Control
    
    /// 开始录制
    func startRecording() async {
        guard recordingState == .idle else { return }
        
        recordingState = .preparing
        
        do {
            try setupAssetWriter()
            recordingState = .recording
            isRecording = true
            startTime = nil
            lastFrameTime = nil
            
            // 启动计时器
            startDurationTimer()
            
        } catch {
            errorMessage = "录制初始化失败: \(error.localizedDescription)"
            recordingState = .idle
        }
    }
    
    /// 停止录制
    func stopRecording() async {
        guard recordingState == .recording else { return }
        
        recordingState = .stopping
        isRecording = false
        
        // 等待写入完成
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        await finishWriting()
        
        recordingState = .saving
        
        // 保存到相册
        await saveToPhotoLibrary()
        
        recordingState = .idle
        recordingDuration = 0
        recordedDurationString = "00:00"
    }
    
    // MARK: - Setup Methods
    
    /// 设置资源写入器
    private func setupAssetWriter() throws {
        // 删除已存在的文件
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // 创建资源写入器
        assetWriter = try AVAssetWriter(url: outputURL, fileType: .mp4)
        
        // 视频输入配置
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        // 像素缓冲适配器
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: videoSize.width,
            kCVPixelBufferHeightKey as String: videoSize.height
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
        
        // 添加输入
        if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
            assetWriter?.add(videoInput)
        }
        
        if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
            assetWriter?.add(audioInput)
        }
        
        // 开始写入
        assetWriter?.startWriting()
    }
    
    /// 完成写入
    private func finishWriting() async {
        await withCheckedContinuation { continuation in
            assetWriter?.finishWriting { [weak self] in
                if self?.assetWriter?.status == .failed {
                    self?.errorMessage = "视频写入失败: \(String(describing: self?.assetWriter?.error?.localizedDescription))"
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - Frame Processing
    
    /// 处理视频帧
    func processFrame(_ sampleBuffer: CMSampleBuffer, isFront: Bool, layoutType: LayoutType) {
        guard isRecording else { return }
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 提取像素缓冲
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            // 缓存帧
            if isFront {
                self.frontFrameBuffer = pixelBuffer
            } else {
                self.backFrameBuffer = pixelBuffer
            }
            
            // 当两个摄像头都有帧时，合成并写入
            if let frontBuffer = self.frontFrameBuffer,
               let backBuffer = self.backFrameBuffer {
                self.composeAndWriteFrame(
                    frontBuffer: frontBuffer,
                    backBuffer: backBuffer,
                    layoutType: layoutType,
                    presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                )
            }
        }
    }
    
    /// 合成并写入帧
    private func composeAndWriteFrame(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layoutType: LayoutType,
        presentationTime: CMTime
    ) {
        // 创建合成图像
        guard let composedImage = composeImages(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layoutType: layoutType
        ) else { return }
        
        // 转换为像素缓冲
        guard let pixelBuffer = imageToPixelBuffer(composedImage) else { return }
        
        // 写入视频
        writeFrame(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }
    
    /// 合成两个摄像头图像
    private func composeImages(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layoutType: LayoutType
    ) -> UIImage? {
        // 转换为UIImage
        let frontImage = pixelBufferToImage(frontBuffer)
        let backImage = pixelBufferToImage(backBuffer)
        
        guard let front = frontImage, let back = backImage else { return nil }
        
        // 创建绘图上下文
        UIGraphicsBeginImageContextWithOptions(videoSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        // 绘制背景
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: videoSize))
        
        // 根据布局类型绘制
        switch layoutType {
        case .pictureInPicture:
            drawPictureInPicture(back: back, front: front)
        case .sideBySide:
            drawSideBySide(back: back, front: front)
        case .topBottom:
            drawTopBottom(back: back, front: front)
        case .diagonal:
            drawDiagonal(back: back, front: front)
        case .focusBack:
            drawFocusBack(back: back, front: front)
        case .focusFront:
            drawFocusFront(back: back, front: front)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
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
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    /// 图像转像素缓冲
    private func imageToPixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(videoSize.width),
            Int(videoSize.height),
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
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
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        
        context.draw(image.cgImage!, in: CGRect(origin: .zero, size: videoSize))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
    
    /// 写入帧
    private func writeFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let adaptor = pixelBufferAdaptor,
              adaptor.assetWriterInput.isReadyForMoreMediaData else { return }
        
        if startTime == nil {
            startTime = presentationTime
            assetWriter?.startSession(atSourceTime: presentationTime)
        }
        
        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        lastFrameTime = presentationTime
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
    
    /// 保存到相册
    private func saveToPhotoLibrary() async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.outputURL)
            }
        } catch {
            self.errorMessage = "保存到相册失败: \(error.localizedDescription)"
        }
    }
}
