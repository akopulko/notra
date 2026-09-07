import Foundation
@testable import Notra
import Testing

@MainActor
/// Covers storage preference semantics and platform-independent root resolution.
struct NoteStorageLocationTests {
    @Test func locationsUseStableOrderAndRawValues() {
        #expect(NoteStorageLocation.allCases == [.iCloud, .localStore])
        #expect(NoteStorageLocation.iCloud.rawValue == "iCloud")
        #expect(NoteStorageLocation.localStore.rawValue == "localStore")
    }

    @Test func absentAndInvalidPreferencesRemainDistinctFromExplicitSelection() throws {
        let suiteName = "Notra.NoteStorageLocationTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let storage = NoteStoragePreferenceStorage(userDefaults: userDefaults)
        #expect(storage.storedRawValue == nil)
        #expect(storage.location == nil)

        userDefaults.set("unknown", forKey: NoteSettingKey.storageLocation)
        #expect(storage.storedRawValue == "unknown")
        #expect(storage.location == nil)

        storage.location = .localStore
        #expect(storage.storedRawValue == "localStore")
        #expect(storage.location == .localStore)
    }

    @Test func defaultsAndRootsRespectAvailabilityAndExistingFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let iCloudContainer = root.appendingPathComponent("iCloud", isDirectory: true)
        let localDocuments = root.appendingPathComponent("Documents", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let availableConfiguration = NoteStorageConfiguration(
            iCloudContainerIdentifier: "iCloud.test",
            iCloudURLProvider: { _ in iCloudContainer },
            localDocumentsURLProvider: { localDocuments }
        )
        let iCloudRoot = try availableConfiguration.rootURL(for: .iCloud)
        #expect(iCloudRoot == iCloudContainer.appendingPathComponent("Documents", isDirectory: true))
        #expect(availableConfiguration.isICloudAvailable)

        let localRoot = try availableConfiguration.rootURL(for: .localStore)
        #if os(iOS)
        #expect(localRoot == localDocuments)
        #else
        #expect(localRoot == localDocuments.appendingPathComponent("Notra", isDirectory: true))
        #endif

        let unavailableConfiguration = NoteStorageConfiguration(
            iCloudContainerIdentifier: "",
            iCloudURLProvider: { _ in iCloudContainer },
            localDocumentsURLProvider: { localDocuments }
        )
        let suiteName = "Notra.NoteStorageDefaultsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preference = NoteStoragePreferenceStorage(userDefaults: userDefaults)

        #expect(availableConfiguration.resolvedLocation(preference: preference) == .iCloud)
        #expect(unavailableConfiguration.resolvedLocation(preference: preference) == .localStore)
    }
}
