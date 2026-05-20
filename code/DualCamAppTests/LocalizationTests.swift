import XCTest
@testable import DualCamApp

final class LocalizationTests: XCTestCase {
    private let localizableFiles = [
        "en": "DualCamApp/Resources/en.lproj/Localizable.strings",
        "zh-Hans": "DualCamApp/Resources/zh-Hans.lproj/Localizable.strings",
        "zh-Hant": "DualCamApp/Resources/zh-Hant.lproj/Localizable.strings",
        "ko": "DualCamApp/Resources/ko.lproj/Localizable.strings"
    ]
    private let infoPlistFiles = [
        "en": "DualCamApp/Resources/en.lproj/InfoPlist.strings",
        "zh-Hans": "DualCamApp/Resources/zh-Hans.lproj/InfoPlist.strings",
        "zh-Hant": "DualCamApp/Resources/zh-Hant.lproj/InfoPlist.strings",
        "ko": "DualCamApp/Resources/ko.lproj/InfoPlist.strings"
    ]

    func testLocalizableKeySetsMatchEnglish() throws {
        let english = try StringsFile.load(localizableFiles["en"]!)

        for (language, path) in localizableFiles where language != "en" {
            let localized = try StringsFile.load(path)

            XCTAssertEqual(Set(english.keys), Set(localized.keys), "Mismatched Localizable.strings keys for \(language)")
        }
    }

    func testInfoPlistKeySetsMatchEnglish() throws {
        let english = try StringsFile.load(infoPlistFiles["en"]!)

        for (language, path) in infoPlistFiles where language != "en" {
            let localized = try StringsFile.load(path)

            XCTAssertEqual(Set(english.keys), Set(localized.keys), "Mismatched InfoPlist.strings keys for \(language)")
        }
    }

    func testFormatPlaceholdersMatchEnglish() throws {
        let english = try StringsFile.load(localizableFiles["en"]!)

        for (language, path) in localizableFiles where language != "en" {
            let localized = try StringsFile.load(path)

            for key in Set(english.keys).intersection(localized.keys).sorted() {
                XCTAssertEqual(
                    StringsFile.placeholderTypes(in: english[key] ?? ""),
                    StringsFile.placeholderTypes(in: localized[key] ?? ""),
                    "Mismatched placeholders for key \(key) in \(language)"
                )
            }
        }
    }

    func testEnumLocalizationKeysExist() throws {
        let keys = Set(try StringsFile.load(localizableFiles["en"]!).keys)
        let requiredKeys = Set([
            "language.system",
            "language.english",
            "language.simplifiedChinese",
            "language.traditionalChinese",
            "language.korean",
            "shape.square",
            "shape.rounded",
            "shape.circle",
            "shape.diagonal",
            "works.filter.all",
            "works.filter.video",
            "works.filter.photo",
            "settings.defaultCaptureMode.photo",
            "settings.defaultCaptureMode.video",
            "settings.defaultCaptureMode.livePhoto",
            "settings.defaultCaptureMode.photo.description",
            "settings.defaultCaptureMode.video.description",
            "settings.defaultCaptureMode.livePhoto.description",
            "settings.videoResolution.720p",
            "settings.videoResolution.1080p",
            "settings.videoResolution.720p.description",
            "settings.videoResolution.1080p.description",
            "settings.videoCodec.h264",
            "settings.videoCodec.hevc",
            "settings.videoCodec.h264.description",
            "settings.videoCodec.hevc.description",
            "settings.livePhotoDuration.short",
            "settings.livePhotoDuration.standard",
            "settings.livePhotoDuration.extended",
            "settings.controlReveal.2",
            "settings.controlReveal.3",
            "settings.controlReveal.5",
            "settings.recordingCountdown.off",
            "settings.recordingCountdown.3",
            "settings.recordingCountdown.5",
            "settings.workNaming.dateLayout",
            "settings.workNaming.dateOnly",
            "settings.workNaming.sequence",
            "settings.workNaming.dateLayout.description",
            "settings.workNaming.dateOnly.description",
            "settings.workNaming.sequence.description"
        ] + LayoutType.allCases.flatMap { layout in
            [
                "layout.\(layout.rawValue).title",
                "layout.\(layout.rawValue).shortTitle",
                "layout.\(layout.rawValue).description"
            ]
        })

        XCTAssertTrue(requiredKeys.isSubset(of: keys), "Missing keys: \(requiredKeys.subtracting(keys).sorted())")
    }

    func testEachSelectableAppLanguageHasLocalizableResources() {
        let availableLanguages = Set(localizableFiles.keys)
        let selectableLanguages = Set(AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue))

        XCTAssertEqual(selectableLanguages, availableLanguages)
    }

    func testMissingLocalizationKeyFallsBackToKey() {
        let missingKey = "tests.missingKey.\(UUID().uuidString)"

        XCTAssertEqual(L10n.string(missingKey), missingKey)
    }
}
