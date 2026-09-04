import Foundation

/// The note property used to order the sidebar.
enum NoteSortField: String, CaseIterable {
    case dateEdited
    case dateCreated

    var menuTitle: String {
        switch self {
        case .dateEdited:
            "Date Edited"
        case .dateCreated:
            "Date Created"
        }
    }
}

/// Whether sorted notes place newer or older values first.
enum NoteSortDirection: String, CaseIterable {
    case latestFirst
    case oldestFirst

    var menuTitle: String {
        switch self {
        case .latestFirst:
            "Latest First"
        case .oldestFirst:
            "Oldest First"
        }
    }
}

/// A serializable sort choice that can order summaries without touching storage.
struct NoteSortPreference: Equatable {
    /// Default ordering keeps recently edited notes at the top of the sidebar.
    static let `default` = NoteSortPreference(field: .dateEdited, direction: .latestFirst)

    /// Property whose values are compared when ordering summaries.
    var field: NoteSortField
    /// Direction applied to the selected field.
    var direction: NoteSortDirection

    /// Returns a deterministic order, using preview text and URL as tie breakers.
    func sorted(_ notes: [NoteSummary]) -> [NoteSummary] {
        let pinnedNotes = NotePinning.sortedPinnedNotes(in: notes)
        let unpinnedNotes = notes.filter { !$0.isPinned }.sorted { lhs, rhs in
            let result: Bool? = switch field {
            case .dateEdited:
                compare(lhs.modifiedAt, rhs.modifiedAt, direction: direction)
                    ?? comparePreviews(lhs, rhs)
            case .dateCreated:
                compare(lhs.createdAt, rhs.createdAt, direction: direction)
                    ?? comparePreviews(lhs, rhs)
            }

            return result ?? (lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending)
        }

        return pinnedNotes + unpinnedNotes
    }

    private func compare(_ lhs: Date, _ rhs: Date, direction: NoteSortDirection) -> Bool? {
        guard lhs != rhs else {
            return nil
        }

        switch direction {
        case .latestFirst:
            return lhs > rhs
        case .oldestFirst:
            return lhs < rhs
        }
    }

    private func comparePreviews(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool? {
        switch lhs.previewText.localizedStandardCompare(rhs.previewText) {
        case .orderedAscending:
            true
        case .orderedDescending:
            false
        case .orderedSame:
            nil
        }
    }
}

/// Groups pinned notes ahead of regular notes while retaining a stable newest-pin-first order.
enum NotePinning {
    /// Limits pinning so the sidebar remains a compact, useful shortcut list.
    static let maximumPinnedNotes = 5

    /// Returns pinned notes ordered by the most recently recorded pin timestamp.
    static func sortedPinnedNotes(in notes: [NoteSummary]) -> [NoteSummary] {
        notes.filter(\.isPinned).sorted { lhs, rhs in
            guard let lhsPinnedAt = lhs.pinnedAt, let rhsPinnedAt = rhs.pinnedAt else {
                return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
            }

            if lhsPinnedAt != rhsPinnedAt {
                return lhsPinnedAt > rhsPinnedAt
            }

            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }

    /// Moves pinned search results ahead of unpinned results without changing search relevance.
    static func pinnedFirst(_ notes: [NoteSummary]) -> [NoteSummary] {
        sortedPinnedNotes(in: notes) + notes.filter { !$0.isPinned }
    }
}

/// Reads and writes the sidebar sort choice using a dedicated UserDefaults suite/key pair.
struct NoteSortPreferenceStorage {
    private enum Key {
        static let field = "notes.sort.field"
        static let direction = "notes.sort.direction"
    }

    static let standard = NoteSortPreferenceStorage(userDefaults: .standard)

    /// UserDefaults store supplied by the app or an isolated test suite.
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// Reads a tolerant preference and writes both raw enum values as one logical choice.
    var preference: NoteSortPreference {
        get {
            NoteSortPreference(
                field: NoteSortField(rawValue: userDefaults.string(forKey: Key.field) ?? "")
                    ?? NoteSortPreference.default.field,
                direction: NoteSortDirection(rawValue: userDefaults.string(forKey: Key.direction) ?? "")
                    ?? NoteSortPreference.default.direction
            )
        }
        nonmutating set {
            userDefaults.set(newValue.field.rawValue, forKey: Key.field)
            userDefaults.set(newValue.direction.rawValue, forKey: Key.direction)
        }
    }
}
