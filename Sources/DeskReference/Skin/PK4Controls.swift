import AppKit
import ConsoleKit
import SwiftUI

// MARK: - Plumbing

/// Where controls send the operator's acts, and the sounds they make by themselves: a
/// button's contact click belongs to the button, not to the machine.
struct SendKey: EnvironmentKey {
    static let defaultValue: @MainActor (ConsoleIntent) -> Void = { _ in }
}

struct SoundKey: EnvironmentKey {
    static let defaultValue: PK4Sound? = nil
}

extension EnvironmentValues {
    var pk4Send: @MainActor (ConsoleIntent) -> Void {
        get { self[SendKey.self] }
        set { self[SendKey.self] = newValue }
    }

    var pk4Sound: PK4Sound? {
        get { self[SoundKey.self] }
        set { self[SoundKey.self] = newValue }
    }
}

enum Haptic {
    @MainActor static func level() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    @MainActor static func detent() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

/// Tab stops here, and Space or Return does what a click does. A click does not focus it,
/// the way a click does not focus a Mac's own buttons: the ring is for the keyboard.
struct KeyOperable: ViewModifier {
    var enabled = true
    var focus: FocusState<Bool>.Binding
    var action: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable(enabled, interactions: .activate)
            .focused(focus)
            .onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
    }
}

/// The focus ring every control uses: 3 points of lit amber, 3 points out.
struct FocusRing: ViewModifier {
    var focused: Bool
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: radius + 3)
                        .strokeBorder(Color(hex: 0xF0B323), lineWidth: 3)
                        .padding(-6)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Pushbutton

/// The cap colours: cream by default, amber for ACKNOWLEDGE only, red only inside a guard.
enum CapTone {
    case cream, amber, red

    func glass(_ palette: PK4Palette) -> LampGlass {
        switch self {
        case .cream: palette.glass(.white)
        case .amber: palette.glass(.amber)
        case .red: palette.glass(.red)
        }
    }
}

/// The part every square button shares: a dark frame, a black hole, and a translucent cap
/// that goes into the hole when pressed. Nothing translates — it shrinks, darkens, and the
/// hole throws its shadow across it.
struct Cap: View {
    var text: String
    var tone: CapTone
    var down: Bool
    var lamp: LampState
    var blinking: Bool

    @Environment(\.pk4) private var palette

    var body: some View {
        let glass = tone.glass(palette)
        let lit = lamp == .on || lamp == .test
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x55554F), Color(hex: 0x121211)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 1) }
                .shadow(color: .white.opacity(0.4), radius: 0, y: 1)

            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x050504))
                Blink(active: blinking) { bright in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tone == .red ? glass.on : (lit ? glass.on : glass.off))
                        if lit {
                            RoundedRectangle(cornerRadius: 6).fill(
                                RadialGradient(
                                    colors: [glass.hot, glass.hot.opacity(0)], center: .center,
                                    startRadius: 0, endRadius: 32))
                        }
                        RoundedRectangle(cornerRadius: 6).fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.34), location: 0),
                                    .init(color: .white.opacity(0), location: 0.38),
                                    .init(color: .black.opacity(0.2), location: 1),
                                ], startPoint: .top, endPoint: .bottom))
                        Text(text.plate)
                            .font(PK4Type.label(15, bold: true))
                            .tracking(0.9)
                            .mark("capText", "", ["text": text])
                            .foregroundStyle(lit ? glass.inkOn : glass.inkOff)
                            .shadow(
                                color: .white.opacity(lit && glass.lightInk ? 0.55 : 0), radius: 2.5
                            )
                    }
                    .brightness(bright ? 0.25 : 0)
                }
                .overlay { Bevel(radius: 6, light: down ? 0.3 : 0.65, dark: 0.28) }
                .shadow(color: .black.opacity(down ? 0 : 0.65), radius: 2, y: 3)
                .shadow(color: glass.spill.opacity(lit ? palette.spillOpacity : 0), radius: 11)
                .scaleEffect(down ? 0.89 : 1)
                .brightness(down ? -0.2 : 0)
                .overlay {
                    // The shadow the hole throws across a sunk cap.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.85), location: 0),
                            .init(color: .black.opacity(0), location: 0.25),
                        ], startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(down ? 1 : 0)
                }
                .animation(.linear(duration: 0.045), value: down)
                .animation(lit ? .easeIn(duration: 0.09) : .easeOut(duration: 0.22), value: lit)
            }
            .padding(6)
        }
        .frame(width: PK4Size.button, height: PK4Size.button)
    }
}

