import AVKit
import Combine
import Photos
import SwiftUI
import UIKit

struct WorksView: View {
    @ObservedObject var manager: WorksManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: WorksFilter = .all
    @State private var isSelecting = false
    @State private var selectedIDs: Set<WorkItem.ID> = []
    @State private var isDeleteConfirmationPresented = false
    @State private var browsingItemID: WorkItem.ID?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var filteredItems: [WorkItem] {
        manager.filteredItems(for: selectedFilter)
    }

    private var selectedCount: Int {
        selectedIDs.count
    }

    private var canShowSelectionControls: Bool {
        manager.readError == nil && !manager.items.isEmpty && browsingItemID == nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WorksDesign.background.ignoresSafeArea()

            if let browsingItemID {
                WorkBrowserView(
                    items: filteredItems,
                    initialItemID: browsingItemID,
                    manager: manager,
                    onClose: { self.browsingItemID = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                libraryView
                    .transition(.opacity)
            }
        }
        .onAppear { manager.reload() }
        .alert("works.message.title", isPresented: statusMessageBinding) {
            Button("works.action.ok", role: .cancel) {}
        } message: {
            Text(manager.statusMessage ?? "")
        }
        .alert("works.delete.confirm.title", isPresented: $isDeleteConfirmationPresented) {
            Button("works.selection.cancel", role: .cancel) {}
            Button("works.delete.action", role: .destructive) {
                performDeleteSelection()
            }
        } message: {
            Text(L10n.string("works.delete.confirm.message", selectedCount))
        }
    }

    private var libraryView: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 18) {
                header
                filterRow
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, isSelecting ? 92 : 18)

            if isSelecting {
                selectionActionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("works.back.camera")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(WorksDesign.accent)
                }

                Spacer()

                Text("works.storage.local")
                    .font(.system(size: 10, weight: .black))
                    .textCase(.uppercase)
                    .foregroundColor(WorksDesign.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(WorksDesign.accent.opacity(0.12)))

                if canShowSelectionControls {
                    Button(action: isSelecting ? exitSelectionMode : enterSelectionMode) {
                        Text(isSelecting ? "works.selection.cancel" : "works.selection.select")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(isSelecting ? .white.opacity(0.72) : .black)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(isSelecting ? Color.white.opacity(0.12) : WorksDesign.accent))
                    }
                }
            }
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("works.title")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text("works.subtitle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WorksDesign.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(WorksFilter.allCases) { filter in
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedFilter = filter
                        selectedIDs.removeAll()
                    }
                }) {
                    Text(filter.titleKey)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(selectedFilter == filter ? .black : .white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(selectedFilter == filter ? Color.white : Color.white.opacity(0.08)))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let readError = manager.readError {
            WorksStateView(
                icon: "exclamationmark.triangle.fill",
                titleKey: "works.error.title",
                message: readError,
                actionTitleKey: "works.action.retry",
                action: manager.reload
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if manager.items.isEmpty {
            WorksStateView(
                icon: "photo.on.rectangle.angled",
                titleKey: "works.empty.title",
                messageKey: "works.empty.message",
                actionTitleKey: "works.back.camera",
                action: { dismiss() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredItems.isEmpty {
            WorksStateView(
                icon: "line.3.horizontal.decrease.circle",
                titleKey: "works.emptyFilter.title",
                messageKey: "works.emptyFilter.message",
                actionTitleKey: "works.filter.all",
                action: {
                    selectedFilter = .all
                    selectedIDs.removeAll()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredItems) { item in
                        if isSelecting {
                            Button(action: { toggleSelection(for: item) }) {
                                WorkCard(
                                    item: item,
                                    isSelected: selectedIDs.contains(item.id),
                                    isSelecting: true
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    browsingItemID = item.id
                                }
                            }) {
                                WorkCard(item: item)
                                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, isSelecting ? 116 : 24)
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("works.selection.count", selectedCount))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.78))

            Spacer()

            Button(action: confirmDeleteSelection) {
                Text("works.delete.action")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(selectedIDs.isEmpty ? .white.opacity(0.28) : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(selectedIDs.isEmpty ? Color.white.opacity(0.06) : Color.red.opacity(0.82)))
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func enterSelectionMode() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSelecting = true
            selectedIDs.removeAll()
        }
    }

    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSelecting = false
            selectedIDs.removeAll()
        }
    }

    private func toggleSelection(for item: WorkItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func confirmDeleteSelection() {
        guard !selectedIDs.isEmpty else { return }
        isDeleteConfirmationPresented = true
    }

    private func performDeleteSelection() {
        let ids = selectedIDs
        manager.deleteItems(withIDs: ids)
        exitSelectionMode()
    }

    private var statusMessageBinding: Binding<Bool> {
        Binding(
            get: { manager.statusMessage != nil },
            set: { isPresented in
                if !isPresented { manager.statusMessage = nil }
            }
        )
    }
}

struct WorksEntryButton: View {
    let latestWork: WorkItem?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.12))

                if let thumbnailURL = latestWork?.thumbnailURL,
                   let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    EmptyAlbumGlyph()
                }
            }
            .frame(width: 54, height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .overlay(alignment: .topTrailing) {
                if latestWork?.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundColor(.black)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(WorksDesign.accent))
                        .offset(x: 4, y: -4)
                }
            }
        }
    }
}

