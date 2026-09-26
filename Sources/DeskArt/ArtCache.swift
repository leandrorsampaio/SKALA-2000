import Foundation

/// The art set on screen, so a view asking again for the same size and style gets it at
/// once. Only one is kept: at 5K full screen a set is some 70 MB.
public final class ArtCache: @unchecked Sendable {

    public static let shared = ArtCache()

    private let lock = NSLock()
    private var recent: [ArtSet] = []

    /// A set for `style` at `scale`, rendered now if need be. Thread-safe; call it off the
    /// main thread.
    public func art(style: ArtStyle, scale: CGFloat) -> ArtSet {
        lock.lock()
        if let hit = recent.first(where: { $0.style == style && abs($0.scale - scale) < 0.001 }) {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let art = ArtSet.render(style: style, scale: scale)
        lock.lock()
        recent = [art]
        lock.unlock()
        return art
    }

    public func removeAll() {
        lock.lock()
        recent.removeAll()
        lock.unlock()
    }
}