/// No answer in 3 s: the cap blinks six times at 6 Hz, and nothing else reports the fault.
struct Blink<Content: View>: View {
    var active: Bool
    @ViewBuilder var content: (_ bright: Bool) -> Content

    @State private var started: Date?

    var body: some View {
        Group {
            if let started, active {
                TimelineView(.periodic(from: started, by: 0.08)) { timeline in
                    let step = Int(timeline.date.timeIntervalSince(started) / 0.08)
                    content(step < 12 && step % 2 == 0)
                }
            } else {
                content(false)
            }
        }
        .onChange(of: active, initial: true) { _, now in started = now ? Date() : nil }
    }
}

/// The 64-point illuminated pushbutton, over its label plate and SB tag. The lamp answers
/// the machine, never the finger: pressing moves the cap and clicks; the light comes only
/// when the model reports the command confirmed.
struct PushButton: View {
    var id: InstrumentID
    var cap: String
    var label: String
    var tone: CapTone = .cream
    var face: ButtonFace
    var code: String?

    var body: some View {
        Labelled(label: label, tag: code) {
            Pressable(id: id, face: face, radius: 10) { down in
                Cap(
                    text: cap, tone: tone, down: down, lamp: face.lamp,
                    blinking: face.phase == .noAnswer)
            }
            .mark("cap", id.rawValue, ["text": cap, "tone": "\(tone)"])
            .accessibilityLabel(label)
            .accessibilityValue(face.lamp == .off ? "dark" : "lit")
        }
    }
}

/// Press and release are separate events with separate clicks, so a `ButtonStyle` will
/// not do. Dragging off the cap before letting go still sends: a real button has no
/// cancel.
///
/// A press that never completes reports both edges, and reports the release however the
/// click ends, so a cap cannot be left down. Clicking does not take keyboard focus.
struct Pressable<Content: View>: View {
    var id: InstrumentID
    var face: ButtonFace
    var radius: CGFloat
    var enabled = true
    @ViewBuilder var content: (_ down: Bool) -> Content

    @State private var finger = false
    @FocusState private var focused: Bool
    @Environment(\.pk4Send) private var send
    @Environment(\.pk4Sound) private var sound

    var body: some View {
        content(finger || face.capDown)
            .contentShape(Rectangle())
            .onLongPressGesture(
                minimumDuration: .infinity, maximumDistance: .infinity, perform: {},
                onPressingChanged: { pressing in pressing ? down() : up() }
            )
            .focusable(enabled, interactions: .activate)
            .focused($focused)
            .onKeyPress(keys: [.space, .return], phases: [.down, .up]) { press in
                press.phase == .down ? down() : up()
                return .handled
            }
            .modifier(FocusRing(focused: focused, radius: radius))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                send(.press(id))
                send(.release(id))
            }
            .allowsHitTesting(enabled)
    }

    private func down() {
        guard enabled, !finger else { return }
        finger = true
        sound?.play(.click)
        Haptic.level()
        send(.press(id))
    }

    private func up() {
        guard finger else { return }
        finger = false
        sound?.play(.click)
        send(.release(id))
    }
}

// MARK: - Round pushbutton

/// A round black bakelite pushbutton in a chrome collar, with a green ON and a white OFF
/// lens above it. The cap never lights: on release both lenses go dark, and the machine's
/// answer lights one.
struct RoundPushButton: View {
    var id: InstrumentID
    var cap: String
    var label: String
    var face: ButtonFace
    var on: LampState
    var off: LampState
    /// No lens codes: a button with no state to show, such as MINIMIZE, has no lenses.
    var codes: (on: String?, off: String?, button: String)

    @Environment(\.pk4) private var palette

