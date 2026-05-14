import Foundation
import XCTest
@testable import DualCameraRecorder

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
            cameraMetadata: WorkCameraMetadata(resolution: "1080×1920", frameRate: 60, dualCaptureMode: "Live Photo")
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(WorkItem.self, from: data)

        XCTAssertEqual(decoded, item)
    }
}
