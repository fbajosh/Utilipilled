import AppKit

// Read-only desktop integration checks. No tap, prompts, app activation or visible
// windows. All preference writes use a disposable suite.
@main enum SwitcherIntegrationChecks {
    static func main() {
        _ = NSApplication.shared
        let suiteName = "local.Utilipilled.SwitcherIntegration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let services = NativeSwitcherServices.shared
        precondition(services.supportsInitialOrder && services.supportsOverview && NativeSwitcherGlass.isAvailable)
        precondition(!NativeSwitcherGlass.configure(NSView(), role: .container))
        guard let nativeOrder = services.initialApplicationOrder() else { fatalError("Native application order unavailable") }
        precondition(Set(nativeOrder).count == nativeOrder.count)
        let registry = ApplicationRegistry()
        registry.start()
        precondition(!registry.applications.isEmpty)
        precondition(Set(registry.history.order) == Set(registry.applications.keys))
        precondition(registry.applications.values.allSatisfy { $0.process.activationPolicy == .regular && !$0.process.isTerminated })
        let exclusions = ExclusionStore(defaults: defaults)
        let running = registry.ordered(excluding: [])
        let first = running[0]
        exclusions.toggle(first.record)
        precondition(!registry.ordered(excluding: exclusions.identifiers).contains { $0.pid == first.pid })
        exclusions.toggle(first.record)
        precondition(registry.ordered(excluding: exclusions.identifiers).map(\.pid) == running.map(\.pid))
        for name in ["Zulu", "Alpha"] {
            exclusions.toggle(ExcludedApplication(bundleIdentifier: "local.Utilipilled.Fake.\(name)", displayName: name, applicationURL: nil))
        }
        let pill = SwitcherHiderPill(defaults: defaults)
        pill.start()
        precondition(!pill.enabled && !defaults.bool(forKey: "switcherHider.enabled"))
        pill.menuNeedsUpdate(pill.appsMenu)
        let separators = pill.appsMenu.items.indices.filter { pill.appsMenu.items[$0].isSeparatorItem }
        precondition(separators.count == 2)
        let separator = separators[0]
        precondition(pill.appsMenu.items[0].title == "Running")
        precondition(pill.appsMenu.items[separator + 1].title == "Not running")
        precondition(pill.appsMenu.items[separators[1] + 1].title == "Show hidden apps")
        let stopped = Array(pill.appsMenu.items[(separator + 2)..<separators[1]])
        precondition(stopped.map(\.title) == ["Alpha", "Zulu"])
        precondition(stopped.allSatisfy { $0.state == .on })
        let titles = pill.appsMenu.items[1..<separator].map(\.title)
        precondition(titles == titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        let choices = Array(pill.appsMenu.items[(separators[1] + 2)...])
        precondition(choices.map(\.title) == ["At end of first cycle", "After start of second cycle", "At end of second cycle", "Never"])
        precondition(choices.filter { $0.state == .on }.map(\.title) == ["Never"])
        pill.appsMenu.performActionForItem(at: separators[1] + 3)
        precondition(ExclusionStore(defaults: defaults).showAfter == .startOfSecondCycle)
        precondition(pill.appsMenu.items.filter { $0.state == .on && $0.action == choices[1].action }.map(\.title) == ["After start of second cycle"])
        precondition(pill.hideAppsMenuTitle(maximumWidth: 1000) == "Hide apps: 0")
        let namesTitle = "Hide apps: Messages, Spotify"
        let namesWidth = (namesTitle as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        precondition(SwitcherHiderPill.hideAppsMenuTitle(names: ["Messages", "Spotify"], maximumWidth: namesWidth) == namesTitle)
        precondition(SwitcherHiderPill.hideAppsMenuTitle(names: ["Messages", "Spotify"], maximumWidth: namesWidth - 1) == "Hide apps: 2")
        precondition(SwitcherHiderPill.hideAppsMenuTitle(names: ["A very long app name"], maximumWidth: 1) == "Hide apps: 1")
        pill.appsMenu.performActionForItem(at: separator + 2)
        pill.menuNeedsUpdate(pill.appsMenu)
        precondition(!pill.appsMenu.items.contains { $0.title == "Alpha" })
        precondition(ExclusionStore(defaults: defaults).records.count == 1)
        pill.setEnabled(false)
        precondition(ExclusionStore(defaults: defaults).records.count == 1)
        if let screen = NSScreen.main {
            let panel = SwitcherPanel()
            panel.prepare(running, selected: first.pid, screen: screen)
            let strip: NSView
            precondition(panel.contentView === panel.containerMaterial)
            precondition(panel.containerMaterial.layer?.mask == nil)
            if #available(macOS 26.0, *), let glass = panel.containerMaterial as? NSGlassEffectView {
                precondition((glass.value(forKey: "_variant") as? NSNumber)?.intValue == 3)
                strip = glass.contentView!
            } else { strip = panel.contentView!.subviews.first! }
            precondition(strip.accessibilityChildren()?.count == running.count)
            precondition(strip.accessibilitySelectedChildren()?.count == 1)
            precondition(!panel.isVisible && !panel.canBecomeKey)
            let independent = SwitcherPanel(independentSelection: true)
            independent.prepare(running, selected: first.pid, screen: screen)
            let independentStrip = independent.contentView!.subviews.last!
            precondition(independentStrip.superview === independent.containerMaterial.superview)
            precondition(independentStrip.accessibilityChildren()?.count == running.count)
            precondition(independent.containerMaterial.layer?.mask == nil)
            if #available(macOS 26.0, *), let bar = independent.containerMaterial as? NSGlassEffectView {
                precondition(bar.contentView != nil && bar.contentView !== independentStrip)
            }
            let singleBlur = SwitcherPanel(independentSelection: true, selectionAddsBlur: false)
            singleBlur.prepare(running, selected: first.pid, screen: screen)
            func selectionView(_ view: NSView) -> NSView? {
                if view.identifier?.rawValue == "switcher-selection-glass" { return view }
                return view.subviews.lazy.compactMap(selectionView).first
            }
            let highlight = selectionView(singleBlur.contentView!)!
            precondition(!(highlight is NSVisualEffectView))
            if #available(macOS 26.0, *) { precondition(!(highlight is NSGlassEffectView)) }
            precondition(highlight.layer?.filters?.isEmpty ?? true)
            precondition(highlight.layer?.backgroundFilters?.isEmpty ?? true)
        }
        let controller = SwitcherController(registry: registry, exclusions: exclusions)
        var events: [SwitcherEvent.Kind] = []
        controller.onEvent = { events.append($0.kind) }
        controller.refresh()
        precondition(controller.begin(backward: false))
        controller.finish(restoreMinimized: false)
        controller.cancel() // Invalidate the queued activation before the run loop runs.
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        precondition(!controller.session.isActive && !events.contains(.activationAccepted) && !events.contains(.activationRejected))
        let revealStore = ExclusionStore(defaults: defaults)
        let previousReveal = revealStore.showAfter
        let hiddenRecord = running.last!.record
        revealStore.toggle(hiddenRecord)
        revealStore.showAfter = .endOfFirstCycle
        let summaryPill = SwitcherHiderPill(defaults: defaults)
        summaryPill.start()
        precondition(summaryPill.hideAppsMenuTitle(maximumWidth: 10000) == "Hide apps: " + hiddenRecord.displayName)
        let revealController = SwitcherController(registry: registry, exclusions: revealStore)
        revealController.refresh()
        let visible = registry.ordered(excluding: revealStore.identifiers)
        let hiddenPIDs = Set(running.filter { revealStore.identifiers.contains($0.record.bundleIdentifier) }.map(\.pid))
        precondition(revealController.begin(backward: false))
        let initialStep = visible.contains { $0.pid == registry.frontmost } ? 1 : 0
        for _ in 0..<max(0, visible.count - initialStep) { revealController.move(1) }
        precondition(revealController.session.hasRevealedHiddenApplications)
        precondition(hiddenPIDs.contains(revealController.session.selected!))
        revealController.refresh()
        precondition(hiddenPIDs.isSubset(of: Set(revealController.session.applications)))
        revealController.cancel()
        precondition(!revealController.session.hasRevealedHiddenApplications)
        revealStore.toggle(hiddenRecord)
        revealStore.showAfter = previousReveal
        lifecycle(defaults: defaults)
        print("Switcher integration passed: native order, registry eligibility, menu sections/toggling, disabled persistence, accessibility and cancellation of queued activation, permission gating and interceptor failure fallback")
    }
    static func lifecycle(defaults: UserDefaults) {
        defaults.set(false, forKey: "switcherHider.enabled")
        var trusted = false
        var supported = true
        var available = true
        var prompts = 0
        let availability = SwitcherAvailability(supported: { supported }, trusted: { trusted },
            requestPermission: { prompts += 1 }, nativeInterfacesAvailable: { available })
        let tap = FakeSwitcherKeyboard()
        let pill = SwitcherHiderPill(defaults: defaults, keyboard: tap, availability: availability)
        pill.start()
        precondition(!pill.enabled && prompts == 0 && tap.starts == 0)
        pill.setEnabled(true)
        precondition(prompts == 1 && !pill.enabled && tap.starts == 0)
        trusted = true; supported = false
        pill.setEnabled(true)
        precondition(prompts == 1 && !pill.enabled && tap.starts == 0)
        supported = true; available = false
        pill.setEnabled(true)
        precondition(!pill.enabled && tap.starts == 0)
        available = true; tap.canStart = false
        pill.setEnabled(true)
        precondition(!pill.enabled && !defaults.bool(forKey: "switcherHider.enabled") && tap.starts == 1)
        tap.canStart = true; pill.setEnabled(true)
        precondition(pill.enabled && tap.isRunning)
        pill.suspend()
        precondition(!pill.enabled && !tap.isRunning && defaults.bool(forKey: "switcherHider.enabled"))
        pill.setEnabled(true)
        tap.onFailure?()
        precondition(!pill.enabled && !tap.isRunning && !defaults.bool(forKey: "switcherHider.enabled"))
        pill.setEnabled(true); trusted = false
        pill.checkAvailability()
        precondition(!pill.enabled && !tap.isRunning && !defaults.bool(forKey: "switcherHider.enabled") && prompts == 1)
        precondition(ExclusionStore(defaults: defaults).records.count == 1)
        // A saved-enabled launch with revoked permission must fail without prompting.
        defaults.set(true, forKey: "switcherHider.enabled")
        let relaunchTap = FakeSwitcherKeyboard()
        let relaunch = SwitcherHiderPill(defaults: defaults, keyboard: relaunchTap, availability: availability)
        relaunch.start()
        precondition(!relaunch.enabled && prompts == 1 && relaunchTap.starts == 0)
    }

}

private final class FakeSwitcherKeyboard: SwitcherKeyboardInterception {
    var begin: ((Bool) -> Bool)?
    var isSwitching: (() -> Bool)?
    var move: ((Int) -> Void)?
    var finish: ((Bool) -> Void)?
    var cancel: (() -> Void)?
    var quitSelected: (() -> Void)?
    var hideSelected: (() -> Void)?
    var overview: (() -> Void)?
    var point: ((CGPoint, Bool) -> Bool)?
    var onFailure: (() -> Void)?
    var isRunning = false
    var canStart = true
    var starts = 0
    func start() -> Bool { starts += 1; isRunning = canStart; return canStart }
    func stop() { isRunning = false }
}
