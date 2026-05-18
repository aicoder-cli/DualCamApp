import XCTest
@testable import DualCamApp

@MainActor
final class CaptureFeedbackServiceTests: XCTestCase {
    func testDisabledFeedbackDoesNotTriggerSoundOrHaptic() {
        let spy = FeedbackSpy()
        let service = CaptureFeedbackService(performer: spy.performer)

        service.perform(.photoCaptured, enabled: false)
        service.perform(.recordingStarted, enabled: false)
        service.perform(.captureFailed, enabled: false)

        XCTAssertTrue(spy.sounds.isEmpty)
        XCTAssertTrue(spy.haptics.isEmpty)
    }

    func testPhotoCapturedFeedbackMapping() {
        let spy = FeedbackSpy()
        let service = CaptureFeedbackService(performer: spy.performer)

        service.perform(.photoCaptured, enabled: true)

        XCTAssertEqual(spy.haptics, [.mediumImpact])
        XCTAssertEqual(spy.sounds, [.photoShutter])
    }

    func testLivePhotoShutterAcceptedFeedbackMapping() {
        let spy = FeedbackSpy()
        let service = CaptureFeedbackService(performer: spy.performer)

        service.perform(.livePhotoShutterAccepted, enabled: true)

        XCTAssertEqual(spy.haptics, [.heavyImpact, .successNotification])
        XCTAssertEqual(spy.sounds, [.photoShutter])
    }

    func testRecordingStartedFeedbackMapping() {
        let spy = FeedbackSpy()
        let service = CaptureFeedbackService(performer: spy.performer)

        service.perform(.recordingStarted, enabled: true)

        XCTAssertEqual(spy.haptics, [.heavyImpact])
        XCTAssertEqual(spy.sounds, [.recordingStarted])
    }

    func testRecordingStoppedFeedbackMapping() {
        let spy = FeedbackSpy()
        let service = CaptureFeedbackService(performer: spy.performer)

        service.perform(.recordingStopped, enabled: true)

        XCTAssertEqual(spy.haptics, [.heavyImpact, .successNotification])
        XCTAssertEqual(spy.sounds, [.recordingStopped])
    }

    func testCaptureFailedFeedbackOnlyTriggersErrorHaptic() {
        let spy = FeedbackSpy()
        let service = CaptureFeedbackService(performer: spy.performer)

        service.perform(.captureFailed, enabled: true)

        XCTAssertEqual(spy.haptics, [.errorNotification])
        XCTAssertTrue(spy.sounds.isEmpty)
    }
}

@MainActor
private final class FeedbackSpy {
    var sounds: [CaptureFeedbackService.Sound] = []
    var haptics: [CaptureFeedbackService.Haptic] = []

    var performer: CaptureFeedbackService.Performer {
        CaptureFeedbackService.Performer(
            playSound: { [self] sound in sounds.append(sound) },
            playHaptic: { [self] haptic in haptics.append(haptic) }
        )
    }
}
