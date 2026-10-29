import Foundation
import CoreMediaIO
import Darwin
import CameraQuietCore

/// Used only on the helper's main thread (or a read-only CLI probe).
/// Compiled scripts are reused; no osascript child processes are spawned.
final class SystemAlertVolume: AlertVolume {
    private var scripts: [String: NSAppleScript] = [:]
    func script(_ source: String) throws -> String {
        guard Thread.isMainThread else { throw QuietError.failure("Audio scripting must run on the helper's main thread") }
        let compiled: NSAppleScript
        if let cached = scripts[source] { compiled = cached }
        else {
            guard let created = NSAppleScript(source: source) else { throw QuietError.failure("Cannot create audio script") }
            compiled = created
            scripts[source] = created
        }
        var error: NSDictionary?
        let result = compiled.executeAndReturnError(&error)
        if let error = error { throw QuietError.failure("Audio settings: \(error)") }
        return result.stringValue ?? ""
    }
    func read() throws -> Int {
        let result = try script("alert volume of (get volume settings) as text")
        guard let value = Int(result), (0...100).contains(value) else {
            throw QuietError.failure("Unexpected alert-volume response: \(result)")
        }
        return value
    }
    func write(_ value: Int) throws {
        guard (0...100).contains(value) else { throw QuietError.failure("Invalid alert volume") }
        _ = try script("set volume alert volume \(value)")
    }
    func diagnostics() throws -> String {
        try script("""
        set v to get volume settings
        return "output volume:" & (output volume of v as text) & ", input volume:" & (input volume of v as text) & ", alert volume:" & (alert volume of v as text) & ", output muted:" & (output muted of v as text)
        """)
    }
}

struct CameraSnapshot {
    var devices: [String] = []
    var running: [String] = []
    var errors: [String] = []
    var active: Bool { !running.isEmpty }
    var known: Bool { errors.isEmpty }
}

/// Observes global device state; never opens a capture session or reads frames.
final class Cameras {
    private var names: [CMIOObjectID: (expires: TimeInterval, label: String)] = [:]
    func list(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector,
              scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)) throws -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: 0)
        var size: UInt32 = 0
        var status = CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard status == noErr else { throw QuietError.failure("Camera list error \(status)") }
        if size == 0 { return [] }
        guard size <= 1_048_576, size % 4 == 0 else { throw QuietError.failure("Invalid camera property size") }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / 4)
        status = ids.withUnsafeMutableBytes { bytes in
            CMIOObjectGetPropertyData(object, &address, 0, nil, size, &size, bytes.baseAddress!)
        }
        guard status == noErr else { throw QuietError.failure("Camera list read error \(status)") }
        return Array(ids.prefix(Int(size) / 4))
    }
    func name(_ id: CMIOObjectID) -> String {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = names[id], cached.expires > now { return cached.label }
        let label = readName(id)
        names[id] = (now + 60, label)
        return label
    }
    private func readName(_ id: CMIOObjectID) -> String {
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
                                          mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: 0)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = CMIOObjectGetPropertyData(id, &a, 0, nil, size, &used, &value)
        guard status == noErr, let name = value else { return "Camera \(id)" }
        return "\(name.takeRetainedValue() as String) [\(id)]"
    }
    func snapshot() -> CameraSnapshot {
        var result = CameraSnapshot()
        do {
            let ids = try list(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            let present = Set(ids)
            names = names.filter { present.contains($0.key) }
            for id in ids {
                do {
                    // Output-only devices are not cameras. Do not enable screen-capture devices.
                    let streams = try list(id, CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
                                           scope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput))
                    if streams.isEmpty { continue }
                    let label = name(id)
                    result.devices.append(label)
                    var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: 0)
                    var value: UInt32 = 0, used: UInt32 = 0
                    let status = CMIOObjectGetPropertyData(id, &a, 0, nil, 4, &used, &value)
                    guard status == noErr, used == 4 else { throw QuietError.failure("Camera \(id) activity error \(status)") }
                    if value != 0 { result.running.append(label) }
                } catch { result.errors.append(error.localizedDescription) }
            }
        } catch { result.errors.append(error.localizedDescription) }
        return result
    }
}

final class InstanceLock {
    private let directory: SecureStateDirectory
    private var fd: Int32 = -1
    init(directory: URL, name: String = "instance.lock") throws {
        self.directory = try SecureStateDirectory(url: directory)
        fd = try self.directory.openPrivateRegularFile(name, flags: O_CREAT | O_RDWR)
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd); fd = -1
            throw QuietError.failure("Utilipilled / Camera Quiet is already running (or recovering). Quit it before using --recover.")
        }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}

/// A bounded line protocol over private inherited pipes. No socket or public IPC endpoint.
private enum GuardianPipe {
    static func send(_ message: String, to fd: Int32) throws {
        let bytes = Array((message + "\n").utf8)
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw QuietError.failure("Audio helper connection closed") }
                offset += count
            }
        }
    }
    static func receive(from fd: Int32, timeout: TimeInterval? = nil) throws -> String? {
        let deadline = timeout.map { ProcessInfo.processInfo.systemUptime + $0 }
        var bytes: [UInt8] = []
        while bytes.count < 4096 {
            if let deadline = deadline {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { throw QuietError.failure("Audio helper timed out; recovery record retained") }
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, 3000)))
                if ready < 0 && errno == EINTR { continue }
                guard ready > 0 else { throw QuietError.failure("Audio helper timed out; recovery record retained") }
            }
            var byte: UInt8 = 0
            let count = Darwin.read(fd, &byte, 1)
            if count < 0 && errno == EINTR { continue }
            if count == 0 {
                guard bytes.isEmpty else { throw QuietError.failure("Incomplete audio helper response") }
                return nil
            }
            guard count > 0 else { throw QuietError.failure("Audio helper read failed") }
            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        throw QuietError.failure("Audio helper message too large")
    }
}