private struct EmptyAlbumGlyph: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.14, green: 0.18, blue: 0.24), Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.34, green: 0.24, blue: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )
                .padding(7)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(WorksDesign.accent)
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.38), lineWidth: 2)
                )
                .padding(9)
        }
    }
}

private struct WorkCard: View {
    let item: WorkItem
    var isSelected = false
    var isSelecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                WorkThumbnail(url: item.thumbnailURL)
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                mediaBadge
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    selectionBadge
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(item.localizedLayoutTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(WorksDesign.accent.opacity(0.86))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.createdAt.workDateText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.workDurationText)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(WorksDesign.mutedText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? WorksDesign.accent : Color.white.opacity(0.09), lineWidth: isSelected ? 1.4 : 0.8)
        )
    }

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? WorksDesign.accent : Color.black.opacity(0.52))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white.opacity(isSelected ? 0 : 0.55), lineWidth: 1.1))

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.black)
            }
        }
    }

    private var mediaBadge: some View {
        ZStack {
            Circle()
                .fill(item.kind == .video ? Color.black.opacity(0.48) : WorksDesign.accent.opacity(0.82))
                .frame(width: 34, height: 34)

            Image(systemName: item.kind == .video ? "play.fill" : "camera.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(item.kind == .video ? WorksDesign.accent : .black)
        }
    }
}

private struct WorkBrowserView: View {
    let items: [WorkItem]
    let initialItemID: WorkItem.ID
    @ObservedObject var manager: WorksManager
    let onClose: () -> Void
    @State private var currentItemID: WorkItem.ID

    init(items: [WorkItem], initialItemID: WorkItem.ID, manager: WorksManager, onClose: @escaping () -> Void) {
        self.items = items
        self.initialItemID = initialItemID
        self.manager = manager
        self.onClose = onClose
        _currentItemID = State(initialValue: initialItemID)
    }

    private var currentIndex: Int? {
        items.firstIndex { $0.id == currentItemID }
    }

    var body: some View {
        VStack(spacing: 0) {
            browserHeader

            if items.isEmpty {
                WorksStateView(
                    icon: "photo.on.rectangle.angled",
                    titleKey: "works.empty.title",
                    messageKey: "works.empty.message",
                    actionTitleKey: "workDetail.back.works",
                    action: onClose
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $currentItemID) {
                    ForEach(items) { item in
                        WorkDetailPage(
                            item: item,
                            manager: manager,
                            isActive: currentItemID == item.id
                        )
                        .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(WorksDesign.background.ignoresSafeArea())
        .onAppear(perform: repairCurrentItemIfNeeded)
        .onChange(of: items) { _ in repairCurrentItemIfNeeded() }
    }

    private var browserHeader: some View {
        HStack {
            Button(action: onClose) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .black))
                    Text("workDetail.back.works")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(WorksDesign.accent)
            }

            Spacer()

            Text("workDetail.title")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Text(pageCountText)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(WorksDesign.accent)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(WorksDesign.background.opacity(0.96))
    }

    private var pageCountText: String {
        guard let currentIndex else { return "0 / 0" }
        return "\(currentIndex + 1) / \(items.count)"
    }

    private func repairCurrentItemIfNeeded() {
        guard !items.isEmpty else { return }
        if !items.contains(where: { $0.id == currentItemID }) {
            currentItemID = items[0].id
        }
    }
}

private struct WorkDetailPage: View {
    let item: WorkItem
    @ObservedObject var manager: WorksManager
    let isActive: Bool
    @State private var isSharing = false
    @State private var isSavingToPhotos = false
    @State private var detailMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WorksDesign.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    preview
                        .frame(maxWidth: .infinity)
                        .frame(height: detailPreviewHeight(for: geometry.size))
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Text(metadataText)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(WorksDesign.mutedText)

                        Text("workDetail.body")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(WorksDesign.mutedText)
                            .fixedSize(horizontal: false, vertical: true)

                        actionRow
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            ActivityView(activityItems: [item.assetURL])
        }
        .alert("works.message.title", isPresented: detailMessageBinding) {
            Button("works.action.ok", role: .cancel) {}
        } message: {
            Text(detailMessage ?? "")
        }
    }

    private var detailMessageBinding: Binding<Bool> {
        Binding(
            get: { detailMessage != nil },
            set: { isPresented in
                if !isPresented { detailMessage = nil }
            }
        )
    }

