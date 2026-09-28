import AppKit
import ConsoleKit
import DeskArt
import Testing

@testable import DeskView

/// The hit table, and the hand and keyboard on a real DeskView in a window of its own.
@MainActor
struct HitTableTests {

    let table = HitTable()

    /// The controls a click can reach with the guards in one state: a closed flap covers
    /// its cap and key, a lifted one bares them and stands over its hinge.
    func reachable(guardsOpen: Bool) -> [HitTable.Control] {
        table.controls.filter { control in
            switch control.kind {
            case .flap: return !guardsOpen
            case .hinge: return guardsOpen
            default: return control.guardedBy == nil || guardsOpen
            }
        }
    }

    /// The worst bug the reference had: invisible paint lying over neighbours' buttons.
    @Test func noTwoControlsOverlap() {
        for open in [false, true] {
            let controls = reachable(guardsOpen: open)
            for (i, a) in controls.enumerated() {
                for b in controls[(i + 1)...] {
                    #expect(
                        !a.rect.intersects(b.rect),
                        "\(a.kind) \(a.id) overlaps \(b.kind) \(b.id) with guards \(open ? "up" : "down")"
                    )
                }
            }
        }
    }

    @Test func everyControlLiesInsideItsPanel() {
        for control in table.controls {
            guard let panel = table.panels[control.panel] else {
                Issue.record("\(control.id) is in no panel")
                continue
            }
            #expect(
                panel.contains(control.rect), "\(control.id) reaches outside panel \(control.panel)"
            )
        }
    }

    @Test func everyButtonHasAControl() {
        let ids = Set(table.controls.map(\.id))
        for id in PK4.litButtons + PK4.round + [PK4.selector, PK4.mains] {
            #expect(ids.contains(id), "\(id) cannot be clicked")
        }
        for slot in PK4.slots { #expect(ids.contains(PK4.pencil(slot: slot))) }
        #expect(table.controls.contains { $0.kind == .key && $0.id == PK4.f12 })
    }

    @Test func everyPanelFitsTheDesk() {
        let desk = CGRect(origin: .zero, size: DeskLayout.size).insetBy(dx: 22, dy: 22)
        for (name, panel) in table.panels {
            #expect(desk.contains(panel), "panel \(name) runs off the desk: \(panel)")
        }
        // Nothing drawn runs off the desk either.
        for element in DeskLayout.elements where element.kind != "desk" {
            #expect(
                CGRect(origin: .zero, size: DeskLayout.size).contains(element.rect),
                "\(element.kind) \(element.id) runs off the desk")
        }
    }

    @Test func aClosedGuardTakesTheClickMeantForItsButton() throws {
        let cap = try #require(table.controls.first { $0.id == PK4.f12 && $0.kind == .button })
        let point = CGPoint(x: cap.rect.midX, y: cap.rect.midY)
        #expect(table.control(at: point, guardsOpen: [])?.kind == .flap)
        #expect(table.control(at: point, guardsOpen: [PK4.f12])?.kind == .button)
    }

    @Test func roundThingsTakeClicksInsideTheirCircle() throws {
        let selector = try #require(table.controls.first { $0.kind == .selector })
        let corner = CGPoint(x: selector.rect.minX + 2, y: selector.rect.minY + 2)
        #expect(table.control(at: corner, guardsOpen: []) == nil)
    }

    @Test func theSelectorsNumeralsAreWhereTheyArePainted() throws {
        let rect = try #require(table.controls.first { $0.kind == .selector }?.rect)
        let k = rect.width / 240
        // Numeral 1 at the left, 4 at the right, 96 units out on the 240-unit dial.
        #expect(HitTable.numeral(at: CGPoint(x: rect.minX + 24 * k, y: rect.midY), in: rect) == 1)
        #expect(HitTable.numeral(at: CGPoint(x: rect.maxX - 24 * k, y: rect.midY), in: rect) == 4)
        #expect(HitTable.numeral(at: CGPoint(x: rect.midX, y: rect.midY), in: rect) == nil)
    }
}

