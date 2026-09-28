import AppKit
import ConsoleKit
import DeskArt
import QuartzCore

/// The desk as a tree of layers in desk units, 2500 × 1800, origin top left.
///
/// The art is drawn once, off the main thread, into an `ArtSet`; this class only places
/// its images, then moves, swaps and fades them as snapshots arrive. Each apply touches
/// only what changed, inside one transaction.
@MainActor
final class DeskLayers {

    let desk = CALayer()
    private let background = CALayer()

    final class Cap {
        let id: InstrumentID
        let round: Bool
        let faceRect: CGRect
        let shadow = CALayer()
        let glow = CALayer()
        let body = CALayer()
        let face = CALayer()
        let lit = CALayer()
        let bright = CALayer()
        /// The face and its lit glass sunk into the hole, shown while the cap is down.
        let faceDown = CALayer()
        let litDown = CALayer()
        let hole = CALayer()
        var down = false
        var isLit: Bool = false
        var phase: CommandPhase = .idle

        init(id: InstrumentID, round: Bool, faceRect: CGRect) {
            self.id = id
            self.round = round
            self.faceRect = faceRect
        }
    }

    final class Guard {
        let collar: CGRect
        let shadow = CALayer()
        let flap = CALayer()
        let hinge = CALayer()
        var open = false
        init(collar: CGRect) { self.collar = collar }
    }

    final class Tube {
        let cell: CGRect
        let xl: Bool
        let separator: Bool
        let glyph = CALayer()
        let ghost = CALayer()
        var shown: Character = " "
        init(cell: CGRect, xl: Bool, separator: Bool) {
            self.cell = cell
            self.xl = xl
            self.separator = separator
        }
    }

    final class Wheel {
        let rect: CGRect
        let clip = CALayer()
        let strip = CALayer()
        var digit = 0
        init(rect: CGRect) { self.rect = rect }
    }

    private(set) var lamps: [InstrumentID: CALayer] = [:]
    private var lampStates: [InstrumentID: LampState] = [:]
    private(set) var caps: [InstrumentID: Cap] = [:]
    private(set) var guards: [InstrumentID: Guard] = [:]
    private(set) var keys: [InstrumentID: CALayer] = [:]
    private(set) var tubes: [InstrumentID: [Tube]] = [:]
    private var nixieGlass: [InstrumentID: CALayer] = [:]
    private(set) var wheels: [InstrumentID: [Wheel]] = [:]
    private var drumGlass: [InstrumentID: CALayer] = [:]
    private(set) var needles: [InstrumentID: CALayer] = [:]
    private var meterGlass: [InstrumentID: CALayer] = [:]
    let pointer = CALayer()
    let knob = CALayer()
    private let knobHighlight = CALayer()
    let lever = CALayer()
    let buzzer = CALayer()
    private(set) var pencils: [Int: CALayer] = [:]
    private var pencilText: [Int: String] = [:]
    private let program = CALayer()
    private var programText: String?
    let focusRing = CAShapeLayer()

    private(set) var art: ArtSet?
    private var shown: ConsoleSnapshot?
    /// Buttons held by the pointer or the keyboard right now, shown down whatever the
    /// model has said so far: the cap goes down in the frame the click lands in.
    var held: Set<InstrumentID> = []
    /// Turned on or off while the desk runs, it reaches what is already moving too.
    var reduceMotion = false {
        didSet { if reduceMotion != oldValue { restartMotion() } }
    }

    private var selectorPosition = 1
    private var mainsOn = true
    private var buzzing = false
    private var meterValues: [InstrumentID: Double] = [:]

    /// The reading a meter's needle shows now, if it has been given one.
    func shownMeter(_ id: InstrumentID) -> Double? { meterValues[id] }
    private var keysArmed: Set<InstrumentID> = []

    // Geometry from the layout.
    private let selectorRect = DeskLayout.all("selector").first?.rect ?? .zero
    private let toggleRect = DeskLayout.all("toggle").first?.rect ?? .zero
    private let buzzerRect = DeskLayout.all("buzzer").first?.rect ?? .zero
    private let edgeDial = DeskLayout.all("edgeDial").first
    private let programRect = DeskLayout.all("programText").first?.rect ?? .zero

