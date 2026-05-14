import Foundation
import XCTest
@testable import DualCameraRecorder

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DualCameraRecorderTests.\(UUID().uuidString)"
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
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.videoResolution), VideoResolution.p720.rawValue)
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.shootingFrameRate), ShootingFrameRate.standard.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.videoCodec), VideoCodec.h264.rawValue)
        XCTAssertEqual(userDefaults.double(forKey: SettingsKey.defaultLivePhotoDuration), 2.5)
        XCTAssertTrue(userDefaults.bool(forKey: SettingsKey.immersiveRecording))
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.controlRevealSeconds), ControlRevealDuration.twoSeconds.rawValue)
        XCTAssertEqual(userDefaults.integer(forKey: SettingsKey.recordingCountdownSeconds), RecordingCountdown.off.rawValue)
        XCTAssertTrue(userDefaults.bool(forKey: SettingsKey.soundAndHapticsEnabled))
        XCTAssertTrue(userDefaults.bool(forKey: SettingsKey.saveToSystemPhotos))
        XCTAssertFalse(userDefaults.bool(forKey: SettingsKey.keepOriginalStreams))
        XCTAssertEqual(userDefaults.string(forKey: SettingsKey.workNamingRule), WorkNamingRule.dateLayout.rawValue)
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
        XCTAssertEqual(VideoResolution.from("bad"), .p720)
        XCTAssertEqual(VideoCodec.from("bad"), .h264)
        XCTAssertEqual(ControlRevealDuration.from(-1), .twoSeconds)
        XCTAssertEqual(RecordingCountdown.from(-1), .off)
        XCTAssertEqual(WorkNamingRule.from("bad"), .dateLayout)
    }

    func testLivePhotoDurationOptionChoosesNearestValue() {
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 1.5), .short)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 3.0), .standard)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 5.0), .extended)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: -100), .short)
        XCTAssertEqual(LivePhotoDurationOption.from(seconds: 4.4), .extended)
    }
}
