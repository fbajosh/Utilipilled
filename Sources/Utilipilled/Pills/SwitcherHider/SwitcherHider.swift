import AppKit
import ApplicationServices

final class SwitcherHiderPill: NSObject, NSMenuDelegate {
    let appsMenu = NSMenu()
    private let defaults: UserDefaults
    private let registry = ApplicationRegistry()
    private let exclusions: ExclusionStore
    private let keyboard: SwitcherKeyboardInterception
    private let availability: SwitcherAvailability
    private let controller: SwitcherController
    private var observers: [NSObjectProtocol] = []
    private var menuIsOpen = false
    private var started = false
    private var appearanceObserver: NSKeyValueObservation?
    private(set) var enabled = false
    private(set) var errorMessage: String?
    var onChange: (() -> Void)?
    var onEvent: ((SwitcherEvent) -> Void)? {
        didSet { controller.onEvent = onEvent }
    }

    init(defaults: UserDefaults = .standard, keyboard: SwitcherKeyboardInterception = KeyboardInterceptor(),
         availability: SwitcherAvailability = .system) {
        self.defaults = defaults; self.keyboard = keyboard; self.availability = availability
        let exclusions = ExclusionStore(defaults: defaults)
        self.exclusions = exclusions
        controller = SwitcherController(registry: registry, exclusions: exclusions)
        super.init()
        appsMenu.delegate = self
        registry.onChange = { [weak self] in
            guard let self else { return }
            self.exclusions.refresh(self.registry.applications.values.map(\.record))
            self.controller.refresh()
            if self.menuIsOpen { self.menuNeedsUpdate(self.appsMenu) }
            self.onChange?()
        }
        keyboard.begin = { [weak self] in self?.controller.begin(backward: $0) ?? false }
        keyboard.isSwitching = { [weak self] in self?.controller.session.isActive ?? false }
        keyboard.move = { [weak self] in self?.controller.move($0) }
        keyboard.finish = { [weak self] in self?.controller.finish(restoreMinimized: $0) }
        keyboard.cancel = { [weak self] in self?.controller.cancel() }
        keyboard.quitSelected = { [weak self] in self?.controller.quitSelected() }
        keyboard.overview = { [weak self] in self?.controller.overview() }
        keyboard.hideSelected = { [weak self] in self?.controller.hideSelected() }
        keyboard.point = { [weak self] in self?.controller.point($0, click: $1) ?? false }
        keyboard.onFailure = { [weak self] in self?.failed("Keyboard interception stopped. The native switcher is available; enable SwitcherMogged again to retry.") }
    }

