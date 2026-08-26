import Foundation

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

struct NoteSortPreference: Equatable {
    static let `default` = NoteSortPreference(field: .dateEdited, direction: .latestFirst)

    var field: NoteSortField
    var direction: NoteSortDirection

    func sorted(_ notes: [NoteSummary]) -> [NoteSummary] {
        notes.sorted { lhs, rhs in
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

struct NoteSortPreferenceStorage {
    private enum Key {
        static let field = "notes.sort.field"
        static let direction = "notes.sort.direction"
    }

    static let standard = NoteSortPreferenceStorage(userDefaults: .standard)

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

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
