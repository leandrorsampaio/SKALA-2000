import CoreGraphics
import Foundation
import IOSurface

/// The last few art sets on disk, in `~/Library/Caches/SKALA-2000/`, so a launch shows the
/// desk at once instead of drawing it first.
///
/// One file per set: a JSON index, then every picture's rows, raw. Read back straight into
/// IOSurfaces. Keyed by the app's build, the layout, the style and the pixel size, so a new
/// build or a changed layout never shows old art.
enum ArtDiskCache {

    static let folder: URL = {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return base.appendingPathComponent("SKALA-2000", isDirectory: true)
    }()

    /// How many sets are kept: the sizes and styles most recently shown.
    static let keep = 4

    struct Index: Codable {
        var format = 1
        var background: Entry
        var sprites: [String: Entry]
    }

    struct Entry: Codable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var width: Int
        var height: Int
        var offset: Int
    }

    /// What makes one build's art different from another's.
    static let buildStamp: String = {
        let info = Bundle.main.infoDictionary
        let version =
            (info?["CFBundleShortVersionString"] as? String ?? "dev") + "-"
            + (info?["CFBundleVersion"] as? String ?? "0")
        // A development build has no version to speak of: the binary's own date stands in.
        let binary = Bundle.main.executableURL.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
        }
        let stamp = Int(binary?.timeIntervalSince1970 ?? 0)
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in DeskLayout.json.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
        return "\(version)-\(stamp)-\(String(hash, radix: 36))"
    }()

    static func url(style: ArtStyle, scale: CGFloat) -> URL {
        let name = "art-\(buildStamp)-\(style.key)-\(Int((scale * 1000).rounded())).bin"
        return folder.appendingPathComponent(name)
    }

    // MARK: - Reading

    /// The set, or nil. A file that does not hold together is deleted, so it is drawn and
    /// written again rather than tried at every launch.
    static func read(style: ArtStyle, scale: CGFloat) -> ArtSet? {
        let url = url(style: style, scale: scale)
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        guard let set = decode(data, style: style, scale: scale) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        // Touched, so the oldest set is the one pruned.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return set
    }

    static func decode(_ data: Data, style: ArtStyle, scale: CGFloat) -> ArtSet? {
        guard data.count > 4 else { return nil }
        let started = Date()
        let headerLength = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard data.count >= 4 + headerLength,
            let index = try? JSONDecoder().decode(
                Index.self, from: data.subdata(in: 4..<4 + headerLength))
        else { return nil }
        let body = 4 + headerLength

        func picture(_ entry: Entry) -> Picture? {
            // Every number checked before any is trusted: a damaged file fails here rather
            // than copying from outside itself.
            let (pixels, tooMany) = entry.width.multipliedReportingOverflow(by: entry.height)
            let (bytes, tooLarge) = pixels.multipliedReportingOverflow(by: 4)
            guard entry.width > 0, entry.height > 0, entry.offset >= 0, !tooMany, !tooLarge,
                entry.offset <= data.count - body, bytes <= data.count - body - entry.offset
            else { return nil }
            return Picture(
                width: entry.width, height: entry.height,
                rows: { destination, bytesPerRow in
                    data.withUnsafeBytes { raw in
                        let source = raw.baseAddress!.advanced(by: body + entry.offset)
                        for row in 0..<entry.height {
                            memcpy(
                                destination.advanced(by: row * bytesPerRow),
                                source.advanced(by: row * entry.width * 4), entry.width * 4)
                        }
                    }
                })
        }
        guard let background = picture(index.background) else { return nil }
        var sprites: [String: Sprite] = [:]
        for (name, entry) in index.sprites {
            guard let picture = picture(entry) else { return nil }
            sprites[name] = Sprite(
                picture: picture,
                frame: CGRect(x: entry.x, y: entry.y, width: entry.w, height: entry.h))
        }
        let set = ArtSet(style: style, scale: scale, background: background, sprites: sprites)
        set.took(Date().timeIntervalSince(started))
        return set
    }

    // MARK: - Writing

    static func write(_ set: ArtSet) {
        guard let file = encode(set) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? file.write(to: url(style: set.style, scale: set.scale), options: .atomic)
        prune()
    }

    static func encode(_ set: ArtSet) -> Data? {
        var body = Data()
        func entry(_ picture: Picture, _ frame: CGRect) -> Entry {
            let entry = Entry(
                x: frame.minX, y: frame.minY, w: frame.width, h: frame.height, width: picture.width,
                height: picture.height, offset: body.count)
            picture.appendRows(to: &body)
            return entry
        }
        let background = entry(set.background, CGRect(origin: .zero, size: DeskLayout.size))
        var sprites: [String: Entry] = [:]
        for (name, sprite) in set.sprites { sprites[name] = entry(sprite.picture, sprite.frame) }
        guard
            let header = try? JSONEncoder().encode(Index(background: background, sprites: sprites))
        else { return nil }
        var file = Data()
        var length = UInt32(header.count)
        file.append(Data(bytes: &length, count: 4))
        file.append(header)
        file.append(body)
        return file
    }

    /// Another build's sets are kept this long after they were last used: a copy in
    /// /Applications and a fresh build take turns, and each would otherwise delete the
    /// other's art and start cold every time.
    static let othersKept: TimeInterval = 7 * 24 * 3600

    /// Keeps the most recently used sets of this build, and another build's for a week.
    static func prune() {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let sets = files.filter { $0.pathExtension == "bin" }
        let stale = Date().addingTimeInterval(-othersKept)
        for file in sets where !file.lastPathComponent.contains(buildStamp) {
            let used =
                (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if used < stale { try? FileManager.default.removeItem(at: file) }
        }
        let current = sets.filter { $0.lastPathComponent.contains(buildStamp) }.sorted {
            let a =
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let b =
                (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return a > b
        }
        for file in current.dropFirst(keep) { try? FileManager.default.removeItem(at: file) }
    }
}
