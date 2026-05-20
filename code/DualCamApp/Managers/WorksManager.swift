import AVFoundation
import Combine
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

enum HighQualityRenderStatus: String, Codable, Equatable {
    case notStarted
    case rendering
    case paused
    case ready
    case failed
    case cancelled
}

final class HighQualityRenderControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var isPaused = false
    private var isCancelled = false

    func pause() {
        condition.lock()
        isPaused = true
        condition.unlock()
    }

    func resume() {
        condition.lock()
        isPaused = false
        condition.broadcast()
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        isCancelled = true
        isPaused = false
        condition.broadcast()
        condition.unlock()
    }

    func waitIfNeeded() throws {
        condition.lock()
        defer { condition.unlock() }
        while isPaused && !isCancelled {
            condition.wait()
        }
        if isCancelled {
            throw CancellationError()
        }
    }
}

private struct HighQualityRenderJob {
    let renderer: VideoRecorder
    let control: HighQualityRenderControl
    let task: Task<Void, Never>
    let backgroundTaskID: UIBackgroundTaskIdentifier
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
    var frontOriginalURL: URL?
    var backOriginalURL: URL?
    var highQualityURL: URL?
    var highQualityRenderStatus: HighQualityRenderStatus
    var highQualityRenderProgress: Double
    var highQualityRenderMessage: String?
    var layoutTimeline: [WorkLayoutTimelineEntry]
    var cameraMetadata: WorkCameraMetadata

    init(
        id: UUID,
        kind: WorkKind,
        title: String,
        createdAt: Date,
        duration: TimeInterval?,
        layout: String,
        thumbnailURL: URL?,
        assetURL: URL,
        pairedVideoURL: URL?,
        frontOriginalURL: URL? = nil,
        backOriginalURL: URL? = nil,
        highQualityURL: URL? = nil,
        highQualityRenderStatus: HighQualityRenderStatus = .notStarted,
        highQualityRenderProgress: Double = 0,
        highQualityRenderMessage: String? = nil,
        layoutTimeline: [WorkLayoutTimelineEntry] = [],
        cameraMetadata: WorkCameraMetadata
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.layout = layout
        self.thumbnailURL = thumbnailURL
        self.assetURL = assetURL
        self.pairedVideoURL = pairedVideoURL
        self.frontOriginalURL = frontOriginalURL
        self.backOriginalURL = backOriginalURL
        self.highQualityURL = highQualityURL
        self.highQualityRenderStatus = highQualityRenderStatus
        self.highQualityRenderProgress = min(max(highQualityRenderProgress, 0), 1)
        self.highQualityRenderMessage = highQualityRenderMessage
        self.layoutTimeline = layoutTimeline
        self.cameraMetadata = cameraMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(WorkKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        layout = try container.decode(String.self, forKey: .layout)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        assetURL = try container.decode(URL.self, forKey: .assetURL)
        pairedVideoURL = try container.decodeIfPresent(URL.self, forKey: .pairedVideoURL)
        frontOriginalURL = try container.decodeIfPresent(URL.self, forKey: .frontOriginalURL)
        backOriginalURL = try container.decodeIfPresent(URL.self, forKey: .backOriginalURL)
        highQualityURL = try container.decodeIfPresent(URL.self, forKey: .highQualityURL)
        highQualityRenderStatus = try container.decodeIfPresent(HighQualityRenderStatus.self, forKey: .highQualityRenderStatus) ?? .notStarted
        let decodedProgress = try container.decodeIfPresent(Double.self, forKey: .highQualityRenderProgress) ?? (highQualityRenderStatus == .ready ? 1 : 0)
        highQualityRenderProgress = min(max(decodedProgress, 0), 1)
        highQualityRenderMessage = try container.decodeIfPresent(String.self, forKey: .highQualityRenderMessage)
        layoutTimeline = try container.decodeIfPresent([WorkLayoutTimelineEntry].self, forKey: .layoutTimeline) ?? []
        cameraMetadata = try container.decode(WorkCameraMetadata.self, forKey: .cameraMetadata)
    }
}

struct RecordedWorkDraft {
    let kind: WorkKind
    let assetURL: URL
    let pairedVideoURL: URL?
    let frontOriginalURL: URL?
    let backOriginalURL: URL?
    let highQualityURL: URL?
    let highQualityRenderStatus: HighQualityRenderStatus
    let highQualityRenderProgress: Double
    let highQualityRenderMessage: String?
    let layoutTimeline: [WorkLayoutTimelineEntry]
    let createdAt: Date
    let duration: TimeInterval?
    let layout: String
    let resolution: CGSize
    let frameRate: Int
    let isLivePhoto: Bool