    init() {
        desk.bounds = CGRect(origin: .zero, size: DeskLayout.size)
        desk.anchorPoint = .zero
        desk.isGeometryFlipped = false
        desk.masksToBounds = true
        func add(_ layer: CALayer) {
            layer.actions = DeskLayers.noActions
            desk.addSublayer(layer)
        }
        background.frame = desk.bounds
        background.contentsGravity = .resize
        background.minificationFilter = .trilinear
        background.isOpaque = true
        add(background)

        for element in DeskLayout.all("lamp") + DeskLayout.all("lens") where !element.id.isEmpty {
            let layer = CALayer()
            layer.opacity = 0
            lamps[InstrumentID(element.id)] = layer
            add(layer)
        }

        for element in DeskLayout.all("cap") {
            caps[InstrumentID(element.id)] = Cap(
                id: InstrumentID(element.id), round: false,
                faceRect: element.rect.insetBy(dx: 6, dy: 6))
        }
        for element in DeskLayout.all("roundCap") {
            caps[InstrumentID(element.id)] = Cap(
                id: InstrumentID(element.id), round: true,
                faceRect: element.rect.insetBy(dx: 8, dy: 8))
        }
        for cap in caps.values.sorted(by: { $0.id < $1.id }) {
            for layer in [cap.shadow, cap.glow, cap.body, cap.hole] { add(layer) }
            cap.glow.opacity = 0
            cap.hole.opacity = 0
            cap.body.frame = cap.faceRect
            cap.body.actions = DeskLayers.noActions
            for layer in [cap.face, cap.lit, cap.bright, cap.faceDown, cap.litDown] {
                layer.actions = DeskLayers.noActions
                cap.body.addSublayer(layer)
            }
            cap.lit.opacity = 0
            cap.bright.opacity = 0
            cap.faceDown.opacity = 0
            cap.litDown.opacity = 0
        }

        for element in DeskLayout.all("key") {
            let layer = CALayer()
            keys[InstrumentID(element.id)] = layer
            add(layer)
        }
        for element in DeskLayout.all("guard") {
            let g = Guard(collar: element.rect)
            guards[InstrumentID(element.id)] = g
            add(g.shadow)
            add(g.flap)
            g.flap.isDoubleSided = true
            add(g.hinge)
        }

        for element in DeskLayout.all("nixie") where !element.id.isEmpty {
            let id = InstrumentID(element.id)
            let cells = DeskLayout.all("tube").filter { $0.id == element.id }
                .sorted { (Int($0.text("index")) ?? 0) < (Int($1.text("index")) ?? 0) }
            tubes[id] = cells.map { cell in
                let tube = Tube(
                    cell: cell.rect, xl: cell.text("xl") == "true",
                    separator: cell.text("separator") == "true")
                tube.ghost.opacity = 0
                add(tube.ghost)
                add(tube.glyph)
                return tube
            }
            let glass = CALayer()
            nixieGlass[id] = glass
            add(glass)
        }

        for element in DeskLayout.all("drum") where !element.id.isEmpty {
            let id = InstrumentID(element.id)
            wheels[id] = DeskLayout.all("wheel").filter { $0.id == element.id }
                .sorted { (Int($0.text("index")) ?? 0) < (Int($1.text("index")) ?? 0) }
                .map { mark in
                    let wheel = Wheel(rect: mark.rect)
                    wheel.clip.frame = mark.rect
                    wheel.clip.masksToBounds = true
                    wheel.clip.actions = DeskLayers.noActions
                    wheel.strip.actions = DeskLayers.noActions
                    wheel.strip.anchorPoint = .zero
                    wheel.clip.addSublayer(wheel.strip)
                    add(wheel.clip)
                    return wheel
                }
            let glass = CALayer()
            drumGlass[id] = glass
            add(glass)
        }

        for element in DeskLayout.all("dial") where !element.id.isEmpty {
            let id = InstrumentID(element.id)
            let needle = CALayer()
            needle.anchorPoint = CGPoint(x: 0.5, y: 1)
            needle.position = CGPoint(x: element.rect.minX + 110, y: element.rect.minY + 118)
            needle.setAffineTransform(
                CGAffineTransform(rotationAngle: DeskLayers.needleAngle(Needle.leftStop)))
            needles[id] = needle
            add(needle)
            let glass = CALayer()
            meterGlass[id] = glass
            add(glass)
        }
        if let edge = edgeDial {
            add(pointer)
            let glass = CALayer()
            meterGlass[InstrumentID(edge.id)] = glass
            add(glass)
        }

        add(knob)
        add(knobHighlight)
        add(lever)
        add(buzzer)
        for element in DeskLayout.all("pencil") {
            let slot = Int(element.text("slot")) ?? 0
            let layer = CALayer()
            pencils[slot] = layer
            add(layer)
        }
        add(program)

        focusRing.fillColor = nil
        focusRing.strokeColor = CGColor(
            srgbRed: 0xF0 / 255, green: 0xB3 / 255, blue: 0x23 / 255, alpha: 1)
        focusRing.lineWidth = 3
        focusRing.isHidden = true
        add(focusRing)
    }

