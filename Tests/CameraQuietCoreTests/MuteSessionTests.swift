import Foundation
import CameraQuietCore

final class FakeVolume: AlertVolume {
    var value: Int
    var writes: [Int] = []
    var writeFails = false
    var readFails = false
    var beforeWrite: (() -> Void)?
    init(_ value: Int) { self.value = value }
    func read() throws -> Int {
        if readFails { throw QuietError.failure("read failed") }; return value
    }
    func write(_ value: Int) throws {
        beforeWrite?()
        if writeFails { throw QuietError.failure("write failed") }
        self.value = value; writes.append(value)
    }
}
final class FakeStore: RecoveryStore {
    var record: RecoveryRecord?
    var saveFails = false
    func load() throws -> RecoveryRecord? { record }
    func save(_ record: RecoveryRecord) throws {
        if saveFails { throw QuietError.failure("disk full") }; self.record = record
    }
    func clear() throws { record = nil }
}
struct MuteSessionTests {
    func testDurableIntentBeforeMuteAndRestoreAfterLastCamera() throws {
        let v = FakeVolume(73), s = FakeStore(), m = MuteSession(volume: v, store: s)
        v.beforeWrite = { XCTAssertNotNil(s.record) }
        try m.update(cameraActive: true, enabled: true)
        XCTAssertEqual(s.record?.originalVolume, 73); XCTAssertEqual(v.value, 0)
        // One of several concurrent users/cameras is still active.
        try m.update(cameraActive: true, enabled: true)
        XCTAssertEqual(v.writes, [0])
        try m.update(cameraActive: false, enabled: true)
        XCTAssertEqual(v.value, 73); XCTAssertNil(s.record)
    }
    func testUserOverrideIsNotOverwrittenOrRemutedUntilIdle() throws {
        let v = FakeVolume(58), s = FakeStore(), m = MuteSession(volume: v, store: s)
        try m.update(cameraActive: true, enabled: true)
        v.value = 31
        try m.update(cameraActive: true, enabled: true)
        try m.update(cameraActive: true, enabled: true)
        XCTAssertTrue(m.overridden); XCTAssertEqual(v.value, 31); XCTAssertNil(s.record)
        try m.update(cameraActive: false, enabled: true)
        XCTAssertEqual(v.value, 31)
        try m.update(cameraActive: true, enabled: true)
        XCTAssertEqual(s.record?.originalVolume, 31); XCTAssertEqual(v.value, 0)
    }
    func testInitiallySilentStaysSilentAndDoesNotClaimUserChange() throws {
        let v = FakeVolume(0), s = FakeStore(), m = MuteSession(volume: v, store: s)
        try m.update(cameraActive: true, enabled: true)
        v.value = 25
        try m.update(cameraActive: true, enabled: true)
        try m.update(cameraActive: false, enabled: true)
        XCTAssertEqual(v.value, 25); XCTAssertTrue(v.writes.isEmpty)
    }
    func testCrashRecoveryAndIdempotency() throws {
        let v = FakeVolume(0), s = FakeStore()
        s.record = RecoveryRecord(originalVolume: 64)
        let restarted = MuteSession(volume: v, store: s)
        try restarted.recover(); try restarted.recover()
        XCTAssertEqual(v.writes, [64]); XCTAssertNil(s.record)
    }
    func testCrashRecoveryPreservesUserChange() throws {
        let v = FakeVolume(20), s = FakeStore(); s.record = RecoveryRecord(originalVolume: 80)
        try MuteSession(volume: v, store: s).recover()
        XCTAssertEqual(v.value, 20); XCTAssertTrue(v.writes.isEmpty); XCTAssertNil(s.record)
    }
    func testCannotMuteWithoutSavingRecovery() throws {
        let v = FakeVolume(50), s = FakeStore(); s.saveFails = true
        XCTAssertThrowsError(try MuteSession(volume: v, store: s).update(cameraActive: true, enabled: true))
        XCTAssertEqual(v.value, 50); XCTAssertTrue(v.writes.isEmpty)
    }
    func testFailedRestoreRetainsJournalForRetry() throws {
        let v = FakeVolume(0), s = FakeStore(); s.record = RecoveryRecord(originalVolume: 40)
        v.writeFails = true
        let m = MuteSession(volume: v, store: s)
        XCTAssertThrowsError(try m.recover()); XCTAssertNotNil(s.record)
        v.writeFails = false; try m.recover(); XCTAssertEqual(v.value, 40)
    }
    func testPauseRestoresAndExplicitOverrideLastsUntilIdle() throws {
        let v = FakeVolume(90), s = FakeStore(), m = MuteSession(volume: v, store: s)
        try m.update(cameraActive: true, enabled: true)
        try m.update(cameraActive: true, enabled: false)
        XCTAssertEqual(v.value, 90)
        try m.update(cameraActive: true, enabled: true)
        try m.restoreAndOverride()
        try m.update(cameraActive: true, enabled: true)
        XCTAssertEqual(v.value, 90)
        try m.update(cameraActive: false, enabled: true)
        try m.update(cameraActive: true, enabled: true)
        XCTAssertEqual(v.value, 0)
    }
    func testFileJournalRoundTripAndCorruptionDoesNotOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try FileRecoveryStore(directory: dir)
        try store.save(RecoveryRecord(originalVolume: 77))
        XCTAssertEqual(try store.load()?.originalVolume, 77)
        try Data("broken".utf8).write(to: store.url)
        let v = FakeVolume(0)
        XCTAssertThrowsError(try MuteSession(volume: v, store: store).recover())
        XCTAssertTrue(v.writes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
    }
}
