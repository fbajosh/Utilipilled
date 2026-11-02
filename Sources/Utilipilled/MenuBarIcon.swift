import AppKit

enum MenuBarIcon {
    private static let off = load("MenuBarOff")
    private static let on = load("MenuBarOn")

    static func image(active: Bool) -> NSImage? { active ? on : off }

    private static func load(_ name: String) -> NSImage? {
        let image = NSImage(named: NSImage.Name(name)) ??
            NSImage(systemSymbolName: "pills", accessibilityDescription: "Utilipilled")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }
}
