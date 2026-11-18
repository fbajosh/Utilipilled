import AppKit
import ApplicationServices

// No shortcut preferences are changed. A disabled/removed/dead tap lets the native
// shortcut through. No key contents are recorded, including in debug mode.
final class KeyboardInterceptor {
    var begin: ((Bool) -> Bool)?
    var isSwitching: (() -> Bool)?
    var move: ((Int) -> Void)?
    var finish: ((Bool) -> Void)?
    var cancel: (() -> Void)?
    var quitSelected: (() -> Void)?
    var overview: (() -> Void)?
    var hideSelected: (() -> Void)?
    var point: ((CGPoint, Bool) -> Bool)?
    var onFailure: (() -> Void)?
    var hasPermission: () -> Bool = { AXIsProcessTrusted() }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumedKeys: Set<Int64> = []
    private var consumedClick = false
    var isRunning: Bool { tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        stop()
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<KeyboardInterceptor>.fromOpaque(info).takeUnretainedValue()
                return owner.intercept(type, event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return isRunning
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; consumedKeys = []; consumedClick = false
    }

    func intercept(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Do not automatically re-enable a failing interceptor.
            DispatchQueue.main.async { [weak self] in self?.stop(); self?.onFailure?() }
            return false
        }
        if type == .keyUp {
            return consumedKeys.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil
        }
        if type == .leftMouseUp, consumedClick { consumedClick = false; return true }
        let active = isSwitching?() ?? false
        if type == .flagsChanged {
            if active && !event.flags.contains(.maskCommand) { finish?(event.flags.contains(.maskAlternate)) }
            return false
        }
        if active && (type == .mouseMoved || type == .leftMouseDown) {
            let hit = point?(event.location, type == .leftMouseDown) ?? false
            if type == .leftMouseDown {
                if !hit { cancel?() }
                consumedClick = true
                return true
            }
            return false
        }
        guard type == .keyDown else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        // Releasing Command before a held Tab must not leak subsequent plain-Tab
        // repeats into the newly activated application. The physical key-up clears it.
        if !active && consumedKeys.contains(key) && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
        let command = event.flags.contains(.maskCommand)
        let backward = event.flags.contains(.maskShift)
        if key == 48 && command && !event.flags.contains(.maskControl) {
            if active { move?(backward ? -1 : 1) }
            else {
                guard hasPermission() else {
                    DispatchQueue.main.async { [weak self] in self?.stop(); self?.onFailure?() }
                    return false
                }
                guard begin?(backward) == true else { return false }
            }
            consumedKeys.insert(key); return true
        }
        guard active else { return false }
        guard command else { cancel?(); return false }
        // Preserve system combinations such as Control-Command-Q (lock) and
        // Option-Command-Escape (Force Quit), including during a session.
        if event.flags.contains(.maskControl) || (key == 53 && event.flags.contains(.maskAlternate)) {
            cancel?(); return false
        }
        // Use the current keyboard layout for character commands. Fixed navigation
        // keys retain their hardware codes; text itself is neither retained nor logged.
        let character = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()
        if character == "q" || character == "h" {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                if character == "q" { quitSelected?() } else { hideSelected?() }
            }
            consumedKeys.insert(key); return true
        }
        if character == "." {
            cancel?(); consumedKeys.insert(key); return true
        }
        if character == "`" || character == "~" {
            move?(-1); consumedKeys.insert(key); return true
        }
        switch key {
        case 50 where character == nil || character == "": move?(-1)
        case 123: move?(-1)
        case 124: move?(1)
        case 53: cancel?()
        case 47 where character == nil || character == "": cancel?()
        case 36, 76: finish?(event.flags.contains(.maskAlternate))
        case 12 where character == nil || character == "": if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { quitSelected?() }
        case 4 where character == nil || character == "": if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { hideSelected?() }
        case 125, 126: overview?()
        default: return false
        }
        consumedKeys.insert(key); return true
    }

    deinit { stop() }
}
