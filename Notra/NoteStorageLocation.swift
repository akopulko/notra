import Foundation

/// Selects the independent directory whose TextBundles appear in the notes list.
enum NoteStorageLocation: String, CaseIterable, Identifiable, Sendable {
    case iCloud
    case localStore

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .iCloud:
            "iCloud"
        case .localStore:
            "Local Store"
        }
    }
}

/// Reads and writes the user's explicit note-storage choice.
struct NoteStoragePreferenceStorage {
    static let standard = NoteStoragePreferenceStorage(userDefaults: .standard)

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// The raw persisted value, including an invalid value, for default resolution.
    var storedRawValue: String? {
        userDefaults.string(forKey: NoteSettingKey.storageLocation)
    }

    /// The explicit selection when the persisted value is valid; absent and invalid values are nil.
    var location: NoteStorageLocation? {
        get {
            storedRawValue.flatMap(NoteStorageLocation.init(rawValue:))
        }
        nonmutating set {
            userDefaults.set(newValue?.rawValue, forKey: NoteSettingKey.storageLocation)
        }
    }
}

/// Resolves note roots and checks whether the configured iCloud container is usable.
struct NoteStorageConfiguration {
    private let fileManager: FileManager
    private let iCloudContainerIdentifier: String?
    private let iCloudURLProvider: (String) -> URL?
    private let localDocumentsURLProvider: () -> URL?

    init(
        fileManager: FileManager = .default,
        iCloudContainerIdentifier: String? = nil,
        iCloudURLProvider: ((String) -> URL?)? = nil,
        localDocumentsURLProvider: (() -> URL?)? = nil
    ) {
        self.fileManager = fileManager
        self.iCloudContainerIdentifier = iCloudContainerIdentifier
            ?? Bundle.main.object(forInfoDictionaryKey: "NotraICloudContainerIdentifier") as? String
        self.iCloudURLProvider = iCloudURLProvider ?? { identifier in
            fileManager.url(forUbiquityContainerIdentifier: identifier)
        }
        self.localDocumentsURLProvider = localDocumentsURLProvider ?? {
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        }
    }

    /// Returns the prepared root for a location, preserving the existing platform folders.
    func rootURL(for location: NoteStorageLocation) throws -> URL {
        let rootURL: URL
        switch location {
        case .iCloud:
            guard let identifier = validContainerIdentifier,
                  let containerURL = iCloudURLProvider(identifier)
            else {
                throw NoteRepositoryError.storageUnavailable
            }
            rootURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        case .localStore:
            guard let documentsURL = localDocumentsURLProvider() else {
                throw NoteRepositoryError.storageUnavailable
            }
            #if os(iOS)
            rootURL = documentsURL
            #else
            rootURL = documentsURL.appendingPathComponent("Notra", isDirectory: true)
            #endif
        }

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            throw NoteRepositoryError.storageUnavailable
        }
        return rootURL
    }

    /// iCloud is available only when its identifier, ubiquity URL, and root preparation all succeed.
    var isICloudAvailable: Bool {
        (try? rootURL(for: .iCloud)) != nil
    }

    /// Resolves an absent or invalid preference using the availability-aware default.
    func resolvedLocation(preference: NoteStoragePreferenceStorage) -> NoteStorageLocation {
        preference.location ?? (isICloudAvailable ? .iCloud : .localStore)
    }

    private var validContainerIdentifier: String? {
        guard let iCloudContainerIdentifier else {
            return nil
        }

        let trimmed = iCloudContainerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension TextBundleNoteRepository {
    /// Chooses the persisted location when possible, otherwise uses the availability-aware default.
    static func production(
        fileManager: FileManager = .default,
        storagePreference: NoteStoragePreferenceStorage = .standard
    ) -> TextBundleNoteRepository {
        let configuration = NoteStorageConfiguration(fileManager: fileManager)
        let preferredLocation = configuration.resolvedLocation(preference: storagePreference)

        do {
            let repository = try repository(for: preferredLocation, configuration: configuration)
            AppLog.info("Using \(repository.storageDescription) note storage")
            return repository
        } catch {
            AppLog.error("Failed to prepare \(preferredLocation.title) note storage: \(error.localizedDescription)")
        }

        do {
            let repository = try repository(for: .localStore, configuration: configuration)
            AppLog.warning("Using Local Store after preferred note storage was unavailable")
            return repository
        } catch {
            AppLog.error("Failed to prepare Local Store: \(error.localizedDescription)")
            return TextBundleNoteRepository(rootURL: fileManager.temporaryDirectory)
        }
    }

    /// Returns whether the configured iCloud container can be selected on this device.
    static func isICloudAvailable(fileManager: FileManager = .default) -> Bool {
        NoteStorageConfiguration(fileManager: fileManager).isICloudAvailable
    }

    /// Prepares a repository for a location before it is exposed to the note store.
    static func repository(
        for location: NoteStorageLocation,
        fileManager: FileManager = .default
    ) throws -> TextBundleNoteRepository {
        try repository(
            for: location,
            configuration: NoteStorageConfiguration(fileManager: fileManager)
        )
    }

    /// Injectable repository construction used by NotesStore and focused tests.
    static func repository(
        for location: NoteStorageLocation,
        configuration: NoteStorageConfiguration
    ) throws -> TextBundleNoteRepository {
        let rootURL = try configuration.rootURL(for: location)
        return TextBundleNoteRepository(rootURL: rootURL, isUsingICloud: location == .iCloud)
    }
}