    var body: some View {
        VStack(spacing: 10) {
            if let lensOn = codes.on, let lensOff = codes.off {
                HStack(spacing: 16) {
                    Labelled(caption: "On", tag: lensOn) {
                        LampLens(color: .green, state: on, id: PK4.lensOn(id).rawValue)
                            .accessibilityHidden(true)
                    }
                    Labelled(caption: "Off", tag: lensOff) {
                        LampLens(color: .white, state: off, id: PK4.lensOff(id).rawValue)
                            .accessibilityHidden(true)
                    }
                }
            }
            Labelled(label: label, tag: codes.button, plateWidth: 118) {
                Pressable(id: id, face: face, radius: 32) { down in
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [
                                        Color(hex: 0xF6F7F2), Color(hex: 0x8E9189),
                                        Color(hex: 0xECEDE7),
                                        Color(hex: 0x6C6F68), Color(hex: 0xDCDDD6),
                                        Color(hex: 0x868981),
                                        Color(hex: 0xF6F7F2),
                                    ], center: .center, angle: .degrees(125))
                            )
                            .overlay { Circle().strokeBorder(palette.bezel, lineWidth: 1.5) }
                            .shadow(color: .black.opacity(0.55), radius: 1.5, y: 2)
                        Circle().fill(Color(hex: 0x050504)).padding(8)
                        ZStack {
                            Circle().fill(
                                RadialGradient(
                                    stops: [
                                        .init(color: Color(hex: 0x66665F), location: 0),
                                        .init(color: Color(hex: 0x2A2A27), location: 0.38),
                                        .init(color: Color(hex: 0x0C0C0B), location: 1),
                                    ], center: UnitPoint(x: 0.38, y: 0.28), startRadius: 0,
                                    endRadius: 30))
                            Text(cap.plate)
                                .font(PK4Type.label(14, bold: true))
                                .tracking(0.84)
                                .mark("roundCapText", "", ["text": cap])
                                .foregroundStyle(palette.engraving)
                        }
                        .shadow(color: .black.opacity(down ? 0 : 0.7), radius: 2, y: 3)
                        .scaleEffect(down ? 0.89 : 1)
                        .brightness(down ? -0.2 : 0)
                        .padding(8)
                        .animation(.linear(duration: 0.045), value: down)
                    }
                    .frame(width: PK4Size.button, height: PK4Size.button)
                }
                .mark("roundCap", id.rawValue, ["text": cap])
                .accessibilityLabel(label)
                .accessibilityValue(on == .on ? "on" : off == .on ? "off" : "no answer")
            }
        }
    }
}

// MARK: - Guarded button

/// A red pushbutton under a hinged red guard in a hazard-striped frame. Three deliberate
/// acts: lift the guard, turn the key where there is one, press and hold for two seconds.
/// Nothing shows the hold — a 1972 desk has no way to draw one.
struct GuardedButton: View {
    var id: InstrumentID
    var cap: String
    var label: String
    var keyed: Bool
    var face: ButtonFace
    var open: Bool
    var armed: Bool
    var code: String

