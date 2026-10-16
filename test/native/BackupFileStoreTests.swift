import Foundation
import XCTest

final class BackupFileStoreTests: XCTestCase {
    private func fixture(_ body: (URL, UserDefaults, BackupFileStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: "../references/onexray-tests/native").standardizedFileURL
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "OneXray.BackupTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        // The command-line test has no sandbox identity. Signed app checks
        // exercise the production security-scoped creation option separately.
        let store = BackupFileStore(preferences: preferences, creationOptions: .minimalBookmark)
        try body(root, preferences, store)
    }

    func testBindingDoesNotOverwriteAndReplacementSurvivesNewStore() throws {
        try fixture { root, preferences, store in
            let file = root.appendingPathComponent("selected.json")
            let original = Data("original backup".utf8)
            try original.write(to: file)
            let identifier = try store.bind(file, create: true)
            XCTAssertTrue(try store.hasContents(identifier))
            XCTAssertEqual(try store.read(identifier), original)
            for value in ["first", "second"] {
                try store.write(identifier, bytes: Data(value.utf8))
                let reopened = BackupFileStore(preferences: preferences, creationOptions: .minimalBookmark)
                XCTAssertEqual(try reopened.read(identifier), Data(value.utf8))
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["selected.json"])
        }
    }

    func testCreateBindsOneFileAndReleaseKeepsItsContents() throws {
        try fixture { root, _, store in
            let file = root.appendingPathComponent(BackupFileStore.fileName)
            let identifier = try store.bind(file, accessURL: root, create: true)
            XCTAssertEqual(identifier, file.absoluteString)
            XCTAssertFalse(try store.hasContents(identifier))
            let bytes = Data("bound file".utf8)
            try store.write(identifier, bytes: bytes)
            XCTAssertTrue(try store.hasContents(identifier))
            XCTAssertEqual(try store.read(identifier), bytes)
            store.release(identifier)
            XCTAssertThrowsError(try store.hasContents(identifier))
            XCTAssertThrowsError(try store.read(identifier))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testMissingFileIsNotRecreatedByAutomaticWrite() throws {
        try fixture { root, _, store in
            let file = root.appendingPathComponent(BackupFileStore.fileName)
            let identifier = try store.bind(file, accessURL: root, create: true)
            try FileManager.default.removeItem(at: file)
            XCTAssertThrowsError(try store.hasContents(identifier))
            XCTAssertThrowsError(try store.write(identifier, bytes: Data([1])))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testSizeLimitsPreserveOldFileAndBoundReads() throws {
        try fixture { root, _, store in
            let file = root.appendingPathComponent("selected.json")
            try Data([42]).write(to: file)
            let identifier = try store.bind(file, create: false)
            XCTAssertThrowsError(try store.write(identifier, bytes: Data()))
            XCTAssertThrowsError(try store.write(identifier, bytes: Data(count: BackupFileStore.byteLimit + 1)))
            XCTAssertEqual(try store.read(identifier), Data([42]))
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(BackupFileStore.byteLimit + 1))
            try handle.close()
            XCTAssertTrue(try store.hasContents(identifier))
            XCTAssertThrowsError(try store.read(identifier))
        }
    }
}

@main
enum BackupFileStoreTestRunner {
    static func main() {
        let suite = BackupFileStoreTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0,
              result.totalFailureCount == 0 else { exit(1) }
    }
}
