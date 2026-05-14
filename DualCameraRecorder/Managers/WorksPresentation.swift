import Foundation

enum WorksLibrary {
    static func filteredItems(_ items: [WorkItem], for filter: WorksFilter) -> [WorkItem] {
        switch filter {
        case .all:
            return items
        case .video:
            return items.filter { $0.kind == .video }
        case .photo:
            return items.filter { $0.kind == .photo }
        }
    }
}

extension WorkItem {
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

extension Date {
    var workDateText: String {
        WorkDateFormatter.shared.string(from: self)
    }
}

extension LayoutType {
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
