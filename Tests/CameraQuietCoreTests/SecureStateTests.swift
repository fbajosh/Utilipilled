import Foundation
import Darwin
import CameraQuietCore

struct SecureStateTests {
    private func temporaryDirectory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        return path
    }

    func testRejectsSymlinkStateDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        _ = try FileRecoveryStore(directory: real)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        XCTAssertThrowsError(try FileRecoveryStore(directory: alias))
    }

    func testRejectsPublicStateDirectoryWithoutChangingItsPermissions() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(chmod(root.path, 0o755), 0)
        XCTAssertThrowsError(try FileRecoveryStore(directory: root))
        var metadata = stat()
        XCTAssertEqual(lstat(root.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & mode_t(0o777), mode_t(0o755))
    }

    func testRejectsJournalSymlinkWithoutReadingOrChangingTarget() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecoveryStore(directory: root.appendingPathComponent("state"))
        let target = root.appendingPathComponent("unrelated.txt")
        let content = Data("unchanged".utf8)
        try content.write(to: target)
        XCTAssertEqual(chmod(target.path, 0o600), 0)
        try FileManager.default.createSymbolicLink(at: store.url, withDestinationURL: target)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(RecoveryRecord(originalVolume: 77)))
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(try Data(contentsOf: target), content)
    }

    func testRejectsFifoWithoutBlocking() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecoveryStore(directory: root)
        XCTAssertEqual(mkfifo(store.url.path, 0o600), 0)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(RecoveryRecord(originalVolume: 77)))
        XCTAssertThrowsError(try store.clear())
    }

    func testRejectsHardLinkedJournal() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecoveryStore(directory: root.appendingPathComponent("state"))
        let target = root.appendingPathComponent("other.json")
        let content = try JSONEncoder().encode(RecoveryRecord(originalVolume: 81))
        try content.write(to: target)
        XCTAssertEqual(chmod(target.path, 0o600), 0)
        XCTAssertEqual(link(target.path, store.url.path), 0)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(RecoveryRecord(originalVolume: 77)))
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(try Data(contentsOf: target), content)
    }

    func testOversizedJournalCannotCauseRecoveryMutation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecoveryStore(directory: root)
        try Data(repeating: 32, count: 4097).write(to: store.url)
        XCTAssertEqual(chmod(store.url.path, 0o600), 0)
        let volume = FakeVolume(0)
        XCTAssertThrowsError(try MuteSession(volume: volume, store: store).recover())
        XCTAssertTrue(volume.writes.isEmpty)
    }

    func testStateOperationsStayAnchoredWhenPathIsReplaced() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = root.appendingPathComponent("state")
        let moved = root.appendingPathComponent("moved")
        let store = try FileRecoveryStore(directory: initial)
        try FileManager.default.moveItem(at: initial, to: moved)
        try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try store.save(RecoveryRecord(originalVolume: 65))
        XCTAssertEqual(try store.load()?.originalVolume, 65)
        XCTAssertFalse(FileManager.default.fileExists(atPath: initial.appendingPathComponent("recovery.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("recovery.json").path))
        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.appendingPathComponent("recovery.json").path))
    }

    func testNewJournalIsPrivateAndAtomicReplacementLeavesNoTemporaryFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecoveryStore(directory: root)
        try store.save(RecoveryRecord(originalVolume: 12))
        try store.save(RecoveryRecord(originalVolume: 34))
        var metadata = stat()
        XCTAssertEqual(lstat(store.url.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & mode_t(0o777), mode_t(0o600))
        XCTAssertEqual(metadata.st_nlink, nlink_t(1))
        XCTAssertEqual(try store.load()?.originalVolume, 34)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["recovery.json"])
        try store.clear()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testPrivateFileHelperRejectsUnsafeLockFilesAndNames() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("state")
        let directory = try SecureStateDirectory(url: stateURL)
        let lockURL = stateURL.appendingPathComponent("instance.lock")
        let other = root.appendingPathComponent("other")
        let bytes = Data("untouched".utf8)
        try bytes.write(to: other)
        XCTAssertEqual(chmod(other.path, 0o600), 0)
        try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: other)
        XCTAssertThrowsError(try directory.openPrivateRegularFile("instance.lock", flags: O_CREAT | O_RDWR))
        XCTAssertEqual(try Data(contentsOf: other), bytes)
        try FileManager.default.removeItem(at: lockURL)
        XCTAssertEqual(mkfifo(lockURL.path, 0o600), 0)
        XCTAssertThrowsError(try directory.openPrivateRegularFile("instance.lock", flags: O_CREAT | O_RDWR))
        try FileManager.default.removeItem(at: lockURL)
        XCTAssertEqual(link(other.path, lockURL.path), 0)
        XCTAssertThrowsError(try directory.openPrivateRegularFile("instance.lock", flags: O_CREAT | O_RDWR))
        XCTAssertThrowsError(try directory.openPrivateRegularFile("../other", flags: O_CREAT | O_RDWR))
        try FileManager.default.removeItem(at: lockURL)
        let valid = try directory.openPrivateRegularFile("instance.lock", flags: O_CREAT | O_RDWR)
        defer { close(valid) }
        XCTAssertTrue(fcntl(valid, F_GETFD) & FD_CLOEXEC != 0)
    }

}