    @State private var angle: Double = 0
    @State private var motion = 0
    @FocusState private var flapFocused: Bool
    @Environment(\.pk4) private var palette
    @Environment(\.pk4Finish) private var finish
    @Environment(\.pk4Send) private var send
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Labelled(label: label, caption: keyed ? "Key + hinged guard" : "Hinged guard", tag: code) {
            ZStack(alignment: .top) {
                frame
                flap
                // The hinge rod across the collar's top edge.
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0xF0F1EC), location: 0),
                                .init(color: Color(hex: 0x7D8079), location: 0.55),
                                .init(color: Color(hex: 0xB9BBB4), location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 7)
                    .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                    .offset(y: -1)
                    .allowsHitTesting(false)
            }
            .fixedSize()
            .mark("guard", id.rawValue, ["keyed": "\(keyed)"])
        }
        .onChange(of: open) { _, now in swing(open: now) }
    }

    private var frame: some View {
        let paint = palette.paint(finish)
        return HStack(spacing: 10) {
            if keyed { KeySwitch(id: id, armed: armed, reachable: open) }
            Pressable(id: id, face: face, radius: 10, enabled: open) { down in
                Cap(
                    text: cap, tone: .red, down: down, lamp: face.lamp,
                    blinking: face.phase == .noAnswer)
            }
            .mark("cap", id.rawValue, ["text": cap, "tone": "red"])
            .accessibilityLabel(label)
            .accessibilityHint(open ? "Press and hold two seconds" : "Guard closed")
        }
        .padding(8)
        .background {
            EnamelPaint(finish: finish, falloff: false)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.45), .clear], startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.15)
                    ).clipShape(RoundedRectangle(cornerRadius: 3))
                }
        }
        .foregroundStyle(paint.ink)
        .padding(10)
        .background {
            // Hazard stripes in the well, sunk inside a raised cast collar.
            ZStack {
                Rectangle().fill(palette.bakelite)
                Canvas { context, box in
                    let stripe: CGFloat = 10 * 1.414
                    var x: CGFloat = -box.height
                    while x < box.width + box.height {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + stripe, y: 0))
                        path.addLine(to: CGPoint(x: x + stripe - box.height, y: box.height))
                        path.addLine(to: CGPoint(x: x - box.height, y: box.height))
                        path.closeSubpath()
                        context.fill(path, with: .color(Color(hex: 0xF0B323)))
                        x += stripe * 2
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.5), .clear], startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xE4604A), Color(hex: 0xD24431), Color(hex: 0xA3281A),
                                Color(hex: 0x7C1B0F),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(
                            Color(red: 0.16, green: 0.02, blue: 0.01).opacity(0.8), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 3)
            }
        }
    }

    /// Plain translucent red acrylic: the stripes already say what it is.
    private var acrylic: some View {
        let raised = angle > 60
        let shadow: (opacity: Double, radius: CGFloat, y: CGFloat) =
            raised ? (0.35, 5, -6) : (0.5, 2.5, 3)
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color(red: 200 / 255, green: 50 / 255, blue: 31 / 255).opacity(0.74))
            .overlay {
                RoundedRectangle(cornerRadius: 4).fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.38), location: 0),
                            .init(color: .white.opacity(0), location: 0.28),
                            .init(color: .white.opacity(0), location: 0.62),
                            .init(color: .white.opacity(0.16), location: 1),
                        ], startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4).strokeBorder(
                    Color(red: 90 / 255, green: 12 / 255, blue: 4 / 255).opacity(0.9), lineWidth: 2)
            }
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }

    private var flap: some View {
        acrylic
            // The ring is on the flap, and swings up with it.
            .modifier(FocusRing(focused: flapFocused, radius: 4))
            .padding(6)
            .rotation3DEffect(
                .degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.35
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleGuard)
            // Lifted, the flap still answers a click, over the hinge where it now stands.
            .allowsHitTesting(!open)
            .overlay(alignment: .top) { hinge }
            // Tab reaches the flap before what it covers.
            .modifier(KeyOperable(focus: $flapFocused, action: toggleGuard))
            .accessibilityElement()
            .accessibilityLabel("Guard of \(label)")
            .accessibilityValue(open ? "lifted" : "closed")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleGuard() }
    }

    @ViewBuilder private var hinge: some View {
        if open {
            Color.clear.frame(height: 36).contentShape(Rectangle()).offset(y: -36)
                .onTapGesture { send(.guard(id, open: false)) }
        }
    }

    private func toggleGuard() {
        send(.guard(id, open: !open))
    }

    /// Lifted by hand: up past its rest to 121° and back to 112°. Let go, it falls under
    /// gravity, lands, bounces twice and settles.
    private func swing(open: Bool) {
        motion += 1
        let run = motion
        guard !reduceMotion else {
            angle = open ? 112 : 0
            return
        }
        func then(_ delay: Double, _ animation: Animation, _ to: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard run == motion else { return }
                withAnimation(animation) { angle = to }
            }
        }
        if open {
            withAnimation(.easeOut(duration: 0.187)) { angle = 121 }
            then(0.187, .easeInOut(duration: 0.073), 112)
        } else {
            withAnimation(.timingCurve(0.55, 0, 1, 0.6, duration: 0.27)) { angle = 0 }
            then(0.27, .easeOut(duration: 0.08), 15)
            then(0.35, .easeIn(duration: 0.08), 0)
            then(0.43, .easeOut(duration: 0.045), 4)
            then(0.475, .easeIn(duration: 0.045), 0)
        }
    }
}

