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
// Preserve the pill's recovery namespace and lock across the original app rename.
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private var item: NSStatusItem!
    private var engine: CameraQuietPill!
    private let keepAwake = KeepAwakePill()
    private let percentageHider = PercentageHiderPill()
    private let switcherHider = SwitcherHiderPill()
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
    private var workModeItem: NSMenuItem!
    private var workMode = UserDefaults.standard.bool(forKey: "workMode")
    private var pillHeadings: [NSMenuItem] = []
    private var pillNames: [String] {
        workMode
            ? ["Mute notifications on video", "Keep screen awake", "Hide battery info", "Organize switcher apps"]
            : ["NotificationRot", "CaffeinePilled", "PowerYeeted", "SwitcherMogged"]
    }
    private var claudeLabel: String { workMode ? "Claude usage target" : "ClaudeMaxxing" }
    private var clipboardLabel: String { workMode ? "Clipboard length" : SkibidiClipboard.label }
    private var titleItem: NSMenuItem!
    private var durationItem: NSMenuItem!
    private var percentageItem: NSMenuItem!
    private var percentageShortcutItem: NSMenuItem!
    private var thresholdItem: NSMenuItem!
    private var percentageErrorItem: NSMenuItem!
    private var switcherItem: NSMenuItem!
    private var switcherAppsItem: NSMenuItem!
    private var claudeTargetItem: NSMenuItem!
    private var claudeTargetTimer: Timer?
    private var clipboardItem: NSMenuItem!
    private let clipboardQueue = DispatchQueue(label: "Utilipilled.clipboard", qos: .userInitiated)
    private var clipboardRead: DispatchWorkItem?
    private var clipboardRequestID: UUID?
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            lock = try InstanceLock(directory: directory)
            engine = try CameraQuietPill(directory: directory, enabled: enabled)
        } catch {
            let a = NSAlert(); a.messageText = "Utilipilled could not start"; a.informativeText = error.localizedDescription
            a.runModal(); NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Earlier versions persisted a hidden state under AppKit's automatic item name.
        item.autosaveName = "Utilipilled"
        item.isVisible = true
        let menu = NSMenu()
        @discardableResult
        func heading(_ title: String, primary: Bool = false) -> NSMenuItem {
            let entry = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            if primary {
                let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 28))
                let label = NSTextField(labelWithString: title)
                label.font = .boldSystemFont(ofSize: 14)
                label.textColor = .labelColor
                label.frame = NSRect(x: 14, y: 4, width: 222, height: 20)
                view.addSubview(label); entry.view = view
            } else {
                setHeading(entry, title: title)
            }
            return entry
        }
        // These key equivalents belong to the status item's menu, not the
        // application's main menu or a global keyboard handler.
        heading("Utilipilled", primary: true)
        menu.addItem(.separator())
        pillHeadings.append(heading(pillNames[0]))
        toggleItem = menu.addItem(withTitle: "Enable", action: #selector(toggle), keyEquivalent: "n")
        menu.addItem(withTitle: "Restore sounds for this camera session", action: #selector(restore), keyEquivalent: "")
        titleItem = menu.addItem(withTitle: status.title, action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Scope: all system alerts…", action: #selector(soundSettings), keyEquivalent: "")
        menu.addItem(.separator())
        pillHeadings.append(heading(pillNames[1]))
        awakeItem = menu.addItem(withTitle: "Enable", action: #selector(toggleKeepAwake), keyEquivalent: "c")
        durationItem = menu.addItem(withTitle: "Duration", action: nil, keyEquivalent: "")
        let durations = NSMenu()
        for (index, duration) in KeepAwakePill.Duration.allCases.enumerated() {
            let entry = durations.addItem(withTitle: duration.rawValue, action: #selector(selectDuration(_:)), keyEquivalent: "")
            entry.tag = index; entry.target = self
        }
        durationItem.submenu = durations
        menu.addItem(.separator())
        pillHeadings.append(heading(pillNames[2]))
        percentageItem = menu.addItem(withTitle: "Enable", action: #selector(togglePercentageHider),
                                      keyEquivalent: BatteryMenuRow.keyEquivalent)
        percentageShortcutItem = menu.addItem(withTitle: "Toggle battery display",
                                              action: #selector(togglePercentageHider), keyEquivalent: "")
        percentageShortcutItem.isHidden = true
        percentageShortcutItem.allowsKeyEquivalentWhenHidden = true
        thresholdItem = menu.addItem(withTitle: "Threshold", action: nil, keyEquivalent: "")
        let thresholds = NSMenu()
        for value in PercentageHiderPolicy.thresholds {
            let entry = thresholds.addItem(withTitle: "\(value)%", action: #selector(selectPercentageThreshold(_:)), keyEquivalent: "")
            entry.tag = value; entry.target = self
        }
        thresholds.addItem(.separator())
        for (index, mode) in PercentageHiderPill.Mode.allCases.enumerated() {
            let entry = thresholds.addItem(withTitle: mode.rawValue, action: #selector(selectPercentageMode(_:)), keyEquivalent: "")
            entry.tag = index; entry.target = self
        }
        thresholds.addItem(.separator())
        for (index, target) in PercentageHiderPill.Target.allCases.enumerated() {
            let entry = thresholds.addItem(withTitle: target.rawValue, action: #selector(selectPercentageTarget(_:)), keyEquivalent: "")
            entry.tag = index; entry.target = self
        }
        thresholdItem.submenu = thresholds
        percentageErrorItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        percentageErrorItem.isHidden = true
        menu.addItem(.separator())
        pillHeadings.append(heading(pillNames[3]))
        switcherItem = menu.addItem(withTitle: "Enable", action: #selector(toggleSwitcherHider), keyEquivalent: "s")
        switcherAppsItem = menu.addItem(withTitle: "Hide apps: 0", action: nil, keyEquivalent: "")
        switcherAppsItem.submenu = switcherHider.appsMenu
        menu.addItem(.separator())
        claudeTargetItem = menu.addItem(withTitle: ClaudeTarget.title(label: claudeLabel), action: nil, keyEquivalent: "")
        clipboardItem = menu.addItem(withTitle: clipboardLabel, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        heading("Utilipilled")
        loginItem = menu.addItem(withTitle: "Launch at login", action: #selector(login), keyEquivalent: "")
        workModeItem = menu.addItem(withTitle: "Work mode", action: #selector(toggleWorkMode), keyEquivalent: "w")
        menu.addItem(withTitle: "About Utilipilled…", action: #selector(about), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Utilipilled", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items where entry.action != nil { entry.target = self }
        menu.delegate = self
        item.menu = menu
        engine.onStatus = { [weak self] status in self?.status = status; self?.render() }
        keepAwake.onChange = { [weak self] in self?.render() }
        do { try keepAwake.resume() }
        catch {
            let alert = NSAlert(); alert.messageText = "CaffeinePilled could not resume"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
        percentageHider.onChange = { [weak self] in self?.render() }
        switcherHider.onChange = { [weak self] in self?.render() }
        render(); engine.start(); percentageHider.start(); switcherHider.start()
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
    func menuNeedsUpdate(_ menu: NSMenu) {
        percentageHider.refreshBatteryStatus()
        updatePercentageItem()
        switcherHider.checkAvailability()
        updateHiddenAppsTitle()
        claudeTargetItem.title = ClaudeTarget.title(label: claudeLabel)
    }
    func menuWillOpen(_ menu: NSMenu) {
        refreshClipboardReadout()
        claudeTargetTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.claudeTargetItem.title = ClaudeTarget.title(label: self.claudeLabel)
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        claudeTargetTimer = timer
    }
    private func refreshClipboardReadout() {
        clipboardRead?.cancel()
        let label = clipboardLabel
        clipboardItem.title = label + ": checking…"
        let requestID = UUID()
        clipboardRequestID = requestID
        let read = DispatchWorkItem { [weak self] in
            let title = SkibidiClipboard.title(for: .general, label: label)
            RunLoop.main.perform(inModes: [.common, .eventTracking]) { [weak self] in
                guard let self, self.clipboardRequestID == requestID else { return }
                self.clipboardItem.title = title
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        clipboardRead = read
        clipboardQueue.async(execute: read)
    }

    func menuDidClose(_ menu: NSMenu) {
        clipboardRead?.cancel()
        clipboardRead = nil
        clipboardRequestID = nil
        claudeTargetTimer?.invalidate(); claudeTargetTimer = nil
    }
    private func render() {
        item.button?.image = MenuBarIcon.image(active: keepAwake.isEnabled || status.quiet || percentageHider.isHiding || switcherHider.enabled)
        let names = pillNames
        let description = """
        Utilipilled
        \(names[0]): \(menuContinuation(status.title))
        \(names[1]): \(keepAwake.isEnabled ? "on" : "off")
        \(names[2]): \(percentageHider.isHiding ? "hiding" : "not hiding")
        \(names[3]): \(switcherHider.enabled ? "on" : "off")
        """
        item.button?.toolTip = description
        item.button?.setAccessibilityLabel(description)
        titleItem.title = "Status: " + menuContinuation(status.title)
        awakeItem.title = keepAwake.isEnabled ? "Disable" : "Enable"
        toggleItem.title = enabled ? "Disable" : "Enable"
        durationItem.title = "Duration: " + menuContinuation(keepAwake.duration.rawValue)
        for entry in durationItem.submenu?.items ?? [] {
            entry.state = entry.title == keepAwake.duration.rawValue ? .on : .off
        }
        updatePercentageItem()
        thresholdItem.title = "Threshold: \(percentageHider.threshold)%"
        for entry in thresholdItem.submenu?.items ?? [] {
            if entry.action == #selector(selectPercentageThreshold(_:)) {
                entry.state = entry.tag == percentageHider.threshold ? .on : .off
            } else if entry.action == #selector(selectPercentageMode(_:)) {
                entry.state = entry.title == percentageHider.mode.rawValue ? .on : .off
            } else if entry.action == #selector(selectPercentageTarget(_:)) {
                entry.state = entry.title == percentageHider.target.rawValue ? .on : .off
            }
        }
        percentageErrorItem.title = percentageHider.errorMessage ?? ""
        percentageErrorItem.isHidden = percentageHider.errorMessage == nil
        switcherItem.title = switcherHider.enabled ? "Disable" : "Enable"
        updateHiddenAppsTitle()
        switcherItem.toolTip = switcherHider.errorMessage ?? "Development preview; native parity validation is pending."
        workModeItem.state = workMode ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        item.menu?.update()
    }
    private func setHeading(_ entry: NSMenuItem, title: String) {
        entry.title = title
        entry.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    @objc private func toggleWorkMode() {
        workMode.toggle()
        UserDefaults.standard.set(workMode, forKey: "workMode")
        for (entry, title) in zip(pillHeadings, pillNames) { setHeading(entry, title: title) }
        clipboardRead?.cancel()
        clipboardRequestID = nil
        clipboardItem.title = clipboardLabel
        render()
    }

    private func updatePercentageItem() {
        let enabled = percentageHider.enabled
        percentageItem.title = enabled ? "Disable" : "Enable"
        guard enabled, let battery = percentageHider.batteryStatus else {
            percentageShortcutItem.keyEquivalent = ""
            percentageItem.keyEquivalent = BatteryMenuRow.keyEquivalent
            percentageItem.view = nil
            return
        }

        // Let AppKit dispatch the shortcut through a standard item while
        // the visible item uses a custom view for the battery readout.
        percentageItem.keyEquivalent = ""
        percentageShortcutItem.keyEquivalent = BatteryMenuRow.keyEquivalent
        let row = percentageItem.view as? BatteryMenuRow ?? BatteryMenuRow()
        row.update(percentage: "\(Int(battery.level.rounded()))%",
                   charging: battery.charging, onExternalPower: battery.onExternalPower)
        if percentageItem.view !== row { percentageItem.view = row }
    }
    private func menuContinuation(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
    private func updateHiddenAppsTitle() {
        guard let menu = item?.menu, let switcherAppsItem else { return }
        // Fit within the menu's existing text width rather than letting a list
        // of app names stretch the whole menu. Reserve the usual check/arrow area.
        let font = NSFont.menuFont(ofSize: 0)
        let otherWidths = menu.items.filter { $0 !== switcherAppsItem && !$0.isHidden }.map {
            ($0.title as NSString).size(withAttributes: [.font: font]).width
        }
        switcherAppsItem.title = switcherHider.hideAppsMenuTitle(maximumWidth: max(210, otherWidths.max() ?? 0))
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        item.isVisible = true
        render()
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.perform(inModes: [.common]) { self.item.button?.performClick(nil) }
        return false
    }
    @objc private func toggleKeepAwake() {
        do { try keepAwake.setEnabled(!keepAwake.isEnabled) }
        catch {
            let a = NSAlert(); a.messageText = "CaffeinePilled could not be changed"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
        render()
    }
    @objc private func toggle() {
        enabled.toggle(); UserDefaults.standard.set(!enabled, forKey: "cameraQuiet.paused")
        engine.setEnabled(enabled); render()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(restore) || status.cameraActive
    }
    @objc private func restore() {
        guard status.cameraActive else { return }
        engine.restoreNow()
    }
    @objc private func selectDuration(_ sender: NSMenuItem) {
        let values = KeepAwakePill.Duration.allCases
        guard values.indices.contains(sender.tag) else { return }
        do { try keepAwake.setDuration(values[sender.tag]) }
        catch {
            let alert = NSAlert(); alert.messageText = "Duration could not be changed"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
        render()
    }
    @objc private func toggleSwitcherHider() {
        switcherHider.setEnabled(!switcherHider.enabled)
        if let message = switcherHider.errorMessage {
            let alert = NSAlert(); alert.messageText = "SwitcherMogged could not be enabled"
            alert.informativeText = message; alert.runModal()
        }
        render()
    }
    @objc private func togglePercentageHider() {
        percentageHider.setEnabled(!percentageHider.enabled); render()
    }
    @objc private func selectPercentageThreshold(_ sender: NSMenuItem) {
        percentageHider.setThreshold(sender.tag); render()
    }
    @objc private func selectPercentageMode(_ sender: NSMenuItem) {
        let modes = PercentageHiderPill.Mode.allCases
        guard modes.indices.contains(sender.tag) else { return }
        percentageHider.setMode(modes[sender.tag]); render()
    }
    @objc private func selectPercentageTarget(_ sender: NSMenuItem) {
        let targets = PercentageHiderPill.Target.allCases
        guard targets.indices.contains(sender.tag) else { return }
        percentageHider.setTarget(targets[sender.tag]); render()
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
        switcherHider.suspend()
        guard engine != nil else { return .terminateNow }
        if quitting { return .terminateLater }
        quitting = true
        engine.stop { error in
            self.percentageHider.stop { percentageError in
                trace("Stop callback reached")
                if let error = error {
                    let a = NSAlert(); a.messageText = "Sounds could not be restored"
                    a.informativeText = error.localizedDescription + "\nThe recovery record was kept. Set Alert volume in Sound settings, or relaunch Utilipilled to retry."
                    a.runModal()
                }
                if let percentageError {
                    let alert = NSAlert(); alert.messageText = "Battery display could not be restored"
                    alert.informativeText = percentageError.localizedDescription + " Reopen Utilipilled to retry."
                    alert.runModal()
                }
                trace("Replying to Cocoa termination")
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
