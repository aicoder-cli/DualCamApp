import Foundation
import SwiftUI

enum SettingsKey {
    static let schemaVersion = "settingsSchemaVersion"
    static let appLanguageCode = "appLanguageCode"
    static let defaultCaptureMode = "defaultCaptureMode"
    static let defaultLayout = "defaultLayout"
    static let rememberLastLayout = "rememberLastLayout"
    static let lastLayout = "lastLayout"
    static let photoAspectRatio = "photoAspectRatio"
    static let videoResolution = "videoResolution"
    static let shootingFrameRate = "shootingFrameRate"
    static let videoCodec = "videoCodec"
    static let defaultLivePhotoDuration = "defaultLivePhotoDuration"
    static let immersiveRecording = "immersiveRecording"
    static let controlRevealSeconds = "controlRevealSeconds"
    static let recordingCountdownSeconds = "recordingCountdownSeconds"
    static let soundAndHapticsEnabled = "soundAndHapticsEnabled"
    static let lastRearFocalLength = "lastRearFocalLength"
    static let saveToSystemPhotos = "saveToSystemPhotos"
    static let keepOriginalStreams = "keepOriginalStreams"
    static let workNamingRule = "workNamingRule"
    static let autoClearCache = "autoClearCache"
}

enum AppSettings {
    static let currentSchemaVersion = 1

    static func migrateIfNeeded(userDefaults: UserDefaults = .standard) {
        registerDefaults(userDefaults: userDefaults)

        let version = userDefaults.integer(forKey: SettingsKey.schemaVersion)
        guard version < currentSchemaVersion else { return }

        userDefaults.set(currentSchemaVersion, forKey: SettingsKey.schemaVersion)
    }

    static func registerDefaults(userDefaults: UserDefaults = .standard) {
        userDefaults.register(defaults: [
            SettingsKey.appLanguageCode: AppLanguage.system.rawValue,
            SettingsKey.defaultCaptureMode: DefaultCaptureMode.video.rawValue,
            SettingsKey.defaultLayout: LayoutType.pictureInPicture.rawValue,
            SettingsKey.rememberLastLayout: true,
            SettingsKey.lastLayout: LayoutType.pictureInPicture.rawValue,
            SettingsKey.photoAspectRatio: PhotoAspectRatio.threeByFour.rawValue,
            SettingsKey.videoResolution: VideoResolution.p1080.rawValue,
            SettingsKey.shootingFrameRate: ShootingFrameRate.standard.rawValue,
            SettingsKey.videoCodec: VideoCodec.h264.rawValue,
            SettingsKey.defaultLivePhotoDuration: 2.5,
            SettingsKey.immersiveRecording: true,
            SettingsKey.controlRevealSeconds: ControlRevealDuration.twoSeconds.rawValue,
            SettingsKey.recordingCountdownSeconds: RecordingCountdown.off.rawValue,
            SettingsKey.soundAndHapticsEnabled: true,
            SettingsKey.lastRearFocalLength: 1.0,
            SettingsKey.saveToSystemPhotos: false,
            SettingsKey.keepOriginalStreams: false,
            SettingsKey.workNamingRule: WorkNamingRule.dateLayout.rawValue,
            SettingsKey.autoClearCache: false
        ])
    }
}

enum DefaultCaptureMode: String, CaseIterable, Identifiable {
    case photo
    case video
    case livePhoto

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .photo: return "settings.defaultCaptureMode.photo"
        case .video: return "settings.defaultCaptureMode.video"
        case .livePhoto: return "settings.defaultCaptureMode.livePhoto"
        }
    }

    var descriptionKey: LocalizedStringKey? {
        switch self {
        case .photo: return "settings.defaultCaptureMode.photo.description"
        case .video: return "settings.defaultCaptureMode.video.description"
        case .livePhoto: return "settings.defaultCaptureMode.livePhoto.description"
        }
    }

    static func from(_ rawValue: String) -> DefaultCaptureMode {
        DefaultCaptureMode(rawValue: rawValue) ?? .video
    }
}

enum PhotoAspectRatio: String, CaseIterable, Identifiable {
    case threeByFour
    case nineBySixteen

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .threeByFour: return "settings.photoAspectRatio.3x4"
        case .nineBySixteen: return "settings.photoAspectRatio.9x16"
        }
    }

    var descriptionKey: LocalizedStringKey? {
        switch self {
        case .threeByFour: return "settings.photoAspectRatio.3x4.description"
        case .nineBySixteen: return "settings.photoAspectRatio.9x16.description"
        }
    }

    var shortLabel: String {
        switch self {
        case .threeByFour: return "3:4"
        case .nineBySixteen: return "9:16"
        }
    }

    var outputSize: CGSize {
        switch self {
        case .threeByFour: return CGSize(width: 1080, height: 1440)
        case .nineBySixteen: return CGSize(width: 1080, height: 1920)
        }
    }

    static func from(_ rawValue: String) -> PhotoAspectRatio {
        PhotoAspectRatio(rawValue: rawValue) ?? .threeByFour
    }
}

