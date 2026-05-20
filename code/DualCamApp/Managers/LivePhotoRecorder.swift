//
//  LivePhotoRecorder.swift
//  DualCamApp
//

@preconcurrency import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum CaptureAudioSettings {
    static let aac: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 44100.0,
        AVEncoderBitRateKey: 128000
    ]
}

final class LivePhotoRecorder: @unchecked Sendable {
    private static let stillImageTimeIdentifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.still-image-time")

    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let metadataInput: AVAssetWriterInput?
    private let metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let stillImageTime: CMTime

    private let frameDuration = CMTime(value: 1, timescale: 30)
    private var firstPresentationTime: CMTime?
    private var nextFrameTime = CMTime.zero
    private var hasStarted = false
    private var hasAppendedStillImageTime = false

    init(movieURL: URL, videoSize: CGSize, assetIdentifier: String, stillImageTime: CMTime = .zero, includeAudio: Bool = true) throws {
        if FileManager.default.fileExists(atPath: movieURL.path) {
            try FileManager.default.removeItem(at: movieURL)
        }

        assetWriter = try AVAssetWriter(url: movieURL, fileType: .mov)
        self.stillImageTime = stillImageTime

        let contentIdentifierItem = AVMutableMetadataItem()
        contentIdentifierItem.identifier = .quickTimeMetadataContentIdentifier
        contentIdentifierItem.value = assetIdentifier as NSString
        contentIdentifierItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        assetWriter.metadata = [contentIdentifierItem]

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(videoInput) else {
            throw NSError(domain: "DualCamApp", code: -30, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.cannotAddVideoInput")])
        }
        assetWriter.add(videoInput)

        if includeAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: CaptureAudioSettings.aac)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                audioInput = input
            } else {
                audioInput = nil
            }
        } else {
            audioInput = nil
        }

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoSize.width,
            kCVPixelBufferHeightKey as String: videoSize.height
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourceAttributes
        )

        if let metadataDescription = Self.makeStillImageTimeMetadataDescription() {
            let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: metadataDescription)
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                metadataInput = input
                metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
            } else {
                metadataInput = nil
                metadataAdaptor = nil
            }
        } else {
            metadataInput = nil
            metadataAdaptor = nil
        }
    }

    func appendVideoFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard presentationTime.isValid, presentationTime.isNumeric else { return }

        if firstPresentationTime == nil {
            firstPresentationTime = presentationTime
        }

        guard let firstPresentationTime else { return }
        let normalizedTime = presentationTime - firstPresentationTime
        guard normalizedTime.isValid, normalizedTime.isNumeric, normalizedTime >= .zero else { return }

        if !hasStarted {
            guard assetWriter.startWriting() else { return }
            assetWriter.startSession(atSourceTime: .zero)
            hasStarted = true
            appendStillImageTimeMetadata()
        }

        let targetFrameIndex = max(0, Int((normalizedTime.seconds * 30).rounded(.down)))
        let targetFrameTime = CMTimeMultiply(frameDuration, multiplier: Int32(targetFrameIndex))

        while nextFrameTime <= targetFrameTime {
            guard videoInput.isReadyForMoreMediaData else { return }
            guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: nextFrameTime) else { return }
            nextFrameTime = nextFrameTime + frameDuration
        }
    }

    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard hasStarted,
              assetWriter.status == .writing,
              let audioInput,
              audioInput.isReadyForMoreMediaData else { return }

        audioInput.append(sampleBuffer)
    }

    func finish() async throws {
        guard hasStarted else {
            throw NSError(domain: "DualCamApp", code: -31, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.noMotionFrames")])
        }

        markInputsAsFinished()

        try await withCheckedThrowingContinuation { continuation in
            assetWriter.finishWriting { [self] in
                if assetWriter.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: assetWriter.error ?? NSError(domain: "DualCamApp", code: -32, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.videoWriteFailed")]))
                }
            }
        }
    }

    func finishSynchronously() throws {
        guard hasStarted else {
            throw NSError(domain: "DualCamApp", code: -31, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.noMotionFrames")])
        }

        markInputsAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        assetWriter.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard assetWriter.status == .completed else {
            throw assetWriter.error ?? NSError(domain: "DualCamApp", code: -32, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.videoWriteFailed")])
        }
    }

    private func markInputsAsFinished() {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        metadataInput?.markAsFinished()
    }

    static func writeStillImage(_ image: UIImage, to url: URL, assetIdentifier: String) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        guard let cgImage = image.cgImage else {
            throw NSError(domain: "DualCamApp", code: -33, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.stillGenerationFailed")])
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "DualCamApp", code: -34, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.cannotCreateStillFile")])
        }

        let metadata: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": assetIdentifier],
            kCGImagePropertyOrientation: 1
        ]

        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "DualCamApp", code: -35, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.livePhoto.stillWriteFailed")])
        }
    }

    private func appendStillImageTimeMetadata() {
        guard !hasAppendedStillImageTime,
              let metadataAdaptor,
              metadataAdaptor.assetWriterInput.isReadyForMoreMediaData else { return }

        let item = AVMutableMetadataItem()
        item.identifier = Self.stillImageTimeIdentifier
        item.value = 0 as NSNumber
        item.dataType = kCMMetadataBaseDataType_SInt8 as String

        let group = AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(start: stillImageTime, duration: CMTime(value: 1, timescale: 30))
        )
        metadataAdaptor.append(group)
        hasAppendedStillImageTime = true
    }

    private static func makeStillImageTimeMetadataDescription() -> CMFormatDescription? {
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: Self.stillImageTimeIdentifier.rawValue,
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String
        ]

        var description: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray,
            formatDescriptionOut: &description
        )
        return description
    }
}