/// One persistent helper executes audio operations AND watches for parent death.
/// It finishes any in-flight write before handling EOF/recovery, closing the old
/// race between an orphaned osascript writer and the watchdog's restore.
final class Watchdog: AlertVolume {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var usable = true
    var running: Bool { usable && process.isRunning }
    init(directory: URL) throws {
        // Foundation writes must return EPIPE rather than terminating the process.
        signal(SIGPIPE, SIG_IGN)
        process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["--watchdog", "--state-dir", directory.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        for handle in [input.fileHandleForReading, input.fileHandleForWriting,
                       output.fileHandleForReading, output.fileHandleForWriting] {
            guard fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC) != -1 else {
                throw QuietError.failure("Cannot secure audio helper pipe")
            }
        }
        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        do {
            guard try GuardianPipe.receive(from: output.fileHandleForReading.fileDescriptor, timeout: 3) == "READY" else {
                throw QuietError.failure("Audio helper did not become ready")
            }
        } catch { invalidate(); throw error }
    }
    deinit { try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
    private func invalidate() {
        usable = false
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let end = ProcessInfo.processInfo.systemUptime + 0.25
            while process.isRunning && ProcessInfo.processInfo.systemUptime < end { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
    }
    private func request(_ command: String) throws -> String {
        guard running else { throw QuietError.failure("Audio helper unavailable") }
        do {
            try GuardianPipe.send(command, to: input.fileHandleForWriting.fileDescriptor)
            guard let response = try GuardianPipe.receive(from: output.fileHandleForReading.fileDescriptor, timeout: 3) else {
                throw QuietError.failure("Audio helper exited; recovery record retained")
            }
            if response.hasPrefix("ERROR ") {
                let encoded = String(response.dropFirst(6))
                let reason = Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) } ?? "Audio operation failed"
                throw QuietError.failure(reason)
            }
            guard response.hasPrefix("OK ") else { throw QuietError.failure("Invalid audio helper response") }
            return String(response.dropFirst(3))
        } catch { invalidate(); throw error }
    }
    func read() throws -> Int {
        let result = try request("READ")
        guard let value = Int(result), (0...100).contains(value) else { throw QuietError.failure("Invalid helper volume") }
        return value
    }
    func write(_ value: Int) throws {
        guard (0...100).contains(value) else { throw QuietError.failure("Invalid alert volume") }
        _ = try request("WRITE \(value)")
    }
    static func run(directory: URL) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        // Separate from the parent's instance lock: an old hung helper must not
        // overlap a new helper even after its parent dies or relaunches.
        var guardianLock: InstanceLock?
        let readyDeadline = ProcessInfo.processInfo.systemUptime + 1.5
        repeat {
            do { guardianLock = try InstanceLock(directory: directory, name: "guardian.lock") }
            catch { Thread.sleep(forTimeInterval: 0.05) }
        } while guardianLock == nil && ProcessInfo.processInfo.systemUptime < readyDeadline
        guard let guardianLock = guardianLock else { return 1 }
        defer { withExtendedLifetime(guardianLock) {} }
        let volume = SystemAlertVolume()
        // EOF is serviced in this same serial loop, after the current operation.
        do {
            _ = try SecureStateDirectory(url: directory)
            try GuardianPipe.send("READY", to: STDOUT_FILENO)
            while let command = try GuardianPipe.receive(from: STDIN_FILENO) {
                let response: String
                do {
                    if command == "READ" { response = "OK \(try volume.read())" }
                    else if command.hasPrefix("WRITE "), let value = Int(command.dropFirst(6)), (0...100).contains(value) {
                        try volume.write(value); response = "OK written"
                    } else { throw QuietError.failure("Invalid audio helper command") }
                } catch {
                    response = "ERROR " + Data(error.localizedDescription.utf8).base64EncodedString()
                }
                try GuardianPipe.send(response, to: STDOUT_FILENO)
            }
        } catch { /* A broken response pipe also means the parent is gone. */ }
        // Never wait for instance.lock while holding guardian.lock: a relaunch
        // may already own instance.lock and be waiting for this helper to leave.
        // That owner will process the durable journal after obtaining the guardian.
        let lock: InstanceLock
        do { lock = try InstanceLock(directory: directory) }
        catch { return 1 }
        return withExtendedLifetime(lock) {
            for _ in 0..<50 {
                do {
                    try MuteSession(volume: volume, store: FileRecoveryStore(directory: directory)).recover()
                    return 0
                } catch { Thread.sleep(forTimeInterval: 0.2) }
            }
            return 1
        }
    }
}

/// Recreates a dead helper before recovery; all callers use a serial worker.
final class GuardedAlertVolume: AlertVolume {
    private let directory: URL
    private var watchdog: Watchdog?
    init(directory: URL) { self.directory = directory }
    func ensureRunning() throws {
        if watchdog?.running != true { watchdog = try Watchdog(directory: directory) }
    }
    func read() throws -> Int { try ensureRunning(); return try watchdog!.read() }
    func write(_ value: Int) throws { try ensureRunning(); try watchdog!.write(value) }
}