    private var preview: some View {
        WorkPreview(item: item, isActive: isActive)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 12)
    }

    private func detailPreviewHeight(for size: CGSize) -> CGFloat {
        min(max(size.height - 250, size.height * 0.70), size.height - 190)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            DetailActionButton(titleKey: "workDetail.share", icon: "square.and.arrow.up") {
                isSharing = true
            }

            DetailActionButton(titleKey: "workDetail.edit", icon: "slider.horizontal.3", isEnabled: false) {}

            DetailActionButton(titleKey: "workDetail.save", icon: "checkmark.circle", isEnabled: !isSavingToPhotos) {
                Task { await saveWorkToPhotoLibrary() }
            }
        }
        .padding(.top, 4)
    }

    private var metadataText: String {
        L10n.string(
            "workDetail.metadata",
            item.localizedLayoutTitle,
            item.cameraMetadata.resolution,
            item.cameraMetadata.frameRate,
            item.workDurationText
        )
    }

    @MainActor
    private func saveWorkToPhotoLibrary() async {
        guard !isSavingToPhotos else { return }
        guard FileManager.default.fileExists(atPath: item.assetURL.path) else {
            detailMessage = L10n.string("error.works.fileMissing")
            return
        }
        if let pairedVideoURL = item.pairedVideoURL,
           !FileManager.default.fileExists(atPath: pairedVideoURL.path) {
            detailMessage = L10n.string("error.works.fileMissing")
            return
        }

        isSavingToPhotos = true
        defer { isSavingToPhotos = false }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status = currentStatus == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            : currentStatus
        guard status == .authorized || status == .limited else {
            detailMessage = L10n.string("error.works.photoLibraryDenied")
            return
        }

        let photoImage = item.kind == .photo && item.pairedVideoURL == nil
            ? UIImage(contentsOfFile: item.assetURL.path)
            : nil
        if item.kind == .photo && item.pairedVideoURL == nil && photoImage == nil {
            detailMessage = L10n.string("error.works.fileMissing")
            return
        }

        do {
            try await performPhotoLibraryChanges {
                switch item.kind {
                case .video:
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: item.assetURL)
                case .photo:
                    if let pairedVideoURL = item.pairedVideoURL {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, fileURL: item.assetURL, options: nil)
                        request.addResource(with: .pairedVideo, fileURL: pairedVideoURL, options: nil)
                    } else if let photoImage {
                        PHAssetChangeRequest.creationRequestForAsset(from: photoImage)
                    }
                }
            }
            detailMessage = L10n.string("works.save.photosSuccess")
        } catch {
            detailMessage = L10n.string("error.works.exportFailed", error.localizedDescription)
        }
    }

    private func performPhotoLibraryChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "DualCamApp", code: -1))
                }
            }
        }
    }
}

private struct WorkPreview: View {
    let item: WorkItem
    let isActive: Bool

    var body: some View {
        if item.kind == .video {
            InlineVideoPreview(item: item, isActive: isActive)
        } else {
            WorkThumbnail(url: item.thumbnailURL ?? item.assetURL)
        }
    }
}

@MainActor
private final class InlineVideoPlayerModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var isPlaying = false

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    deinit {
        player.pause()
    }
}

private struct InlineVideoPreview: View {
    let item: WorkItem
    let isActive: Bool
    @StateObject private var playerModel: InlineVideoPlayerModel

    init(item: WorkItem, isActive: Bool) {
        self.item = item
        self.isActive = isActive
        _playerModel = StateObject(wrappedValue: InlineVideoPlayerModel(url: item.assetURL))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if FileManager.default.fileExists(atPath: item.assetURL.path) {
                VideoPlayer(player: playerModel.player)
                    .background(Color.black)
            } else {
                WorkThumbnail(url: item.thumbnailURL)
            }

            Button(action: playerModel.togglePlayback) {
                Image(systemName: playerModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(WorksDesign.accent))
                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 6)
            }
            .padding(18)
            .disabled(!FileManager.default.fileExists(atPath: item.assetURL.path))
            .opacity(FileManager.default.fileExists(atPath: item.assetURL.path) ? 1 : 0.45)
        }
        .onChange(of: isActive) { active in
            if !active {
                playerModel.pause()
            }
        }
        .onDisappear {
            playerModel.pause()
        }
    }
}

private struct DetailActionButton: View {
    let titleKey: LocalizedStringKey
    let icon: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(titleKey)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.82) : .white.opacity(0.32))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 0.09 : 0.045))
            )
        }
        .disabled(!isEnabled)
    }
}

private struct WorksStateView: View {
    let icon: String
    let titleKey: LocalizedStringKey
    var message: String?
    var messageKey: LocalizedStringKey?
    let actionTitleKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(WorksDesign.accent)

            VStack(spacing: 8) {
                Text(titleKey)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                if let message {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(WorksDesign.mutedText)
                        .multilineTextAlignment(.center)
                } else if let messageKey {
                    Text(messageKey)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(WorksDesign.mutedText)
                        .multilineTextAlignment(.center)
                }
            }

            Button(action: action) {
                Text(actionTitleKey)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(WorksDesign.accent))
            }
        }
        .padding(24)
    }
}

private struct WorkThumbnail: View {
    let url: URL?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.14, blue: 0.19), Color.black, Color(red: 0.32, green: 0.24, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url,
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white.opacity(0.48))
            }
        }
        .clipped()
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum WorksDesign {
    static let background = Color(red: 0.02, green: 0.024, blue: 0.032)
    static let accent = Color(red: 0.84, green: 1.0, blue: 0.30)
    static let mutedText = Color.white.opacity(0.56)
}
