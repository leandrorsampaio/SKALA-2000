import ConsoleKit
import CoreGraphics
import DeskArt

/// Every control on the desk as a rectangle in desk units, with what it is: the only thing
/// a click is ever tested against.
///
/// Drawing never takes part. In the reference, each panel's lighting gradients reached far
/// past its edges, and SwiftUI kept that clipped paint hit-testable, so panels drawn later
/// lay invisibly over their neighbours' buttons and SIL, ACK, TEST and F1–F7 never got a
/// click. A table can't have that bug, and `HitTableTests` proves no two controls overlap
/// and every one lies inside its panel.
public struct HitTable: Sendable {

    public enum Kind: String, Sendable {
        /// A square pushbutton's cap, or the red cap in a guard.
        case button
        /// A round pushbutton.
        case round
        /// A guard's flap, closed: a click lifts it.
        case flap
        /// Over a lifted flap, where it now stands: a click lets it fall.
        case hinge
        /// F10's key switch, reachable with the guard up.
        case key
        case selector
        case toggle
        case pencil
    }

    public struct Control: Sendable, Hashable {
        public let id: InstrumentID
        public let kind: Kind
        public let rect: CGRect
        /// The guard a control sits under, if any.
        public let guardedBy: InstrumentID?
        /// The panel it belongs to, A to E, or the header.
        public let panel: String
        /// Its corner radius, for the focus ring; half the width for round things.
        public let radius: CGFloat
        public var round: Bool { kind == .round || kind == .key || kind == .selector }
    }

    public let controls: [Control]
    public let panels: [String: CGRect]

    public init() {
        var panels: [String: CGRect] = [:]
        for panel in DeskLayout.all("panel") { panels[String(panel.id.prefix(1))] = panel.rect }
        func panel(of rect: CGRect) -> String {
            panels.first { $0.value.insetBy(dx: -1, dy: -1).contains(rect) }?.key ?? "header"
        }
        let guards = DeskLayout.all("guard")
        func guardOf(_ rect: CGRect) -> InstrumentID? {
            guards.first { $0.rect.contains(rect) }.map { InstrumentID($0.id) }
        }

        var controls: [Control] = []
        for cap in DeskLayout.all("cap") {
            controls.append(
                Control(
                    id: InstrumentID(cap.id), kind: .button, rect: cap.rect,
                    guardedBy: guardOf(cap.rect),
                    panel: panel(of: cap.rect), radius: 10))
        }
        for cap in DeskLayout.all("roundCap") {
            controls.append(
                Control(
                    id: InstrumentID(cap.id), kind: .round, rect: cap.rect, guardedBy: nil,
                    panel: panel(of: cap.rect), radius: cap.rect.width / 2))
        }
        for element in guards {
            let collar = element.rect
            let id = InstrumentID(element.id)
            controls.append(
                Control(
                    id: id, kind: .flap, rect: collar, guardedBy: nil, panel: panel(of: collar),
                    radius: 4))
            controls.append(
                Control(
                    id: id, kind: .hinge,
                    rect: CGRect(
                        x: collar.minX, y: collar.minY - 36, width: collar.width, height: 36),
                    guardedBy: nil, panel: panel(of: collar), radius: 4))
        }
        for key in DeskLayout.all("key") {
            controls.append(
                Control(
                    id: InstrumentID(key.id), kind: .key, rect: key.rect,
                    guardedBy: guardOf(key.rect),
                    panel: panel(of: key.rect), radius: key.rect.width / 2))
        }
        for selector in DeskLayout.all("selector") {
            controls.append(
                Control(
                    id: PK4.selector, kind: .selector, rect: selector.rect, guardedBy: nil,
                    panel: panel(of: selector.rect), radius: selector.rect.width / 2))
        }
        for toggle in DeskLayout.all("toggle") {
            controls.append(
                Control(
                    id: PK4.mains, kind: .toggle, rect: toggle.rect, guardedBy: nil,
                    panel: panel(of: toggle.rect), radius: 5))
        }
        for pencil in DeskLayout.all("pencil") {
            controls.append(
                Control(
                    id: InstrumentID(pencil.id), kind: .pencil, rect: pencil.rect, guardedBy: nil,
                    panel: panel(of: pencil.rect), radius: 3))
        }
        self.controls = controls
        self.panels = panels
    }

    /// What a click at `point` (desk units) lands on, given which guards are up. A closed
    /// guard's flap covers its cap and key; a lifted one leaves them bare and stands over
    /// its hinge instead.
    public func control(at point: CGPoint, guardsOpen: Set<InstrumentID>) -> Control? {
        for control in controls where control.rect.contains(point) {
            switch control.kind {
            case .flap: if guardsOpen.contains(control.id) { continue }
            case .hinge: if !guardsOpen.contains(control.id) { continue }
            default: break
            }
            if let guardID = control.guardedBy, !guardsOpen.contains(guardID) { continue }
            // Round things take clicks inside their circle only.
            if control.round,
                hypot(point.x - control.rect.midX, point.y - control.rect.midY) > control.rect.width
                    / 2
            {
                continue
            }
            return control
        }
        return nil
    }

    /// The selector's four numerals: 96 units out from the centre of its 240-unit dial,
    /// at −180°, −120°, −60° and 0°, 20 units across.
    public static func numeral(at point: CGPoint, in rect: CGRect) -> Int? {
        let k = rect.width / 240
        let local = CGPoint(x: (point.x - rect.minX) / k, y: (point.y - rect.minY) / k)
        for index in 0..<4 {
            let angle = (-90 + 60 * Double(index) - 90) * .pi / 180
            let numeral = CGPoint(x: 120 + 96 * cos(angle), y: 120 + 96 * sin(angle))
            if hypot(local.x - numeral.x, local.y - numeral.y) < 20 { return index + 1 }
        }
        return nil
    }

    /// Tab order: panel A to E, and within a panel top to bottom, left to right.
    public var tabOrder: [Control] {
        let rank = ["A": 0, "B": 1, "C": 2, "D": 3, "E": 4, "header": 5]
        return controls.filter { $0.kind != .hinge }.sorted { a, b in
            let pa = rank[a.panel] ?? 9
            let pb = rank[b.panel] ?? 9
            if pa != pb { return pa < pb }
            if abs(a.rect.midY - b.rect.midY) > 20 { return a.rect.midY < b.rect.midY }
            if a.rect.minX != b.rect.minX { return a.rect.minX < b.rect.minX }
            // A flap before what it covers.
            return a.kind == .flap && b.kind != .flap
        }
    }
}
