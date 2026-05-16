import AVFoundation
import SwiftUI
import UIKit

struct WorkCameraMetadata: Codable, Equatable {
    let resolution: String
    let frameRate: Int
    let dualCaptureMode: String
}

enum WorkKind: String, Codable, CaseIterable, Identifiable {
    case video
    case photo

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .video: return "works.filter.video"
        case .photo: return "works.filter.photo"
        }
    }
}

enum WorksFilter: String, CaseIterable, Identifiable {
    case all
    case video
    case photo

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: return "works.filter.all"
        case .video: return "works.filter.video"
        case .photo: return "works.filter.photo"
        }
    }
}

struct WorkItem: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: WorkKind
    var title: String
    var createdAt: Date
    var duration: TimeInterval?
    var layout: String
    var thumbnailURL: URL?
    var assetURL: URL
    var pairedVideoURL: URL?
    var cameraMetadata: WorkCameraMetadata
}

struct RecordedWorkDraft {
    let kind: WorkKind
    let assetURL: URL
    let pairedVideoURL: URL?
    let createdAt: Date
    let duration: TimeInterval?
    let layout: String
    let resolution: CGSize
    let frameRate: Int
    let isLivePhoto: Bool
}

@MainActor
final class WorksManager: ObservableObject {
    @Published private(set) var items: [WorkItem] = []
    @Published var readError: String?
    @Published var statusMessage: String?

    private let fileManager: FileManager
    private let indexURL: URL
    private let thumbnailsDirectory: URL
    private let documentsDirectory: URL