    static let noActions: [String: any CAAction] = [
        "contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
        "opacity": NSNull(), "transform": NSNull(), "hidden": NSNull(), "sublayers": NSNull(),
        "anchorPoint": NSNull(), "path": NSNull(), "backgroundColor": NSNull(),
    ]

    // MARK: - Art

    /// Places a freshly rendered set of images. Called on the main thread, in one
    /// transaction, so no frame shows two sets at once.
    func install(_ art: ArtSet) {
        self.art = art
        background.contents = art.background.contents

        func place(_ layer: CALayer, _ sprite: Sprite?) {
            guard let sprite else {
                layer.contents = nil
                return
            }
            layer.contents = sprite.picture.contents
            layer.bounds = CGRect(origin: .zero, size: sprite.frame.size)
            layer.position = CGPoint(
                x: sprite.frame.minX + layer.anchorPoint.x * sprite.frame.width,
                y: sprite.frame.minY + layer.anchorPoint.y * sprite.frame.height)
        }
        func placeInside(_ layer: CALayer, _ sprite: Sprite?, origin: CGPoint) {
            guard let sprite else { return }
            layer.contents = sprite.picture.contents
            layer.frame = sprite.frame.offsetBy(dx: -origin.x, dy: -origin.y)
        }

        for (id, layer) in lamps { place(layer, art.lamps[id]) }

        for cap in caps.values {
            guard let sprites = art.caps[cap.id] else { continue }
            place(cap.shadow, sprites.shadow)
            place(cap.glow, sprites.glow)
            placeInside(cap.face, sprites.face, origin: cap.faceRect.origin)
            placeInside(cap.lit, sprites.lit, origin: cap.faceRect.origin)
            placeInside(cap.faceDown, sprites.faceDown, origin: cap.faceRect.origin)
            placeInside(cap.litDown, sprites.litDown, origin: cap.faceRect.origin)
            placeInside(cap.bright, sprites.bright, origin: cap.faceRect.origin)
            place(cap.hole, sprites.hole)
        }

        for (id, layer) in keys {
            place(layer, art.keySlots[id])
            layer.setAffineTransform(
                CGAffineTransform(rotationAngle: keysArmed.contains(id) ? .pi / 2 : 0))
        }
        for (id, g) in guards {
            guard let sprites = art.guards[id] else { continue }
            place(g.shadow, sprites.shadow)
            place(g.hinge, sprites.hinge)
            // The flap hinges on its top edge.
            g.flap.anchorPoint = CGPoint(x: 0.5, y: 0)
            place(g.flap, sprites.flap)
            g.flap.transform = flapTransform(g.open ? 112 : 0, g)
        }

        for (id, list) in tubes {
            for tube in list {
                let margin = art.nixieGlyphMargin
                tube.glyph.frame = tube.cell.insetBy(dx: -margin, dy: -margin)
                tube.ghost.frame = tube.glyph.frame
                tube.glyph.contents = glyph(tube.shown, tube)
            }
            place(nixieGlass[id]!, art.nixieGlass[id])
        }

        for (id, list) in wheels {
            for wheel in list {
                guard let strip = art.drumStrip else { continue }
                wheel.strip.contents = strip.picture.contents
                wheel.strip.bounds = CGRect(origin: .zero, size: strip.frame.size)
                wheel.strip.position = CGPoint(x: 0, y: -CGFloat(wheel.digit) * wheel.rect.height)
            }
            place(drumGlass[id]!, art.drumGlass[id])
        }

        for (id, needle) in needles {
            if let sprite = art.needle {
                needle.contents = sprite.picture.contents
                needle.bounds = CGRect(origin: .zero, size: sprite.frame.size)
            }
            place(meterGlass[id]!, art.meterGlass[id])
        }
        if let edge = edgeDial {
            place(meterGlass[InstrumentID(edge.id)]!, art.meterGlass[InstrumentID(edge.id)])
            if let sprite = art.pointer {
                pointer.contents = sprite.picture.contents
                pointer.anchorPoint = CGPoint(
                    x: -sprite.frame.minX / sprite.frame.width,
                    y: -sprite.frame.minY / sprite.frame.height)
                pointer.bounds = CGRect(origin: .zero, size: sprite.frame.size)
                pointer.position = pointerPosition(meterValues[PK4.batteryMeter] ?? 0)
            }
        }

        if let sprite = art.knob {
            knob.contents = sprite.picture.contents
            knob.bounds = CGRect(origin: .zero, size: sprite.frame.size)
            knob.anchorPoint = CGPoint(
                x: (selectorRect.midX - sprite.frame.minX) / sprite.frame.width,
                y: (selectorRect.midY - sprite.frame.minY) / sprite.frame.height)
            knob.position = CGPoint(x: selectorRect.midX, y: selectorRect.midY)
            knob.setAffineTransform(CGAffineTransform(rotationAngle: knobAngle(selectorPosition)))
        }
        place(knobHighlight, art.knobHighlight)
        if let sprite = art.lever {
            lever.contents = sprite.picture.contents
            lever.bounds = CGRect(origin: .zero, size: sprite.frame.size)
            let pivot = CGPoint(x: toggleRect.minX + 36, y: toggleRect.minY + 70)
            lever.anchorPoint = CGPoint(
                x: (pivot.x - sprite.frame.minX) / sprite.frame.width,
                y: (pivot.y - sprite.frame.minY) / sprite.frame.height)
            lever.position = pivot
            lever.setAffineTransform(CGAffineTransform(scaleX: 1, y: mainsOn ? 1 : -1))
        }
        place(buzzer, art.buzzer)

        for (slot, layer) in pencils {
            guard
                let holder = DeskLayout.all("pencil").first(where: { $0.text("slot") == "\(slot)" }
                )?.rect
            else {
                continue
            }
            place(layer, art.pencil(pencilText[slot] ?? "", holder: holder))
        }
        place(program, art.programBuild(programText ?? " ", in: programRect))
    }

