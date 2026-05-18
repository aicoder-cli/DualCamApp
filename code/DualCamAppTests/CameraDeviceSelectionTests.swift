import AVFoundation
@testable import DualCamApp
import XCTest

final class CameraDeviceSelectionTests: XCTestCase {
    func testFrontDeviceTypeRankPrefersWideThenUltraWideThenTrueDepth() {
        XCTAssertGreaterThan(
            CameraDeviceSelection.frontCameraDeviceTypeRank(.builtInWideAngleCamera),
            CameraDeviceSelection.frontCameraDeviceTypeRank(.builtInUltraWideCamera)
        )
        XCTAssertGreaterThan(
            CameraDeviceSelection.frontCameraDeviceTypeRank(.builtInUltraWideCamera),
            CameraDeviceSelection.frontCameraDeviceTypeRank(.builtInTrueDepthCamera)
        )
    }

    func testFrontDeviceTypeSupportIncludesIpadFrontCameraVariants() {
        XCTAssertTrue(CameraDeviceSelection.isSupportedFrontCameraDeviceType(.builtInUltraWideCamera))
        XCTAssertTrue(CameraDeviceSelection.isSupportedFrontCameraDeviceType(.builtInTrueDepthCamera))
    }

    func testUnsupportedFrontDeviceTypeRanksLast() {
        XCTAssertEqual(CameraDeviceSelection.frontCameraDeviceTypeRank(.builtInTelephotoCamera), 0)
        XCTAssertFalse(CameraDeviceSelection.isSupportedFrontCameraDeviceType(.builtInTelephotoCamera))
    }

    func testMultiCamReadinessRequiresOutputAndPreviewConnections() {
        XCTAssertTrue(CameraDeviceSelection.isMultiCamCameraReady(hasOutputConnection: true, hasPreviewConnection: true))
        XCTAssertFalse(CameraDeviceSelection.isMultiCamCameraReady(hasOutputConnection: false, hasPreviewConnection: true))
        XCTAssertFalse(CameraDeviceSelection.isMultiCamCameraReady(hasOutputConnection: true, hasPreviewConnection: false))
    }

    func testSingleSessionReadinessRequiresInputOutputAndVideoConnection() {
        XCTAssertTrue(CameraDeviceSelection.isSingleSessionCameraReady(didAddInput: true, didAddOutput: true, hasVideoConnection: true))
        XCTAssertFalse(CameraDeviceSelection.isSingleSessionCameraReady(didAddInput: false, didAddOutput: true, hasVideoConnection: true))
        XCTAssertFalse(CameraDeviceSelection.isSingleSessionCameraReady(didAddInput: true, didAddOutput: false, hasVideoConnection: true))
        XCTAssertFalse(CameraDeviceSelection.isSingleSessionCameraReady(didAddInput: true, didAddOutput: true, hasVideoConnection: false))
    }
}
