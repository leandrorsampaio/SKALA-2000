import SwiftUI

/// One primitive of the desk, as the reference skin placed it: what it is, which
/// instrument it belongs to, the few facts a painter needs, and its frame in desk units.
struct DeskMark {
    var kind: String
    var id: String
    var info: [String: String]
    var anchor: Anchor<CGRect>
}

struct DeskMarks: PreferenceKey {
    static let defaultValue: [DeskMark] = []
    static func reduce(value: inout [DeskMark], nextValue: () -> [DeskMark]) {
        value += nextValue()
    }
}

extension View {
    /// Records this view's frame for the layout export. Changes nothing drawn.
    func mark(_ kind: String, _ id: String = "", _ info: [String: String] = [:]) -> some View {
        // Appends rather than sets: a plain preference would hide every mark inside this view.
        transformAnchorPreference(key: DeskMarks.self, value: .bounds) { marks, anchor in
            marks.append(DeskMark(kind: kind, id: id, info: info, anchor: anchor))
        }
    }
}
