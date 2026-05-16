import CoreGraphics
import XCTest
@testable import DualCamApp

final class LayoutManagerTests: XCTestCase {
    func testLayoutTypeFromUnknownRawValueReturnsPictureInPicture() {
        XCTAssertEqual(LayoutType.from("unknown-layout"), .pictureInPicture)
        XCTAssertEqual(LayoutType.from(LayoutType.diagonalCut.rawValue), .diagonalCut)
    }

    func testZeroContainerReturnsZeroFrames() {
        let manager = LayoutManager()
        manager.containerSize = .zero

        TestSupport.assertRect(manager.getFrontCameraLayout().frame, .zero)
        TestSupport.assertRect(manager.getBackCameraLayout().frame, .zero)
    }

    func testSplitVerticalPlacesFrontLeftAndBackRight() {
        let manager = makeManager(layout: .splitVertical)

        let front = manager.getFrontCameraLayout()
        let back = manager.getBackCameraLayout()

        TestSupport.assertRect(front.frame, CGRect(x: 0, y: 0, width: 195, height: 844))
        TestSupport.assertRect(back.frame, CGRect(x: 195, y: 0, width: 195, height: 844))
        XCTAssertGreaterThan(front.zIndex, back.zIndex)
        XCTAssertEqual(front.clipShape, .rectangle)
        XCTAssertEqual(back.clipShape, .rectangle)
        XCTAssertFalse(front.showBorder)
        XCTAssertFalse(back.showBorder)
    }

    func testSplitHorizontalPlacesBackTopAndFrontBottom() {
        let manager = makeManager(layout: .splitHorizontal)

        let front = manager.getFrontCameraLayout()
        let back = manager.getBackCameraLayout()

        TestSupport.assertRect(front.frame, CGRect(x: 0, y: 422, width: 390, height: 422))
        TestSupport.assertRect(back.frame, CGRect(x: 0, y: 0, width: 390, height: 422))
        XCTAssertGreaterThan(front.zIndex, back.zIndex)
    }

    func testPictureInPictureUsesFullBackAndFloatingFront() {
        let manager = makeManager(layout: .pictureInPicture)

        let front = manager.getFrontCameraLayout()
        let back = manager.getBackCameraLayout()

        TestSupport.assertRect(back.frame, CGRect(x: 0, y: 0, width: 390, height: 844))
        TestSupport.assertRect(front.frame, CGRect(x: 230.1, y: 464.2, width: 132.6, height: 286.96))
        XCTAssertEqual(front.clipShape, .roundedRectangle)
        XCTAssertTrue(front.showBorder)
        XCTAssertGreaterThan(front.zIndex, back.zIndex)
    }