    func start() {
        guard !started else { return }
        started = true
        registry.start()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.resume() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.controller.cancel() })
        observers.append(center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.controller.refreshAppearance() })
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.controller.refreshAppearance() }
        }
        resume()
    }

    func setEnabled(_ value: Bool) {
        if !value {
            defaults.set(false, forKey: "switcherHider.enabled")
            errorMessage = nil; suspend(); return
        }
        guard availability.supported() else {
            failed("SwitcherMogged's development preview currently supports macOS 26 on Apple silicon. macOS's native switcher remains available.")
            return
        }
        // Only an explicit Enable action is allowed to prompt. Launch/wake never prompt.
        guard availability.trusted() else {
            availability.requestPermission()
            failed("Allow Utilipilled in System Settings → Privacy & Security → Accessibility, then choose Enable again. The native switcher remains available.")
            return
        }
        defaults.set(true, forKey: "switcherHider.enabled")
        resume()
    }

    func suspend() {
        keyboard.stop(); controller.cancel(); enabled = false; onChange?()
    }

    private func resume() {
        guard defaults.bool(forKey: "switcherHider.enabled") else { return }
        guard availability.supported(), availability.nativeInterfacesAvailable(), availability.trusted() else {
            failed("SwitcherMogged is unavailable on this configuration or needs Accessibility access. The native switcher remains available.")
            return
        }
        registry.refresh(initialOrder: registry.nativeOrderAvailable ? nil : NativeSwitcherServices.shared.initialApplicationOrder())
        guard registry.nativeOrderAvailable else {
            failed("macOS could not supply its application ordering. The native switcher remains available."); return
        }
        guard keyboard.start() else {
            keyboard.stop()
            failed("macOS could not create the keyboard interceptor. Check Accessibility access and enable again. The native switcher remains available.")
            return
        }
        enabled = true; errorMessage = nil; onChange?()
    }

    private func failed(_ message: String) {
        defaults.set(false, forKey: "switcherHider.enabled")
        errorMessage = message; suspend()
    }

    func checkAvailability() {
        if enabled && (!availability.trusted() || !keyboard.isRunning) {
            failed("SwitcherMogged lost keyboard access. The native switcher is available; check Accessibility access and enable again.")
        }
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Multiple running instances share one exclusion preference/menu entry.
        var running: [String: SwitcherApplication] = [:]
        for application in registry.ordered(excluding: []) {
            if running[application.record.bundleIdentifier] == nil { running[application.record.bundleIdentifier] = application }
        }
        func sorted(_ values: [ExcludedApplication]) -> [ExcludedApplication] {
            values.sorted {
                let result = $0.displayName.localizedStandardCompare($1.displayName)
                return result == .orderedSame ? $0.bundleIdentifier < $1.bundleIdentifier : result == .orderedAscending
            }
        }
        func add(_ record: ExcludedApplication) {
            let entry = menu.addItem(withTitle: record.displayName, action: #selector(toggleApplication(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = record
            entry.state = exclusions.identifiers.contains(record.bundleIdentifier) ? .on : .off
        }
        func section(_ title: String) {
            if #available(macOS 14.0, *) { menu.addItem(.sectionHeader(title: title)) }
            else {
                let header = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
                header.isEnabled = false
            }
        }
        section("Running")
        for record in sorted(running.values.map(\.record)) { add(record) }
        if running.isEmpty { menu.addItem(withTitle: "None", action: nil, keyEquivalent: "") }
        let stopped = exclusions.records.values.filter { running[$0.bundleIdentifier] == nil }
        menu.addItem(.separator())
        section("Not running")
        for record in sorted(Array(stopped)) { add(record) }
        if stopped.isEmpty { menu.addItem(withTitle: "None", action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        section("Show hidden apps")
        for setting in HiddenAppReveal.allCases {
            let entry = menu.addItem(withTitle: setting.title, action: #selector(setShowAfter(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = setting.rawValue
            entry.state = exclusions.showAfter == setting ? .on : .off
        }
    }

    @objc private func setShowAfter(_ sender: NSMenuItem) {
        guard let setting = HiddenAppReveal(rawValue: sender.tag) else { return }
        exclusions.showAfter = setting
        menuNeedsUpdate(appsMenu)
    }

    @objc private func toggleApplication(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? ExcludedApplication else { return }
        exclusions.toggle(record); controller.refresh()
        onChange?()
    }

    func hideAppsMenuTitle(maximumWidth: CGFloat) -> String {
        let hiddenIDs = exclusions.identifiers
        var running: [String: String] = [:]
        for application in registry.ordered(excluding: []) where hiddenIDs.contains(application.record.bundleIdentifier) {
            running[application.record.bundleIdentifier] = application.record.displayName
        }
        let names = running.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return Self.hideAppsMenuTitle(names: names, maximumWidth: maximumWidth)
    }

    static func hideAppsMenuTitle(names: [String], maximumWidth: CGFloat) -> String {
        let countTitle = "Hide apps: \(names.count)"
        guard !names.isEmpty else { return countTitle }
        let namesTitle = "Hide apps: " + names.joined(separator: ", ")
        let width = (namesTitle as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        return width <= maximumWidth ? namesTitle : countTitle
    }

    deinit {
        keyboard.stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
