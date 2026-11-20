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
    private var policyTimer: Timer?
    private var icons: [URL: NSImage] = [:]
    private let runningApplications: () -> [NSRunningApplication]
    private var generation = 0

    init(runningApplications: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }) {
        self.runningApplications = runningApplications
    }

    func start() {
        guard observers.isEmpty else { return }
        let token = generation
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let activated = name == NSWorkspace.didActivateApplicationNotification
                    ? (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier : nil
                // Finish AppKit's running-application callback before replacing
                // application objects or notifying the menu/controller.
                RunLoop.main.perform(inModes: [.common]) { [weak self] in
                    guard let self, self.generation == token, !self.observers.isEmpty else { return }
                    self.refresh(activated: activated)
                }
            })
        }
        refresh(initialOrder: NativeSwitcherServices.shared.initialApplicationOrder())
        // Avoid per-process activationPolicy KVO on short-lived application
        // objects: repeated crash reports end in AppKit's
        // runningApplicationNotificationCallback. Keep registry mutation out of
        // that callback and use no per-process observers.
        // Workspace notifications handle normal changes; polling also catches apps
        // that become user-facing after their launch notification.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshEligibility() }
        timer.tolerance = 0.5
        policyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh(initialOrder: [pid_t]? = nil, activated: pid_t? = nil) {
        if initialOrder != nil {
            history = ApplicationHistory(); nativeOrderAvailable = true
        }
        let running = runningApplications()
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

    func refreshEligibility() {
        let eligible = Set(runningApplications().filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleIdentifier != nil
        }.map(\.processIdentifier))
        if eligible != Set(applications.keys) { refresh() }
    }

    func stop() {
        generation += 1
        policyTimer?.invalidate(); policyTimer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    deinit { stop() }
}
