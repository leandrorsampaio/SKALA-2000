import AppKit
import ConsoleKit
import DeskArt

/// VoiceOver's view of the desk: every instrument one element, labelled with its plate and
/// valued in words, grouped by panel A to E in that order. Buttons press, the selector is
/// adjustable, MAINS toggles, a pencil strip opens its field.
///
/// Elements read their value from the view's current snapshot when asked, so a snapshot
/// costs VoiceOver nothing until someone listens.
@MainActor
final class DeskAccessibility {

    weak var view: DeskView?
    private var built: [NSAccessibilityElement]?

    init(view: DeskView) { self.view = view }

    func update(_ snapshot: ConsoleSnapshot) {}

    /// The five panels, and the header, in reading order.
    var children: [NSAccessibilityElement] {
        if let built { return built }
        guard let view else { return [] }
        let made = Self.build(view)
        built = made
        return made
    }

    // MARK: - Building

    struct Item {
        let rect: CGRect
        let panel: String
        let element: DeskElement
    }

    static func build(_ view: DeskView) -> [NSAccessibilityElement] {
        let table = view.hitTable
        func panel(of rect: CGRect) -> String {
            table.panels.first { $0.value.insetBy(dx: -1, dy: -1).contains(rect) }?.key ?? "header"
        }
        var items: [Item] = []
        func add(_ rect: CGRect, _ element: DeskElement) {
            items.append(Item(rect: rect, panel: panel(of: rect), element: element))
        }

        // Lamp windows: panel A by row and session, panel B by group, D and E by name.
        let rows: [AnnunciatorRow: String] = [
            .run: "Running", .busy: "Busy", .wait: "Waiting for operator", .done: "Turn done",
            .agent: "Agent done", .bkgd: "Background job", .block: "Blocked", .cmpct: "Compacting",
        ]
        let groups = [
            "b.perm.": "Permission mode", "b.effort.": "Effort", "b.model.": "Model",
            "b.mode.": "Mode",
            "b.kind.": "Kind", "b.tier.": "Service tier", "b.warn.": "Warnings",
        ]
        for lamp in DeskLayout.all("lamp") where !lamp.id.isEmpty {
            let id = InstrumentID(lamp.id)
            let window = lamp.text("label").replacingOccurrences(of: "\n", with: " ")
            var label = window.capitalizedFirst
            for row in AnnunciatorRow.allCases {
                for slot in PK4.slots where id == PK4.annunciator(row, slot: slot) {
                    label = "\(rows[row] ?? window), session \(slot)"
                }
            }
            if let group = groups.first(where: { lamp.id.hasPrefix($0.key) })?.value {
                label = "\(group), \(window.lowercased())"
            }
            add(lamp.rect, LampElement(view: view, id: id, label: label))
        }

        // Nixie rows. SELECTED and the panel B copy of the target say what the selector
        // does, so they are left out, as in the reference.
        let nixieLabels: [InstrumentID: String] = [
            PK4.sessionsRunning: "Sessions running", PK4.sessionsBusy: "Sessions busy",
            PK4.targetC: "Command goes to session", PK4.contextUsed: "Context used",
            PK4.inputTokens: "Input tokens", PK4.outputTokens: "Output tokens",
            PK4.thinkingTokens: "Thinking tokens", PK4.cacheRead: "Cache read, thousands",
            PK4.cacheWritten: "Cache written, thousands", PK4.queueDepth: "Queue depth",
            PK4.toolCalls: "Tool calls", PK4.lastTurn: "Last turn, minutes and seconds",
            PK4.turnMessages: "Turn messages", PK4.uptime: "Session uptime, hours and minutes",
            PK4.cost: "Cost, last checkpoint, dollars",
        ]
        for nixie in DeskLayout.all("nixie") {
            let id = InstrumentID(nixie.id)
            guard let label = nixieLabels[id] else { continue }
            add(nixie.rect, NixieElement(view: view, id: id, label: label))
        }

        let meterLabels: [InstrumentID: String] = [
            PK4.contextMeter: "Context remaining", PK4.apiShareMeter: "API share of time",
            PK4.toolShareMeter: "Tool share of time", PK4.batteryMeter: "Battery",
        ]
        for meter in DeskLayout.all("meter") + DeskLayout.all("edgewise") {
            let id = InstrumentID(meter.id)
            add(meter.rect, MeterElement(view: view, id: id, label: meterLabels[id] ?? meter.id))
        }

        let drumLabels: [InstrumentID: (String, String?)] = [
            PK4.totalCost: ("Total cost", "dollars"),
            PK4.totalOutput: ("Total output", "thousand tokens"),
            PK4.linesAdded: ("Lines added", nil), PK4.linesRemoved: ("Lines removed", nil),
            PK4.hoursInService: ("Hours in service", "hours"),
        ]
        for drum in DeskLayout.all("drum") {
            let id = InstrumentID(drum.id)
            guard let (label, unit) = drumLabels[id] else { continue }
            add(drum.rect, DrumElement(view: view, id: id, label: label, unit: unit))
        }

        for control in table.controls where control.kind != .hinge {
            add(
                control.rect,
                ControlElement(view: view, control: control, label: Self.label(for: control)))
        }
        if let buzzer = DeskLayout.all("buzzer").first {
            add(buzzer.rect, BuzzerElement(view: view))
        }
        if let program = DeskLayout.all("programCard").first {
            add(program.rect, ProgramElement(view: view))
        }

        // Panels in reading order, and their instruments top to bottom, left to right.
        let order = ["header", "A", "B", "C", "D", "E"]
        let names = [
            "header": "Header", "A": "A · All sessions, annunciator",
            "B": "B · Selected session, instruments",
            "C": "C · Control, selected session", "D": "D · Computer controls",
            "E": "E · Power and service",
        ]
        return order.compactMap { key -> NSAccessibilityElement? in
            let members = items.filter { $0.panel == key }.sorted { a, b in
                abs(a.rect.midY - b.rect.midY) > 20
                    ? a.rect.midY < b.rect.midY : a.rect.minX < b.rect.minX
            }
            guard !members.isEmpty else { return nil }
            let rect =
                table.panels[key] ?? CGRect(x: 0, y: 0, width: DeskLayout.size.width, height: 97)
            let group = PanelElement(view: view, rect: rect, label: names[key] ?? key)
            for member in members {
                member.element.rect = member.rect
                member.element.setAccessibilityParent(group)
            }
            group.setAccessibilityChildren(members.map(\.element))
            group.setAccessibilityParent(view)
            return group
        }
    }

