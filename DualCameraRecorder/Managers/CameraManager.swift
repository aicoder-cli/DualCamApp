//
//  CameraManager.swift
//  DualCameraRecorder
//
//  多摄像头管理器 - 负责同时管理前后摄像头
//

import AVFoundation
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
    
    // MARK: - Private Properties
    private let frontSession = AVCaptureSession()
    private let backSession = AVCaptureSession()
    
    private var frontCamera: CameraConfiguration!
    private var backCamera: CameraConfiguration!
    
    private let videoDataOutputQueue = DispatchQueue(label: "com.dualcamera.videoOutput", qos: .userInteractive)
    private let audioSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone], mediaType: .audio, position: .unspecified)
    
    // 视频帧回调
    var frontVideoFrameHandler: ((CMSampleBuffer) -> Void)?
    var backVideoFrameHandler: ((CMSampleBuffer) -> Void)?
    
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
        
        hasMultiCameraSupport = !frontDevices.isEmpty && !backDevices.isEmpty
        
        // 创建预览层
        let frontPreviewLayer = AVCaptureVideoPreviewLayer(session: frontSession)
        frontPreviewLayer.videoGravity = .resizeAspectFill
        
        let backPreviewLayer = AVCaptureVideoPreviewLayer(session: backSession)
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
            errorMessage = "请在设置中允许访问摄像头"
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
            errorMessage = "请在设置中允许访问麦克风"
            return false
        @unknown default:
            return false
        }
    }
    
    /// 启动摄像头会话
    func startCapture() async {
        guard await requestPermissions() else { return }
        guard await requestMicrophonePermission() else { return }
        
        await setupFrontCamera()
        await setupBackCamera()
        
        frontSession.startRunning()
        backSession.startRunning()
        
        isSessionRunning = true
    }
    
    /// 停止摄像头会话
    func stopCapture() {
        frontSession.stopRunning()
        backSession.stopRunning()
        isSessionRunning = false
    }
    
    // MARK: - Camera Setup
    
    /// 设置前置摄像头
    private func setupFrontCamera() async {
        do {
            frontSession.beginConfiguration()
            frontSession.sessionPreset = .high
            
            // 获取前置摄像头设备
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                errorMessage = "无法找到前置摄像头"
                return
            }
            
            frontCamera.device = device
            
            // 创建输入
            let input = try AVCaptureDeviceInput(device: device)
            frontCamera.input = input
            
            if frontSession.canAddInput(input) {
                frontSession.addInput(input)
            }
            
            // 创建视频输出
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            frontCamera.output = videoOutput
            
            if frontSession.canAddOutput(videoOutput) {
                frontSession.addOutput(videoOutput)
            }
            
            // 设置连接
            if let connection = videoOutput.connection(with: .video) {
                frontCamera.connection = connection
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            
            frontSession.commitConfiguration()
            frontCameraReady = true
            
        } catch {
            errorMessage = "前置摄像头设置失败: \(error.localizedDescription)"
        }
    }
    
    /// 设置后置摄像头
    private func setupBackCamera() async {
        do {
            backSession.beginConfiguration()
            backSession.sessionPreset = .high
            
            // 获取后置摄像头设备
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                errorMessage = "无法找到后置摄像头"
                return
            }
            
            backCamera.device = device
            
            // 创建输入
            let input = try AVCaptureDeviceInput(device: device)
            backCamera.input = input
            
            if backSession.canAddInput(input) {
                backSession.addInput(input)
            }
            
            // 创建视频输出
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            backCamera.output = videoOutput
            
            if backSession.canAddOutput(videoOutput) {
                backSession.addOutput(videoOutput)
            }
            
            // 设置连接
            if let connection = videoOutput.connection(with: .video) {
                backCamera.connection = connection
            }
            
            backSession.commitConfiguration()
            backCameraReady = true
            
        } catch {
            errorMessage = "后置摄像头设置失败: \(error.localizedDescription)"
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
        // 交换预览层的session
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
        guard let device = camera.device else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
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
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // 判断是哪个摄像头的输出
        if output === frontCamera.output {
            frontVideoFrameHandler?(sampleBuffer)
        } else if output === backCamera.output {
            backVideoFrameHandler?(sampleBuffer)
        }
    }
}
