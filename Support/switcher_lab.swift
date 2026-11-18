import AppKit
import ApplicationServices

@main
enum SwitcherLab {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = SwitcherLabDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class SwitcherLabDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let pill = SwitcherHiderPill()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let metrics = NSTextField(wrappingLabelWithString: "No switching sessions recorded.")
    private var toggle: NSButton!
    private var events: [SwitcherEvent] = []
    private var refreshPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = menu.addItem(withTitle: "Switcher Lab", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Switcher Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let apps = menu.addItem(withTitle: "Hide apps", action: nil, keyEquivalent: "")
        apps.submenu = pill.appsMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 390),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Switcher Hider Lab"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Switcher Hider")
        title.font = .boldSystemFont(ofSize: 24)
        let detail = NSTextField(wrappingLabelWithString: "Isolated development app. Only the switcher runs here. Saved exclusions and permission grants belong to this lab app.")
        toggle = NSButton(title: "Enable", target: self, action: #selector(togglePill))
        let clear = NSButton(title: "Clear measurements", target: self, action: #selector(clearMeasurements))
        let export = NSButton(title: "Save measurements", target: self, action: #selector(exportMeasurements))
        let buttons = NSStackView(views: [toggle, clear, export]); buttons.orientation = .horizontal; buttons.spacing = 12
        let instructions = NSTextField(wrappingLabelWithString: "Use Hide apps in the menu bar to choose apps and when to reveal them. Hold Command and press Tab to switch; Escape cancels. Up/Down requests App Exposé. Option-release sends the selected app its normal reopen event.\n\nMeasurements report AppKit processing, not physical display latency. Native comparisons and manual recovery checks are still required.")
        metrics.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let stack = NSStackView(views: [title, detail, buttons, status, metrics, instructions])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        pill.onChange = { [weak self] in self?.render() }
        pill.onEvent = { [weak self] event in
            guard let self else { return }
            // Only semantic switcher events, with no app identities or raw key data.
            self.events.append(event)
            if self.events.count > 8192 { self.events.removeFirst(4096) }
            guard !self.refreshPending else { return }
            self.refreshPending = true
            DispatchQueue.main.async { [weak self] in self?.refreshPending = false; self?.render() }
        }
        pill.start(); render()
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func render() {
        guard toggle != nil else { return }
        toggle.title = pill.enabled ? "Disable" : "Enable"
        status.stringValue = pill.errorMessage ?? (pill.enabled ? "Enabled — test Command-Tab now." : "Disabled — the native switcher remains available.")
        let committed = events.filter { $0.kind == .commit }.count
        let shown = events.filter { $0.kind == .presentation }.count
        let rejected = events.filter { $0.kind == .activationRejected }.count
        let confirmed = events.filter { $0.kind == .activationConfirmed }.count
        let unconfirmed = events.filter { $0.kind == .activationUnconfirmed }.count
        metrics.stringValue = "Invocations: \(events.filter { $0.kind == .invocation }.count)   Presented: \(shown)   Commits: \(committed)\nAPI refusals: \(rejected)   Focus confirmed: \(confirmed)   Unconfirmed: \(unconfirmed)\nRecorded events: \(events.count)\nAccessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")"
    }

    @objc private func togglePill() { pill.setEnabled(!pill.enabled); render() }
    @objc private func clearMeasurements() { events = []; render() }
    @objc private func exportMeasurements() {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("switcher-measurements.json")
        let data: [String: Any] = [
            "schema": 1,
            "clock": "DispatchTime.uptimeNanoseconds",
            "measurement": "AppKit submission; not physical display latency",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "events": events.map { ["kind": $0.kind.rawValue, "time": $0.time, "session": $0.session] as [String: Any] }
        ]
        do {
            try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            status.stringValue = "Saved switcher-measurements.json beside the lab app."
        }
        catch { let alert = NSAlert(error: error); alert.runModal() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { pill.suspend(); return .terminateNow }
}