    private func glyph(_ character: Character, _ tube: Tube) -> Any? {
        guard character != " ", let art else { return nil }
        return art.nixieGlyphs[tube.xl]?[character]?.contents
    }

    // MARK: - Geometry

    static func needleAngle(_ value: Double) -> CGFloat {
        // Never outside the scale: resting below zero read as a zero that was wrong.
        CGFloat((-60 + 120 * min(1, max(0, value))) * .pi / 180)
    }

    private func knobAngle(_ position: Int, lean: Double = 0) -> CGFloat {
        CGFloat((-90 + 60 * Double(position - 1) + lean) * .pi / 180)
    }

    private func pointerPosition(_ value: Double) -> CGPoint {
        guard let dial = edgeDial?.rect else { return .zero }
        let top: CGFloat = 16
        let bottom: CGFloat = 204
        let fraction = CGFloat(min(1, max(0, value)))
        return CGPoint(x: dial.minX, y: dial.minY + bottom - (bottom - top) * fraction)
    }

    /// The flap turned `degrees` about its top edge, in perspective, as the reference's
    /// `rotation3DEffect(perspective: 0.35)`.
    private func flapTransform(_ degrees: Double, _ g: Guard) -> CATransform3D {
        var transform = CATransform3DIdentity
        let size = g.flap.bounds.size
        transform.m34 = -0.35 / max(size.width, size.height, 1)
        return CATransform3DRotate(transform, CGFloat(degrees * .pi / 180), 1, 0, 0)
    }

