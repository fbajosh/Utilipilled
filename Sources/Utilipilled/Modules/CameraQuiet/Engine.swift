import Foundation
import CameraQuietCore

struct Status: Equatable {
    var title: String
    var detail: String
    var cameraActive: Bool = false
    var quiet: Bool = false
    var error: Bool = false
}

final class CameraQuietModule {
    private let queue = DispatchQueue(label: "CameraQuiet.control", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let volume: GuardedAlertVolume
    private let session: MuteSession
    private let cameras = Cameras()
    private var enabled: Bool
    private var sleeping = false
    private var stopping = false
    private var policy = CameraPolicy()
    private var faulted = false
    private var lastPublishedStatus: Status?
    var onStatus: ((Status) -> Void)?
    init(directory: URL, enabled: Bool) throws {
        self.enabled = enabled
        let volume = GuardedAlertVolume(directory: directory)
        self.volume = volume
        session = MuteSession(volume: volume, store: try FileRecoveryStore(directory: directory))
    }
    func start() {
        queue.async {
            do {
                try self.volume.ensureRunning()
                try self.session.recover()
            } catch { self.faulted = true; self.publishError(error) }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
        }
    }
    private func publish(_ status: Status) {
        guard status != lastPublishedStatus else { return }
        lastPublishedStatus = status
        DispatchQueue.main.async { self.onStatus?(status) }
    }
    private func publishError(_ error: Error) {
        publish(Status(title: "Needs attention — alerts restored if possible", detail: error.localizedDescription, error: true))
    }
    private func handleFailure(_ error: Error) {
        // Menu actions and sleep notifications must enter the same safe state as
        // polling failures. Otherwise the next tick can hide an unresolved error.
        faulted = true
        let original = error.localizedDescription
        do { try session.recover() }
        catch {
            publishError(QuietError.failure(original + " Restore failed: " + error.localizedDescription))
            return
        }
        publishError(QuietError.failure(original))
    }
    private func tick() {
        if stopping { return }
        do {
            if faulted { return } // Requires explicit resume; don't silently re-mute after a fault.
            try volume.ensureRunning()
            let snapshot = cameras.snapshot()
            let wasActive = try policy.update(runningCount: snapshot.running.count,
                                                  reliable: snapshot.known)
            try session.update(cameraActive: wasActive, enabled: enabled && !sleeping)
            let title: String
            if sleeping { title = "Sleeping — alerts restored" }
            else if !enabled { title = "Paused — alerts restored" }
            else if !snapshot.known && !snapshot.active { title = "Camera state uncertain — waiting" }
            else if session.ownsMute { title = "Camera in use — system alerts silent" }
            else if wasActive { title = "Camera in use — keeping your sound setting" }
            else { title = "Ready — camera idle" }
            let detail = "\(snapshot.running.count) active / \(snapshot.devices.count) detected cameras. " +
                (session.ownsMute ? "All system alert sounds are quiet; call/media volume is unchanged." : "Banners and call/media volume are unchanged.")
            publish(Status(title: title, detail: detail, cameraActive: wasActive, quiet: session.ownsMute))
        } catch {
            handleFailure(error)
        }
    }
    func setEnabled(_ value: Bool) {
        queue.async {
            self.enabled = value
            if value { self.faulted = false; self.policy = CameraPolicy() }
            do {
                if !value {
                    try self.session.recover()
                    if self.faulted {
                        self.publish(Status(title: "Paused — alerts restored", detail: "Toggle Automatic quiet on to retry.", cameraActive: self.policy.active))
                        return
                    }
                }
                self.tick()
            }
            catch { self.handleFailure(error) }
        }
    }
    func restoreNow() {
        queue.async {
            do { try self.session.restoreAndOverride(); self.tick() }
            catch { self.handleFailure(error) }
        }
    }
    func sleep(_ value: Bool) {
        queue.async {
            self.sleeping = value
            do { if value { try self.session.recover() }; self.tick() }
            catch { self.handleFailure(error) }
        }
    }
    func stop(_ completion: @escaping (Error?) -> Void) {
        queue.async {
            trace("Stop worker running")
            self.stopping = true; self.timer?.cancel(); self.timer = nil
            var failure: Error?
            do { try self.session.recover() } catch { failure = error }
            trace("Restoration finished; scheduling stop callback")
            let finalFailure = failure
            // Cocoa may run a nested termination loop. Deliver through its run loop,
            // rather than queueing behind the main-dispatch callback that requested quit.
            RunLoop.main.perform(inModes: [.common]) { completion(finalFailure) }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
}
