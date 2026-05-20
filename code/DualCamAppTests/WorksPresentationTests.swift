import Foundation
import XCTest
@testable import DualCamApp

final class WorksPresentationTests: XCTestCase {
    func testVideoDurationTextFormatsSeconds() {
        let cases: [(TimeInterval?, String)] = [
            (nil, "00:00"),
            (-4, "00:00"),
            (0, "00:00"),
            (65, "01:05"),
            (3_599, "59:59"),
            (3_600, "60:00")
        ]

        for (duration, expected) in cases {
            let item = TestSupport.makeWorkItem(kind: .video, duration: duration)
            XCTAssertEqual(item.workDurationText, expected)
        }
    }

    func testPhotoDurationTextDistinguishesStillPhotoAndLivePhoto() {
        let photo = TestSupport.makeWorkItem(kind: .photo, duration: nil, pairedVideoURL: nil)
        let livePhoto = TestSupport.makeWorkItem(kind: .photo, duration: nil, pairedVideoURL: URL(fileURLWithPath: "/tmp/live.mov"))

        XCTAssertEqual(photo.workDurationText, L10n.string("works.duration.photo"))
        XCTAssertEqual(livePhoto.workDurationText, L10n.string("works.duration.livePhoto"))
    }

    func testLocalizedLayoutTitleUsesKnownLayoutAndFallsBackToRawValue() {
        let known = TestSupport.makeWorkItem(layout: LayoutType.splitVertical.rawValue)
        let unknown = TestSupport.makeWorkItem(layout: "experimentalLayout")

        XCTAssertEqual(known.localizedLayoutTitle, LayoutType.splitVertical.localizedTitle)
        XCTAssertEqual(unknown.localizedLayoutTitle, "experimentalLayout")
    }

    func testFilteringPreservesOrderAndMatchesKind() {
        let firstVideo = TestSupport.makeWorkItem(id: UUID(), kind: .video, title: "First Video")
        let photo = TestSupport.makeWorkItem(id: UUID(), kind: .photo, title: "Photo")
        let secondVideo = TestSupport.makeWorkItem(id: UUID(), kind: .video, title: "Second Video")
        let items = [firstVideo, photo, secondVideo]

        XCTAssertEqual(WorksLibrary.filteredItems(items, for: .all), items)
        XCTAssertEqual(WorksLibrary.filteredItems(items, for: .video), [firstVideo, secondVideo])
        XCTAssertEqual(WorksLibrary.filteredItems(items, for: .photo), [photo])
    }

