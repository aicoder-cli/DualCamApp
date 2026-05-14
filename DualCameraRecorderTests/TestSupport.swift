import CoreGraphics
import Foundation
import XCTest
@testable import DualCameraRecorder

enum TestSupport {
    static func assertCGFloat(_ actual: CGFloat, _ expected: CGFloat, accuracy: CGFloat = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }

    static func assertSize(_ actual: CGSize, _ expected: CGSize, accuracy: CGFloat = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        assertCGFloat(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        assertCGFloat(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    static func assertRect(_ actual: CGRect, _ expected: CGRect, accuracy: CGFloat = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        assertCGFloat(actual.origin.x, expected.origin.x, accuracy: accuracy, file: file, line: line)
        assertCGFloat(actual.origin.y, expected.origin.y, accuracy: accuracy, file: file, line: line)
        assertCGFloat(actual.size.width, expected.size.width, accuracy: accuracy, file: file, line: line)
        assertCGFloat(actual.size.height, expected.size.height, accuracy: accuracy, file: file, line: line)
    }

    static func makeWorkItem(
        id: UUID = UUID(),
        kind: WorkKind = .video,
        title: String = "Test Work",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        duration: TimeInterval? = 65,
        layout: String = LayoutType.pictureInPicture.rawValue,
        thumbnailURL: URL? = nil,
        assetURL: URL = URL(fileURLWithPath: "/tmp/dual_camera_test.mp4"),
        pairedVideoURL: URL? = nil,
        cameraMetadata: WorkCameraMetadata = WorkCameraMetadata(resolution: "720×1280", frameRate: 30, dualCaptureMode: "DualCam")
    ) -> WorkItem {
        WorkItem(
            id: id,
            kind: kind,
            title: title,
            createdAt: createdAt,
            duration: duration,
            layout: layout,
            thumbnailURL: thumbnailURL,
            assetURL: assetURL,
            pairedVideoURL: pairedVideoURL,
            cameraMetadata: cameraMetadata
        )
    }
}

enum SourcePaths {
    static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func resource(_ relativePath: String) -> URL {
        projectRoot.appendingPathComponent(relativePath)
    }
}

enum StringsFile {
    static func load(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String: String] {
        let url = SourcePaths.resource(relativePath)
        let data = try Data(contentsOf: url)
        guard let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
            XCTFail("Unable to parse strings file at \(url.path)", file: file, line: line)
            return [:]
        }
        return values
    }

    static func placeholderTypes(in value: String) -> [String] {
        let pattern = #"(?<!%)%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[hlLzjtq]?[diuoxXfFeEgGaAcCsSp@]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: value), let specifier = value[matchRange].last else { return nil }
            return String(specifier)
        }
    }
}
