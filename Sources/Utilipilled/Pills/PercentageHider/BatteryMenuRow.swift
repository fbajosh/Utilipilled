import AppKit

/// AppKit stretches this view to the menu's width. The trailing stack follows
/// the actual row bounds, including when other items make the menu wider.
final class BatteryMenuRow: NSView {
    static let keyEquivalent = "b"
    private let actionLabel = NSTextField(labelWithString: "Disable")
    private let shortcutLabel = NSTextField(labelWithString: "⌘ " + BatteryMenuRow.keyEquivalent.uppercased())
    private let percentageLabel = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private var hovered = false

    init() {
        let font = NSFont.menuFont(ofSize: 0)
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: ceil(font.ascender - font.descender) + 8))
        autoresizingMask = [.width]
        actionLabel.font = font
        percentageLabel.font = font
        shortcutLabel.font = font
        let battery = NSStackView(views: [percentageLabel, icon])
        battery.alignment = .centerY
        battery.spacing = 4
        let readout = NSStackView(views: [battery, shortcutLabel])
        readout.alignment = .centerY
        readout.spacing = 12
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        readout.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionLabel)
        addSubview(readout)
        // Account for the leading space AppKit reserves on the native rows.
        let titleInset: CGFloat
        let shortcutInset: CGFloat
        if #available(macOS 26.0, *) {
            titleInset = 24
            shortcutInset = 16
        } else {
            titleInset = 14
            shortcutInset = 14
        }
        NSLayoutConstraint.activate([
            actionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: titleInset),
            actionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            readout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -shortcutInset),
            readout.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
    }

    required init?(coder: NSCoder) { nil }

    func update(percentage: String, charging: Bool, onExternalPower: Bool) {
        percentageLabel.stringValue = percentage
        let status = charging ? "Charging" : (onExternalPower ? "Plugged in" : nil)
        icon.image = status.flatMap { label in
            NSImage(systemSymbolName: charging ? "bolt.fill" : "powerplug", accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: NSFont.menuFont(ofSize: 0).pointSize - 2, weight: .regular))
        }
        icon.isHidden = icon.image == nil
        let detail = [percentage, status].compactMap { $0 }.joined(separator: ", ")
        toolTip = "Battery: " + detail
        setAccessibilityLabel("Disable, " + detail)
        updateColors()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways], owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovered = false
        updateColors()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; updateColors() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateColors() }

    private func updateColors() {
        let selected = hovered && enclosingMenuItem?.isEnabled == true
        let color: NSColor = selected ? .selectedMenuItemTextColor : .labelColor
        actionLabel.textColor = color
        percentageLabel.textColor = color
        shortcutLabel.textColor = selected ? color : .tertiaryLabelColor
        icon.contentTintColor = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hovered, enclosingMenuItem?.isEnabled == true else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4).fill()
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { _ = accessibilityPerformPress() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu,
              let index = menu.items.firstIndex(where: { $0 === item }) else { return false }
        menu.cancelTracking()
        menu.performActionForItem(at: index)
        return true
    }
}
