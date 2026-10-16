import Foundation

/// Owns only file grants and coordinated bytes. The Dart backup service owns
/// binding, scheduling, the document format and destructive restore.
final class BackupFileStore {
    static let fileName = "OneXray-backup.json"
    static let byteLimit = 64 * 1024 * 1024
    private let preferences: UserDefaults
    private let key = "onexray.backup.fileBookmarks"
    private let creationOptions: URL.BookmarkCreationOptions

    init(preferences: UserDefaults = .standard,
         creationOptions: URL.BookmarkCreationOptions? = nil) {
        self.preferences = preferences
        #if os(macOS)
        self.creationOptions = creationOptions ?? .withSecurityScope
        #else
        self.creationOptions = creationOptions ?? .minimalBookmark
        #endif
    }

    private var bookmarks: [String: [String: Any]] {
        preferences.dictionary(forKey: key) as? [String: [String: Any]] ?? [:]
    }

    /// A directory grant may authorize creation, but the target is always one
    /// file. An existing file is never truncated by selecting/creating a target.
    func bind(_ file: URL, accessURL: URL? = nil, create: Bool) throws -> String {
        let grant = accessURL ?? file
        return try withAccess(grant) {
            if create {
                try coordinate(file, writing: true) { url in
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try Data().write(to: url, options: .withoutOverwriting)
                    }
                }
            }
            let identifier = file.absoluteString
            var record: [String: Any] = ["bookmark": try bookmark(grant)]
            if grant != file { record["fileName"] = file.lastPathComponent }
            var saved = bookmarks
            saved[identifier] = record
            preferences.set(saved, forKey: key)
            return identifier
        }
    }

    func requireAccess(_ identifier: String) throws {
        try withFile(identifier) { url in
            guard try url.checkResourceIsReachable() else { throw failure("Select the backup file again.") }
        }
    }

    func hasContents(_ identifier: String) throws -> Bool {
        try withFile(identifier) { file in
            try coordinate(file, writing: false) { url in
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                return !(try handle.read(upToCount: 1) ?? Data()).isEmpty
            }
        }
    }

    func read(_ identifier: String) throws -> Data {
        try withFile(identifier) { file in
            try coordinate(file, writing: false) { url in
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var bytes = Data()
                while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    guard bytes.count + chunk.count <= Self.byteLimit else {
                        throw failure("Backup exceeds 64 MiB.")
                    }
                    bytes.append(chunk)
                }
                return bytes
            }
        }
    }

    func write(_ identifier: String, bytes: Data) throws {
        guard !bytes.isEmpty && bytes.count <= Self.byteLimit else {
            throw failure("Invalid backup size.")
        }
        try withFile(identifier, refresh: true) { file in
            try coordinate(file, writing: true) { url in
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw failure("The backup file is missing. Select it again.")
                }
                try bytes.write(to: url, options: .atomic)
            }
        }
    }

    func release(_ identifier: String) {
        var saved = bookmarks
        saved.removeValue(forKey: identifier)
        preferences.set(saved, forKey: key)
    }

    private func withFile<T>(_ identifier: String, refresh: Bool = false,
                             _ operation: (URL) throws -> T) throws -> T {
        guard var record = bookmarks[identifier], let data = record["bookmark"] as? Data else {
            throw failure("Backup file access expired. Select the file again.")
        }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = creationOptions.contains(.withSecurityScope)
            ? [.withSecurityScope, .withoutUI] : [.withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let grant = try URL(resolvingBookmarkData: data, options: options,
                            relativeTo: nil, bookmarkDataIsStale: &stale)
        return try withAccess(grant) {
            let file = (record["fileName"] as? String).map { grant.appendingPathComponent($0) } ?? grant
            let result = try operation(file)
            // Replacement may change the file identity. Keep the binding key
            // stable for the saved target while refreshing its bookmark.
            if stale || refresh {
                record["bookmark"] = try bookmark(grant)
                var saved = bookmarks
                saved[identifier] = record
                preferences.set(saved, forKey: key)
            }
            return result
        }
    }

    private func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func withAccess<T>(_ url: URL, _ operation: () throws -> T) rethrows -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // URLs inside the app's own container need no security scope. Actual
        // access is enforced by the filesystem for both kinds of URL.
        return try operation()
    }

    private func coordinate<T>(_ url: URL, writing: Bool,
                                _ operation: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result: Result<T, Error>?
        let accessor: (URL) -> Void = { accessedURL in result = Result { try operation(accessedURL) } }
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error, byAccessor: accessor)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error, byAccessor: accessor)
        }
        if let error { throw error }
        guard let result else { throw failure("Could not access the backup file.") }
        return try result.get()
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "OneXray.Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
