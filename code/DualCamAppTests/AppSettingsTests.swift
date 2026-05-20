import CoreGraphics
import Foundation
import XCTest
@testable import DualCamApp

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DualCamAppTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRegisterDefaultsSetsExpectedDefaults() {
        AppSettings.registerDefaults(userDefaults: userDefaults)

        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.appLanguageCode), AppLanguage.system.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.defaultCaptureMode), DefaultCaptureMode.video.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.defaultLayout), LayoutType.pictureInPicture.rawValue)
        XCTAssertTrue(userDefaults.bool(forKey: SettingsKey.rememberLastLayout))
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.lastLayout), LayoutType.pictureInPicture.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.photoAspectRatio), PhotoAspectRatio.threeByFour.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.videoResolution), VideoResolution.p1080.rawValue)
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.shootingFrameRate), ShootingFrameRate.standard.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.videoCodec), VideoCodec.h264.rawValue)
        XCTAssertEqual(userDefaults.double(forKey: SettingsKey.defaultLivePhotoDuration), 2.5)
        XCTAssertTrue(userDefaults.bool(forKey: SettingsKey.immersiveRecording))
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.controlRevealSeconds), ControlRevealDuration.twoSeconds.rawValue)
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.recordingCountdownSeconds), RecordingCountdown.off.rawValue)
        XCTAssertTrue(userDefaults.bool(forKey: SettingsKey.soundAndHapticsEnabled))
        XCTAssertEqual(userDefaults.double(forKey: SettingsKey.lastRearFocalLength), 1.0)
        XCTAssertFalse(userDefaults.bool(forKey: SettingsKey.saveToSystemPhotos))
        XCTAssertFalse(userDefaults.bool(forKey: SettingsKey.keepOriginalStreams))
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.workNamingRule), WorkNamingRule.dateLayout.rawValue)
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.workNamingSequence), 1)
        XCTAssertFalse(userDefaults.bool(forKey: SettingsKey.autoClearCache))
    }

    func testMigrateIfNeededWritesCurrentSchemaVersion() {
        AppSettings.migrateIfNeeded(userDefaults: userDefaults)

        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.schemaVersion), AppSettings.currentSchemaVersion)
    }

    func testMigrateIfNeededDoesNotDowngradeFutureSchemaVersion() {
        let futureVersion = AppSettings.currentSchemaVersion + 10
        userDefaults.set(futureVersion, forKey: SettingsKey.schemaVersion)

        AppSettings.migrateIfNeeded(userDefaults: userDefaults)

        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.schemaVersion), futureVersion)
    }

    func testEnumFallbacksForUnknownValues() {
        XCTAssertEqual(AppLanguage.from("bad"), .system)
        XCTAssertEqual(DefaultCaptureMode.from("bad"), .video)
        XCTAssertEqual(LayoutType.from("bad"), .pictureInPicture)
        XCTAssertEqual(PhotoAspectRatio.from("bad"), .threeByFour)
        XCTAssertEqual(VideoResolution.from("bad"), .p1080)
        XCTAssertEqual(VideoCodec.from("bad"), .h264)
        XCTAssertEqual(ControlRevealDuration.from(-1), .twoSeconds)
        XCTAssertEqual(RecordingCountdown.from(-1), .off)
        XCTAssertEqual(WorkNamingRule.from("bad"), .dateLayout)
    }

    func testMediaOutputSizesMatchNativeLikeDefaults() {
        XCTAssertEqual(PhotoAspectRatio.threeByFour.outputSize, CGSize(width: 1080, height: 1440))
        XCTAssertEqual(PhotoAspectRatio.nineBySixteen.outputSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(VideoResolution.p720.outputSize, CGSize(width: 720, height: 1280))
        XCTAssertEqual(VideoResolution.p1080.outputSize, CGSize(width: 1080, height: 1920))

        let spec = MediaOutputSpec(
            photoAspectRatio: .threeByFour,
            videoResolution: .p1080,
            frameRate: 30,
            videoCodec: .h264
        )
        XCTAssertEqual(spec.photoBadgeText, "3:4 · JPEG · 1080×1440")
        XCTAssertEqual(spec.videoBadgeText, "1080P · MP4 · 30")
    }

    func testLivePhotoDurationOptionChoosesNearestValue() {
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 1.5), .short)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 3.0), .standard)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 5.0), .extended)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: -100), .short)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 4.4), .extended)
    }

    func testWorkNamingRuleFormatsTitlesAndConsumesSequence() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 5
        components.day = 20
        components.hour = 9
        components.minute = 8
        let date = components.date!

        userDefaults.set(7, forKey: SettingsKey.workNamingSequence)

        XCTAssertEqual(
            WorkNamingRule.dateLayout.title(for: date, layout: LayoutType.pictureInPicture.rawValue, userDefaults: userDefaults),
            "2026-05-20 09:08 · \(LayoutType.pictureInPicture.localizedTitle)"
        )
        XCTAssertEqual(WorkNamingRule.dateOnly.title(for: date, layout: LayoutType.pictureInPicture.rawValue, userDefaults: userDefaults), "2026-05-20 09:08")
        XCTAssertEqual(WorkNamingRule.sequence.title(for: date, layout: LayoutType.pictureInPicture.rawValue, userDefaults: userDefaults), "DualCam 0007")
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.workNamingSequence), 8)
    }

    func testWorkNamingRuleFormatsFileStemFromCurrentSequence() {
        userDefaults.set(12, forKey: SettingsKey.workNamingSequence)
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 5
        components.day = 20
        components.hour = 9
        components.minute = 8
        components.second = 7
        let date = components.date!

        let dateLayoutStem = WorkNamingRule.dateLayout.fileNameStem(
            for: date,
            layout: LayoutType.pictureInPicture.rawValue,
            prefix: "photo",
            userDefaults: userDefaults
        )
        let sequenceStem = WorkNamingRule.sequence.fileNameStem(
            for: date,
            layout: LayoutType.pictureInPicture.rawValue,
            prefix: "live",
            userDefaults: userDefaults
        )

        XCTAssertTrue(dateLayoutStem.hasPrefix("dual_camera_photo_20260520_090807_\(LayoutType.pictureInPicture.rawValue)_"))
        XCTAssertTrue(sequenceStem.hasPrefix("dual_camera_live_0012_"))
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.workNamingSequence), 12)
    }

    func testRearFocalCapabilityFiltersPrototypeZoomsToSupportedRange() {
        let capability = RearFocalCapability(
            minZoomFactor: 1,
            maxZoomFactor: 2.5,
            availableLensKinds: [.wide]
        )

        XCTAssertEqual(capability.recommendedZoomFactors, [1, 2])
        XCTAssertEqual(capability.clampedZoomFactor(0.5), 1)
        XCTAssertEqual(capability.clampedZoomFactor(5), 2.5)
    }

    func testRearFocalCapabilityMapsPhysicalLensStatusAndDigitalCrop() {
        let capability = RearFocalCapability(
            minZoomFactor: 0.5,
            maxZoomFactor: 5,
            physicalLensByZoom: [0.5: .ultra, 1: .wide, 3: .tele]
        )

        XCTAssertEqual(capability.lensStatus(for: 0.5), .physical(.ultra))
        XCTAssertEqual(capability.lensStatus(for: 1), .physical(.wide))
        XCTAssertEqual(capability.lensStatus(for: 3), .physical(.tele))
        XCTAssertEqual(capability.lensStatus(for: 1.4), .digitalCrop)
    }

    func testRearFocalCapabilityUsesPhysicalLensZoomsForThirteenProStyleRange() {
        let capability = RearFocalCapability(
            minZoomFactor: 0.5,
            maxZoomFactor: 15,
            physicalLensByZoom: [0.5: .ultra, 1: .wide, 3: .tele]
        )

        XCTAssertEqual(capability.recommendedZoomFactors, [0.5, 1, 3])
        XCTAssertEqual(capability.maxZoomFactor, 15)
    }

    func testRearFocalCapabilityAddsTwoTimesCropForFiveTimesTeleRange() {
        let capability = RearFocalCapability(
            minZoomFactor: 0.5,
            maxZoomFactor: 25,
            physicalLensByZoom: [0.5: .ultra, 1: .wide, 5: .tele]
        )

        XCTAssertEqual(capability.recommendedZoomFactors, [0.5, 1, 2, 5])
    }

    func testRearFocalCapabilityFormatsZoomFactors() {
        XCTAssertEqual(RearFocalCapability.formattedZoomFactor(0.5), "0.5×")
        XCTAssertEqual(RearFocalCapability.formattedZoomFactor(1), "1×")
        XCTAssertEqual(RearFocalCapability.formattedZoomFactor(2.3), "2.3×")
    }
}
