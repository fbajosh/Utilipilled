import AppKit
import ServiceManagement
import CameraQuietCore
import Darwin

let args = CommandLine.arguments
func trace(_ text: String) {
    if args.contains("--debug") { fputs("Utilipilled: \(text)\n", stderr); fflush(stderr) }
}
func argument(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
// Preserve the module's recovery namespace and lock across the original app rename.
// This also prevents the old CameraQuiet app and Utilipilled from muting concurrently.
let directory = argument("--state-dir").map { URL(fileURLWithPath: $0, isDirectory: true) } ??
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CameraQuiet", isDirectory: true)
func fail(_ error: Error) -> Never {
    fputs("Utilipilled: \(error.localizedDescription)\n", stderr); exit(1)
}

if args.contains("--watchdog") { exit(Watchdog.run(directory: directory)) }
if args.contains("--probe") {
    let cameras = Cameras().snapshot()
    print("Detected: \(cameras.devices.joined(separator: ", "))")
    print("Active: \(cameras.running.joined(separator: ", "))")
    print("Camera errors: \(cameras.errors.joined(separator: "; "))")
    do { print("Audio: \(try SystemAlertVolume().diagnostics())") } catch { fail(error) }
    exit(cameras.known ? 0 : 1)
}
if args.contains("--recover") || args.contains("--exercise-session") {
    do {
        let lock = try InstanceLock(directory: directory)
        try withExtendedLifetime(lock) {
            let volume = GuardedAlertVolume(directory: directory)
            let session = MuteSession(volume: volume, store: try FileRecoveryStore(directory: directory))
            try session.recover()
            if args.contains("--exercise-session") {
                guard let raw = argument("--exercise-session"), let seconds = Double(raw), (1...120).contains(seconds) else {
                    throw QuietError.failure("Use --exercise-session SECONDS (1–120); this temporarily mutes system alerts.")
                }
                try withExtendedLifetime(volume) {
                    try volume.ensureRunning()
                    try session.update(cameraActive: true, enabled: true)
                    print("Exercise active; pid=\(getpid()), alert volume=\(try volume.read())")
                    fflush(stdout)
                    let end = ProcessInfo.processInfo.systemUptime + seconds
                    while ProcessInfo.processInfo.systemUptime < end {
                        Thread.sleep(forTimeInterval: 0.5)
                        try session.update(cameraActive: true, enabled: true)
                    }
                    try session.recover()
                }
            }
            print("Recovery complete; alert volume=\(try volume.read())")
        }
        exit(0)
    } catch { fail(error) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var engine: CameraQuietModule!
    private let keepAwake = KeepAwakeModule()
    private var lock: InstanceLock?
    private var observers: [NSObjectProtocol] = []
    private var signals: [DispatchSourceSignal] = []
    private var status = Status(title: "Starting…", detail: "System alert volume only")
    // Import the original app's preferences when the new host has no setting yet.
    private var enabled: Bool = {
        if UserDefaults.standard.object(forKey: "cameraQuiet.paused") != nil {
            return !UserDefaults.standard.bool(forKey: "cameraQuiet.paused")
        }
        let previousHost = UserDefaults.standard.persistentDomain(forName: "local.JoshTools")
        if let paused = previousHost?["cameraQuiet.paused"] as? Bool { return !paused }
        let previous = UserDefaults.standard.persistentDomain(forName: "local.CameraQuiet")
        return !(previous?["paused"] as? Bool ?? false)
    }()
    private var toggleItem: NSMenuItem!
    private var awakeItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var titleItem: NSMenuItem!
    private var durationItem: NSMenuItem!
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            lock = try InstanceLock(directory: directory)
            engine = try CameraQuietModule(directory: directory, enabled: enabled)
        } catch {
            let a = NSAlert(); a.messageText = "Utilipilled could not start"; a.informativeText = error.localizedDescription
            a.runModal(); NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Earlier versions persisted a hidden state under AppKit's automatic item name.
        item.autosaveName = "Utilipilled"
        item.isVisible = true
        let menu = NSMenu()
        func heading(_ title: String, primary: Bool = false) {
            let entry = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            if primary {
                let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 28))
                let label = NSTextField(labelWithString: title)
                label.font = .boldSystemFont(ofSize: 14)
                label.textColor = .labelColor
                label.frame = NSRect(x: 14, y: 4, width: 222, height: 20)
                view.addSubview(label); entry.view = view
                return
            }
            entry.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.boldSystemFont(ofSize: primary ? 14 : 12),
                .foregroundColor: primary ? NSColor.labelColor : NSColor.secondaryLabelColor
            ])
        }
        heading("Utilipilled", primary: true)
        menu.addItem(.separator())
        heading("Camera Quiet")
        toggleItem = menu.addItem(withTitle: "Enable", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Restore sounds for this camera session", action: #selector(restore), keyEquivalent: "")
        titleItem = menu.addItem(withTitle: status.title, action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Scope: all system alerts…", action: #selector(soundSettings), keyEquivalent: "")
        menu.addItem(.separator())
        heading("Keep Awake")
        awakeItem = menu.addItem(withTitle: "Enable", action: #selector(toggleKeepAwake), keyEquivalent: "")
        durationItem = menu.addItem(withTitle: "Duration", action: nil, keyEquivalent: "")
        let durations = NSMenu()
        for (index, duration) in KeepAwakeModule.Duration.allCases.enumerated() {
            let entry = durations.addItem(withTitle: duration.rawValue, action: #selector(selectDuration(_:)), keyEquivalent: "")
            entry.tag = index; entry.target = self
        }
        durationItem.submenu = durations
        menu.addItem(.separator())
        heading("Utilipilled")
        loginItem = menu.addItem(withTitle: "Launch at login", action: #selector(login), keyEquivalent: "")
        menu.addItem(withTitle: "About Utilipilled…", action: #selector(about), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Utilipilled", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items where entry.action != nil { entry.target = self }
        item.menu = menu
        engine.onStatus = { [weak self] status in self?.status = status; self?.render() }
        keepAwake.onChange = { [weak self] in self?.render() }
        do { try keepAwake.resume() }
        catch {
            let alert = NSAlert(); alert.messageText = "Keep Awake could not resume"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
        render(); engine.start()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.engine.sleep(true) })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.engine.sleep(false); self?.keepAwake.checkExpiration() })
        observers.append(center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in NSApp.terminate(nil) })
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                trace("Termination signal received")
                RunLoop.main.perform(inModes: [.common]) { NSApp.terminate(nil) }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }; source.resume(); signals.append(source)
        }
    }
    private func render() {
        item.button?.image = MenuBarIcon.image(active: keepAwake.isEnabled || status.quiet)
        let description = "Utilipilled · Keep Awake: \(keepAwake.isEnabled ? "On" : "Off") · Camera Quiet: \(status.title)"
        item.button?.toolTip = description
        item.button?.setAccessibilityLabel(description)
        titleItem.title = "Status: " + status.title
        awakeItem.title = keepAwake.isEnabled ? "Disable" : "Enable"
        toggleItem.title = enabled ? "Disable" : "Enable"
        durationItem.title = "Duration: " + keepAwake.duration.rawValue
        for entry in durationItem.submenu?.items ?? [] {
            entry.state = entry.title == keepAwake.duration.rawValue ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        item.isVisible = true
        render()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.item.button?.performClick(nil) }
        return false
    }
    @objc private func toggleKeepAwake() {
        do { try keepAwake.setEnabled(!keepAwake.isEnabled) }
        catch {
            let a = NSAlert(); a.messageText = "Keep Awake could not be changed"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
        render()
    }
    @objc private func toggle() {
        enabled.toggle(); UserDefaults.standard.set(!enabled, forKey: "cameraQuiet.paused")
        engine.setEnabled(enabled); render()
    }
    @objc private func restore() { engine.restoreNow() }
    @objc private func selectDuration(_ sender: NSMenuItem) {
        let values = KeepAwakeModule.Duration.allCases
        guard values.indices.contains(sender.tag) else { return }
        do { try keepAwake.setDuration(values[sender.tag]) }
        catch {
            let alert = NSAlert(); alert.messageText = "Duration could not be changed"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
        render()
    }
    @objc private func login() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let a = NSAlert(); a.messageText = "Login startup could not be changed"
            a.informativeText = error.localizedDescription + "\nInstall Utilipilled in Applications first. You can also add it in System Settings → General → Login Items."
            a.runModal()
        }
        render()
    }
    @objc private func soundSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        trace("Termination requested")
        keepAwake.suspend()
        guard engine != nil else { return .terminateNow }
        if quitting { return .terminateLater }
        quitting = true
        engine.stop { error in
            trace("Stop callback reached")
            if let error = error {
                let a = NSAlert(); a.messageText = "Sounds could not be restored"
                a.informativeText = error.localizedDescription + "\nThe recovery record was kept. Set Alert volume in Sound settings, or relaunch Utilipilled to retry."
                a.runModal()
            }
            trace("Replying to Cocoa termination")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