/// F12's key switch: it turns 90° to ARMED and stays there until turned back. It sits in
/// the well under the guard, so it turns only with the guard up.
struct KeySwitch: View {
    var id: InstrumentID
    var armed: Bool
    var reachable: Bool

    @FocusState private var focused: Bool
    @Environment(\.pk4) private var palette
    @Environment(\.pk4Send) private var send

    var body: some View {
        ZStack {
            Circle().fill(
                RadialGradient(
                    stops: [
                        .init(color: palette.aluminium, location: 0),
                        .init(color: palette.aluminium, location: 0.43),
                        .init(color: Color(hex: 0x8D8D86), location: 0.46),
                        .init(color: Color(hex: 0x8D8D86), location: 0.5),
                        .init(color: palette.aluminium, location: 0.54),
                    ], center: .center, startRadius: 0, endRadius: 28))
            Circle().strokeBorder(palette.bezel, lineWidth: 3)
            Rectangle().fill(Color(hex: 0x111111)).frame(width: 4, height: 22)
                .rotationEffect(.degrees(armed ? 90 : 0))
                .animation(.timingCurve(0.4, 1.6, 0.6, 1, duration: 0.14), value: armed)
        }
        .frame(width: 56, height: 56)
        .mark("key", id.rawValue)
        .contentShape(Circle())
        .onTapGesture(perform: turn)
        .allowsHitTesting(reachable)
        // Under a closed guard the key cannot be reached by hand, so not by Tab either.
        .modifier(KeyOperable(enabled: reachable, focus: $focused, action: turn))
        .modifier(FocusRing(focused: focused, radius: 28))
        .accessibilityElement()
        .accessibilityLabel("Key switch")
        .accessibilityValue(armed ? "armed" : "safe")
        .accessibilityHint(reachable ? "" : "Under the guard")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if reachable { turn() }
        }
    }

    private func turn() {
        send(.key(id, armed: !armed))
    }
}

// MARK: - Rotary selector

/// A four-position rotary switch that chooses which session feeds panel B and receives the
/// commands. Detents 60° apart and a stop pin at each end: it does not wrap. Only the
/// knurling, the bar, the index line and the screw turn; the skirt's shading stays with
/// the room light.
struct RotarySelector: View {
    var position: Int
    var size: CGFloat = 160

    @State private var lean: Double = 0
    @FocusState private var focused: Bool
    @Environment(\.pk4) private var palette
    @Environment(\.pk4Send) private var send
    @Environment(\.pk4Sound) private var sound
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let positions = 4
    private static let start = -60.0 * Double(positions - 1) / 2

    var body: some View {
        let scale = size / 240
        ZStack {
            SelectorPlate(palette: palette)
            SelectorKnob()
                .rotationEffect(.degrees(Self.start + 60 * Double(position - 1) + lean))
                .animation(
                    reduceMotion ? nil : .spring(response: 0.17, dampingFraction: 0.45),
                    value: position
                )
                .animation(.easeOut(duration: 0.09), value: lean)
            // The specular highlight is fixed to the room: if it turned with the knob it
            // would look like a sticker.
            Circle().fill(
                RadialGradient(
                    colors: [.white.opacity(0.35), .white.opacity(0)],
                    center: UnitPoint(x: 0.35, y: 0.25),
                    startRadius: 0, endRadius: 65)
            )
            .frame(width: 108, height: 108)
            .allowsHitTesting(false)
        }
        .frame(width: 240, height: 240)
        .scaleEffect(scale)
        .frame(width: size, height: size)
        .mark("selector", PK4.selector.rawValue)
        .contentShape(Circle())
        .gesture(SpatialTapGesture().onEnded { tap in click(at: tap.location, scale: scale) })
        .focusable(interactions: .activate)
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in
            step(-1)
            return .handled
        }
        .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in
            step(1)
            return .handled
        }
        .modifier(FocusRing(focused: focused, radius: size / 2))
        .accessibilityElement()
        .accessibilityLabel("Session selector")
        .accessibilityValue("Session \(position)")
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private func click(at point: CGPoint, scale: CGFloat) {
        // A numeral walks the knob there, one detent at a time.
        let local = CGPoint(x: point.x / scale, y: point.y / scale)
        for index in 0..<Self.positions {
            let angle = (Self.start + 60 * Double(index) - 90) * .pi / 180
            let numeral = CGPoint(x: 120 + 96 * cos(angle), y: 120 + 96 * sin(angle))
            if hypot(local.x - numeral.x, local.y - numeral.y) < 20 {
                send(.selectorGoTo(index + 1))
                return
            }
        }
        // Otherwise the right half turns it clockwise, the left half back.
        step(local.x >= 120 ? 1 : -1)
    }

    private func step(_ direction: Int) {
        let next = position + direction
        guard (1...Self.positions).contains(next) else {
            // At a stop the knob leans on the pin and springs back, with a dull click.
            sound?.play(.click)
            lean = Double(direction) * 6
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { lean = 0 }
            return
        }
        send(.selectorStep(direction))
    }
}