enum VideoResolution: String, CaseIterable, Identifiable {
    case p720
    case p1080

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .p720: return "settings.videoResolution.720p"
        case .p1080: return "settings.videoResolution.1080p"
        }
    }

    var descriptionKey: LocalizedStringKey? {
        switch self {
        case .p720: return "settings.videoResolution.720p.description"
        case .p1080: return "settings.videoResolution.1080p.description"
        }
    }

    var outputSize: CGSize {
        switch self {
        case .p720: return CGSize(width: 720, height: 1280)
        case .p1080: return CGSize(width: 1080, height: 1920)
        }
    }

    var shortLabel: String {
        switch self {
        case .p720: return "720P"
        case .p1080: return "1080P"
        }
    }

    static func from(_ rawValue: String) -> VideoResolution {
        VideoResolution(rawValue: rawValue) ?? .p1080
    }
}

struct MediaOutputSpec: Equatable {
    let photoAspectRatio: PhotoAspectRatio
    let videoResolution: VideoResolution
    let frameRate: Int
    let videoCodec: VideoCodec

    var photoSize: CGSize { photoAspectRatio.outputSize }
    var videoSize: CGSize { videoResolution.outputSize }

    var photoBadgeText: String {
        "\(photoAspectRatio.shortLabel) · JPEG · \(Self.sizeText(photoSize))"
    }

    var videoBadgeText: String {
        "\(videoResolution.shortLabel) · MP4 · \(frameRate)"
    }

    var settingsSummaryText: String {
        "Photo \(Self.sizeText(photoSize)) · Video \(Self.sizeText(videoSize))"
    }

    static func sizeText(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .h264: return "settings.videoCodec.h264"
        case .hevc: return "settings.videoCodec.hevc"
        }
    }

    var descriptionKey: LocalizedStringKey? {
        switch self {
        case .h264: return "settings.videoCodec.h264.description"
        case .hevc: return "settings.videoCodec.hevc.description"
        }
    }

    static func from(_ rawValue: String) -> VideoCodec {
        VideoCodec(rawValue: rawValue) ?? .h264
    }
}

enum LivePhotoDurationOption: String, CaseIterable, Identifiable {
    case short = "1.5"
    case standard = "3.0"
    case extended = "5.0"

    var id: String { rawValue }

    var seconds: Double {
        switch self {
        case .short: return 1.5
        case .standard: return 3.0
        case .extended: return 5.0
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .short: return "settings.livePhotoDuration.short"
        case .standard: return "settings.livePhotoDuration.standard"
        case .extended: return "settings.livePhotoDuration.extended"
        }
    }

    var descriptionKey: LocalizedStringKey? { nil }

    static func from(seconds: Double) -> LivePhotoDurationOption {
        LivePhotoDurationOption.allCases.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) } ?? .standard
    }
}

enum ControlRevealDuration: Int, CaseIterable, Identifiable {
    case twoSeconds = 2
    case threeSeconds = 3
    case fiveSeconds = 5

    var id: Int { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .twoSeconds: return "settings.controlReveal.2"
        case .threeSeconds: return "settings.controlReveal.3"
        case .fiveSeconds: return "settings.controlReveal.5"
        }
    }

    var descriptionKey: LocalizedStringKey? { nil }

    static func from(_ rawValue: Int) -> ControlRevealDuration {
        ControlRevealDuration(rawValue: rawValue) ?? .twoSeconds
    }
}

enum RecordingCountdown: Int, CaseIterable, Identifiable {
    case off = 0
    case threeSeconds = 3
    case fiveSeconds = 5

    var id: Int { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "settings.recordingCountdown.off"
        case .threeSeconds: return "settings.recordingCountdown.3"
        case .fiveSeconds: return "settings.recordingCountdown.5"
        }
    }

    var descriptionKey: LocalizedStringKey? { nil }

    static func from(_ rawValue: Int) -> RecordingCountdown {
        RecordingCountdown(rawValue: rawValue) ?? .off
    }
}

enum WorkNamingRule: String, CaseIterable, Identifiable {
    case dateLayout
    case dateOnly
    case sequence

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .dateLayout: return "settings.workNaming.dateLayout"
        case .dateOnly: return "settings.workNaming.dateOnly"
        case .sequence: return "settings.workNaming.sequence"
        }
    }

    var descriptionKey: LocalizedStringKey? {
        switch self {
        case .dateLayout: return "settings.workNaming.dateLayout.description"
        case .dateOnly: return "settings.workNaming.dateOnly.description"
        case .sequence: return "settings.workNaming.sequence.description"
        }
    }

    static func from(_ rawValue: String) -> WorkNamingRule {
        WorkNamingRule(rawValue: rawValue) ?? .dateLayout
    }
}
