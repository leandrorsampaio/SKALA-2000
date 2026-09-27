import CoreGraphics
import Foundation
import Testing

@testable import DeskArt

/// The art cache's file format, in memory: the tests never touch the app's cache folder.
struct ArtDiskCacheTests {

    static func file(_ index: ArtDiskCache.Index, body: Data = Data(count: 64)) throws -> Data {
        let header = try JSONEncoder().encode(index)
        var length = UInt32(header.count)
        var data = Data(bytes: &length, count: 4)
        data.append(header)
        data.append(body)
        return data
    }

    @Test func aSetComesBackAsItWent() throws {
        let set = ArtSet.render(style: ArtStyle(), scale: 0.25)
        let data = try #require(ArtDiskCache.encode(set))
        let back = try #require(ArtDiskCache.decode(data, style: set.style, scale: set.scale))
        #expect(back.sprites.count == set.sprites.count)
        #expect(back.background.width == set.background.width)
        #expect(back.background.height == set.background.height)
    }

    /// A damaged number fails the read: none may copy from outside the file, or trap.
    @Test func aDamagedFileIsRefused() throws {
        func entry(width: Int = 2, height: Int = 2, offset: Int = 0) -> ArtDiskCache.Entry {
            ArtDiskCache.Entry(
                x: 0, y: 0, w: 1, h: 1, width: width, height: height, offset: offset)
        }
        for bad in [
            entry(offset: -16), entry(width: -2), entry(width: .max, height: 3),
            entry(width: 4, height: 4, offset: 60), entry(offset: .max),
        ] {
            let data = try Self.file(ArtDiskCache.Index(background: bad, sprites: [:]))
            #expect(ArtDiskCache.decode(data, style: ArtStyle(), scale: 1) == nil)
        }
        let good = try Self.file(ArtDiskCache.Index(background: entry(), sprites: [:]))
        #expect(ArtDiskCache.decode(good, style: ArtStyle(), scale: 1) != nil)
        // A header longer than the file.
        #expect(
            ArtDiskCache.decode(Data([255, 255, 255, 255, 0]), style: ArtStyle(), scale: 1) == nil)
    }
}