private struct SelectorPlate: View, Equatable {
    var palette: PK4Palette

    static func == (lhs: SelectorPlate, rhs: SelectorPlate) -> Bool {
        lhs.palette.isNight == rhs.palette.isNight
    }

    var body: some View {
        Canvas { context, _ in Self.draw(&context, ink: palette.tagInk) }
            .frame(width: 240, height: 240)
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    private static func onDial(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: 120 + r * cos(angle), y: 120 + r * sin(angle))
    }

    private static func draw(_ context: inout GraphicsContext, ink: Color) {
        let centre = CGPoint(x: 120, y: 120)
        let dial = circle(centre, 114)
        let brushed = Gradient(stops: [
            .init(color: Color(hex: 0xECEEE8), location: 0),
            .init(color: Color(hex: 0xC3C5BD), location: 0.45),
            .init(color: Color(hex: 0x9DA097), location: 1),
        ])
        context.fill(
            dial,
            with: .linearGradient(brushed, startPoint: .zero, endPoint: CGPoint(x: 240, y: 240)))
        context.stroke(dial, with: .color(Color(hex: 0x2A2A27)), lineWidth: 2)
        context.stroke(circle(centre, 110), with: .color(.white.opacity(0.45)), lineWidth: 1)

        for index in 0..<4 {
            let degrees: CGFloat = -90 + 60 * CGFloat(index) - 90
            let angle: CGFloat = degrees * .pi / 180
            var tick = Path()
            tick.move(to: onDial(angle, 66))
            tick.addLine(to: onDial(angle, 78))
            context.stroke(tick, with: .color(Color(hex: 0x1B1B19)), lineWidth: 3)
            let numeral = Text(String(index + 1)).font(PK4Type.label(30, bold: true))
                .foregroundStyle(ink)
            context.draw(numeral, at: onDial(angle, 96))
        }
        for x in [CGFloat(-62), 62] {
            let pin = circle(CGPoint(x: centre.x + x, y: centre.y + 78), 4.5)
            context.fill(pin, with: .color(Color(hex: 0xB4B7AF)))
            context.stroke(pin, with: .color(Color(hex: 0x2A2A27)), lineWidth: 1)
        }

        var shadow = context
        shadow.addFilter(.blur(radius: 4))
        shadow.fill(circle(CGPoint(x: 125, y: 128), 56), with: .color(.black.opacity(0.55)))
        let skirt = circle(centre, 54)
        let bakelite = Gradient(stops: [
            .init(color: Color(hex: 0x5B5B55), location: 0),
            .init(color: Color(hex: 0x262624), location: 0.45),
            .init(color: Color(hex: 0x080807), location: 1),
        ])
        context.fill(
            skirt,
            with: .radialGradient(
                bakelite, center: CGPoint(x: 99, y: 92), startRadius: 0, endRadius: 92))
        context.stroke(skirt, with: .color(.black), lineWidth: 1.5)
    }
}