    // MARK: - Snapshot

    /// Brings every instrument to `snapshot`, animating what moves. Only what changed is
    /// touched.
    func apply(_ snapshot: ConsoleSnapshot, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
            shown = snapshot
        }
        let old = shown
        let animate = animated && old != nil

        // Lamps and lenses.
        for (id, layer) in lamps {
            let state = snapshot.lamp(id)
            let before = lampStates[id] ?? .off
            guard state != before || old == nil else { continue }
            lampStates[id] = state
            setLamp(layer, state, from: before, animate: animate)
        }

        // Buttons.
        for cap in caps.values {
            let face = snapshot.button(cap.id)
            setCap(cap, face: face, animate: animate)
        }

        // Guards and keys.
        for (id, g) in guards {
            let open = snapshot.guardsOpen.contains(id)
            if open != g.open {
                g.open = open
                swing(g, open: open, animate: animate)
            }
        }
        if snapshot.keysArmed != keysArmed {
            for (id, layer) in keys where snapshot.keysArmed.contains(id) != keysArmed.contains(id)
            {
                let armed = snapshot.keysArmed.contains(id)
                let angle: CGFloat = armed ? .pi / 2 : 0
                if animate && !reduceMotion {
                    let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                    turn.fromValue = armed ? 0 : CGFloat.pi / 2
                    turn.toValue = angle
                    turn.duration = Motion.keyTurn
                    turn.timingFunction = Motion.backOut
                    layer.add(turn, forKey: "turn")
                }
                layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            }
            keysArmed = snapshot.keysArmed
        }

        // Nixies.
        for (id, list) in tubes {
            let value = Array(snapshot.nixie(id))
            for (index, tube) in list.enumerated() {
                let character = index < value.count ? value[index] : " "
                guard character != tube.shown else { continue }
                let previous = tube.shown
                tube.shown = character
                tube.glyph.contents = glyph(character, tube)
                // The old digit lingers as a 35% ghost for 60 ms: a cathode cooling.
                if animate, previous != " " {
                    tube.ghost.contents = glyph(previous, tube)
                    let ghost = CABasicAnimation(keyPath: "opacity")
                    ghost.fromValue = 0.35
                    ghost.toValue = 0.35
                    ghost.duration = Motion.nixieGhost
                    tube.ghost.add(ghost, forKey: "ghost")
                }
            }
        }

        // Drum counters roll forward only.
        for (id, list) in wheels {
            let value = max(0, snapshot.drum(id)) % 1_000_000
            let digits = String(format: "%06d", value).compactMap(\.wholeNumberValue)
            for (index, wheel) in list.enumerated() where index < digits.count {
                roll(
                    wheel, to: digits[index],
                    delay: Double(list.count - 1 - index) * Motion.wheelStagger, animate: animate)
            }
        }