    init(
        kind: WorkKind,
        assetURL: URL,
        pairedVideoURL: URL?,
        frontOriginalURL: URL? = nil,
        backOriginalURL: URL? = nil,
        highQualityURL: URL? = nil,
        highQualityRenderStatus: HighQualityRenderStatus = .notStarted,
        highQualityRenderProgress: Double = 0,
        highQualityRenderMessage: String? = nil,
        layoutTimeline: [WorkLayoutTimelineEntry] = [],
        createdAt: Date,
        duration: TimeInterval?,
        layout: String,
        resolution: CGSize,
        frameRate: Int,
        isLivePhoto: Bool
    ) {
        self.kind = kind
        self.assetURL = assetURL
        self.pairedVideoURL = pairedVideoURL
        self.frontOriginalURL = frontOriginalURL
        self.backOriginalURL = backOriginalURL
        self.highQualityURL = highQualityURL
        self.highQualityRenderStatus = highQualityRenderStatus
        self.highQualityRenderProgress = min(max(highQualityRenderProgress, 0), 1)
        self.highQualityRenderMessage = highQualityRenderMessage
        self.layoutTimeline = layoutTimeline
        self.createdAt = createdAt
        self.duration = duration
        self.layout = layout
        self.resolution = resolution
        self.frameRate = frameRate
        self.isLivePhoto = isLivePhoto
    }
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
    private var highQualityRenderJobs: [WorkItem.ID: HighQualityRenderJob] = [:]

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
            items = normalizeRenderStates(uniqueItems(loadedItems.sorted { $0.createdAt > $1.createdAt }))
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
                cancelHighQualityRender(for: item)
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

    func startHighQualityRender(for item: WorkItem) {
        let itemID = item.id
        guard highQualityRenderJobs[itemID] == nil else { return }
        guard let currentItem = self.item(withID: itemID) else { return }
        guard let frontOriginalURL = currentItem.frontOriginalURL,
              fileManager.fileExists(atPath: frontOriginalURL.path) else {
            statusMessage = L10n.string("error.works.highQualityMissingOriginals")
            return
        }
        if let backOriginalURL = currentItem.backOriginalURL,
           !fileManager.fileExists(atPath: backOriginalURL.path) {
            statusMessage = L10n.string("error.works.highQualityMissingOriginals")
            return
        }

        let control = HighQualityRenderControl()
        let renderer = VideoRecorder()
        let backgroundTaskID = beginHighQualityBackgroundTask(for: itemID)
        updateHighQualityRenderState(for: itemID, status: .rendering, progress: 0, message: L10n.string("works.highQuality.phase.preparing"))

        let task = Task<Void, Never> { [weak self, control, renderer] in
            do {
                let highQualityURL = try await renderer.renderHighQualityVideo(
                    frontURL: frontOriginalURL,
                    backURL: currentItem.backOriginalURL,
                    layoutTimeline: currentItem.layoutTimeline,
                    frameRate: currentItem.cameraMetadata.frameRate,
                    control: control,
                    progress: { progress, message in
                        Task { @MainActor [weak self] in
                            self?.updateHighQualityRenderProgress(for: itemID, progress: progress, message: message)
                        }
                    }
                )
                await MainActor.run { [weak self] in
                    self?.completeHighQualityRender(for: itemID, url: highQualityURL)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.item(withID: itemID)?.highQualityRenderStatus != .cancelled {
                        self.pauseHighQualityRenderAfterInterruption(for: itemID)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.failHighQualityRender(for: itemID, error: error)
                }
            }
        }

        highQualityRenderJobs[itemID] = HighQualityRenderJob(
            renderer: renderer,
            control: control,
            task: task,
            backgroundTaskID: backgroundTaskID
        )
    }

    func pauseHighQualityRender(for item: WorkItem) {
        guard let job = highQualityRenderJobs[item.id] else {
            updateHighQualityRenderState(for: item.id, status: .paused, message: L10n.string("works.highQuality.phase.paused"))
            return
        }
        job.control.pause()
        updateHighQualityRenderState(for: item.id, status: .paused, message: L10n.string("works.highQuality.phase.paused"))
    }

    func resumeHighQualityRender(for item: WorkItem) {
        if let job = highQualityRenderJobs[item.id] {
            job.control.resume()
            updateHighQualityRenderState(for: item.id, status: .rendering, message: L10n.string("works.highQuality.phase.rendering"))
        } else {
            startHighQualityRender(for: item)
        }
    }

    func cancelHighQualityRender(for item: WorkItem) {
        if let job = highQualityRenderJobs[item.id] {
            job.control.cancel()
            job.task.cancel()
            endHighQualityBackgroundTask(job.backgroundTaskID)
            highQualityRenderJobs[item.id] = nil
        }
        updateHighQualityRenderState(for: item.id, status: .cancelled, progress: 0, message: L10n.string("works.highQuality.phase.cancelled"))
    }

    func markHighQualityRenderStarted(for item: WorkItem) {
        updateHighQualityRenderState(for: item.id, status: .rendering, progress: 0, message: L10n.string("works.highQuality.phase.preparing"))
    }

    func markHighQualityRenderCompleted(for item: WorkItem, url: URL) {
        completeHighQualityRender(for: item.id, url: url)
    }

    func markHighQualityRenderFailed(for item: WorkItem, error: Error) {
        failHighQualityRender(for: item.id, error: error)
    }

    func item(withID id: WorkItem.ID) -> WorkItem? {
        items.first { $0.id == id }
    }

    private func updateHighQualityRenderProgress(for id: WorkItem.ID, progress: Double, message: String?) {
        updateItem(id) { current in
            current.highQualityRenderProgress = min(max(progress, 0), 1)
            current.highQualityRenderMessage = message
        }
    }

    private func updateHighQualityRenderState(for id: WorkItem.ID, status: HighQualityRenderStatus, progress: Double? = nil, message: String? = nil) {
        updateItem(id) { current in
            current.highQualityRenderStatus = status
            if let progress {
                current.highQualityRenderProgress = min(max(progress, 0), 1)
            }
            current.highQualityRenderMessage = message
            if status != .ready {
                current.highQualityURL = status == .rendering || status == .paused ? current.highQualityURL : nil
            }
        }
    }

    private func completeHighQualityRender(for id: WorkItem.ID, url: URL) {
        if let job = highQualityRenderJobs[id] {
            endHighQualityBackgroundTask(job.backgroundTaskID)
            highQualityRenderJobs[id] = nil
        }
        updateItem(id) { current in
            current.highQualityURL = url
            current.highQualityRenderStatus = .ready
            current.highQualityRenderProgress = 1
            current.highQualityRenderMessage = L10n.string("works.highQuality.phase.completed")
        }
        statusMessage = L10n.string("works.highQuality.ready")
    }

    private func failHighQualityRender(for id: WorkItem.ID, error: Error) {
        if let job = highQualityRenderJobs[id] {
            endHighQualityBackgroundTask(job.backgroundTaskID)
            highQualityRenderJobs[id] = nil
        }
        updateItem(id) { current in
            current.highQualityRenderStatus = .failed
            current.highQualityRenderMessage = error.localizedDescription
        }
        statusMessage = L10n.string("error.works.highQualityFailed", error.localizedDescription)
    }

    private func pauseHighQualityRenderAfterInterruption(for id: WorkItem.ID) {
        if let job = highQualityRenderJobs[id] {
            endHighQualityBackgroundTask(job.backgroundTaskID)
            highQualityRenderJobs[id] = nil
        }
        updateHighQualityRenderState(for: id, status: .paused, progress: 0, message: L10n.string("works.highQuality.phase.paused"))
    }

    private func beginHighQualityBackgroundTask(for id: WorkItem.ID) -> UIBackgroundTaskIdentifier {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "DualCamHighQualityRender") { [weak self] in
            Task { @MainActor in
                guard let self, let job = self.highQualityRenderJobs[id] else { return }
                job.control.cancel()
                job.task.cancel()
                self.endHighQualityBackgroundTask(taskID)
                self.highQualityRenderJobs[id] = nil
                self.updateHighQualityRenderState(for: id, status: .paused, progress: 0, message: L10n.string("works.highQuality.phase.paused"))
            }
        }
        return taskID
    }