/// The parts that turn: the knurling, the bar grip with its white index line, the screw.
private struct SelectorKnob: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.75), style: StrokeStyle(lineWidth: 5, dash: [3.2, 3.475]))
                .frame(width: 102, height: 102)
            RoundedRectangle(cornerRadius: 13).fill(.black.opacity(0.5))
                .frame(width: 30, height: 120).blur(radius: 4).offset(x: 3, y: 5)
            RoundedRectangle(cornerRadius: 13)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x0B0B0A), location: 0),
                            .init(color: Color(hex: 0x4E4E49), location: 0.3),
                            .init(color: Color(hex: 0x2C2C29), location: 0.5),
                            .init(color: Color(hex: 0x141413), location: 0.8),
                            .init(color: Color(hex: 0x050505), location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                )
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.black, lineWidth: 1) }
                .frame(width: 30, height: 120)
            RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0xF1EFE6))
                .frame(width: 3.5, height: 34)
                .offset(y: -38)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x6F726B), Color(hex: 0xF4F5F0), Color(hex: 0xB4B7AF),
                            Color(hex: 0x55584F),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                )
                .overlay { Circle().strokeBorder(Color(hex: 0x111111), lineWidth: 1) }
                .frame(width: 14, height: 14)
            Rectangle().fill(Color(hex: 0x222222)).frame(width: 12, height: 2)
        }
        .frame(width: 240, height: 240)
    }
}

// MARK: - Toggle switch

/// MAINS: a chrome bat-handle toggle on a brushed plate, up for ON. The lever swings toward
/// the operator, so seen from the front it foreshortens rather than rotating; the loudest
/// clunk on the console lands as it passes centre.
struct ToggleSwitch: View {
    var label: String
    var on: Bool
    var code: String

    @FocusState private var focused: Bool
    @Environment(\.pk4) private var palette
    @Environment(\.pk4Send) private var send

    var body: some View {
        Labelled(label: label, tag: code) {
            ZStack {
                Canvas { context, _ in
                    let plate = Path(
                        roundedRect: CGRect(x: 1, y: 1, width: 70, height: 138), cornerRadius: 5)
                    context.fill(
                        plate,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(hex: 0xECEEE8), Color(hex: 0xC3C5BD), Color(hex: 0x9DA097),
                            ]),
                            startPoint: .zero, endPoint: CGPoint(x: 72, y: 140)))
                    context.stroke(plate, with: .color(Color(hex: 0x2A2A27)), lineWidth: 2)
                    for point in [
                        CGPoint(x: 9, y: 9), CGPoint(x: 63, y: 9), CGPoint(x: 9, y: 131),
                        CGPoint(x: 63, y: 131),
                    ] {
                        let screw = Path(
                            ellipseIn: CGRect(
                                x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
                        context.fill(screw, with: .color(Color(hex: 0xB4B7AF)))
                        context.stroke(screw, with: .color(Color(hex: 0x2A2A27)), lineWidth: 1)
                    }
                    context.draw(
                        Text("ON").font(PK4Type.label(12, bold: true)).foregroundStyle(
                            palette.tagInk), at: CGPoint(x: 36, y: 15))
                    context.draw(
                        Text("OFF").font(PK4Type.label(12, bold: true)).foregroundStyle(
                            palette.tagInk), at: CGPoint(x: 36, y: 126))
                    var nut = Path()
                    for index in 0..<6 {
                        let angle = Double(index) * .pi / 3
                        let point = CGPoint(x: 36 + 17 * cos(angle), y: 70 + 17 * sin(angle))
                        index == 0 ? nut.move(to: point) : nut.addLine(to: point)
                    }
                    nut.closeSubpath()
                    context.fill(nut.offsetBy(dx: 2, dy: 3), with: .color(.black.opacity(0.4)))
                    context.fill(nut, with: .color(Color(hex: 0xC9CBC3)))
                    context.stroke(nut, with: .color(Color(hex: 0x33352F)), lineWidth: 1)
                    context.fill(
                        Path(ellipseIn: CGRect(x: 25, y: 59, width: 22, height: 22)),
                        with: .color(Color(hex: 0x8A8D85)))
                    context.fill(
                        Path(ellipseIn: CGRect(x: 28, y: 62, width: 16, height: 16)),
                        with: .color(Color(hex: 0x0C0C0B)))
                }
                Lever()
                    .scaleEffect(x: 1, y: on ? 1 : -1, anchor: UnitPoint(x: 0.5, y: 0.5))
                    .animation(.timingCurve(0.7, 0, 0.3, 1, duration: 0.1), value: on)
            }
            .frame(width: 72, height: 140)
            .mark("toggle", PK4.mains.rawValue)
            .contentShape(Rectangle())
            .onTapGesture { send(.mains(!on)) }
            .focusable(interactions: .activate)
            .focused($focused)
            .onKeyPress(keys: [.space, .return]) { _ in
                send(.mains(!on))
                return .handled
            }
            .modifier(FocusRing(focused: focused, radius: 5))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(on ? "on" : "off")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { send(.mains(!on)) }
        }
    }

    private struct Lever: View {
        var body: some View {
            Canvas { context, _ in
                let cx: CGFloat = 36
                let cy: CGFloat = 70
                var lever = Path()
                lever.move(to: CGPoint(x: cx - 4, y: cy))
                lever.addLine(to: CGPoint(x: cx - 7.5, y: cy - 36))
                lever.addArc(
                    center: CGPoint(x: cx, y: cy - 36), radius: 7.5, startAngle: .degrees(180),
                    endAngle: .degrees(0), clockwise: false)
                lever.addLine(to: CGPoint(x: cx + 4, y: cy))
                lever.closeSubpath()
                var shadow = context
                shadow.addFilter(.blur(radius: 3))
                shadow.fill(lever.offsetBy(dx: 4, dy: 3), with: .color(.black.opacity(0.45)))
                context.fill(
                    lever,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: 0x6F726B), Color(hex: 0xF4F5F0), Color(hex: 0xB4B7AF),
                            Color(hex: 0x55584F),
                        ]),
                        startPoint: CGPoint(x: cx - 8, y: 0), endPoint: CGPoint(x: cx + 8, y: 0)))
                context.stroke(lever, with: .color(Color(hex: 0x33352F)), lineWidth: 1)
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - 5, y: cy - 41, width: 6, height: 6)),
                    with: .color(.white.opacity(0.7)))
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - 7.5, y: cy - 7.5, width: 15, height: 15)),
                    with: .color(Color(hex: 0xB4B7AF)))
            }
            .frame(width: 72, height: 140)
        }
    }
}