        // Meters.
        let powered = snapshot.mains
        for (id, needle) in needles {
            let value = snapshot.meter(id)
            guard meterValues[id] != value || old?.mains != powered else { continue }
            let before = meterValues[id] ?? Needle.leftStop
            meterValues[id] = value
            let from = DeskLayers.needleAngle(before)
            let to = DeskLayers.needleAngle(value)
            if animate && !reduceMotion && from != to {
                if powered {
                    let spring = Motion.needle()
                    spring.fromValue =
                        needle.presentation()?.value(forKeyPath: "transform.rotation.z") ?? from
                    spring.toValue = to
                    needle.add(spring, forKey: "swing")
                } else {
                    let fall = CABasicAnimation(keyPath: "transform.rotation.z")
                    fall.fromValue =
                        needle.presentation()?.value(forKeyPath: "transform.rotation.z") ?? from
                    fall.toValue = to
                    fall.duration = Motion.needleFall
                    fall.timingFunction = Motion.easeIn
                    needle.add(fall, forKey: "swing")
                }
            }
            needle.setAffineTransform(CGAffineTransform(rotationAngle: to))
        }
        let battery = snapshot.meter(PK4.batteryMeter)
        if meterValues[PK4.batteryMeter] != battery {
            meterValues[PK4.batteryMeter] = battery
            let target = pointerPosition(battery)
            if animate && !reduceMotion {
                let spring = Motion.pointer()
                spring.fromValue = pointer.presentation()?.position.y ?? pointer.position.y
                spring.toValue = target.y
                pointer.add(spring, forKey: "slide")
            }
            pointer.position = target
        }

        // The selector.
        if snapshot.selector != selectorPosition {
            let from = knobAngle(selectorPosition)
            selectorPosition = snapshot.selector
            let to = knobAngle(selectorPosition)
            if animate && !reduceMotion {
                let spring = Motion.detent()
                spring.fromValue =
                    knob.presentation()?.value(forKeyPath: "transform.rotation.z") ?? from
                spring.toValue = to
                knob.add(spring, forKey: "detent")
            }
            knob.setAffineTransform(CGAffineTransform(rotationAngle: to))
        }

        // MAINS.
        if snapshot.mains != mainsOn {
            mainsOn = snapshot.mains
            let to: CGFloat = mainsOn ? 1 : -1
            if animate && !reduceMotion {
                let flip = CABasicAnimation(keyPath: "transform.scale.y")
                flip.fromValue = -to
                flip.toValue = to
                flip.duration = Motion.toggle
                flip.timingFunction = Motion.toggleCurve
                lever.add(flip, forKey: "throw")
            }
            lever.setAffineTransform(CGAffineTransform(scaleX: 1, y: to))
        }

        // The buzzer trembles while it sounds.
        if snapshot.buzzer != buzzing {
            buzzing = snapshot.buzzer
            shakeBuzzer()
        }