    static func label(for control: HitTable.Control) -> String {
        let names: [InstrumentID: String] = [
            PK4.silence: "Silence", PK4.acknowledge: "Acknowledge", PK4.lampTest: "Lamp test",
            PK4.buzzerTest: "Buzzer test", PK4.printText: "Print text",
            PK4.function(1): "Open folder",
            PK4.function(2): "Terminal here", PK4.function(3): "Copy resume",
            PK4.function(4): "Safety log",
            PK4.function(5): "Show transcript", PK4.function(6): "Function 6, unassigned",
            PK4.function(7): "Function 7, unassigned", PK4.function(8): "Function 8, unassigned",
            PK4.function(9): "Function 9, unassigned", PK4.f10: "Function 10, unassigned",
            PK4.f11: "Function 11, unassigned", PK4.f12: "End session", PK4.sleepMode: "Sleep mode",
            PK4.monitorOff: "Turn off monitor", PK4.fc1: "Keep awake, display on",
            PK4.fc2: "Keep awake, display off", PK4.selector: "Session selector",
            PK4.mains: "Mains 220 volts 50 hertz",
        ]
        switch control.kind {
        case .flap: return "Guard of \(names[control.id] ?? control.id.rawValue)"
        case .key: return "Key switch"
        case .pencil:
            let slot = control.id.rawValue.split(separator: ".").last.map(String.init) ?? ""
            return "Project name, session \(slot), in pencil"
        default: return names[control.id] ?? control.id.rawValue
        }
    }
}

// MARK: - Elements

/// An element whose frame follows the desk wherever the window and its size put it.
@MainActor
class DeskElement: NSAccessibilityElement {
    weak var view: DeskView?
    var rect: CGRect = .zero

    init(view: DeskView) {
        self.view = view
        super.init()
    }

    var snapshot: ConsoleSnapshot { view?.snapshot ?? ConsoleSnapshot() }

    override func accessibilityFrame() -> NSRect {
        guard let view, let window = view.window else { return .zero }
        let inView = view.viewRect(rect)
        return window.convertToScreen(view.convert(inView, to: nil))
    }

    override func isAccessibilityElement() -> Bool { true }
}

final class PanelElement: DeskElement {
    init(view: DeskView, rect: CGRect, label: String) {
        super.init(view: view)
        self.rect = rect
        setAccessibilityRole(.group)
        setAccessibilityLabel(label)
    }
}

final class LampElement: DeskElement {
    let id: InstrumentID
    init(view: DeskView, id: InstrumentID, label: String) {
        self.id = id
        super.init(view: view)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(label)
    }
    override func accessibilityValue() -> Any? { DeskWords.lamp(snapshot.lamp(id)) }
}