    func testCircleReactionUsesCircleFloatingFront() {
        let manager = makeManager(layout: .circleReaction)

        let front = manager.getFrontCameraLayout()
        let back = manager.getBackCameraLayout()

        TestSupport.assertRect(back.frame, CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(front.clipShape, .circle)
        TestSupport.assertCGFloat(front.frame.width, front.frame.height)
    }

    func testDirectorStackUsesOverlappingRoundedFrames() {
        let manager = makeManager(layout: .directorStack)

        let front = manager.getFrontCameraLayout()
        let back = manager.getBackCameraLayout()

        TestSupport.assertRect(front.frame, CGRect(x: 93.6, y: 135.04, width: 280.8, height: 573.92))
        TestSupport.assertRect(back.frame, CGRect(x: 15.6, y: 50.64, width: 280.8, height: 573.92))
        XCTAssertEqual(front.cornerRadius, 28)
        XCTAssertEqual(back.cornerRadius, 28)
        XCTAssertEqual(front.clipShape, .roundedRectangle)
        XCTAssertEqual(back.clipShape, .roundedRectangle)
        XCTAssertTrue(front.showBorder)
        XCTAssertTrue(back.showBorder)
        XCTAssertGreaterThan(front.zIndex, back.zIndex)
    }

    func testDiagonalCutUsesComplementaryClipShapes() {
        let manager = makeManager(layout: .diagonalCut)

        let front = manager.getFrontCameraLayout()
        let back = manager.getBackCameraLayout()

        TestSupport.assertRect(front.frame, CGRect(x: 0, y: 0, width: 390, height: 844))
        TestSupport.assertRect(back.frame, CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(front.clipShape, .diagonalTrailing)
        XCTAssertEqual(back.clipShape, .diagonalLeading)
    }

    func testScaleUpdatesClampToMinAndMax() {
        let manager = makeManager(layout: .splitVertical)

        manager.updateFrontCameraScale(0.1)
        manager.updateBackCameraScale(2.0)

        XCTAssertEqual(manager.frontCameraScale, manager.minScale)
        XCTAssertEqual(manager.backCameraScale, manager.maxScale)
    }

    func testOffsetUpdatesAccumulate() {
        let manager = makeManager(layout: .pictureInPicture)

        manager.updateFrontCameraOffset(CGSize(width: 10, height: -4))
        manager.updateFrontCameraOffset(CGSize(width: -3, height: 6))
        manager.updateBackCameraOffset(CGSize(width: 8, height: 12))
        manager.updateBackCameraOffset(CGSize(width: 2, height: -5))

        TestSupport.assertSize(manager.frontCameraOffset, CGSize(width: 7, height: 2))
        TestSupport.assertSize(manager.backCameraOffset, CGSize(width: 10, height: 7))
    }

    func testPointHitTestingMatchesComputedFrame() {
        let manager = makeManager(layout: .pictureInPicture)
        let frontFrame = manager.getFrontCameraLayout().frame

        XCTAssertTrue(manager.isPointInCameraArea(CGPoint(x: frontFrame.midX, y: frontFrame.midY), for: .front))
        XCTAssertFalse(manager.isPointInCameraArea(CGPoint(x: 10, y: 10), for: .front))
        XCTAssertTrue(manager.isPointInCameraArea(CGPoint(x: 10, y: 10), for: .back))
    }

    func testRecordingLayoutSnapshotScalesFramesAndPreservesMetadata() {
        let manager = makeManager(layout: .pictureInPicture)
        let frontBefore = manager.getFrontCameraLayout()
        let backBefore = manager.getBackCameraLayout()
        let outputSize = CGSize(width: 1080, height: 1920)

        let snapshot = manager.makeRecordingLayoutSnapshot(outputSize: outputSize)

        let scale = min(outputSize.width / manager.containerSize.width, outputSize.height / manager.containerSize.height)
        let scaledSize = CGSize(width: manager.containerSize.width * scale, height: manager.containerSize.height * scale)
        let origin = CGPoint(x: (outputSize.width - scaledSize.width) / 2, y: (outputSize.height - scaledSize.height) / 2)

        XCTAssertEqual(snapshot.outputSize, outputSize)
        assertScaled(snapshot.front, from: frontBefore, scale: scale, origin: origin)
        assertScaled(snapshot.back, from: backBefore, scale: scale, origin: origin)
    }

    private func makeManager(layout: LayoutType) -> LayoutManager {
        let manager = LayoutManager()
        manager.containerSize = CGSize(width: 390, height: 844)
        manager.currentLayout = layout
        return manager
    }

    private func assertScaled(_ actual: CameraLayoutInfo, from expected: CameraLayoutInfo, scale: CGFloat, origin: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        TestSupport.assertRect(
            actual.frame,
            CGRect(
                x: origin.x + expected.frame.origin.x * scale,
                y: origin.y + expected.frame.origin.y * scale,
                width: expected.frame.width * scale,
                height: expected.frame.height * scale
            ),
            file: file,
            line: line
        )
        TestSupport.assertCGFloat(actual.cornerRadius, expected.cornerRadius * scale, file: file, line: line)
        XCTAssertEqual(actual.zIndex, expected.zIndex, file: file, line: line)
        XCTAssertEqual(actual.showBorder, expected.showBorder, file: file, line: line)
        XCTAssertEqual(actual.clipShape, expected.clipShape, file: file, line: line)
    }
}