@MainActor
@Suite(.serialized)
final class DeskViewInputTests {

    let window: NSWindow
    let view: DeskView
    var sent: [ConsoleIntent] = []
    var clicks = 0

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1250, height: 900), styleMask: [.titled],
            backing: .buffered, defer: true)
        view = DeskView(frame: NSRect(x: 0, y: 0, width: 1250, height: 900))
        window.contentView = view
        view.send = { [weak self] in self?.sent.append($0) }
        view.click = { [weak self] in self?.clicks += 1 }
        view.apply(ConsoleSnapshot())
    }

    /// A mouse event at a point in desk units.
    func event(_ type: NSEvent.EventType, at desk: CGPoint) -> NSEvent {
        let k = view.deskScale
        let origin = view.deskOrigin
        // The view is flipped; the window is not.
        let inView = CGPoint(x: origin.x + desk.x * k, y: origin.y + desk.y * k)
        let inWindow = view.convert(inView, to: nil)
        return NSEvent.mouseEvent(
            with: type, location: inWindow, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 1)!
    }

    func key(_ code: UInt16, down: Bool, shift: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: shift ? .shift : [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func center(of id: InstrumentID, _ kind: HitTable.Kind = .button) -> CGPoint {
        let rect = view.hitTable.controls.first { $0.id == id && $0.kind == kind }!.rect
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test func mouseDownPressesAndTheCapGoesDownAtOnce() {
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.acknowledge)))
        #expect(sent == [.press(PK4.acknowledge)])
        #expect(view.layers.held.contains(PK4.acknowledge))
        #expect(clicks == 1)
    }

    /// A real button has no cancel: dragging off the cap and letting go still sends.
    @Test func mouseUpAnywhereReleases() {
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.silence)))
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 5, y: 5)))
        #expect(sent == [.press(PK4.silence), .release(PK4.silence)])
        #expect(!view.layers.held.contains(PK4.silence))
        #expect(clicks == 2)
    }

    @Test func losingTheWindowReleasesWhatIsHeld() {
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.lampTest)))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(sent == [.press(PK4.lampTest), .release(PK4.lampTest)])
    }

    @Test func clickingAClosedGuardLiftsItAndPressesNothing() {
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.f12)))
        #expect(sent == [.guard(PK4.f12, open: true)])
    }

    @Test func theKeyAndCapAnswerOnlyWithTheGuardUp() {
        var s = ConsoleSnapshot()
        s.guardsOpen = [PK4.f12]
        view.apply(s)
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.f12, .key)))
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.f12)))
        #expect(sent == [.key(PK4.f12, armed: true), .press(PK4.f12)])
    }

    @Test func theSelectorWalksToANumeralOrStepsByHalves() throws {
        let rect = try #require(view.hitTable.controls.first { $0.kind == .selector }?.rect)
        let k = rect.width / 240
        view.mouseDown(
            with: event(.leftMouseDown, at: CGPoint(x: rect.maxX - 24 * k, y: rect.midY)))
        view.mouseDown(
            with: event(.leftMouseDown, at: CGPoint(x: rect.midX + 10, y: rect.midY + 30)))
        #expect(sent == [.selectorGoTo(4), .selectorStep(1)])
    }

    @Test func theSelectorLeansOnItsStopAndSendsNothing() throws {
        // The lean is motion: whatever this Mac's Reduce Motion says, it is under test here.
        view.layers.reduceMotion = false
        let rect = try #require(view.hitTable.controls.first { $0.kind == .selector }?.rect)
        view.mouseDown(
            with: event(.leftMouseDown, at: CGPoint(x: rect.midX - 10, y: rect.midY + 30)))
        #expect(sent.isEmpty)
        #expect(view.layers.knob.animation(forKey: "lean") != nil)
    }

    @Test func theMainsToggleThrows() {
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.mains, .toggle)))
        #expect(sent == [.mains(false)])
    }

    @Test func paintAndLampsTakeNoClicks() throws {
        let lamp = try #require(
            DeskLayout.first("lamp", id: PK4.annunciator(.run, slot: 1).rawValue))
        view.mouseDown(
            with: event(.leftMouseDown, at: CGPoint(x: lamp.rect.midX, y: lamp.rect.midY)))
        // The gap between panels A and B, and an instruction plate.
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 680, y: 1000)))
        let plate = try #require(DeskLayout.all("instruction").first)
        view.mouseDown(
            with: event(.leftMouseDown, at: CGPoint(x: plate.rect.midX, y: plate.rect.midY)))
        #expect(sent.isEmpty)
    }

    /// The ring is for the keyboard: a click never moves focus.
    @Test func aClickNeverMovesKeyboardFocus() {
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.acknowledge)))
        view.mouseUp(with: event(.leftMouseUp, at: center(of: PK4.acknowledge)))
        #expect(view.keyboardFocus == nil)
        #expect(view.layers.focusRing.isHidden)
    }

    @Test func tabWalksThePanelsInOrderAndSpacePresses() throws {
        view.keyDown(with: key(48, down: true))
        let first = try #require(view.keyboardFocus)
        #expect(first.panel == "A")
        #expect(!view.layers.focusRing.isHidden)
        var panels: [String] = [first.panel]
        for _ in 0..<60 {
            view.keyDown(with: key(48, down: true))
            if let focus = view.keyboardFocus, focus.panel != panels.last {
                panels.append(focus.panel)
            }
        }
        // Panel E has nothing to press since MAINS moved to D: from D, Tab comes round to A.
        #expect(Array(panels.prefix(5)) == ["A", "B", "C", "D", "A"])

        // Back to a button and press it with the space bar: down on keydown, up on keyup.
        let silence = try #require(view.hitTable.controls.first { $0.id == PK4.silence })
        view.setFocus(silence)
        sent = []
        view.keyDown(with: key(49, down: true))
        view.keyUp(with: key(49, down: false))
        #expect(sent == [.press(PK4.silence), .release(PK4.silence)])
    }

    @Test func aClosedGuardsButtonIsNotATabStop() {
        #expect(!view.focusable.contains { $0.id == PK4.f11 && $0.kind == .button })
        #expect(view.focusable.contains { $0.id == PK4.f11 && $0.kind == .flap })
        var s = ConsoleSnapshot()
        s.guardsOpen = [PK4.f11]
        view.apply(s)
        #expect(view.focusable.contains { $0.id == PK4.f11 && $0.kind == .button })
    }

    /// The guard falls over the button that has the keyboard: the focus goes to the flap.
    @Test func aFallingGuardTakesTheFocusWithIt() throws {
        var s = ConsoleSnapshot()
        s.guardsOpen = [PK4.f11]
        view.apply(s)
        let cap = try #require(
            view.hitTable.controls.first { $0.id == PK4.f11 && $0.kind == .button })
        view.setFocus(cap)
        view.apply(ConsoleSnapshot())
        #expect(view.keyboardFocus?.id == PK4.f11)
        #expect(view.keyboardFocus?.kind == .flap)
    }

    @Test func arrowsTurnTheFocusedSelector() throws {
        let selector = try #require(view.hitTable.controls.first { $0.kind == .selector })
        view.setFocus(selector)
        view.keyDown(with: key(124, down: true))
        #expect(sent == [.selectorStep(1)])
    }

    @Test func thePencilOpensAFieldAndWritesTwelveCharactersAtMost() throws {
        view.mouseDown(with: event(.leftMouseDown, at: center(of: PK4.pencil(slot: 2), .pencil)))
        let field = try #require(view.pencilField)
        field.stringValue = "a very long project name"
        field.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(field.stringValue == "a very long ")
        view.endPencil(commit: true)
        #expect(sent.last == .pencil(slot: 2, text: "a very long "))
        #expect(view.pencilField == nil)
    }
}

