import Foundation

/// The art set on screen, so a view asking again for the same size and style gets it at
/// once. Only one is kept: at 5K full screen a set is some 70 MB.
public final class ArtCache: @unchecked Sendable {

    public static let shared = ArtCache()

    private let lock = NSLock()
    private var recent: [ArtSet] = []
    private var disk = false
    /// One set drawn at a time. Each already uses every core, and a second view asking for
    /// the set being drawn waits for it rather than drawing it again.
    private let drawing = NSLock()

    /// Whether sets are also kept in `~/Library/Caches/SKALA-2000/` for the next launch.
    /// Only the app turns it on: the tests and the reference tool must neither read its
    /// sets nor prune them as another build's.
    public var usesDisk: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return disk
        }
        set {
            lock.lock()
            disk = newValue
            lock.unlock()
        }
    }

    /// A set for `style` at `scale`, rendered now if need be, or `nil` if it could not be.
    /// Thread-safe; call it off the main thread.
    public func art(style: ArtStyle, scale: CGFloat) -> ArtSet? {
        if let hit = cached(style, scale) { return hit }
        drawing.lock()
        defer { drawing.unlock() }
        if let hit = cached(style, scale) { return hit }
        let disk = usesDisk
        let art: ArtSet
        if disk, let saved = ArtDiskCache.read(style: style, scale: scale) {
            art = saved
        } else {
            guard let drawn = ArtSet.render(style: style, scale: scale) else { return nil }
            art = drawn
            // Written in the background: the view is waiting for this set, not for the disk.
            if disk { DispatchQueue.global(qos: .utility).async { ArtDiskCache.write(art) } }
        }
        lock.lock()
        recent = [art]
        lock.unlock()
        return art
    }

    private func cached(_ style: ArtStyle, _ scale: CGFloat) -> ArtSet? {
        lock.lock()
        defer { lock.unlock() }
        return recent.first { $0.style == style && abs($0.scale - scale) < 0.001 }
    }

    public func removeAll() {
        lock.lock()
        recent.removeAll()
        lock.unlock()
    }
}