final class NixieElement: DeskElement {
    let id: InstrumentID
    init(view: DeskView, id: InstrumentID, label: String) {
        self.id = id
        super.init(view: view)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(label)
    }
    override func accessibilityValue() -> Any? { DeskWords.digits(snapshot.nixie(id)) }
}

final class MeterElement: DeskElement {
    let id: InstrumentID
    init(view: DeskView, id: InstrumentID, label: String) {
        self.id = id
        super.init(view: view)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel(label)
    }
    override func accessibilityValue() -> Any? { DeskWords.meter(snapshot.meter(id)) }
}

final class DrumElement: DeskElement {
    let id: InstrumentID
    let unit: String?
    init(view: DeskView, id: InstrumentID, label: String, unit: String?) {
        self.id = id
        self.unit = unit
        super.init(view: view)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(label)
    }
    override func accessibilityValue() -> Any? {
        let value = snapshot.drum(id)
        return unit.map { "\(value) \($0)" } ?? "\(value)"
    }
}

final class BuzzerElement: DeskElement {
    override init(view: DeskView) {
        super.init(view: view)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Buzzer")
    }
    override func accessibilityValue() -> Any? { snapshot.buzzer ? "sounding" : "silent" }
}

final class ProgramElement: DeskElement {
    override init(view: DeskView) {
        super.init(view: view)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Program build")
    }
    override func accessibilityValue() -> Any? { snapshot.programBuild ?? "unknown" }
}

/// Anything the operator can work: buttons press and release, the selector steps, MAINS
/// toggles, a guard lifts and falls, the key turns, a pencil strip opens its field.
final class ControlElement: DeskElement {
    let control: HitTable.Control

    init(view: DeskView, control: HitTable.Control, label: String) {
        self.control = control
        super.init(view: view)
        setAccessibilityLabel(label)
        switch control.kind {
        case .button, .round: setAccessibilityRole(.button)
        case .flap, .key: setAccessibilityRole(.button)
        case .selector: setAccessibilityRole(.slider)
        case .toggle: setAccessibilityRole(.checkBox)
        case .pencil: setAccessibilityRole(.textField)
        case .hinge: setAccessibilityRole(.button)
        }
    }

    override func accessibilityValue() -> Any? {
        let s = snapshot
        switch control.kind {
        case .button:
            let face = s.button(control.id)
            if let guardID = control.guardedBy, !s.guardsOpen.contains(guardID) {
                return "under its guard"
            }
            return face.lamp == .off ? "dark" : "lit"
        case .round:
            let on = s.lamp(PK4.lensOn(control.id)) != .off
            let off = s.lamp(PK4.lensOff(control.id)) != .off
            return on ? "on" : off ? "off" : "no answer"
        case .flap: return s.guardsOpen.contains(control.id) ? "lifted" : "closed"
        case .key: return s.keysArmed.contains(control.id) ? "armed" : "safe"
        case .selector: return "Session \(s.selector)"
        case .toggle: return s.mains ? 1 : 0
        case .pencil:
            let slot = Int(control.id.rawValue.split(separator: ".").last ?? "") ?? 0
            let text = s.pencil(slot: slot)
            return text.isEmpty ? "blank" : text
        case .hinge: return nil
        }
    }

    override func isAccessibilityEnabled() -> Bool {
        guard let guardID = control.guardedBy else { return true }
        return snapshot.guardsOpen.contains(guardID)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let view, isAccessibilityEnabled() else { return false }
        switch control.kind {
        case .button, .round:
            let id = control.id
            view.send(.press(id))
            if PK4.guarded.contains(id) {
                // A guarded button fires only after 2 s held: VoiceOver's press holds it
                // that long. Guard, key and password still stand in the way.
                DispatchQueue.main.asyncAfter(deadline: .now() + ConsoleTiming.holdToFire + 0.2) {
                    [weak view] in
                    view?.send(.release(id))
                }
            } else {
                view.send(.release(id))
            }
        case .flap: view.send(.guard(control.id, open: !snapshot.guardsOpen.contains(control.id)))
        case .key: view.send(.key(control.id, armed: !snapshot.keysArmed.contains(control.id)))
        case .toggle: view.send(.mains(!snapshot.mains))
        case .pencil: view.beginPencil(control)
        case .selector, .hinge: return false
        }
        return true
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard control.kind == .selector, let view else { return false }
        view.turnSelector(1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard control.kind == .selector, let view else { return false }
        view.turnSelector(-1)
        return true
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst().lowercased() }
}

extension DeskView {
    public override func accessibilityChildren() -> [Any]? { accessibility.children }
    public override func isAccessibilityElement() -> Bool { false }
    public override func accessibilityRole() -> NSAccessibility.Role? { .group }
    public override func accessibilityLabel() -> String? { "SKALA-2000 operator console" }
}
