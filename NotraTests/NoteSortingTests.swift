import Foundation
@testable import Notra
import Testing

struct NoteSortingTests {
    @Test func defaultSortPreferenceUsesDateEditedLatestFirst() {
        #expect(NoteSortPreference.default == NoteSortPreference(field: .dateEdited, direction: .latestFirst))
    }

    @Test func sortsByDateEdited() {
        let notes = makeNotes()

        #expect(
            NoteSortPreference(field: .dateEdited, direction: .latestFirst)
                .sorted(notes)
                .map(\.previewText) == ["Beta", "Gamma", "Alpha"]
        )
        #expect(
            NoteSortPreference(field: .dateEdited, direction: .oldestFirst)
                .sorted(notes)
                .map(\.previewText) == ["Alpha", "Gamma", "Beta"]
        )
    }

    @Test func sortsByDateCreated() {
        let notes = makeNotes()

        #expect(
            NoteSortPreference(field: .dateCreated, direction: .latestFirst)
                .sorted(notes)
                .map(\.previewText) == ["Gamma", "Alpha", "Beta"]
        )
        #expect(
            NoteSortPreference(field: .dateCreated, direction: .oldestFirst)
                .sorted(notes)
                .map(\.previewText) == ["Beta", "Alpha", "Gamma"]
        )
    }

    @Test func sortPreferencePersists() throws {
        let suiteName = "Notra.NoteSortingTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let storage = NoteSortPreferenceStorage(userDefaults: userDefaults)
        #expect(storage.preference == .default)

        storage.preference = NoteSortPreference(field: .dateCreated, direction: .oldestFirst)

        let reloadedStorage = NoteSortPreferenceStorage(userDefaults: userDefaults)
        #expect(reloadedStorage.preference == NoteSortPreference(field: .dateCreated, direction: .oldestFirst))
    }

    @Test func staleTitleSortPreferenceFallsBackToDefaultField() throws {
        let suiteName = "Notra.NoteSortingTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set("title", forKey: "notes.sort.field")
        userDefaults.set(NoteSortDirection.oldestFirst.rawValue, forKey: "notes.sort.direction")

        let storage = NoteSortPreferenceStorage(userDefaults: userDefaults)

        #expect(storage.preference == NoteSortPreference(field: .dateEdited, direction: .oldestFirst))
    }

    private func makeNotes() -> [NoteSummary] {
        [
            makeNote(title: "Alpha", createdAt: 20, modifiedAt: 10),
            makeNote(title: "Beta", createdAt: 10, modifiedAt: 30),
            makeNote(title: "Gamma", createdAt: 30, modifiedAt: 20)
        ]
    }

    private func makeNote(title: String, createdAt: TimeInterval, modifiedAt: TimeInterval) -> NoteSummary {
        NoteSummary(
            url: URL(fileURLWithPath: "/tmp/\(title).textbundle"),
            previewText: title,
            createdAt: Date(timeIntervalSince1970: createdAt),
            modifiedAt: Date(timeIntervalSince1970: modifiedAt)
        )
    }
}