@MainActor
struct AccessibilityTests {

    func desk() -> (DeskView, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1250, height: 900), styleMask: [.titled],
            backing: .buffered, defer: true)
        let view = DeskView(frame: NSRect(x: 0, y: 0, width: 1250, height: 900))
        window.contentView = view
        return (view, window)
    }

    func elements(_ view: DeskView) -> [NSAccessibilityElement] {
        (view.accessibilityChildren() as? [NSAccessibilityElement] ?? []).flatMap {
            $0.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        }
    }

    @Test func thePanelsAreGroupsInReadingOrder() {
        let (view, window) = desk()
        let panels = (view.accessibilityChildren() as? [NSAccessibilityElement] ?? []).compactMap {
            $0.accessibilityLabel()
        }
        #expect(panels.count == 6)
        #expect(panels.dropFirst().map { String($0.prefix(1)) } == ["A", "B", "C", "D", "E"])
        _ = window
    }

    @Test func everyInstrumentSpeaksItsPlateAndValue() throws {
        let (view, window) = desk()
        var s = ConsoleSnapshot()
        s.lamps[PK4.annunciator(.wait, slot: 2)] = .flash
        s.meters[PK4.contextMeter] = 0.62
        s.nixies[PK4.queueDepth] = "000003"
        s.drums[PK4.totalCost] = 27
        view.apply(s)
        let all = elements(view)
        func value(_ label: String) -> String? {
            all.first { $0.accessibilityLabel() == label }?.accessibilityValue() as? String
        }
        #expect(value("Waiting for operator, session 2") == "alarm, flashing")
        #expect(value("Context remaining") == "62 percent")
        #expect(value("API share of time") == "no reading")
        #expect(value("Queue depth") == "000003")
        #expect(value("Total cost") == "27 dollars")
        #expect(value("Permission mode, bypass") == "dark")
        #expect(value("Session selector") == "Session 1")
        // 72 lamps, 18 nixie rows, 6 meters, 5 drums, 31 controls, the buzzer, the build card.
        #expect(all.count == 134)
        _ = window
    }

    @Test func buttonsPressAndTheSelectorAdjusts() throws {
        let (view, window) = desk()
        var sent: [ConsoleIntent] = []
        view.send = { sent.append($0) }
        let all = elements(view)
        let ack = try #require(all.first { $0.accessibilityLabel() == "Acknowledge" })
        #expect(ack.accessibilityRole() == .button)
        #expect(ack.accessibilityPerformPress())
        let selector = try #require(all.first { $0.accessibilityLabel() == "Session selector" })
        #expect(selector.accessibilityPerformIncrement())
        #expect(sent == [.press(PK4.acknowledge), .release(PK4.acknowledge), .selectorStep(1)])
        // Under a closed guard there is nothing to press.
        let f10 = try #require(all.first { $0.accessibilityLabel() == "End session" })
        #expect(!f10.accessibilityPerformPress())
        _ = window
    }

    /// A guarded button fires only after 2 s held: VoiceOver's press holds it that long.
    @Test func aGuardedButtonIsHeldForItsTwoSeconds() async throws {
        let (view, window) = desk()
        var sent: [ConsoleIntent] = []
        view.send = { sent.append($0) }
        var s = ConsoleSnapshot()
        s.guardsOpen = [PK4.f11]
        view.apply(s)
        let f9 = try #require(
            elements(view).first { $0.accessibilityLabel() == "Function 11, unassigned" })
        #expect(f9.accessibilityPerformPress())
        #expect(sent == [.press(PK4.f11)])
        // Released about 2.2 s later: waited for, as other suites share the main thread.
        let asked = Date()
        let deadline = asked.addingTimeInterval(10)
        while sent.count < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(sent == [.press(PK4.f11), .release(PK4.f11)])
        #expect(Date().timeIntervalSince(asked) >= ConsoleTiming.holdToFire)
        _ = window
    }
}
