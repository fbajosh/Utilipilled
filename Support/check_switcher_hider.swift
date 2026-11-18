import AppKit

@main
enum SwitcherHiderChecks {
    static func main() {
        layout()
        historyAndSession()
        revealCycles()
        revealAfterWrap()
        persistence()
        interception()
        print("Switcher Hider MRU, exclusion/reveal persistence, cycle reveal/reset, session lifecycle, keyboard routing and failure checks passed")
    }

    static func layout() {
        for count in [1, 2, 5, 10, 30, 100] {
            for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 450, width: 1920, height: 1080)] {
                let layout = SwitcherLayout(count: count, screen: screen)
                precondition(screen.contains(layout.frame))
                precondition(abs(layout.frame.midX - screen.midX) < 0.001)
                precondition(abs(layout.frame.midY - screen.midY) < 0.001)
                for index in 0..<count {
                    let tile = layout.tile(at: index)
                    precondition(layout.index(at: CGPoint(x: tile.midX, y: tile.midY)) == index)
                }
                precondition(layout.index(at: .zero) == nil)
                precondition(layout.index(at: CGPoint(x: layout.frame.width - 16, y: 30)) == nil)
                precondition(layout.index(at: CGPoint(x: 20, y: layout.frame.height - 6)) == nil)
            }
        }
        let native = SwitcherLayout(count: 8, screen: CGRect(x: 0, y: 0, width: 1440, height: 932))
        precondition(native.frame == CGRect(x: 164, y: 378, width: 1112, height: 176))
        precondition(native.icon(at: 1).width == 128 && native.selection(at: 1).width == 120)
        precondition(native.tile(at: 2).midX - native.tile(at: 1).midX == 134)
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        precondition(SwitcherLayout.cocoaPoint(fromQuartz: CGPoint(x: -500, y: -150), primaryScreen: primary) == CGPoint(x: -500, y: 1050))
    }

    static func historyAndSession() {
        var history = ApplicationHistory()
        history.synchronize([1, 2, 3], frontmost: 2)
        precondition(history.order == [2, 1, 3])
        history.activate(3)
        history.synchronize([1, 2, 3, 4], frontmost: 3)
        precondition(history.order == [3, 2, 1, 4])
        // Exclusion filtering must not destroy history; re-inclusion recovers its position.
        precondition(history.order.filter { $0 != 2 } == [3, 1, 4])
        precondition(history.order == [3, 2, 1, 4])
        history.synchronize([1, 2, 4], frontmost: 4)
        precondition(history.order == [4, 2, 1])
        var session = SwitcherSession()
        session.begin([4, 2, 1], frontmost: 4, backward: false)
        precondition(session.selected == 2)
        session.move(1); precondition(session.selected == 1)
        session.move(1); precondition(session.selected == 4)
        session.move(-1); precondition(session.selected == 1)
        session.retain([4, 2]); precondition(session.selected == 2)
        session.retain([]); precondition(!session.isActive && session.selected == nil)
        session.begin([4, 2, 1], frontmost: 4, backward: true)
        precondition(session.selected == 1)
        session.begin([2, 1], frontmost: 99, backward: false)
        precondition(session.selected == 2) // excluded foreground
        session.begin([2, 1], frontmost: 99, backward: true)
        precondition(session.selected == 2)
        session.begin([2], frontmost: 2, backward: true)
        session.move(1); precondition(session.selected == 2)
        session.select(99); precondition(session.selected == 2)
        session.end(); precondition(!session.isActive)
        session.begin([], frontmost: 99, backward: false)
        precondition(!session.isActive && session.selected == nil)
    }

    static func persistence() {
        let name = "local.Utilipilled.SwitcherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        precondition(!defaults.bool(forKey: "switcherHider.enabled"))
        let record = ExcludedApplication(bundleIdentifier: "com.apple.MobileSMS", displayName: "Messages",
                                         applicationURL: URL(fileURLWithPath: "/System/Applications/Messages.app"))
        let store = ExclusionStore(defaults: defaults)
        precondition(store.showAfter == .never)
        store.showAfter = .endOfSecondCycle
        precondition(ExclusionStore(defaults: defaults).showAfter == .endOfSecondCycle)
        store.showAfter = .endOfFirstCycle
        precondition(ExclusionStore(defaults: defaults).showAfter == .endOfFirstCycle)
        store.showAfter = .startOfSecondCycle
        precondition(ExclusionStore(defaults: defaults).showAfter == .startOfSecondCycle)
        defaults.set(1, forKey: "switcherHider.showAfter")
        precondition(store.showAfter == .endOfFirstCycle)
        defaults.set(2, forKey: "switcherHider.showAfter")
        precondition(store.showAfter == .endOfSecondCycle)
        defaults.set(99, forKey: "switcherHider.showAfter")
        precondition(store.showAfter == .never)
        store.toggle(record)
        precondition(ExclusionStore(defaults: defaults).records[record.bundleIdentifier] == record)
        let renamed = ExcludedApplication(bundleIdentifier: record.bundleIdentifier, displayName: "Renamed", applicationURL: record.applicationURL)
        store.refresh([renamed]); precondition(store.records[record.bundleIdentifier] == renamed)
        precondition(!defaults.bool(forKey: "switcherHider.enabled")) // preferences work while disabled
        store.toggle(record); precondition(ExclusionStore(defaults: defaults).records.isEmpty)
        defaults.set(Data("corrupt".utf8), forKey: "switcherHider.excludedApps")
        precondition(ExclusionStore(defaults: defaults).records.isEmpty)
        let duplicate = try! JSONEncoder().encode([record, renamed])
        defaults.set(duplicate, forKey: "switcherHider.excludedApps")
        precondition(ExclusionStore(defaults: defaults).records.count == 1)
    }

    static func revealCycles() {
        var session = SwitcherSession()
        for policy in [HiddenAppReveal.endOfFirstCycle, .endOfSecondCycle] {
            for backward in [false, true] {
                session.begin([1, 2, 3], frontmost: 1, backward: backward,
                              hidden: [9, 8, 9, 2], showAfter: policy)
                let direction = backward ? -1 : 1
                for _ in 1..<(3 * policy.rawValue) {
                    precondition(session.applications == [1, 2, 3])
                    session.move(direction)
                }
                precondition(session.applications == [1, 2, 3, 9, 8])
                precondition(session.selected == (backward ? 8 : 9))
                precondition(session.hasRevealedHiddenApplications)
                session.move(direction)
                precondition(session.applications == [1, 2, 3, 9, 8])
                session.end()
                session.begin([1, 2, 3], frontmost: 1, backward: backward,
                              hidden: [9, 8], showAfter: policy)
                precondition(session.applications == [1, 2, 3] && !session.hasRevealedHiddenApplications)
            }
        }
        session.begin([1, 2, 3], frontmost: 1, backward: false, hidden: [9], showAfter: .never)
        session.move(30); precondition(session.applications == [1, 2, 3])
        session.begin([1, 2, 3], frontmost: 1, backward: false, hidden: [9], showAfter: .endOfFirstCycle)
        for _ in 0..<20 { session.move(-1); session.move(1) }
        precondition(!session.hasRevealedHiddenApplications)
        session.move(2); precondition(session.selected == 9)
        session.begin([1, 2, 3], frontmost: 1, backward: false, hidden: [9, 8], showAfter: .endOfSecondCycle)
        session.move(2) // Finish one forward lap.
        precondition(!session.hasRevealedHiddenApplications)
        session.move(-3) // A complete backward lap also counts.
        precondition(session.hasRevealedHiddenApplications && session.selected == 8)
        // Pointer selection restarts progress; a hidden foreground is not counted
        // as a step through an app that was never in the visible strip.
        session.begin([1, 2, 3], frontmost: 1, backward: false, hidden: [9], showAfter: .endOfFirstCycle)
        session.select(3); session.move(2)
        precondition(!session.hasRevealedHiddenApplications)
        session.move(1); precondition(session.selected == 9)
        session.begin([1, 2, 3], frontmost: 9, backward: false, hidden: [9], showAfter: .endOfFirstCycle)
        session.move(2); precondition(!session.hasRevealedHiddenApplications)
        session.move(1); precondition(session.selected == 9)
        // App exit removes deferred candidates and restarts a changed-length lap.
        session.begin([1, 2, 3], frontmost: 1, backward: false, hidden: [9, 8], showAfter: .endOfFirstCycle)
        session.move(1)
        session.retain([1, 2], hiddenEligible: [8])
        session.move(1); precondition(!session.hasRevealedHiddenApplications)
        session.move(1); precondition(session.applications == [1, 2, 8] && session.selected == 8)
        session.retain([1, 8]); precondition(session.selected == 8)
        session.begin([1], frontmost: 1, backward: false, hidden: [9], showAfter: .endOfFirstCycle)
        precondition(session.selected == 9)
        session.begin([], frontmost: 9, backward: false, hidden: [9, 8], showAfter: .endOfSecondCycle)
        precondition(session.selected == 8 && session.hasRevealedHiddenApplications)
        session.begin([], frontmost: 9, backward: false, hidden: [9, 8], showAfter: .never)
        precondition(!session.isActive)
        session.begin([1, 2], frontmost: 1, backward: false, showAfter: .endOfFirstCycle)
        session.move(10); precondition(session.applications == [1, 2] && !session.hasRevealedHiddenApplications)
    }

    static func revealAfterWrap() {
        var session = SwitcherSession()
        for count in [1, 2, 3, 6] {
            let visible = (1...count).map(Int32.init)
            for backward in [false, true] {
                let direction = backward ? -1 : 1
                session.begin(visible, frontmost: 1, backward: backward, hidden: [9, 8], showAfter: .startOfSecondCycle)
                for _ in 1..<count { session.move(direction) }
                precondition(!session.hasRevealedHiddenApplications && session.selected == 1)
                precondition(session.applications == visible) // Full lap wraps normally.
                session.move(direction)
                precondition(session.hasRevealedHiddenApplications)
                precondition(session.selected == (backward ? 8 : 9))
                session.end()
                session.begin(visible, frontmost: 1, backward: backward, hidden: [9, 8], showAfter: .startOfSecondCycle)
                for _ in 1..<count { session.move(direction) }
                session.end() // Release at the wrap must not arm the next session.
                session.begin(visible, frontmost: 1, backward: backward, hidden: [9, 8], showAfter: .startOfSecondCycle)
                precondition(!session.hasRevealedHiddenApplications)
            }
        }
        session.begin([1, 2], frontmost: 1, backward: false, hidden: [9], showAfter: .startOfSecondCycle)
        session.move(1)
        session.retain([1, 2], hiddenEligible: [])
        session.move(1)
        precondition(session.selected == 2 && !session.hasRevealedHiddenApplications)
    }

    static func interception() {
        // Exercise the actual event callback routing without installing a global tap,
        // requesting permissions, posting events, or switching the user's applications.
        let keyboard = KeyboardInterceptor()
        keyboard.hasPermission = { true }
        var session = SwitcherSession()
        var committed: Int32?
        var option = false
        var quits = 0
        var hides = 0
        var overviews = 0
        var failures = 0
        keyboard.begin = { backward in session.begin([1, 2, 3], frontmost: 1, backward: backward); return true }
        keyboard.isSwitching = { session.isActive }
        keyboard.move = { session.move($0) }
        keyboard.cancel = { session.end() }
        keyboard.finish = { option = $0; committed = session.selected; session.end() }
        keyboard.quitSelected = { quits += 1 }
        keyboard.overview = { overviews += 1; session.end() }
        keyboard.hideSelected = { hides += 1 }
        keyboard.onFailure = { failures += 1; session.end() }
        func key(_ code: CGKeyCode, down: Bool = true, flags: CGEventFlags = .maskCommand, repeatKey: Bool = false) -> Bool {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            return keyboard.intercept(down ? .keyDown : .keyUp, event)
        }
        func release(_ flags: CGEventFlags = []) {
            let event = CGEvent(source: nil)!; event.flags = flags
            precondition(!keyboard.intercept(.flagsChanged, event))
        }
        precondition(!key(12)) // Cmd-Q outside switcher passes through
        precondition(!key(48, flags: [.maskCommand, .maskControl]))
        precondition(key(48) && session.selected == 2)
        release(.maskCommand); precondition(session.isActive && committed == nil) // Another Command key is still held.
        precondition(key(48, down: false)) // matching Tab up swallowed
        precondition(key(48, repeatKey: true) && session.selected == 3)
        release(); precondition(committed == 3 && !session.isActive)
        precondition(key(48, flags: [], repeatKey: true) && !session.isActive)
        precondition(key(48, down: false)) // up after dismissal still swallowed
        precondition(!key(48, down: false))
        precondition(key(48, flags: [.maskCommand, .maskShift]) && session.selected == 3)
        precondition(key(50) && session.selected == 2)
        precondition(key(123) && session.selected == 1)
        precondition(key(124) && session.selected == 2)
        precondition(key(12) && key(4)); precondition(quits == 1 && hides == 1)
        precondition(key(12, repeatKey: true)); precondition(quits == 1)
        precondition(!key(0)) // unrelated input passes through unchanged
        release(.maskAlternate); precondition(option && committed == 2)
        precondition(key(48)); precondition(key(53)); precondition(!session.isActive)
        precondition(key(53, down: false)); precondition(!key(50)) // grave outside switcher
        precondition(key(48)); precondition(key(36)); precondition(!session.isActive)
        precondition(key(48)); precondition(key(47)); precondition(!session.isActive)
        precondition(key(47, down: false))
        precondition(key(48))
        precondition(!key(12, flags: [])); precondition(!session.isActive && quits == 1)
        keyboard.begin = { _ in false }
        precondition(!key(48)) // A controller refusing interception preserves native switching.
        keyboard.begin = { backward in session.begin([1, 2, 3], frontmost: 1, backward: backward); return true }
        precondition(key(48)); precondition(key(125)); precondition(overviews == 1 && !session.isActive)
        precondition(key(48)); precondition(key(126)); precondition(overviews == 2 && !session.isActive)
        precondition(key(48))
        precondition(!key(12, flags: [.maskCommand, .maskControl]) && !session.isActive && quits == 1)
        precondition(key(48))
        precondition(!key(53, flags: [.maskCommand, .maskAlternate]) && !session.isActive)
        keyboard.begin = { backward in
            session.begin([1, 2, 3], frontmost: 1, backward: backward,
                          hidden: [9], showAfter: .endOfSecondCycle)
            return true
        }
        precondition(key(48)); precondition(key(48, repeatKey: true))
        release(); precondition(committed == 3 && !session.isActive)
        precondition(key(48) && !session.hasRevealedHiddenApplications)
        for _ in 1..<6 { precondition(key(48, repeatKey: true)) }
        precondition(session.selected == 9 && session.hasRevealedHiddenApplications)
        release(); precondition(committed == 9 && !session.isActive)
        precondition(key(48) && session.applications == [1, 2, 3])
        precondition(key(53) && !session.isActive)
        keyboard.begin = { backward in
            session.begin([1, 2, 3], frontmost: 1, backward: backward,
                          hidden: [9], showAfter: .startOfSecondCycle)
            return true
        }
        precondition(key(48)); precondition(key(48)); precondition(key(48))
        precondition(session.selected == 1 && !session.hasRevealedHiddenApplications)
        release(); precondition(committed == 1)
        precondition(key(48) && session.selected == 2)
        precondition(key(48)); precondition(key(48)); precondition(key(48))
        precondition(session.selected == 9 && session.hasRevealedHiddenApplications)
        release(); precondition(committed == 9)
        keyboard.begin = { backward in session.begin([1, 2, 3], frontmost: 1, backward: backward); return true }
        keyboard.hasPermission = { false }
        precondition(!key(48))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        precondition(failures == 1)
        keyboard.hasPermission = { true }
        precondition(key(48))
        precondition(!keyboard.intercept(.tapDisabledByTimeout, CGEvent(source: nil)!))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        precondition(failures == 2 && !session.isActive && !keyboard.isRunning)
        precondition(!keyboard.intercept(.tapDisabledByUserInput, CGEvent(source: nil)!))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        precondition(failures == 3 && !keyboard.isRunning)
        keyboard.stop()
    }
}
