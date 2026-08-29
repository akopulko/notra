import Foundation
import OSLog
import SQLite3

/// One ranked search hit returned by the SQLite full-text index.
struct NoteSearchResult: Equatable, Identifiable, Sendable {
    let noteID: URL
    let rank: Double

    var id: URL {
        noteID
    }
}

/// A page of search results plus the count needed to decide whether to load more.
struct NoteSearchPage: Equatable, Sendable {
    let results: [NoteSearchResult]
    let hasMore: Bool
}

/// Describes index readiness and synchronization progress shown by the sidebar.
enum NoteSearchStatus: Equatable, Sendable {
    case notReady
    case indexing
    case ready
    case unavailable
}

/// Errors that can be surfaced when the local search index cannot be used.
enum NoteSearchIndexError: LocalizedError, Equatable, Sendable {
    case database(String)
    case notReady
    case invalidDatabaseLocation

    var errorDescription: String? {
        switch self {
        case let .database(message):
            "The note search index could not be opened: \(message)"
        case .notReady:
            "The note search index is still being prepared."
        case .invalidDatabaseLocation:
            "The note search index location is unavailable."
        }
    }
}

/// Owns the SQLite full-text index so database access stays serialized off the main actor.
actor SQLiteNoteSearchIndex {
    /// Cache location is deliberately separate from note storage; the index can always be rebuilt.
    private nonisolated static let databaseDirectoryName = "Notra"
    private nonisolated static let databaseFilename = "NoteSearch.sqlite"
    private nonisolated static let schemaVersion = 2
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.notra.Notra",
        category: "SearchIndex"
    )

    private let databaseURL: URL
    /// SQLite handle owned exclusively by this actor.
    private var database: OpaquePointer?
    /// Prevents queries from running before schema setup and initial synchronization finish.
    private var isReady = false

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    /// Places the rebuildable database in the platform cache directory.
    static func production(fileManager: FileManager = .default) -> SQLiteNoteSearchIndex {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = cachesURL.appendingPathComponent(databaseDirectoryName, isDirectory: true)
        return SQLiteNoteSearchIndex(
            databaseURL: directoryURL.appendingPathComponent(databaseFilename)
        )
    }

    /// Upserts changed notes and removes database rows for bundles no longer present on disk.
    func synchronize(noteIDs: [URL]) async throws {
        log("Synchronizing index; noteCount=\(noteIDs.count)")
        try ensureDatabase()
        let normalizedIDs = noteIDs.map(Self.normalizedID)
        var indexedCount = 0
        var skippedCount = 0
        var removedCount = 0

        try withTransaction {
            let existingIDs = try metadataIDs()
            let currentIDs = Set(normalizedIDs)

            for noteID in normalizedIDs {
                let source = URL(fileURLWithPath: noteID)
                let tags = sourceTags(for: source)
                let metadata = try sourceMetadata(for: source, tags: tags)
                if try metadataMatches(noteID: noteID, metadata: metadata) {
                    skippedCount += 1
                    continue
                }

                let markdownURL = source.appendingPathComponent(TextBundleNoteRepository.textFilename)
                do {
                    let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
                    try upsert(noteID: noteID, markdown: markdown, tags: tags, metadata: metadata)
                    indexedCount += 1
                } catch {
                    logError(
                        "Failed to index note; note=\(source.lastPathComponent); "
                            + "error=\(error.localizedDescription)"
                    )
                    throw error
                }
            }

            for staleID in existingIDs.subtracting(currentIDs) {
                try delete(noteID: staleID)
                removedCount += 1
            }
        }

        isReady = true
        log(
            "Index synchronization completed; indexed=\(indexedCount); "
                + "skipped=\(skippedCount); removed=\(removedCount); ready=true"
        )
    }

    /// Drops all database files before rebuilding from the current note list.
    func rebuild(noteIDs: [URL]) async throws {
        log("Rebuilding index; noteCount=\(noteIDs.count)")
        closeDatabase()
        try removeDatabaseFiles()
        isReady = false
        try await synchronize(noteIDs: noteIDs)
    }

    /// Upserts one changed note immediately after an editor or metadata mutation.
    func index(noteID: URL, markdown: String, tags: [NoteTag]) async throws {
        log("Indexing changed note; note=\(noteID.lastPathComponent); markdownBytes=\(markdown.utf8.count)")
        try ensureDatabase()
        let normalizedID = Self.normalizedID(noteID)
        let metadata = try sourceMetadata(for: noteID, tags: tags)

        try withTransaction {
            try upsert(noteID: normalizedID, markdown: markdown, tags: tags, metadata: metadata)
        }
        isReady = true
        log("Changed note indexed; note=\(noteID.lastPathComponent)")
    }

    /// Removes a deleted note without touching the source TextBundle.
    func remove(noteID: URL) async throws {
        log("Removing note from index; note=\(noteID.lastPathComponent)")
        try ensureDatabase()
        let normalizedID = Self.normalizedID(noteID)

        try withTransaction {
            try delete(noteID: normalizedID)
        }
    }

    /// Executes a ranked FTS query and returns a bounded page for sidebar pagination.
    func search(_ query: String, limit: Int, offset: Int) async throws -> NoteSearchPage {
        guard isReady else {
            logError("Search rejected because index is not ready; queryLength=\(query.count)")
            throw NoteSearchIndexError.notReady
        }

        let resultLimit = max(1, min(limit, 500))
        let resultOffset = max(0, offset)
        let matchQuery = Self.ftsQuery(from: query)
        guard !matchQuery.isEmpty else {
            log("Search ignored empty query; queryLength=\(query.count)")
            return NoteSearchPage(results: [], hasMore: false)
        }

        log(
            "Executing search; queryLength=\(query.count); "
                + "limit=\(resultLimit); offset=\(resultOffset)"
        )

        let statement = try prepare(
            """
            SELECT note_id, bm25(note_search)
            FROM note_search
            WHERE note_search MATCH ?
            ORDER BY bm25(note_search) ASC, note_id ASC
            LIMIT ? OFFSET ?
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(matchQuery, to: 1, in: statement)
        try bind(Int32(resultLimit + 1), to: 2, in: statement)
        try bind(Int32(resultOffset), to: 3, in: statement)

        var results: [NoteSearchResult] = []
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                guard let idPointer = sqlite3_column_text(statement, 0) else {
                    continue
                }
                let id = String(cString: idPointer)
                results.append(
                    NoteSearchResult(
                        noteID: URL(fileURLWithPath: id).standardizedFileURL,
                        rank: sqlite3_column_double(statement, 1)
                    )
                )
            case SQLITE_DONE:
                let hasMore = results.count > resultLimit
                if hasMore {
                    results.removeLast()
                }
                log("Search completed; resultCount=\(results.count); hasMore=\(hasMore)")
                return NoteSearchPage(results: results, hasMore: hasMore)
            default:
                let error = databaseError()
                logError("Search query failed; error=\(error.localizedDescription)")
                throw error
            }
        }
    }
}

private extension SQLiteNoteSearchIndex {
    struct SearchMetadata {
        let modifiedAt: Date
        let byteCount: Int64
        let tagHash: String
    }

    /// Opens the handle, creates the schema, and applies any supported schema migration.
    func ensureDatabase() throws {
        if database != nil {
            return
        }

        let directoryURL = databaseURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            logError("Failed to create search index directory; error=\(error.localizedDescription)")
            throw NoteSearchIndexError.database(error.localizedDescription)
        }

        let sqliteVersion = String(cString: sqlite3_libversion())
        let fts5Enabled = "ENABLE_FTS5".withCString { sqlite3_compileoption_used($0) != 0 }
        log(
            "Opening SQLite search index; "
                + "sqliteVersion=\(sqliteVersion); fts5Enabled=\(fts5Enabled)"
        )

        var openedDatabase: OpaquePointer?
        let openResult = databaseURL.path(percentEncoded: false).withCString { path in
            sqlite3_open_v2(
                path,
                &openedDatabase,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }

        guard openResult == SQLITE_OK, let openedDatabase else {
            let message = openedDatabase.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned code \(openResult)"
            logError("Failed to open SQLite search index; error=\(message)")
            if let openedDatabase {
                sqlite3_close_v2(openedDatabase)
            }
            throw NoteSearchIndexError.database(message)
        }

        database = openedDatabase
        do {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try migrateSchemaIfNeeded()
            try execute(
                """
                CREATE TABLE IF NOT EXISTS note_search_metadata (
                    note_id TEXT PRIMARY KEY NOT NULL,
                    modified_at REAL NOT NULL,
                    byte_count INTEGER NOT NULL,
                    tag_hash TEXT NOT NULL
                )
                """
            )
            try execute(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS note_search USING fts5(
                    note_id UNINDEXED,
                    content,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """
            )
            try execute("PRAGMA user_version = \(Self.schemaVersion)")
            log("SQLite search schema is ready; version=\(Self.schemaVersion)")
        } catch {
            logError("Failed to prepare SQLite search schema; error=\(error.localizedDescription)")
            closeDatabase()
            throw error
        }
    }

    /// Removes SQLite sidecar files as well as the primary database during a rebuild.
    func removeDatabaseFiles() throws {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let fileURL = URL(fileURLWithPath: databaseURL.path(percentEncoded: false) + suffix)
            if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    throw NoteSearchIndexError.database(error.localizedDescription)
                }
            }
        }
    }

    /// Finalizes the actor-owned SQLite handle before deleting or reopening database files.
    func closeDatabase() {
        if let database {
            sqlite3_close_v2(database)
            self.database = nil
        }
    }

    /// Executes schema or transaction SQL and converts SQLite failures into app errors.
    func execute(_ sql: String) throws {
        guard let database else {
            throw NoteSearchIndexError.invalidDatabaseLocation
        }

        let result = sql.withCString { sqlite3_exec(database, $0, nil, nil, nil) }
        guard result == SQLITE_OK else {
            throw databaseError()
        }
    }

    func userVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw databaseError()
        }
        return sqlite3_column_int(statement, 0)
    }

    /// Advances the user-version marker while retaining indexed data where possible.
    func migrateSchemaIfNeeded() throws {
        let version = try userVersion()
        guard version != 0, version != Self.schemaVersion else {
            return
        }

        log("Rebuilding search cache for schema migration; oldVersion=\(version); newVersion=\(Self.schemaVersion)")
        try execute("DROP TABLE IF EXISTS note_search")
        try execute("DROP TABLE IF EXISTS note_search_metadata")
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else {
            throw NoteSearchIndexError.invalidDatabaseLocation
        }

        var statement: OpaquePointer?
        let result = sql.withCString {
            sqlite3_prepare_v2(database, $0, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw databaseError()
        }
        return statement
    }

    func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, destructor)
        }
        guard result == SQLITE_OK else {
            throw databaseError()
        }
    }

    func bind(_ value: Int32, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int(statement, index, value) == SQLITE_OK else {
            throw databaseError()
        }
    }

    /// Groups related SQLite writes so a partial index update cannot become visible.
    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Reads IDs tracked by the metadata table to detect stale notes during synchronization.
    func metadataIDs() throws -> Set<String> {
        let statement = try prepare("SELECT note_id FROM note_search_metadata")
        defer { sqlite3_finalize(statement) }

        var ids: Set<String> = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let idPointer = sqlite3_column_text(statement, 0) {
                    ids.insert(String(cString: idPointer))
                }
            case SQLITE_DONE:
                return ids
            default:
                throw databaseError()
            }
        }
    }

    /// Avoids re-reading a note when its file metadata is unchanged since the last index pass.
    func metadataMatches(noteID: String, metadata: SearchMetadata) throws -> Bool {
        let statement = try prepare(
            "SELECT modified_at, byte_count, tag_hash FROM note_search_metadata WHERE note_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(noteID, to: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return false
        }

        let modifiedAt = sqlite3_column_double(statement, 0)
        let byteCount = sqlite3_column_int64(statement, 1)
        let tagHash = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        return modifiedAt == metadata.modifiedAt.timeIntervalSince1970
            && byteCount == metadata.byteCount
            && tagHash == metadata.tagHash
    }

    /// Writes searchable Markdown/tags and the source metadata used for incremental sync.
    func upsert(noteID: String, markdown: String, tags: [NoteTag], metadata: SearchMetadata) throws {
        try delete(noteID: noteID)
        let searchableContent = ([markdown] + tags.map(\.name)).joined(separator: "\n")

        let insertSearch = try prepare(
            "INSERT INTO note_search (note_id, content) VALUES (?, ?)"
        )
        defer { sqlite3_finalize(insertSearch) }
        try bind(noteID, to: 1, in: insertSearch)
        try bind(searchableContent, to: 2, in: insertSearch)
        guard sqlite3_step(insertSearch) == SQLITE_DONE else {
            throw databaseError()
        }

        let insertMetadata = try prepare(
            """
            INSERT INTO note_search_metadata (note_id, modified_at, byte_count, tag_hash)
            VALUES (?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(insertMetadata) }
        try bind(noteID, to: 1, in: insertMetadata)
        guard sqlite3_bind_double(
            insertMetadata,
            2,
            metadata.modifiedAt.timeIntervalSince1970
        ) == SQLITE_OK else {
            throw databaseError()
        }
        guard sqlite3_bind_int64(insertMetadata, 3, metadata.byteCount) == SQLITE_OK else {
            throw databaseError()
        }
        try bind(metadata.tagHash, to: 4, in: insertMetadata)
        guard sqlite3_step(insertMetadata) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    /// Deletes both the metadata row and its corresponding FTS row.
    func delete(noteID: String) throws {
        let deleteSearch = try prepare("DELETE FROM note_search WHERE note_id = ?")
        defer { sqlite3_finalize(deleteSearch) }
        try bind(noteID, to: 1, in: deleteSearch)
        guard sqlite3_step(deleteSearch) == SQLITE_DONE else {
            throw databaseError()
        }

        let deleteMetadata = try prepare("DELETE FROM note_search_metadata WHERE note_id = ?")
        defer { sqlite3_finalize(deleteMetadata) }
        try bind(noteID, to: 1, in: deleteMetadata)
        guard sqlite3_step(deleteMetadata) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    func sourceMetadata(for noteURL: URL, tags: [NoteTag]) throws -> SearchMetadata {
        let markdownURL = noteURL.appendingPathComponent(TextBundleNoteRepository.textFilename)
        let values = try markdownURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return SearchMetadata(
            modifiedAt: values.contentModificationDate ?? .distantPast,
            byteCount: Int64(values.fileSize ?? 0),
            tagHash: Self.tagHash(for: tags)
        )
    }

    func sourceTags(for noteURL: URL) -> [NoteTag] {
        let infoURL = noteURL.appendingPathComponent(TextBundleNoteRepository.infoFilename)
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? JSONDecoder().decode(TextBundleInfo.self, from: data)
        else {
            return []
        }
        return info.notra.tags
    }

    func databaseError() -> NoteSearchIndexError {
        guard let database else {
            return .invalidDatabaseLocation
        }
        return .database(String(cString: sqlite3_errmsg(database)))
    }

    func log(_ message: String) {
        let line = "[SearchIndex] \(message)"
        print(line)
        Self.logger.info("\(line, privacy: .public)")
    }

    func logError(_ message: String) {
        let line = "[SearchIndex] \(message)"
        print(line)
        Self.logger.error("\(line, privacy: .public)")
    }

    nonisolated static func normalizedID(_ noteID: URL) -> String {
        noteID.standardizedFileURL.path(percentEncoded: false)
    }

    nonisolated static func ftsQuery(from query: String) -> String {
        var tokens: [(value: String, isPhrase: Bool)] = []
        var current = ""
        var isInsideQuotes = false

        func appendCurrent() {
            guard !current.isEmpty else {
                return
            }
            tokens.append((current, isInsideQuotes))
            current = ""
        }

        for character in query.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character == "\"" {
                if isInsideQuotes {
                    appendCurrent()
                }
                isInsideQuotes.toggle()
            } else if character.isWhitespace, !isInsideQuotes {
                appendCurrent()
            } else {
                current.append(character)
            }
        }
        appendCurrent()

        return tokens.compactMap { token in
            let words = token.value.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !words.isEmpty else {
                return nil
            }

            let escaped = words.map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            if token.isPhrase {
                return "\"\(escaped.joined(separator: " "))\""
            }
            return escaped.map { "\($0)*" }.joined(separator: " ")
        }
        .joined(separator: " ")
    }

    nonisolated static func tagHash(for tags: [NoteTag]) -> String {
        tags.map(\.normalizedKey).joined(separator: "\u{1F}")
    }
}