    private func endHighQualityBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
    }

    private func updateItem(_ id: WorkItem.ID, update: (inout WorkItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var current = items[index]
        update(&current)
        items[index] = current
        try? saveIndex()
    }

    private func deleteFiles(for item: WorkItem) throws {
        try removeFileIfPresent(at: item.assetURL)
        if let pairedVideoURL = item.pairedVideoURL {
            try removeFileIfPresent(at: pairedVideoURL)
        }
        if let frontOriginalURL = item.frontOriginalURL {
            try removeFileIfPresent(at: frontOriginalURL)
        }
        if let backOriginalURL = item.backOriginalURL {
            try removeFileIfPresent(at: backOriginalURL)
        }
        if let highQualityURL = item.highQualityURL {
            try removeFileIfPresent(at: highQualityURL)
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

    private func normalizeRenderStates(_ source: [WorkItem]) -> [WorkItem] {
        source.map { item in
            var current = item
            if current.highQualityRenderStatus == .rendering {
                current.highQualityRenderStatus = .paused
                current.highQualityRenderMessage = L10n.string("works.highQuality.phase.paused")
            }
            if let highQualityURL = current.highQualityURL {
                if fileManager.fileExists(atPath: highQualityURL.path) {
                    current.highQualityRenderStatus = .ready
                    current.highQualityRenderProgress = 1
                    current.highQualityRenderMessage = L10n.string("works.highQuality.phase.completed")
                } else if current.highQualityRenderStatus == .ready {
                    current.highQualityURL = nil
                    current.highQualityRenderStatus = .failed
                    current.highQualityRenderProgress = 0
                    current.highQualityRenderMessage = L10n.string("error.works.fileMissing")
                }
            }
            return current
        }
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
            frontOriginalURL: draft.frontOriginalURL,
            backOriginalURL: draft.backOriginalURL,
            highQualityURL: draft.highQualityURL,
            highQualityRenderStatus: draft.highQualityRenderStatus,
            highQualityRenderProgress: draft.highQualityRenderProgress,
            highQualityRenderMessage: draft.highQualityRenderMessage,
            layoutTimeline: draft.layoutTimeline,
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
