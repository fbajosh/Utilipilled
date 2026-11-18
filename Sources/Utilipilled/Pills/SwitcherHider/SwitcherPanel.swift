import AppKit

final class SwitcherPanel: NSPanel {
    private let tiles: SwitcherTiles
    private let material = makeSwitcherGlass(selection: false)
    var containerMaterial: NSView { material }
    private var applications: [SwitcherPresentation] = []
    private var layout: SwitcherLayout?
    var onDragSelection: ((pid_t) -> Void)? { didSet { tiles.onDragSelection = onDragSelection } }
    var onSpringLoad: ((pid_t) -> Void)? { didSet { tiles.onSpringLoad = onSpringLoad } }
    var onDrop: (([URL], pid_t) -> Bool)? { didSet { tiles.onDrop = onDrop } }
    var onActivate: ((pid_t) -> Void)? { didSet { tiles.onActivate = onActivate } }

    init(independentSelection: Bool = false, selectionAddsBlur: Bool = true) {
        tiles = SwitcherTiles(selectionAddsBlur: selectionAddsBlur)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        ignoresMouseEvents = false // Nonactivating; the tap consumes clicks. AppKit receives native drag sessions.
        animationBehavior = .none
        tiles.autoresizingMask = [.width, .height]
        if independentSelection {
            let root = NSView()
            contentView = root
            material.frame = root.bounds; material.autoresizingMask = [.width, .height]
            if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
                // Keep a real contentView so AppKit still establishes the bar's
                // native backdrop treatment, while the ring lives outside it.
                glass.contentView = NSView()
            }
            root.addSubview(material)
            tiles.frame = root.bounds
            root.addSubview(tiles)
        } else {
            contentView = material
            tiles.frame = material.bounds
            if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
                glass.contentView = tiles
            } else { material.addSubview(tiles) }
        }
        setAccessibilityLabel("Application switcher")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func prepare(_ applications: [SwitcherApplication], selected: pid_t?, screen: NSScreen) {
        prepareItems(applications.map(SwitcherPresentation.init), selected: selected, screenFrame: screen.frame)
    }

    func prepareItems(_ applications: [SwitcherPresentation], selected: pid_t?, screenFrame: CGRect) {
        self.applications = applications
        let layout = SwitcherLayout(count: applications.count, screen: screenFrame)
        if self.layout != layout { setFrame(layout.frame, display: false); self.layout = layout }
        tiles.frame = material.bounds
        tiles.applications = applications; tiles.selected = selected; tiles.layout = layout
        tiles.updateAccessibility()
        let accessibility = NSWorkspace.shared
        tiles.highContrast = accessibility.accessibilityDisplayShouldIncreaseContrast
        let opaque = accessibility.accessibilityDisplayShouldReduceTransparency
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.cornerRadius = layout.cornerRadius
            glass.tintColor = opaque ? .windowBackgroundColor : nil
        } else if let effect = material as? NSVisualEffectView {
            effect.state = opaque ? .inactive : .active
            effect.material = opaque ? .windowBackground : .hudWindow
            effect.layer?.cornerRadius = layout.cornerRadius
        }
        material.layer?.borderWidth = accessibility.accessibilityDisplayShouldIncreaseContrast ? 1 : 0
        material.layer?.borderColor = NSColor.labelColor.cgColor
        tiles.updatePresentation()

    }

    func show() {
        orderFrontRegardless()
        if let selected = tiles.selectedAccessibilityElement {
            NSAccessibility.post(element: selected, notification: .focusedUIElementChanged)
        }
    }
    func dismiss() { orderOut(nil); applications = []; tiles.applications = []; tiles.updateAccessibility() }

    func application(at point: CGPoint) -> pid_t? {
        guard isVisible, let primary = NSScreen.screens.first else { return nil }
        // Quartz's origin is the upper left of the primary screen; AppKit uses its lower left.
        guard let layout else { return nil }
        let location = SwitcherLayout.cocoaPoint(fromQuartz: point, primaryScreen: primary.frame)
        let local = NSPoint(x: location.x - frame.minX, y: location.y - frame.minY)
        guard let index = layout.index(at: local) else { return nil }
        return applications[index].pid
    }
}

private final class SwitcherTiles: NSView, NSSpringLoadingDestination {
    var applications: [SwitcherPresentation] = []
    private let canvas = SwitcherIconCanvas()
    private let selectionMaterial: NSView
    var highContrast = false
    var selected: pid_t?
    var layout: SwitcherLayout?
    var tileSize: CGFloat { layout?.tileWidth ?? 128 }
    var onActivate: ((pid_t) -> Void)?
    private var accessibleTiles: [pid_t: SwitcherAccessibilityTile] = [:]
    var selectedAccessibilityElement: NSAccessibilityElement? { selected.flatMap { accessibleTiles[$0] } }

