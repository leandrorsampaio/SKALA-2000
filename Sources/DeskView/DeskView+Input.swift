import AppKit
import ConsoleKit
import DeskArt

/// The operator's hand and keyboard.
///
/// - Mouse-down on a button presses it and shows the cap down in the same frame; mouse-up
///   **anywhere** releases it. A real button has no cancel, and a release is never lost:
///   the window losing key, or the view leaving it, releases too.
/// - A click never moves keyboard focus. The amber ring is for the keyboard only.
extension DeskView {

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        let point = deskPoint(convert(event.locationInWindow, from: nil))
        guard let control = hitTable.control(at: point, guardsOpen: snapshot.guardsOpen) else {
            // The window has no title bar: bare steel is where it is picked up and moved.
            window?.performDrag(with: event)
            return
        }
        act(on: control, at: point)
    }

    public override func mouseUp(with event: NSEvent) {
        releasePressed()
    }

    public override func rightMouseDown(with event: NSEvent) {}

    /// Anything held is let go. Called on mouse-up anywhere, and whenever the window stops
    /// being able to deliver one.
    public func releasePressed() {
        guard let id = pressed else { return }
        pressed = nil
        layers.held.remove(id)
        layers.apply(snapshot, animated: true)
        click()
        send(.release(id))
    }

    func act(on control: HitTable.Control, at point: CGPoint) {
        switch control.kind {
        case .button, .round:
            press(control.id)
        case .flap:
            send(.guard(control.id, open: true))
        case .hinge:
            send(.guard(control.id, open: false))
        case .key:
            send(.key(control.id, armed: !snapshot.keysArmed.contains(control.id)))
        case .selector:
            if let numeral = HitTable.numeral(at: point, in: control.rect) {
                send(.selectorGoTo(numeral))
            } else {
                turnSelector(point.x >= control.rect.midX ? 1 : -1)
            }
        case .toggle:
            send(.mains(!snapshot.mains))
        case .pencil:
            beginPencil(control)
        }
    }

    func press(_ id: InstrumentID) {
        guard pressed == nil else { return }
        pressed = id
        // The cap goes down in this frame, before the model has said anything.
        layers.held.insert(id)
        layers.apply(snapshot, animated: true)
        click()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        send(.press(id))
    }

    func turnSelector(_ direction: Int) {
        let next = snapshot.selector + direction
        guard PK4.slots.contains(next) else {
            // At a stop the knob leans on its pin and springs back, with a dull click.
            layers.leanOnStop(direction)
            stopClick()
            return
        }
        send(.selectorStep(direction))
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        releasePressed()
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResignKeyNotification, object: nil)
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification,
                object: newWindow)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func windowResigned() {
        releasePressed()
        endPencil(commit: true)
    }

    // MARK: - Keyboard

    var focusable: [HitTable.Control] {
        hitTable.tabOrder.filter { control in
            switch control.kind {
            // Under a closed guard there is nothing to reach, by hand or by Tab.
            case .button, .key:
                if let guardID = control.guardedBy { return snapshot.guardsOpen.contains(guardID) }
                return true
            default: return true
            }
        }
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48:  // Tab
            moveFocus(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 49, 36, 76:  // Space, Return, Enter
            guard let control = keyboardFocus else { return super.keyDown(with: event) }
            if event.isARepeat { return }
            switch control.kind {
            case .button, .round: press(control.id)
            case .flap: send(.guard(control.id, open: !snapshot.guardsOpen.contains(control.id)))
            case .key: send(.key(control.id, armed: !snapshot.keysArmed.contains(control.id)))
            case .toggle: send(.mains(!snapshot.mains))
            case .pencil: beginPencil(control)
            case .selector, .hinge: break
            }
        case 123, 125:  // Left, down
            if keyboardFocus?.kind == .selector {
                turnSelector(-1)
            } else {
                super.keyDown(with: event)
            }
        case 124, 126:  // Right, up
            if keyboardFocus?.kind == .selector {
                turnSelector(1)
            } else {
                super.keyDown(with: event)
            }
        case 53:  // Escape
            setFocus(nil)
        default:
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36, 76: releasePressed()
        default: super.keyUp(with: event)
        }
    }

    func moveFocus(_ direction: Int) {
        let order = focusable
        guard !order.isEmpty else { return }
        let index = keyboardFocus.flatMap { focus in
            order.firstIndex { $0.id == focus.id && $0.kind == focus.kind }
        }
        let next: Int
        if let index {
            next = (index + direction + order.count) % order.count
        } else {
            next = direction > 0 ? 0 : order.count - 1
        }
        setFocus(order[next])
    }

    func setFocus(_ control: HitTable.Control?) {
        keyboardFocus = control
        focusFromKeyboard = control != nil
        layers.showFocus(
            control?.rect, round: control?.round ?? false, radius: control?.radius ?? 0)
    }

    /// A guard that falls takes the focus off what it now covers.
    func refreshFocus() {
        guard let focus = keyboardFocus else { return }
        if !focusable.contains(where: { $0.id == focus.id && $0.kind == focus.kind }) {
            setFocus(hitTable.controls.first { $0.kind == .flap && $0.id == focus.guardedBy })
        }
    }

    // MARK: - Pencil

    /// Picks up the pencil: a real, borderless text field over the strip, twelve
    /// characters at most. Return or clicking away puts it down.
    func beginPencil(_ control: HitTable.Control) {
        endPencil(commit: true)
        guard let slot = Int(control.id.rawValue.split(separator: ".").last ?? "") else { return }
        let field = PencilField(slot: slot)
        field.stringValue = snapshot.pencil(slot: slot)
        field.frame = viewRect(control.rect.insetBy(dx: 6, dy: 6))
        field.font = NSFont(name: DeskFonts.pencil, size: 22 * deskScale)
        field.onEnd = { [weak self] commit in self?.endPencil(commit: commit) }
        field.onChange = { [weak self] text in self?.send(.pencil(slot: slot, text: text)) }
        addSubview(field)
        window?.makeFirstResponder(field)
        pencilField = field
    }

    func endPencil(commit: Bool) {
        guard let field = pencilField else { return }
        pencilField = nil
        if commit { send(.pencil(slot: field.slot, text: String(field.stringValue.prefix(12)))) }
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
    }
}

/// The pencil on the paper strip while the operator writes.
final class PencilField: NSTextField, NSTextFieldDelegate {
    let slot: Int
    var onEnd: (Bool) -> Void = { _ in }
    var onChange: (String) -> Void = { _ in }

    init(slot: Int) {
        self.slot = slot
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        alignment = .center
        textColor = NSColor(srgbRed: 0x4A / 255, green: 0x4A / 255, blue: 0x48 / 255, alpha: 1)
        delegate = self
        cell?.usesSingleLineMode = true
        cell?.lineBreakMode = .byClipping
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func controlTextDidChange(_ notification: Notification) {
        if stringValue.count > 12 { stringValue = String(stringValue.prefix(12)) }
        onChange(stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool
    {
        if selector == #selector(NSResponder.insertNewline(_:))
            || selector == #selector(NSResponder.cancelOperation(_:))
        {
            onEnd(true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        onEnd(true)
    }
}
