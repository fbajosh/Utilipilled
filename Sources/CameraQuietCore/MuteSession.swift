import Foundation
import Darwin

public protocol AlertVolume {
    func read() throws -> Int
    func write(_ value: Int) throws
}
public struct RecoveryRecord: Codable, Equatable {
    public let version: Int
    public let originalVolume: Int
    public init(originalVolume: Int) { self.version = 1; self.originalVolume = originalVolume }
}
public protocol RecoveryStore {
    func load() throws -> RecoveryRecord?
    func save(_ record: RecoveryRecord) throws
    func clear() throws
}
public enum QuietError: Error, LocalizedError {
    case failure(String)
    public var errorDescription: String? { if case .failure(let s) = self { return s }; return nil }
}

/// All calls belong to one serial worker. Durable intent precedes every mute.
public final class MuteSession {
    private let volume: AlertVolume
    private let store: RecoveryStore
    public private(set) var ownsMute = false
    public private(set) var overridden = false
    public init(volume: AlertVolume, store: RecoveryStore) { self.volume = volume; self.store = store }

    public func recover() throws {
        guard let record = try store.load() else { ownsMute = false; return }
        guard record.version == 1, (0...100).contains(record.originalVolume) else {
            throw QuietError.failure("Invalid recovery record; inspect recovery.json before continuing.")
        }
        // Compare before restore. Never replace an observed nonzero user setting.
        if !overridden, try volume.read() == 0 {
            try volume.write(record.originalVolume)
            guard try volume.read() == record.originalVolume else {
                throw QuietError.failure("Alert-volume restore could not be verified. Recovery record retained.")
            }
        }
        try store.clear()
        ownsMute = false
    }

    public func update(cameraActive: Bool, enabled: Bool) throws {
        if !cameraActive || !enabled {
            try recover()
            if !cameraActive { overridden = false }
            return
        }
        if overridden { return }
        if ownsMute {
            if try volume.read() != 0 {
                // The user wins for the rest of this camera session.
                ownsMute = false
                overridden = true
                try store.clear()
            }
            return
        }
        let previous = try volume.read()
        guard (0...100).contains(previous) else { throw QuietError.failure("Invalid alert volume") }
        if previous == 0 { overridden = true; return } // Already silent: nothing to restore or claim.
        try store.save(RecoveryRecord(originalVolume: previous))
        ownsMute = true // Keep intent even when a write throws after partially succeeding.
        try volume.write(0)
        let actual = try volume.read()
        if actual != 0 {
            try store.clear()
            ownsMute = false
            overridden = true
        }
    }

    public func restoreAndOverride() throws {
        try recover()
        overridden = true
    }
}

public final class FileRecoveryStore: RecoveryStore {
    public let url: URL
    private let directory: SecureStateDirectory
    private let filename = "recovery.json"
    private let maximumRecordBytes = 4096

    public init(directory: URL) throws {
        self.directory = try SecureStateDirectory(url: directory)
        url = directory.appendingPathComponent(filename)
    }

    public func load() throws -> RecoveryRecord? {
        guard let fd = try directory.openExistingPrivateRegularFile(filename) else { return nil }
        defer { close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw SecureStateDirectory.operationError("inspect recovery record") }
        guard metadata.st_size >= 0, metadata.st_size <= maximumRecordBytes else {
            throw QuietError.failure("Recovery record is too large; inspect recovery.json before continuing.")
        }
        // Enforce the bound during reads too, in case the opened file changes after fstat.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: maximumRecordBytes + 1)
        while data.count <= maximumRecordBytes {
            let available = maximumRecordBytes + 1 - data.count
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress!, available) }
            if count < 0 {
                if errno == EINTR { continue }
                throw SecureStateDirectory.operationError("read recovery record")
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= maximumRecordBytes else { throw QuietError.failure("Recovery record is too large") }
        return try JSONDecoder().decode(RecoveryRecord.self, from: data)
    }

    public func save(_ record: RecoveryRecord) throws {
        // Refuse to silently replace suspicious existing state, even though rename itself
        // would replace a final symlink rather than write through it.
        if let existing = try directory.openExistingPrivateRegularFile(filename) { close(existing) }
        let temporary = ".recovery-\(UUID().uuidString).tmp"
        let fd = try directory.openPrivateRegularFile(temporary, flags: O_WRONLY | O_CREAT | O_EXCL)
        defer { close(fd); _ = unlinkat(directory.descriptor, temporary, 0) }
        let data = try JSONEncoder().encode(record)
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw SecureStateDirectory.operationError("write recovery record")
                }
                guard count > 0 else { throw QuietError.failure("Could not finish writing recovery record") }
                written += count
            }
        }
        guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else {
            throw SecureStateDirectory.operationError("synchronize recovery record")
        }
        guard renameat(directory.descriptor, temporary, directory.descriptor, filename) == 0 else {
            throw SecureStateDirectory.operationError("publish recovery record")
        }
        // Persist the directory entry as well as the file before a mute can begin.
        try directory.synchronize()
    }

    public func clear() throws {
        guard let fd = try directory.openExistingPrivateRegularFile(filename) else { return }
        defer { close(fd) }
        guard unlinkat(directory.descriptor, filename, 0) == 0 else {
            if errno == ENOENT { return }
            throw SecureStateDirectory.operationError("remove recovery record")
        }
        try directory.synchronize()
    }
}