    func testWorkItemCodingRoundTripPreservesFields() throws {
        let item = TestSupport.makeWorkItem(
            id: UUID(uuidString: "E1B8D79F-45F4-48A9-A182-8A0B82944A19")!,
            kind: .photo,
            title: "Round Trip",
            createdAt: Date(timeIntervalSince1970: 123_456),
            duration: 42,
            layout: LayoutType.directorStack.rawValue,
            thumbnailURL: URL(fileURLWithPath: "/tmp/thumb.jpg"),
            assetURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            pairedVideoURL: URL(fileURLWithPath: "/tmp/photo.mov"),
            frontOriginalURL: URL(fileURLWithPath: "/tmp/front.mov"),
            backOriginalURL: URL(fileURLWithPath: "/tmp/back.mov"),
            highQualityURL: URL(fileURLWithPath: "/tmp/high_quality.mp4"),
            highQualityRenderStatus: .paused,
            highQualityRenderProgress: 0.42,
            highQualityRenderMessage: "Generating high-quality video…",
            layoutTimeline: [makeTimelineEntry(seconds: 1.25)],
            cameraMetadata: WorkCameraMetadata(resolution: "1080×1920", frameRate: 60, dualCaptureMode: "Live Photo")
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(WorkItem.self, from: data)

        XCTAssertEqual(decoded, item)
    }

    func testWorkItemDecodingDefaultsHighQualityRenderFields() throws {
        let data = try JSONEncoder().encode(LegacyWorkItem(highQualityRenderStatus: nil))
        let decoded = try JSONDecoder().decode(WorkItem.self, from: data)

        XCTAssertEqual(decoded.highQualityRenderStatus, .notStarted)
        XCTAssertEqual(decoded.highQualityRenderProgress, 0)
        XCTAssertNil(decoded.highQualityRenderMessage)
        XCTAssertEqual(decoded.layoutTimeline, [])
    }

    func testReadyHighQualityRenderWithoutStoredProgressDefaultsToComplete() throws {
        let data = try JSONEncoder().encode(LegacyWorkItem(highQualityRenderStatus: .ready))
        let decoded = try JSONDecoder().decode(WorkItem.self, from: data)

        XCTAssertEqual(decoded.highQualityRenderStatus, .ready)
        XCTAssertEqual(decoded.highQualityRenderProgress, 1)
    }

    func testWorkItemClampsDecodedHighQualityProgress() throws {
        let tooHigh = TestSupport.makeWorkItem(highQualityRenderProgress: 3)
        let tooLow = TestSupport.makeWorkItem(highQualityRenderProgress: -1)

        XCTAssertEqual(tooHigh.highQualityRenderProgress, 1)
        XCTAssertEqual(tooLow.highQualityRenderProgress, 0)
    }

    private func makeTimelineEntry(seconds: Double) -> WorkLayoutTimelineEntry {
        let front = CameraLayoutInfo(
            frame: CGRect(x: 10, y: 20, width: 200, height: 300),
            zIndex: 2,
            cornerRadius: 24,
            showBorder: true,
            clipShape: .roundedRectangle
        )
        let back = CameraLayoutInfo(
            frame: CGRect(x: 0, y: 0, width: 1080, height: 1920),
            zIndex: 1,
            cornerRadius: 0,
            showBorder: false,
            clipShape: .rectangle
        )
        let snapshot = RecordingLayoutSnapshot(front: front, back: back, outputSize: CGSize(width: 1080, height: 1920))

        return WorkLayoutTimelineEntry(seconds: seconds, snapshot: snapshot)
    }

    private struct LegacyWorkItem: Encodable {
        let id = UUID(uuidString: "6A12DCB6-C156-4D95-A87A-06D73288A9A7")!
        let kind = WorkKind.video
        let title = "Legacy Work"
        let createdAt = Date(timeIntervalSince1970: 456_789)
        let duration: TimeInterval? = 12
        let layout = LayoutType.pictureInPicture.rawValue
        let thumbnailURL: URL? = nil
        let assetURL = URL(fileURLWithPath: "/tmp/legacy.mp4")
        let pairedVideoURL: URL? = nil
        let frontOriginalURL: URL? = nil
        let backOriginalURL: URL? = nil
        let highQualityURL: URL? = nil
        let highQualityRenderStatus: HighQualityRenderStatus?
        let cameraMetadata = WorkCameraMetadata(resolution: "720×1280", frameRate: 30, dualCaptureMode: "DualCam")

        enum CodingKeys: String, CodingKey {
            case id
            case kind
            case title
            case createdAt
            case duration
            case layout
            case thumbnailURL
            case assetURL
            case pairedVideoURL
            case frontOriginalURL
            case backOriginalURL
            case highQualityURL
            case highQualityRenderStatus
            case cameraMetadata
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(kind, forKey: .kind)
            try container.encode(title, forKey: .title)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encodeIfPresent(duration, forKey: .duration)
            try container.encode(layout, forKey: .layout)
            try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
            try container.encode(assetURL, forKey: .assetURL)
            try container.encodeIfPresent(pairedVideoURL, forKey: .pairedVideoURL)
            try container.encodeIfPresent(frontOriginalURL, forKey: .frontOriginalURL)
            try container.encodeIfPresent(backOriginalURL, forKey: .backOriginalURL)
            try container.encodeIfPresent(highQualityURL, forKey: .highQualityURL)
            try container.encodeIfPresent(highQualityRenderStatus, forKey: .highQualityRenderStatus)
            try container.encode(cameraMetadata, forKey: .cameraMetadata)
        }
    }
}
