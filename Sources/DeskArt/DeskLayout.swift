import CoreGraphics
import Foundation

/// Every primitive of the desk and its frame in desk units: 3352 × 1800, origin top left.
///
/// Exported from the reference SwiftUI desk by `swift run DeskReference layout`, never
/// placed by eye. The painters draw from it and the hit table is built from it, so the two
/// can't disagree.
public enum DeskLayout {

    public static let size = CGSize(width: 3352, height: 1800)
    /// The desk without panel F, the fourth column: A to D, the width it had before F.
    public static let compactSize = CGSize(width: 2500, height: 1800)

    public struct Element: Sendable, Hashable {
        public let kind: String
        public let id: String
        public let info: [String: String]
        public let rect: CGRect

        public func text(_ key: String = "text") -> String { info[key] ?? "" }
    }

    private struct Row: Decodable {
        var kind: String
        var id: String
        var info: [String: String]
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    /// In the order the reference listed them.
    public static let elements: [Element] = {
        guard let rows = try? JSONDecoder().decode([Row].self, from: Data(json.utf8)) else {
            return []
        }
        return rows.map {
            Element(
                kind: $0.kind, id: $0.id, info: $0.info,
                rect: CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h))
        }
    }()

    private static let byKind: [String: [Element]] = Dictionary(grouping: elements, by: \.kind)

    public static func all(_ kind: String) -> [Element] { byKind[kind] ?? [] }

    public static func first(_ kind: String, id: String) -> Element? {
        all(kind).first { $0.id == id }
    }

    /// The elements of `kind` that lie inside `rect`.
    public static func all(_ kind: String, in rect: CGRect) -> [Element] {
        all(kind).filter { rect.insetBy(dx: -0.5, dy: -0.5).contains($0.rect) }
    }
}
