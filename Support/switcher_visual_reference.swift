import AppKit

@main enum SwitcherVisualReference {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = VisualReferenceDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class ReferenceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class VisualReferenceDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var image = NSImageView()
    private var overlay: NSView!
    private var presentationRoot: NSView?
    private var nativeImage: NSImage!
    private var backgroundImage: NSImage!
    private var panel: SwitcherPanel!
    private var glassWindow: NSWindow?
    private var applications: [SwitcherPresentation] = []
    private var currentMode = "dock"
    private var revision = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "ReferenceDirectory") as! String)
        nativeImage = NSImage(contentsOf: root.appendingPathComponent("native.png"))!
        backgroundImage = NSImage(contentsOf: root.appendingPathComponent("without.png"))!
        let size = NSSize(width: 1440, height: 932)
        let screenOrigin = NSScreen.main?.frame.origin ?? .zero
        window = ReferenceWindow(contentRect: NSRect(origin: screenOrigin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Switcher Visual Comparison"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        // Keep one opaque, always-populated image window as the keyboard target.
        // The glass is a non-key child window, so it cannot be covered by its backdrop.
        window.isOpaque = true; window.backgroundColor = .windowBackgroundColor
        image.frame = NSRect(origin: .zero, size: size)
        image.imageScaling = .scaleAxesIndependently
        image.image = backgroundImage
        image.setAccessibilityLabel("Supplied reference background")
        window.contentView = image
        let definitions = [
            ("com.apple.Preview", "Preview"), ("com.google.Chrome", "Google Chrome"),
            ("com.mitchellh.ghostty", "Ghostty"), ("com.apple.finder", "Finder"),
            ("com.anthropic.claudefordesktop", "Claude"), ("com.openai.codex", "ChatGPT"),
            ("com.spotify.client", "Spotify"), ("com.microsoft.VSCode", "Visual Studio Code")]
        applications = definitions.enumerated().map { index, definition -> SwitcherPresentation in
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: definition.0).first
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: definition.0)
            let icon = running?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(named: NSImage.applicationIconName)!
            return SwitcherPresentation(pid: Int32(index + 1), displayName: definition.1, icon: icon)
        }
        let menu = NSMenu()
        let appItem = menu.addItem(withTitle: "Switcher Visual Comparison", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Visual Comparison", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let compare = menu.addItem(withTitle: "Compare", action: nil, keyEquivalent: "")
        let options = NSMenu(); compare.submenu = options
        for (title, action, key) in [("Native reference", #selector(showNative), "1"),
                                     ("Replacement — clear glass", #selector(showClear), "2"),
                                     ("Replacement — regular glass", #selector(showRegular), "3"),
                                     ("Replacement — Dock material", #selector(showDock), "5"),
                                     ("Ring — previous double glass", #selector(showLightClearRing), "6"),
                                     ("Ring — intermediate white tint", #selector(showLightRegularRing), "7"),
                                     ("Ring — single blur, light highlight", #selector(showLightDockRing), "8"),
                                     ("Ring — 100% opacity (previous)", #selector(showLightIconRing), "9"),
                                     ("Background only", #selector(showBackground), "4")] {
            let item = options.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        NSApp.mainMenu = menu
        showLightDockRing()
        NSApp.activate(ignoringOtherApps: true)
        (glassWindow ?? window).makeKeyAndOrderFront(nil)
    }

    private func replacePanel(containerVariant: Int = 3, ringVariant: Int = 14, lightRing: Bool = false, ringOpacity: CGFloat = 1, whiteTint: CGFloat? = nil, selectionAddsBlur: Bool = true) {
        discardPanel()
        image.image = backgroundImage
        window.orderFront(nil)
        let next = SwitcherPanel(independentSelection: lightRing, selectionAddsBlur: selectionAddsBlur)
        next.level = window.level
        next.collectionBehavior = [.managed, .fullScreenAuxiliary]
        next.ignoresMouseEvents = true
        next.appearance = NSAppearance(named: .darkAqua)
        next.prepareItems(applications, selected: 2, screenFrame: NSRect(origin: .zero, size: window.frame.size))
        panel = next
        presentationRoot = next.contentView
        overlay = next.containerMaterial
        if NativeSwitcherGlass.isAvailable {
            next.containerMaterial.setValue(NSNumber(value: containerVariant), forKey: "_variant")
            if let ring = selectionGlass() {
                ring.appearance = lightRing ? NSAppearance(named: .aqua) : nil
                ring.alphaValue = ringOpacity
                if #available(macOS 26.0, *), let glass = ring as? NSGlassEffectView {
                    glass.setValue(NSNumber(value: ringVariant), forKey: "_variant")
                    glass.tintColor = whiteTint.map { NSColor.white.withAlphaComponent($0) }
                } else {
                    ring.layer?.backgroundColor = NSColor.white.withAlphaComponent(whiteTint ?? 1).cgColor
                }
            }
        }
        let child = ReferenceWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        child.title = "Switcher glass comparison"
        child.isReleasedWhenClosed = false
        child.isOpaque = false; child.backgroundColor = .clear; child.hasShadow = false
        child.ignoresMouseEvents = false
        // Attaching the glass to the image window changes AppKit's backdrop
        // context. Keep the original independent-window sampling topology.
        child.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        child.appearance = NSAppearance(named: .darkAqua)
        let root = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        let glassRoot = next.contentView!
        next.contentView = NSView()
        glassRoot.frame = next.frame
        root.addSubview(glassRoot)
        child.contentView = root
        glassWindow = child
        child.makeKeyAndOrderFront(nil)
        revision += 1
        saveRenderState()
    }
    @objc private func showDock() { currentMode = "dock"; replacePanel() }
    private func selectionGlass() -> NSView? {
        func find(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == "switcher-selection-glass" { return view }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        return presentationRoot.flatMap { find($0) }
    }
    @objc private func showLightClearRing() { showRing(whiteTint: 1, selectionAddsBlur: true) }
    @objc private func showLightRegularRing() { showRing(whiteTint: 0.85) }
    @objc private func showLightDockRing() { showRing(whiteTint: 1) }
    @objc private func showLightIconRing() { currentMode = "previous-opaque-ring"; replacePanel(ringVariant: 3, lightRing: true) }
    private func showRing(whiteTint: CGFloat?, selectionAddsBlur: Bool = false) {
        currentMode = "ring-\(selectionAddsBlur ? "double-blur" : "single-blur")-white-tint-\(whiteTint ?? 0)"
        replacePanel(ringVariant: 3, lightRing: true, ringOpacity: 0.45, whiteTint: whiteTint, selectionAddsBlur: selectionAddsBlur)
    }
    private func discardPanel() {
        if let child = glassWindow {
            child.orderOut(nil)
            child.close()
            glassWindow = nil
        }
        panel?.close()
        panel = nil
        presentationRoot = nil
    }
    private func showImage(_ reference: NSImage, mode: String) {
        currentMode = mode
        discardPanel()
        image.image = reference
        window.makeKeyAndOrderFront(nil)
        revision += 1
        saveRenderState()
    }
    @objc private func showNative() { showImage(nativeImage, mode: "native") }
    @objc private func showBackground() { showImage(backgroundImage, mode: "background") }
    @objc private func showClear() { currentMode = "clear"; replacePanel(containerVariant: 2) }
    @objc private func showRegular() { currentMode = "regular"; replacePanel(containerVariant: 1) }
    private func saveRenderState() {
        let expectedRevision = revision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.revision == expectedRevision else { return }
            var data: [String: Any] = ["private_recipe_available": NativeSwitcherGlass.isAvailable,
                                      "frame": NSStringFromRect(self.panel?.frame ?? .zero),
                                      "mode": self.currentMode, "revision": self.revision,
                                      "child_window_count": self.window.childWindows?.count ?? 0,
                                      "background_image_present": self.image.image != nil,
                                      "background_window_visible": self.window.isVisible,
                                      "panel_visible": self.glassWindow?.isVisible ?? false]
            data["glass_window_key"] = self.glassWindow?.isKeyWindow ?? false
            data["glass_window_can_be_key"] = self.glassWindow?.canBecomeKey ?? false
            for key in ["_variant", "_adaptiveAppearance", "_subvariant"] where self.panel != nil && self.panel.containerMaterial.responds(to: NSSelectorFromString(key)) {
                data[key] = self.panel.containerMaterial.value(forKey: key) ?? NSNull()
            }
            if self.panel != nil, let ring = self.selectionGlass(), NativeSwitcherGlass.isAvailable {
                data["selection_opacity"] = ring.alphaValue
                data["selection_appearance"] = ring.appearance?.name.rawValue ?? "inherited"
                data["selection_nested_in_container"] = ring.isDescendant(of: self.overlay)
                if #available(macOS 26.0, *), let glass = ring as? NSGlassEffectView {
                    data["selection_variant"] = glass.value(forKey: "_variant")
                    data["selection_adds_blur"] = true
                    data["selection_white_tint_alpha"] = glass.tintColor?.alphaComponent ?? 0
                } else {
                    data["selection_adds_blur"] = false
                }
            }
            if #available(macOS 26.0, *), let bar = self.overlay as? NSGlassEffectView {
                data["container_corner_radius"] = bar.cornerRadius
                data["container_content_present"] = bar.contentView != nil
            }
            let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "ReferenceDirectory") as! String)
            if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
                try? encoded.write(to: root.appendingPathComponent("render-state.json"), options: .atomic)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidBecomeActive(_ notification: Notification) {
        glassWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationDidResignActive(_ notification: Notification) {
        glassWindow?.orderOut(nil)
    }
}