    var latestWork: WorkItem? { items.first }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualCamApp", isDirectory: true)
        thumbnailsDirectory = supportDirectory.appendingPathComponent("WorksThumbnails", isDirectory: true)
        indexURL = supportDirectory.appendingPathComponent("works_index.json")
        reload()
    }

    func reload() {
        do {
            try ensureDirectories()
            var loadedItems = try loadIndex()
            loadedItems = try repairIndex(uniqueItems(loadedItems))
            items = uniqueItems(loadedItems.sorted { $0.createdAt > $1.createdAt })
            try saveIndex()
            readError = nil
        } catch {
            readError = L10n.string("error.works.readFailed", error.localizedDescription)
        }
    }

    func filteredItems(for filter: WorksFilter) -> [WorkItem] {
        WorksLibrary.filteredItems(items, for: filter)
    }

    func add(_ draft: RecordedWorkDraft) {
        do {
            try ensureDirectories()
            let item = try makeWorkItem(from: draft)
            let itemAssetPath = assetPath(for: item.assetURL)
            items.removeAll { assetPath(for: $0.assetURL) == itemAssetPath }
            items.insert(item, at: 0)
            items = uniqueItems(items.sorted { $0.createdAt > $1.createdAt })
            try saveIndex()
            readError = nil
        } catch {
            readError = L10n.string("error.works.saveFailed", error.localizedDescription)
        }
    }

    func deleteItems(withIDs ids: Set<WorkItem.ID>) {
        guard !ids.isEmpty else { return }

        do {
            let targets = items.filter { ids.contains($0.id) }
            guard !targets.isEmpty else { return }

            for item in targets {
                try deleteFiles(for: item)
            }

            items.removeAll { ids.contains($0.id) }
            try saveIndex()
            readError = nil
            statusMessage = L10n.string("works.delete.success", targets.count)
        } catch {
            statusMessage = L10n.string("error.works.deleteFailed", error.localizedDescription)
        }
    }

    func confirmSavedLocally(_ item: WorkItem) {
        guard fileManager.fileExists(atPath: item.assetURL.path) else {
            statusMessage = L10n.string("error.works.fileMissing")
            return
        }

        statusMessage = L10n.string("works.save.localSuccess")
    }

    private func deleteFiles(for item: WorkItem) throws {
        try removeFileIfPresent(at: item.assetURL)
        if let pairedVideoURL = item.pairedVideoURL {
            try removeFileIfPresent(at: pairedVideoURL)
        }
        if let thumbnailURL = item.thumbnailURL {
            try removeFileIfPresent(at: thumbnailURL)
        }
    }

    private func removeFileIfPresent(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    private func loadIndex() throws -> [WorkItem] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try JSONDecoder().decode([WorkItem].self, from: data).filter { fileManager.fileExists(atPath: $0.assetURL.path) }
    }

    private func saveIndex() throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: indexURL, options: .atomic)
    }

    private func repairIndex(_ currentItems: [WorkItem]) throws -> [WorkItem] {
        var repairedItems = currentItems
        var knownPaths = Set(currentItems.map { assetPath(for: $0.assetURL) })
        let urls = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])

        for url in urls where shouldImport(url) && !knownPaths.contains(assetPath(for: url)) {
            let draft = RecordedWorkDraft(
                kind: url.pathExtension.lowercased() == "mp4" ? .video : .photo,
                assetURL: url,
                pairedVideoURL: nil,
                createdAt: fileDate(for: url),
                duration: url.pathExtension.lowercased() == "mp4" ? videoDuration(for: url) : nil,
                layout: LayoutType.pictureInPicture.rawValue,
                resolution: CGSize(width: 720, height: 1280),
                frameRate: 30,
                isLivePhoto: url.lastPathComponent.hasPrefix("dual_camera_live_")
            )
            let item = try makeWorkItem(from: draft)
            repairedItems.append(item)
            knownPaths.insert(assetPath(for: url))
        }

        return uniqueItems(repairedItems)
    }

    private func uniqueItems(_ source: [WorkItem]) -> [WorkItem] {
        var seenAssetPaths = Set<String>()
        return source.filter { seenAssetPaths.insert(assetPath(for: $0.assetURL)).inserted }
    }

    private func assetPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func shouldImport(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard name.hasPrefix("dual_camera_") else { return false }
        return ext == "mp4" || ext == "jpg" || ext == "jpeg"
    }

    private func makeWorkItem(from draft: RecordedWorkDraft) throws -> WorkItem {
        let thumbnailURL = try? makeThumbnail(for: draft)
        let titleKey = draft.kind == .video ? "works.defaultTitle.video" : (draft.isLivePhoto ? "works.defaultTitle.livePhoto" : "works.defaultTitle.photo")
        let metadata = WorkCameraMetadata(
            resolution: "\(Int(draft.resolution.width))×\(Int(draft.resolution.height))",
            frameRate: draft.frameRate,
            dualCaptureMode: draft.isLivePhoto ? "Live Photo" : "DualCam"
        )
        return WorkItem(
            id: UUID(),
            kind: draft.kind,
            title: L10n.string(titleKey),
            createdAt: draft.createdAt,
            duration: draft.duration,
            layout: draft.layout,
            thumbnailURL: thumbnailURL,
            assetURL: draft.assetURL,
            pairedVideoURL: draft.pairedVideoURL,
            cameraMetadata: metadata
        )
    }

    private func makeThumbnail(for draft: RecordedWorkDraft) throws -> URL? {
        let image: UIImage?
        switch draft.kind {
        case .photo:
            image = UIImage(contentsOfFile: draft.assetURL.path)
        case .video:
            let asset = AVAsset(url: draft.assetURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            image = UIImage(cgImage: cgImage)
        }

        guard let thumbnail = image?.scaledToFit(maxDimension: 480),
              let data = thumbnail.jpegData(compressionQuality: 0.82) else { return nil }

        let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try data.write(to: thumbnailURL, options: .atomic)
        return thumbnailURL
    }

    private func fileDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date()
    }

    private func videoDuration(for url: URL) -> TimeInterval? {
        let seconds = CMTimeGetSeconds(AVAsset(url: url).duration)
        return seconds.isFinite ? seconds : nil
    }
}

private extension UIImage {
    func scaledToFit(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }
        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
