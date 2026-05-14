import AVKit
import SwiftUI
import UIKit

struct WorksView: View {
    @ObservedObject var manager: WorksManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: WorksFilter = .all

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var filteredItems: [WorkItem] {
        manager.filteredItems(for: selectedFilter)
    }

    var body: some View {
        NavigationView {
            ZStack {
                WorksDesign.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    header
                    filterRow
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .navigationBarHidden(true)
            .onAppear { manager.reload() }
            .alert("works.message.title", isPresented: statusMessageBinding) {
                Button("works.action.ok", role: .cancel) {}
            } message: {
                Text(manager.statusMessage ?? "")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
                action: { selectedFilter = .all }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredItems) { item in
                        NavigationLink(destination: WorkDetailView(item: item, manager: manager)) {
                            WorkCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                WorkThumbnail(url: item.thumbnailURL)
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                mediaBadge
                    .padding(10)
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
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
        )
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

private struct WorkDetailView: View {
    let item: WorkItem
    @ObservedObject var manager: WorksManager
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false
    @State private var isPlayingVideo = false
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
        .navigationTitle(Text("workDetail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .black))
                        Text("workDetail.back.works")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(WorksDesign.accent)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { detailMessage = L10n.string("workDetail.more.placeholder") }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(WorksDesign.accent)
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            ActivityView(activityItems: [item.assetURL])
        }
        .sheet(isPresented: $isPlayingVideo) {
            VideoPlayer(player: AVPlayer(url: item.assetURL))
                .ignoresSafeArea()
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
        Button(action: {
            if item.kind == .video { isPlayingVideo = true }
        }) {
            ZStack {
                WorkThumbnail(url: item.thumbnailURL ?? item.assetURL)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                if item.kind == .video {
                    Circle()
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 68, height: 68)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(WorksDesign.accent)
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .buttonStyle(.plain)
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

            DetailActionButton(titleKey: "workDetail.save", icon: "checkmark.circle") {
                detailMessage = FileManager.default.fileExists(atPath: item.assetURL.path)
                    ? L10n.string("works.save.localSuccess")
                    : L10n.string("error.works.fileMissing")
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

private extension WorkItem {
    var localizedLayoutTitle: String {
        LayoutType(rawValue: layout)?.localizedTitle ?? layout
    }

    var workDurationText: String {
        if kind == .photo {
            return pairedVideoURL == nil ? L10n.string("works.duration.photo") : L10n.string("works.duration.livePhoto")
        }

        let totalSeconds = max(0, Int(duration ?? 0))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private extension Date {
    var workDateText: String {
        WorkDateFormatter.shared.string(from: self)
    }
}

private extension LayoutType {
    var localizedTitle: String {
        switch self {
        case .splitVertical: return L10n.string("layout.splitVertical.title")
        case .splitHorizontal: return L10n.string("layout.splitHorizontal.title")
        case .pictureInPicture: return L10n.string("layout.pictureInPicture.title")
        case .circleReaction: return L10n.string("layout.circleReaction.title")
        case .directorStack: return L10n.string("layout.directorStack.title")
        case .diagonalCut: return L10n.string("layout.diagonalCut.title")
        }
    }
}

private enum WorkDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