// MARK: - Pencil strip

/// A paper strip in an aluminium card holder, where the operator writes the project name
/// by hand. The only free text on the console: twelve characters, in pencil. Click it to
/// write; Return or clicking away puts the pencil down.
struct PencilStrip: View {
    var slot: Int
    var text: String

    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool
    @FocusState private var cardFocused: Bool
    @Environment(\.pk4) private var palette
    @Environment(\.pk4Send) private var send

    var body: some View {
        card
            .modifier(FocusRing(focused: cardFocused, radius: 3))
            .contentShape(Rectangle())
            .onTapGesture(perform: pickUpPencil)
            // Tab stops at the card; Return picks up the pencil, as a click does.
            .modifier(KeyOperable(enabled: !editing, focus: $cardFocused, action: pickUpPencil))
            .onChange(of: focused) { _, now in if !now { editing = false } }
            .onChange(of: draft) { _, now in write(now) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Project name, session \(slot), in pencil")
            .accessibilityValue(text.isEmpty ? "blank" : text)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { pickUpPencil() }
    }

    @ViewBuilder private var writing: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { editing = false }
                .onAppear { focused = true }
        } else {
            // Twelve characters in pencil do not always fit the card: the hand writes
            // smaller rather than off the edge.
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    private var paper: some View {
        ZStack {
            palette.paper
            LinearGradient(
                colors: [.black.opacity(0.06), .clear], startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.3))
        }
    }

    private var holder: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: 0xF4F5F0), Color(hex: 0xDFE0D9), Color(hex: 0x9A9D95),
                        Color(hex: 0x74776F),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 2)
    }

    private var card: some View {
        writing
            .font(PK4Type.pencil(22))
            .foregroundStyle(Color(hex: 0x4A4A48))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .frame(width: PK4Size.windowWidth - 8, height: PK4Size.windowHeight - 8)
            .background { paper }
            .clipped()
            .padding(4)
            .background { holder }
            .mark("pencil", PK4.pencil(slot: slot).rawValue, ["slot": "\(slot)"])
    }

    private func write(_ now: String) {
        guard editing else { return }
        let clipped = String(now.prefix(12))
        if clipped != now { draft = clipped }
        if clipped != text { send(.pencil(slot: slot, text: clipped)) }
    }

    private func pickUpPencil() {
        draft = text
        editing = true
    }
}
