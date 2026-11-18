import Foundation

struct SwitcherLayout: Equatable {
    let frame: CGRect
    let tileWidth: CGFloat
    let count: Int
    var scale: CGFloat { tileWidth / 134 }
    var iconSize: CGFloat { 128 * scale }
    var cornerRadius: CGFloat { min(56, frame.height / 2) }

    init(count: Int, screen: CGRect) {
        self.count = max(0, count)
        let available = max(41, screen.width - 80)
        tileWidth = min(134, max(1, (available - 40) / CGFloat(max(1, count))))
        let size = CGSize(width: tileWidth * CGFloat(self.count) + 40, height: 128 * (tileWidth / 134) + 48)
        frame = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                       width: size.width, height: size.height)
    }

    func tile(at index: Int) -> CGRect {
        CGRect(x: 20 + CGFloat(index) * tileWidth, y: 6, width: tileWidth, height: frame.height - 12)
    }

    func icon(at index: Int) -> CGRect {
        let tile = tile(at: index)
        return CGRect(x: tile.midX - iconSize / 2, y: 24, width: iconSize, height: iconSize)
    }

    func selection(at index: Int) -> CGRect {
        let icon = icon(at: index)
        return icon.insetBy(dx: 4 * scale, dy: 4 * scale)
    }

    func label(at index: Int) -> CGRect {
        let width = min(max(130, tileWidth), frame.width - 16)
        let center = tile(at: index).midX
        let left = min(max(8, center - width / 2), frame.width - width - 8)
        return CGRect(x: left, y: 6, width: width, height: 18)
    }

    func index(at point: CGPoint) -> Int? {
        guard point.x >= 20, point.x < frame.width - 20,
              point.y >= 6, point.y < frame.height - 6 else { return nil }
        let index = Int((point.x - 20) / tileWidth)
        return (0..<count).contains(index) ? index : nil
    }

    static func cocoaPoint(fromQuartz point: CGPoint, primaryScreen: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreen.maxY - point.y)
    }
}
