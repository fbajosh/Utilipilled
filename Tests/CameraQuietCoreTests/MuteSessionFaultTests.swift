import Foundation
import CameraQuietCore

private final class FaultVolume: AlertVolume {
    var value: Int
    var writes: [Int] = []
    var readAttempts = 0
    var failOnRead: Int?
    var failAfterZeroWrite = false
    var valueAfterMute: Int?
    init(_ value: Int) { self.value = value }
    func read() throws -> Int {
        readAttempts += 1
        if readAttempts == failOnRead { throw QuietError.failure("Injected audio read failure") }
        return value
    }
    func write(_ value: Int) throws {
        self.value = value == 0 ? (valueAfterMute ?? value) : value
        writes.append(value)
        if value == 0 && failAfterZeroWrite { throw QuietError.failure("Injected failure after mute took effect") }
    }
}

private final class FaultRecoveryStore: RecoveryStore {
    var record: RecoveryRecord?
    var loadFails = false
    var clearFails = false
    var clearAttempts = 0
    func load() throws -> RecoveryRecord? {
        if loadFails { throw QuietError.failure("Injected journal read failure") }
        return record
    }
    func save(_ record: RecoveryRecord) throws { self.record = record }
    func clear() throws {
        clearAttempts += 1
        if clearFails { throw QuietError.failure("Injected journal removal failure") }
        record = nil
    }
}

struct MuteSessionFaultTests {
    func testPartialMuteFailureRetainsBaselineAndRecovers() throws {
        let volume = FaultVolume(63), store = FaultRecoveryStore()
        let session = MuteSession(volume: volume, store: store)
        volume.failAfterZeroWrite = true
        XCTAssertThrowsError(try session.update(cameraActive: true, enabled: true))
        XCTAssertEqual(volume.value, 0)
        XCTAssertEqual(store.record?.originalVolume, 63)
        XCTAssertTrue(session.ownsMute)
        volume.failAfterZeroWrite = false
        try session.recover()
        XCTAssertEqual(volume.writes, [0, 63])
        XCTAssertNil(store.record)
        XCTAssertFalse(session.ownsMute)
    }

    func testPostMuteReadFailureKeepsRecordForRecovery() throws {
        let volume = FaultVolume(82), store = FaultRecoveryStore()
        let session = MuteSession(volume: volume, store: store)
        // The baseline read succeeds; only verification of the applied mute fails.
        volume.failOnRead = 2
        XCTAssertThrowsError(try session.update(cameraActive: true, enabled: true))
        XCTAssertEqual(volume.value, 0)
        XCTAssertEqual(store.record?.originalVolume, 82)
        XCTAssertTrue(session.ownsMute)
        try session.recover()
        XCTAssertEqual(volume.writes, [0, 82])
        XCTAssertNil(store.record)
    }

    func testRecoveryAudioReadFailureDoesNotDiscardJournalOrOwnership() throws {
        let volume = FaultVolume(47), store = FaultRecoveryStore()
        let session = MuteSession(volume: volume, store: store)
        try session.update(cameraActive: true, enabled: true)
        volume.failOnRead = volume.readAttempts + 1
        XCTAssertThrowsError(try session.recover())
        XCTAssertEqual(volume.writes, [0])
        XCTAssertEqual(store.record?.originalVolume, 47)
        XCTAssertTrue(session.ownsMute)
        try session.recover()
        XCTAssertEqual(volume.value, 47)
        XCTAssertNil(store.record)
    }

    func testJournalLoadFailureDoesNotWriteAudioOrForgetOwnership() throws {
        let volume = FaultVolume(56), store = FaultRecoveryStore()
        let session = MuteSession(volume: volume, store: store)
        try session.update(cameraActive: true, enabled: true)
        store.loadFails = true
        XCTAssertThrowsError(try session.recover())
        XCTAssertEqual(volume.writes, [0])
        XCTAssertTrue(session.ownsMute)
        XCTAssertEqual(store.record?.originalVolume, 56)
        store.loadFails = false
        try session.recover()
        XCTAssertEqual(volume.value, 56)
        XCTAssertNil(store.record)
    }

    func testFailedJournalRemovalAfterRestoreCanRetryWithoutRepeatedAudioWrite() throws {
        let volume = FaultVolume(68), store = FaultRecoveryStore()
        let session = MuteSession(volume: volume, store: store)
        try session.update(cameraActive: true, enabled: true)
        store.clearFails = true
        XCTAssertThrowsError(try session.recover())
        XCTAssertEqual(volume.value, 68)
        XCTAssertEqual(store.record?.originalVolume, 68)
        XCTAssertEqual(volume.writes, [0, 68])
        store.clearFails = false
        try session.recover()
        XCTAssertEqual(volume.writes, [0, 68])
        XCTAssertNil(store.record)
        XCTAssertFalse(session.ownsMute)
    }

    func testObservedUserOverrideSurvivesJournalRemovalFailure() throws {
        // Observe the user change either immediately after the mute or on a later poll.
        for duringInitialMute in [true, false] {
            let volume = FaultVolume(91), store = FaultRecoveryStore()
            let session = MuteSession(volume: volume, store: store)
            if duringInitialMute { volume.valueAfterMute = 24 }
            else {
                try session.update(cameraActive: true, enabled: true)
                volume.value = 24
            }
            store.clearFails = true
            XCTAssertThrowsError(try session.update(cameraActive: true, enabled: true))
            // Disk cleanup failure must not revoke the user preference already observed.
            XCTAssertTrue(session.overridden)
            XCTAssertFalse(session.ownsMute)
            XCTAssertEqual(volume.value, 24)
            XCTAssertEqual(volume.writes, [0])
            // The user's later zero is their setting, not a mute still owned by us.
            volume.value = 0
            try session.update(cameraActive: true, enabled: true)
            XCTAssertEqual(volume.writes, [0])
            store.clearFails = false
            try session.recover()
            XCTAssertEqual(volume.value, 0)
            XCTAssertEqual(volume.writes, [0])
            XCTAssertNil(store.record)
        }
    }

    func testInvalidRecoveryRecordVersionAndRangeNeverWriteAudio() throws {
        let invalid = [
            "{\"version\":99,\"originalVolume\":44}",
            "{\"version\":1,\"originalVolume\":-1}",
            "{\"version\":1,\"originalVolume\":101}",
        ]
        for json in invalid {
            let volume = FaultVolume(0), store = FaultRecoveryStore()
            store.record = try JSONDecoder().decode(RecoveryRecord.self, from: Data(json.utf8))
            let previous = store.record
            XCTAssertThrowsError(try MuteSession(volume: volume, store: store).recover())
            XCTAssertTrue(volume.writes.isEmpty)
            XCTAssertEqual(store.record, previous)
            XCTAssertEqual(store.clearAttempts, 0)
        }
    }
}