        // Paper.
        if let art {
            for (slot, layer) in pencils {
                let text = snapshot.pencil(slot: slot)
                guard pencilText[slot] != text else { continue }
                pencilText[slot] = text
                if let holder = DeskLayout.all("pencil").first(where: {
                    $0.text("slot") == "\(slot)"
                })?.rect {
                    if let sprite = art.pencil(text, holder: holder) {
                        layer.contents = sprite.picture.contents
                        layer.frame = sprite.frame
                    }
                }
            }
            if snapshot.programBuild != programText {
                programText = snapshot.programBuild
                if let sprite = art.programBuild(programText ?? " ", in: programRect) {
                    program.contents = sprite.picture.contents
                    program.frame = sprite.frame
                }
            }
        } else {
            for slot in pencils.keys { pencilText[slot] = snapshot.pencil(slot: slot) }
            programText = snapshot.programBuild
        }
    }

    private func setLamp(
        _ layer: CALayer, _ state: LampState, from before: LampState, animate: Bool
    ) {
        switch state {
        case .flash:
            layer.opacity = 0
            layer.add(Motion.flash(reduceMotion: reduceMotion), forKey: "flash")
        case .on, .test, .off:
            let lit = state != .off
            let current = layer.presentation()?.opacity ?? layer.opacity
            layer.removeAnimation(forKey: "flash")
            layer.opacity = lit ? 1 : 0
            if animate {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = current
                fade.toValue = layer.opacity
                fade.duration = lit ? Motion.lampOn : Motion.lampOff
                fade.timingFunction = lit ? Motion.easeIn : Motion.easeOut
                layer.add(fade, forKey: "fade")
            }
        }
    }

    private func setCap(_ cap: Cap, face: ButtonFace, animate: Bool) {
        let down = face.capDown || held.contains(cap.id)
        let lit = !cap.round && (face.lamp == .on || face.lamp == .test)
        let wasDown = cap.down
        let wasLit = cap.isLit
        guard down != wasDown || lit != wasLit || face.phase != cap.phase else { return }
        cap.down = down
        cap.isLit = lit

        // Every layer that shows, and how opaque it should be now.
        let targets: [(CALayer, Float, CFTimeInterval, CAMediaTimingFunction)] = [
            (cap.face, down ? 0 : 1, Motion.cap, Motion.linear),
            (cap.faceDown, down ? 1 : 0, Motion.cap, Motion.linear),
            (
                cap.lit, lit && !down ? 1 : 0,
                lit != wasLit ? (lit ? Motion.lampOn : Motion.lampOff) : Motion.cap,
                lit != wasLit ? (lit ? Motion.easeIn : Motion.easeOut) : Motion.linear
            ),
            (
                cap.litDown, lit && down ? 1 : 0,
                lit != wasLit ? (lit ? Motion.lampOn : Motion.lampOff) : Motion.cap,
                lit != wasLit ? (lit ? Motion.easeIn : Motion.easeOut) : Motion.linear
            ),
            (
                cap.glow, lit ? 1 : 0, lit ? Motion.lampOn : Motion.lampOff,
                lit ? Motion.easeIn : Motion.easeOut
            ),
            (cap.hole, down ? 1 : 0, Motion.cap, Motion.linear),
            (cap.shadow, down ? 0 : 1, Motion.cap, Motion.linear),
        ]
        for (layer, target, duration, curve) in targets where layer.opacity != target {
            if animate {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
                fade.toValue = target
                fade.duration = duration
                fade.timingFunction = curve
                layer.add(fade, forKey: "fade")
            }
            layer.opacity = target
        }
        if down != wasDown {
            let scale: CGFloat = down ? 0.89 : 1
            if animate {
                let press = CABasicAnimation(keyPath: "transform.scale")
                press.fromValue =
                    cap.body.presentation()?.value(forKeyPath: "transform.scale")
                    ?? (down ? 1 : 0.89)
                press.toValue = scale
                press.duration = Motion.cap
                press.timingFunction = Motion.linear
                cap.body.add(press, forKey: "press")
            }
            cap.body.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        if face.phase != cap.phase {
            cap.phase = face.phase
            if face.phase == .noAnswer, !cap.round {
                cap.bright.add(Motion.noAnswerBlink(), forKey: "blink")
            } else {
                cap.bright.removeAnimation(forKey: "blink")
            }
        }
    }

    private func roll(_ wheel: Wheel, to digit: Int, delay: Double, animate: Bool) {
        guard digit != wheel.digit else { return }
        let height = wheel.rect.height
        // Forward only: a wheel passing 9 goes on to 0 in the same direction.
        let steps = (digit - wheel.digit + 10) % 10
        let from = CGFloat(wheel.digit)
        let to = from + CGFloat(steps)
        wheel.digit = digit
        let rest = CGPoint(x: 0, y: -CGFloat(digit) * height)
        guard animate, !reduceMotion else {
            wheel.strip.position = rest
            return
        }
        // Roll down the strip to the digit's second appearance if need be, then settle on
        // its first without anyone seeing the jump.
        let spring = Motion.wheel()
        spring.fromValue = -from * height
        spring.toValue = -to * height
        spring.beginTime = CACurrentMediaTime() + delay
        spring.fillMode = .backwards
        wheel.strip.add(spring, forKey: "roll")
        wheel.strip.position = CGPoint(x: 0, y: -to * height)
        if to != CGFloat(digit) {
            let settle = spring.duration + delay
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak wheel] in
                guard let wheel, wheel.digit == digit else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                wheel.strip.removeAnimation(forKey: "roll")
                wheel.strip.position = rest
                CATransaction.commit()
            }
        }
    }

    /// Lifted by hand: up past its rest to 121° and back to 112°. Let go, it falls under
    /// gravity, lands, bounces twice and settles.
    private func swing(_ g: Guard, open: Bool, animate: Bool) {
        let rest: Double = open ? 112 : 0
        g.flap.transform = flapTransform(rest, g)
        g.shadow.opacity = open ? 0 : 1
        guard animate, !reduceMotion else {
            g.flap.removeAnimation(forKey: "swing")
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        let from = (g.flap.presentation()?.value(forKeyPath: "transform.rotation.x") as? Double).map
        { $0 * 180 / .pi }
        if open {
            let start = from ?? 0
            animation.values = [start, 121, 112].map {
                NSValue(caTransform3D: flapTransform($0, g))
            }
            animation.keyTimes = [0, NSNumber(value: 0.187 / 0.26), 1]
            animation.timingFunctions = [Motion.easeOut, Motion.easeInOut]
            animation.duration = 0.26
        } else {
            let start = from ?? 112
            animation.values = [start, 0, 15, 0, 4, 0].map {
                NSValue(caTransform3D: flapTransform($0, g))
            }
            animation.keyTimes = [0, 0.27, 0.35, 0.43, 0.475, 0.52].map {
                NSNumber(value: $0 / 0.52)
            }
            animation.timingFunctions = [
                CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.6), Motion.easeOut,
                Motion.easeIn,
                Motion.easeOut, Motion.easeIn,
            ]
            animation.duration = 0.52
        }
        g.flap.add(animation, forKey: "swing")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = open ? 1 : 0
        fade.toValue = open ? 0 : 1
        fade.duration = open ? 0.1 : 0.27
        fade.beginTime = CACurrentMediaTime() + (open ? 0 : 0.2)
        fade.fillMode = .backwards
        g.shadow.add(fade, forKey: "fade")
    }

    private func shakeBuzzer() {
        guard buzzing && !reduceMotion else {
            buzzer.removeAnimation(forKey: "shake")
            return
        }
        let shake = CABasicAnimation(keyPath: "position.x")
        shake.byValue = 0.6
        shake.duration = 0.02
        shake.autoreverses = true
        shake.repeatCount = .infinity
        // Nobody sees 120 trembles a second, and every frame costs WindowServer a redraw.
        shake.preferredFrameRateRange = Motion.flashRate
        buzzer.add(shake, forKey: "shake")
    }

    /// What never stops by itself takes a new Reduce Motion at once: the flash's period,
    /// the buzzer's tremble. What moves once is only ever started with the current one.
    private func restartMotion() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, layer) in lamps where lampStates[id] == .flash {
            layer.add(Motion.flash(reduceMotion: reduceMotion), forKey: "flash")
        }
        shakeBuzzer()
        CATransaction.commit()
    }

    /// The knob leans 6° on its stop pin and springs back, 90 + 170 ms.
    func leanOnStop(_ direction: Int) {
        guard !reduceMotion else { return }
        let rest = knobAngle(selectorPosition)
        let lean = knobAngle(selectorPosition, lean: Double(direction) * 6)
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [rest, lean, rest]
        animation.keyTimes = [0, NSNumber(value: 0.09 / 0.26), 1]
        animation.timingFunctions = [Motion.easeOut, Motion.backOut]
        animation.duration = 0.26
        knob.add(animation, forKey: "lean")
    }

    // MARK: - Focus

    func showFocus(_ rect: CGRect?, round: Bool, radius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            // 3 points of lit amber, 3 points out.
            let ring = rect.insetBy(dx: -4.5, dy: -4.5)
            focusRing.path =
                round
                ? CGPath(ellipseIn: ring, transform: nil)
                : CGPath(
                    roundedRect: ring, cornerWidth: radius + 4.5, cornerHeight: radius + 4.5,
                    transform: nil)
            focusRing.isHidden = false
        } else {
            focusRing.isHidden = true
        }
        CATransaction.commit()
    }
}