    func updateAccessibility() {
        guard let layout, let window else { return }
        let current = Set(applications.map(\.pid))
        accessibleTiles = accessibleTiles.filter { current.contains($0.key) }
        var children: [NSAccessibilityElement] = []
        for (index, application) in applications.enumerated() {
            let element = accessibleTiles[application.pid] ?? SwitcherAccessibilityTile()
            element.setAccessibilityRole(.button)
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(application.displayName)
            element.setAccessibilitySelected(application.pid == selected)
            element.setAccessibilityFrame(window.convertToScreen(convert(layout.tile(at: index), to: nil)))
            let pid = application.pid
            element.onPress = { [weak self] in self?.onActivate?(pid) }
            accessibleTiles[pid] = element; children.append(element)
        }
        setAccessibilityElement(true); setAccessibilityRole(.list)
        setAccessibilityLabel("Applications")
        setAccessibilityChildren(children)
        setAccessibilitySelectedChildren(selectedAccessibilityElement.map { [$0] } ?? [])
    }
    var onDragSelection: ((pid_t) -> Void)?
    var onSpringLoad: ((pid_t) -> Void)?
    var onDrop: (([URL], pid_t) -> Bool)?
    private var dragTarget: pid_t?

    init(selectionAddsBlur: Bool = true) {
        selectionMaterial = selectionAddsBlur ? makeSwitcherGlass(selection: true) : NSView()
        super.init(frame: .zero)
        if !selectionAddsBlur {
            // A highlight over the bar's existing diffusion, with no second
            // backdrop filter and no change to the underlying native material.
            selectionMaterial.wantsLayer = true
            selectionMaterial.layer?.backgroundColor = NSColor.white.cgColor
            selectionMaterial.layer?.cornerCurve = .continuous
            selectionMaterial.alphaValue = 0.45
        }
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff, .pdf, .html, .rtf, .rtfd])
        addSubview(selectionMaterial)
        selectionMaterial.identifier = NSUserInterfaceItemIdentifier("switcher-selection-glass")
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func target(_ sender: NSDraggingInfo) -> pid_t? {
        let point = convert(sender.draggingLocation, from: nil)
        guard let index = layout?.index(at: point) else { return nil }
        return applications[index].pid
    }

    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        let next = target(sender)
        if next != dragTarget { dragTarget = next; sender.resetSpringLoading() }
        guard let next else { return [] }
        onDragSelection?(next)
        // Non-URL drags may spring-load an app, but cannot be dropped on an icon.
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
        let allowed = sender.draggingSourceOperationMask
        if allowed.contains(.copy) { return .copy }
        if allowed.contains(.link) { return .link }
        return allowed.contains(.generic) ? .generic : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { dragTarget = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        target(sender) != nil && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let target = target(sender),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return false }
        return onDrop?(urls, target) ?? false
    }
    func springLoadingEntered(_ draggingInfo: NSDraggingInfo) -> NSSpringLoadingOptions {
        target(draggingInfo) == nil ? [] : .enabled
    }
    func springLoadingUpdated(_ draggingInfo: NSDraggingInfo) -> NSSpringLoadingOptions {
        _ = updateDrag(draggingInfo)
        return target(draggingInfo) == nil ? [] : .enabled
    }
    func springLoadingActivated(_ activated: Bool, draggingInfo: NSDraggingInfo) {
        if activated, let target = target(draggingInfo) { onSpringLoad?(target) }
    }
    func springLoadingHighlightChanged(_ draggingInfo: NSDraggingInfo) { needsDisplay = true }
    func springLoadingExited(_ draggingInfo: NSDraggingInfo) { dragTarget = nil }


    func updatePresentation() {
        canvas.frame = bounds
        canvas.applications = applications; canvas.selected = selected; canvas.layout = layout
        canvas.needsDisplay = true
        guard let layout, let selected, let index = applications.firstIndex(where: { $0.pid == selected }) else {
            selectionMaterial.isHidden = true; return
        }
        selectionMaterial.isHidden = false
        selectionMaterial.frame = layout.selection(at: index)
        if #available(macOS 26.0, *), let glass = selectionMaterial as? NSGlassEffectView {
            glass.cornerRadius = 32 * layout.scale
        } else { selectionMaterial.layer?.cornerRadius = 32 * layout.scale }
        selectionMaterial.layer?.borderWidth = highContrast ? 1 : 0
        selectionMaterial.layer?.borderColor = NSColor.labelColor.cgColor
    }
}

// This view draws above the selection glass. Glass must never blur the app icons.
private final class SwitcherIconCanvas: NSView {
    var applications: [SwitcherPresentation] = []
    var selected: pid_t?
    var layout: SwitcherLayout?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layout else { return }
        for (index, application) in applications.enumerated() {
            application.icon.draw(in: layout.icon(at: index))
            if selected == application.pid {
                let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
                (application.displayName as NSString).draw(in: layout.label(at: index), withAttributes: attributes)
            }
        }
    }
}

struct SwitcherPresentation {
    let pid: pid_t
    let displayName: String
    let icon: NSImage
    init(pid: pid_t, displayName: String, icon: NSImage) {
        self.pid = pid; self.displayName = displayName; self.icon = icon
    }
    init(_ application: SwitcherApplication) {
        self.init(pid: application.pid, displayName: application.record.displayName, icon: application.icon)
    }
}

private func makeSwitcherGlass(selection: Bool) -> NSView {
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = selection ? 32 : 64
        glass.tintColor = nil
        _ = NativeSwitcherGlass.configure(glass, role: selection ? .selection : .container)
        return glass
    }
    let effect = NSVisualEffectView()
    effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = selection ? 32 : 64
    effect.layer?.masksToBounds = true
    if selection { effect.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor }
    return effect
}

private final class SwitcherAccessibilityTile: NSAccessibilityElement {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress(); return true
    }
}
