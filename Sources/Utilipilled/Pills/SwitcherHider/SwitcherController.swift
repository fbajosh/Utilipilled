import AppKit

final class SwitcherController {
    let registry: ApplicationRegistry
    let exclusions: ExclusionStore
    private let panel = SwitcherPanel(independentSelection: true, selectionAddsBlur: false)
    private let activator = ApplicationActivator()
    var onEvent: ((SwitcherEvent) -> Void)?
    private(set) var session = SwitcherSession()
    private var eligible: [SwitcherApplication] = []
    private var hidden: [SwitcherApplication] = []
    private var foreground: pid_t?
    private var generation = 0
    private var eventSession = 0
    private var renderPending = false
    private var screen: NSScreen?
    private var activationObserver: NSObjectProtocol?
    private var activationGeneration = 0

    init(registry: ApplicationRegistry, exclusions: ExclusionStore) {
        self.registry = registry; self.exclusions = exclusions
        panel.onActivate = { [weak self] pid in
            guard let self, self.session.applications.contains(pid) else { return }
            self.session.select(pid); self.finish(restoreMinimized: false)
        }
        panel.onDragSelection = { [weak self] pid in
            self?.session.select(pid); self?.scheduleRender()
        }
        panel.onSpringLoad = { [weak self] pid in
            guard let self, self.session.applications.contains(pid) else { return }
            self.session.select(pid); self.finish(restoreMinimized: false)
        }
        panel.onDrop = { [weak self] urls, pid in self?.drop(urls, on: pid) ?? false }
    }

    func refresh() {
        let all = registry.ordered(excluding: [])
        let excluded = exclusions.identifiers
        eligible = all.filter { !excluded.contains($0.record.bundleIdentifier) }
        hidden = all.filter { excluded.contains($0.record.bundleIdentifier) }
        foreground = registry.frontmost
        if session.isActive {
            session.retain(Set((session.hasRevealedHiddenApplications ? all : eligible).map(\.pid)),
                           hiddenEligible: Set(hidden.map(\.pid)))
            if !session.isActive { cancel() }
            else { scheduleRender() }
        }
    }

    func begin(backward: Bool) -> Bool {
        activator.cancelPendingOverview()
        eventSession += 1; emit(.invocation)
        session.begin(eligible.map(\.pid), frontmost: foreground, backward: backward,
                      hidden: hidden.map(\.pid), showAfter: exclusions.showAfter)
        // Consume an invocation with no eligible apps without exposing excluded apps.
        guard session.isActive else { cancel(); return true }
        generation += 1
        let token = generation
        // The native switcher delays presentation for a quick Cmd-Tab. Activation
        // does not wait for presentation, and a quick release cancels this work.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.session.isActive else { return }
            self.screen = NSScreen.main ?? NSScreen.screens.first
            self.render()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.generation == token, self.session.isActive else { return }
            if self.screen != nil { self.panel.show(); self.emit(.presentation) }
        }
        return true
    }

    func refreshAppearance() { if session.isActive { scheduleRender() } }

    func move(_ delta: Int) { session.move(delta); emit(.selection); scheduleRender() }

    func finish(restoreMinimized: Bool) {
        let application = session.selected.flatMap { registry.applications[$0] }
        emit(.commit)
        cancel()
        let token = generation
        let diagnosticSession = eventSession
        // AppKit/window-server work is kept out of the event tap callback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, let application else { return }
            self.observeActivation(of: application.pid, session: diagnosticSession)
            self.activator.activate(application, restoreMinimized: restoreMinimized) { [weak self] accepted in
                self?.emit(accepted ? .activationAccepted : .activationRejected, session: diagnosticSession)
            }
        }
    }

    func cancel() {
        generation += 1; session.end(); activator.cancelPendingOverview(); emit(.dismissal)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.session.isActive else { return }
            self.panel.dismiss(); self.screen = nil
        }
    }

    private func observeActivation(of pid: pid_t, session: Int) {
        stopObservingActivation()
        guard onEvent != nil else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            emit(.activationConfirmed, session: session); return
        }
        let token = activationGeneration
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, self.activationGeneration == token,
                      let process = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      process.processIdentifier == pid else { return }
                self.stopObservingActivation(); self.emit(.activationConfirmed, session: session)
            }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.activationGeneration == token else { return }
            self.stopObservingActivation(); self.emit(.activationUnconfirmed, session: session)
        }
    }

    private func stopObservingActivation() {
        activationGeneration += 1
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func drop(_ urls: [URL], on pid: pid_t) -> Bool {
        guard session.applications.contains(pid), let application = registry.applications[pid], !urls.isEmpty else { return false }
        emit(.drop); cancel()
        let token = generation
        let diagnosticSession = eventSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.observeActivation(of: pid, session: diagnosticSession)
            self.activator.open(urls, in: application) { [weak self] accepted in
                self?.emit(accepted ? .activationAccepted : .activationRejected, session: diagnosticSession)
            }
        }
        return true
    }

    func overview() {
        let application = session.selected.flatMap { registry.applications[$0] }
        cancel()
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, let application else { return }
            self.activator.showOverview(application) { [weak self] accepted in
                if accepted { self?.emit(.overview) }
            }
        }
    }

    private func emit(_ kind: SwitcherEvent.Kind, session: Int? = nil) {
        if let onEvent { onEvent(SwitcherEvent(kind, session: session ?? eventSession)) }
    }

    func quitSelected() {
        guard let selected = session.selected, let application = registry.applications[selected] else { return }
        DispatchQueue.main.async { [weak self] in self?.activator.quit(application) }
    }

    func hideSelected() {
        guard let selected = session.selected, let application = registry.applications[selected] else { return }
        DispatchQueue.main.async { [weak self] in self?.activator.hide(application) }
    }

    func point(_ point: CGPoint, click: Bool) -> Bool {
        guard let pid = panel.application(at: point), session.applications.contains(pid) else { return false }
        session.select(pid); scheduleRender()
        if click { finish(restoreMinimized: false) }
        return true
    }

    private func scheduleRender() {
        guard !renderPending else { return }
        renderPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderPending = false
            if self.session.isActive { self.render() }
        }
    }

    deinit { stopObservingActivation() }

    private func render() {
        guard let screen else { return }
        let applications = session.applications.compactMap { registry.applications[$0] }
        panel.prepare(applications, selected: session.selected, screen: screen)
        if panel.isVisible { panel.displayIfNeeded(); emit(.render) }
    }
}
