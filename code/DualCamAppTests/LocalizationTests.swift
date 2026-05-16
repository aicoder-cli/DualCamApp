import XCTest
@testable import DualCamApp

final class LocalizationTests: XCTestCase {
    private let localizableEN = "DualCamApp/Resources/en.lproj/Localizable.strings"
    private let localizableZH = "DualCamApp/Resources/zh-Hans.lproj/Localizable.strings"
    private let infoPlistEN = "DualCamApp/Resources/en.lproj/InfoPlist.strings"
    private let infoPlistZH = "DualCamApp/Resources/zh-Hans.lproj/InfoPlist.strings"

    func testLocalizableKeySetsMatchBetweenEnglishAndSimplifiedChinese() throws {
        let english = try StringsFile.load(localizableEN)
        let simplifiedChinese = try StringsFile.load(localizableZH)

        XCTAssertEqual(Set(english.keys), Set(simplifiedChinese.keys))
    }

    func testInfoPlistKeySetsMatchBetweenEnglishAndSimplifiedChinese() throws {
        let english = try StringsFile.load(infoPlistEN)
        let simplifiedChinese = try StringsFile.load(infoPlistZH)

        XCTAssertEqual(Set(english.keys), Set(simplifiedChinese.keys))
    }

    func testFormatPlaceholdersMatchBetweenEnglishAndSimplifiedChinese() throws {
        let english = try StringsFile.load(localizableEN)
        let simplifiedChinese = try StringsFile.load(localizableZH)

        for key in Set(english.keys).intersection(simplifiedChinese.keys).sorted() {
            XCTAssertEqual(
                StringsFile.placeholderTypes(in: english[key] ?? ""),
                StringsFile.placeholderTypes(in: simplifiedChinese[key] ?? ""),
                "Mismatched placeholders for key \(key)"
            )
        }
    }

    func testEnumLocalizationKeysExist() throws {
        let keys = Set(try StringsFile.load(localizableEN).keys)
        let requiredKeys = Set([
            "language.system",
            "language.english",
            "language.simplifiedChinese",
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

    func testMissingLocalizationKeyFallsBackToKey() {
        let missingKey = "tests.missingKey.\(UUID().uuidString)"

        XCTAssertEqual(L10n.string(missingKey), missingKey)
    }
}
