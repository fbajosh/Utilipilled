import AppKit

enum SkibidiClipboard {
    static let label = "Skibidi Clipboard"

    static func title(for pasteboard: NSPasteboard, label: String = SkibidiClipboard.label) -> String {
        let changeCount = pasteboard.changeCount
        guard let items = pasteboard.pasteboardItems else { return "\(label): unavailable" }
        guard !items.isEmpty else { return "\(label): 0 characters" }

        var allText = true
        var characters = 0
        var bytes = 0.0
        for item in items {
            if !item.types.contains(.fileURL), let text = item.string(forType: .string) {
                characters += text.count
                bytes += Double(text.utf8.count)
            } else {
                allText = false
                guard let size = size(of: item) else { return "\(label): unavailable" }
                bytes += Double(size)
            }
        }
        guard pasteboard.changeCount == changeCount else { return "\(label): clipboard changed" }
        if allText {
            return "\(label): \(characters) \(characters == 1 ? "character" : "characters")"
        }
        return "\(label): \(formatBytes(bytes))"
    }

    private static func size(of item: NSPasteboardItem) -> Int? {
        if let address = item.string(forType: .fileURL),
           let url = URL(string: address), url.isFileURL,
           let resource = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
           resource.isRegularFile == true, let size = resource.fileSize {
            return size
        }

        // An item can offer the same content in multiple formats. Measure one
        // representation rather than counting each encoding as a separate copy.
        let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff, .pdf, .rtfd, .rtf, .html, .fileURL, .URL]
        let offered = item.types
        for type in preferred.filter(offered.contains) + offered.filter({ !preferred.contains($0) }) {
            if let data = item.data(forType: type) { return data.count }
        }
        return nil
    }

    static func formatBytes(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        var value = bytes
        var unit = 0
        while unit < units.count - 1, (value * 10).rounded() >= 10_000 {
            value /= 1000
            unit += 1
        }
        return String(format: "%.1f", locale: .current, value) + " " + units[unit]
    }
}
