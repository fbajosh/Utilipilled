import AppKit

struct SwitcherApplication {
    let process: NSRunningApplication
    let record: ExcludedApplication
    let icon: NSImage
    var pid: pid_t { process.processIdentifier }
}

final class ApplicationRegistry {
    private(set) var applications: [pid_t: SwitcherApplication] = [:]
    private(set) var history = ApplicationHistory()
    private(set) var nativeOrderAvailable = false
    private(set) var frontmost: pid_t?
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var policyObservers: [pid_t: NSKeyValueObservation] = [:]
    private var icons: [URL: NSImage] = [:]

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let activated = name == NSWorkspace.didActivateApplicationNotification
                    ? (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier : nil
                self?.refresh(activated: activated)
            })
        }
        refresh(initialOrder: NativeSwitcherServices.shared.initialApplicationOrder())
    }

    func refresh(initialOrder: [pid_t]? = nil, activated: pid_t? = nil) {
        if initialOrder != nil {
            history = ApplicationHistory(); nativeOrderAvailable = true
        }
        let running = NSWorkspace.shared.runningApplications
        let live = Set(running.map(\.processIdentifier))
        policyObservers = policyObservers.filter { live.contains($0.key) }
        // Applications may become user-facing after their launch notification.
        for app in running where policyObservers[app.processIdentifier] == nil {
            policyObservers[app.processIdentifier] = app.observe(\.activationPolicy) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        var next: [pid_t: SwitcherApplication] = [:]
        for app in running where app.activationPolicy == .regular && !app.isTerminated {
            guard let bundle = app.bundleIdentifier else { continue }
            let name = app.localizedName ?? bundle
            let icon: NSImage
            if let url = app.bundleURL {
                icon = icons[url] ?? app.icon ?? NSWorkspace.shared.icon(forFile: url.path)
                icons[url] = icon
            } else {
                icon = app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 128, height: 128))
            }
            next[app.processIdentifier] = SwitcherApplication(process: app,
                record: ExcludedApplication(bundleIdentifier: bundle, displayName: name, applicationURL: app.bundleURL), icon: icon)
        }
        applications = next
        let urls = Set(next.values.compactMap { $0.record.applicationURL })
        icons = icons.filter { urls.contains($0.key) }
        // Seed from LaunchServices once, then maintain history from activation events.
        // A PID-order fallback remains available to diagnostics on unsupported systems.
        let seed = (initialOrder ?? []).filter { next[$0] != nil } + next.keys.sorted().filter { !(initialOrder ?? []).contains($0) }
        frontmost = activated ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        history.synchronize(seed, frontmost: frontmost)
        onChange?()
    }

    func ordered(excluding identifiers: Set<String>) -> [SwitcherApplication] {
        history.order.compactMap { applications[$0] }.filter { !identifiers.contains($0.record.bundleIdentifier) }
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
