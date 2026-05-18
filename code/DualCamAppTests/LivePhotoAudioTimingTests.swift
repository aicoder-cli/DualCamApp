import AVFoundation
import XCTest
@testable import DualCamApp

final class LivePhotoAudioTimingTests: XCTestCase {
    func testRetimedAudioSampleBufferSubtractsTimelineOrigin() throws {
        let sampleBuffer = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 12.5, preferredTimescale: 600)
        )

        let retimedSampleBuffer = try XCTUnwrap(
            VideoRecorder.retimedAudioSampleBuffer(
                sampleBuffer,
                timelineOrigin: CMTime(seconds: 10.0, preferredTimescale: 600)
            )
        )

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(retimedSampleBuffer).seconds, 2.5, accuracy: 0.0001)
    }

    func testRetimedAudioSampleBufferPreservesDuration() throws {
        let duration = CMTime(value: 1024, timescale: 44100)
        let sampleBuffer = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 5.0, preferredTimescale: 600),
            duration: duration
        )

        let retimedSampleBuffer = try XCTUnwrap(
            VideoRecorder.retimedAudioSampleBuffer(
                sampleBuffer,
                timelineOrigin: CMTime(seconds: 4.0, preferredTimescale: 600)
            )
        )

        XCTAssertEqual(CMSampleBufferGetDuration(retimedSampleBuffer), duration)
    }

    func testRetimedAudioSampleBufferDropsSamplesBeforeTimelineOrigin() throws {
        let sampleBuffer = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 0.75, preferredTimescale: 600)
        )

        let retimedSampleBuffer = VideoRecorder.retimedAudioSampleBuffer(
            sampleBuffer,
            timelineOrigin: CMTime(seconds: 1.0, preferredTimescale: 600)
        )

        XCTAssertNil(retimedSampleBuffer)
    }

    func testAudioSampleWindowIncludesOnlyCaptureRange() {
        let timelineOrigin = CMTime(seconds: 10.0, preferredTimescale: 600)
        let captureEndTime = CMTime(seconds: 12.0, preferredTimescale: 600)
        let range = timelineOrigin...captureEndTime

        XCTAssertFalse(VideoRecorder.isAudioSample(presentationTime: CMTime(seconds: 9.99, preferredTimescale: 600), within: range))
        XCTAssertTrue(VideoRecorder.isAudioSample(presentationTime: timelineOrigin, within: range))
        XCTAssertTrue(VideoRecorder.isAudioSample(presentationTime: CMTime(seconds: 11.0, preferredTimescale: 600), within: range))
        XCTAssertTrue(VideoRecorder.isAudioSample(presentationTime: captureEndTime, within: range))
        XCTAssertFalse(VideoRecorder.isAudioSample(presentationTime: CMTime(seconds: 12.01, preferredTimescale: 600), within: range))
    }

    private func makeAudioSampleBuffer(
        presentationTime: CMTime,
        duration: CMTime = CMTime(value: 1024, timescale: 44100)
    ) throws -> CMSampleBuffer {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw NSError(domain: "LivePhotoAudioTimingTests", code: Int(status))
        }

        var blockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: 2,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: 2,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw NSError(domain: "LivePhotoAudioTimingTests", code: Int(status))
        }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = 2
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw NSError(domain: "LivePhotoAudioTimingTests", code: Int(status))
        }

        return sampleBuffer
    }
}
