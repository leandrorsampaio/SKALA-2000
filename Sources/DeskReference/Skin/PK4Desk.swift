import AppKit
import ConsoleKit
import SwiftUI

/// The assembled PK-4 desk, scaled to its window.
///
/// The desk is one fixed drawing 2500 units wide and 1800 tall, scaled uniformly with a
/// single transform: it never re-lays itself out for the window's size. The window's
/// aspect ratio is locked to match, so nothing is ever cropped or letterboxed.
public struct PK4ConsoleScreen: View {

    public let snapshot: ConsoleSnapshot
    public let send: @MainActor (ConsoleIntent) -> Void
    public let sound: PK4Sound?
    public var lampCodes: Bool

    @Environment(\.colorScheme) private var scheme

    /// The screen only draws. The relays, the buzzer and the text log's window are driven
    /// by `PK4Director` from the model itself, so they keep working while the window is
    /// hidden and this view is not drawn at all.
    public init(
        snapshot: ConsoleSnapshot, send: @escaping @MainActor (ConsoleIntent) -> Void,
        sound: PK4Sound? = nil, lampCodes: Bool = true
    ) {
        self.snapshot = snapshot
        self.send = send
        self.sound = sound
        self.lampCodes = lampCodes
    }

    public static let aspectRatio = CGSize(width: PK4Size.deskWidth, height: PK4Size.deskHeight)

    public var body: some View {
        GeometryReader { box in
            let scale = box.size.width / PK4Size.deskWidth
            PK4Desk(snapshot: snapshot)
                .frame(width: PK4Size.deskWidth, height: PK4Size.deskHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: box.size.width, height: box.size.height, alignment: .topLeading)
        }
        .background(Color(hex: 0x1A1C1B))
        .environment(\.pk4, PK4Palette(night: scheme == .dark))
        .environment(\.pk4Finish, snapshot.finish)
        .environment(\.pk4Send, send)
        .environment(\.pk4Sound, sound)
        .environment(\.pk4LampCodes, lampCodes)
    }
}

/// The desk at its own size.
public struct PK4Desk: View {
    public let snapshot: ConsoleSnapshot

    @Environment(\.pk4) private var palette
    @Environment(\.pk4Finish) private var finish

    public init(snapshot: ConsoleSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        let s = snapshot
        DeskLayout {
            DeskHeader(build: s.programBuild)
            panel("A · All sessions", PanelA(s: s))
            panel("B · Selected session", PanelB(s: s))
            panel("C · Control", PanelC(s: s))
            panel("D · Computer controls", PanelD(s: s))
            panel("E · Power and service", PanelE(s: s))
        }
        .padding(22)
        .mark("desk")
        .background {
            EnamelPaint(finish: finish)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { Bevel(radius: 6, light: 0.35, dark: 0.4) }
        }
        .foregroundStyle(palette.paint(finish).ink)
    }
}

extension PK4Desk {
    /// A panel is one stop for VoiceOver, so moving between panels is one step.
    private func panel(_ name: String, _ content: some View) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Nothing inside a panel takes a click outside it.
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(name)
    }
}

/// Three columns, five panels, listed in reading order: A, B, C, D, E.
///
/// VoiceOver and the Tab key go through the panels in the order they are listed, not the
/// order they are drawn, and a column of stacks would list E, at the foot of the first
/// column, before B. So the desk is one layout that puts each panel where it belongs: A
/// over E on the left, B in the middle, C over D on the right. A and D take whatever
/// height their column leaves; B takes it all.
struct DeskLayout: Layout {
    static let columns: [CGFloat] = [650, 1190, 580]
    static let gap: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard subviews.count == 6 else { return }
        let gap = Self.gap
        let widths = Self.columns
        func natural(_ index: Int, width: CGFloat) -> CGFloat {
            subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        func place(_ index: Int, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            subviews[index].place(
                at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: height))
        }

        let header = natural(0, width: bounds.width)
        place(0, bounds.minX, bounds.minY, bounds.width, header)
        let top = bounds.minY + header + gap
        let height = bounds.maxY - top
        let left = bounds.minX
        let middle = left + widths[0] + gap
        let right = middle + widths[1] + gap

        let e = natural(5, width: widths[0])
        place(1, left, top, widths[0], height - e - gap)
        place(5, left, bounds.maxY - e, widths[0], e)
        place(2, middle, top, widths[1], height)
        let c = natural(3, width: widths[2])
        place(3, right, top, widths[2], c)
        place(4, right, top + c + gap, widths[2], height - c - gap)
    }
}

// MARK: - Header

private struct DeskHeader: View {
    var build: String?

    @Environment(\.pk4) private var palette

    var body: some View {
        HStack(spacing: 24) {
            Screw(seed: "desk.left", size: 20)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("Operator console SKALA-2000 · Claude Code".plate)
                    .font(PK4Type.label(40, bold: true)).tracking(2.4)
                    .mark("headerTitle", "", ["text": "Operator console SKALA-2000 · Claude Code"])
                Text("Type DD-72 · 4 sessions · 1972".plate)
                    .font(PK4Type.label(20)).tracking(1.2)
                    .mark("headerSubtitle", "", ["text": "Type DD-72 · 4 sessions · 1972"])
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Plate(text: "Program build")
                // Typed on a paper card slid into a holder: the only string the Mac writes on
                // the desk, and it is a version number.
                Text(build ?? " ")
                    .font(PK4Type.typewriter(18))
                    .foregroundStyle(palette.tagInk)
                    .frame(minWidth: 96)
                    .mark("programText")
                    .padding(.vertical, 4)
                    .padding(.horizontal, 14)
                    .background(palette.paper)
                    .mark("programPaper")
                    .padding(4)
                    .mark("programCard")
                    .background {
                        RoundedRectangle(cornerRadius: 2).fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xF4F5F0), Color(hex: 0x9A9D95),
                                    Color(hex: 0x74776F),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 1.5, y: 2)
                    }
                    .accessibilityLabel("Program build \(build ?? "unknown")")
            }
            VStack(spacing: 1) {
                Text("Instrument works No 4 · Dresden".plate).mark(
                    "nameplateLine", "", ["line": "0", "text": "Instrument works No 4 · Dresden"])
                Text("Console SKALA-2000 DD-72 · Serial No 0047 · 1972".plate).mark(
                    "nameplateLine", "",
                    ["line": "1", "text": "Console SKALA-2000 DD-72 · Serial No 0047 · 1972"])
                Text("220 V 50 Hz 0.6 kVA · Made in GDR".plate).mark(
                    "nameplateLine", "", ["line": "2", "text": "220 V 50 Hz 0.6 kVA · Made in GDR"])
            }
            .font(PK4Type.engraved(12))
            .tracking(1.08)
            .foregroundStyle(palette.tagInk)
            .shadow(color: .white.opacity(0.6), radius: 0, y: 1)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .mark("nameplate")
            .background {
                RoundedRectangle(cornerRadius: 2).fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0xECEEE8), location: 0),
                            .init(color: palette.aluminium, location: 0.6),
                            .init(color: Color(hex: 0xA4A79F), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(
                        .black.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 1.5, y: 2)
            }
            .accessibilityHidden(true)
            Text("INV. No 0417")
                .font(PK4Type.marker(26))
                .foregroundStyle(palette.stockroomRed)
                .mark("inventory", "", ["text": "INV. No 0417"])
                .rotationEffect(.degrees(-3))
                .accessibilityHidden(true)
            Screw(seed: "desk.right", size: 20)
        }
    }
}

// MARK: - Panel A · all sessions

private struct PanelA: View {
    let s: ConsoleSnapshot

    static let rows: [(AnnunciatorRow, String, String, LampColor)] = [
        (.run, "Running", "Run", .white), (.busy, "Busy", "Busy", .green),
        (.wait, "Waiting for operator", "Wait", .red), (.done, "Turn done", "Done", .green),
        (.agent, "Agent done", "Agent", .white), (.bkgd, "Background job", "Bkgd", .white),
        (.block, "Blocked", "Block", .red), (.cmpct, "Compacting", "Cmpct", .amber),
        (.lowctx, "Low context", "Low ctx", .red),
    ]

    var body: some View {
        PK4Panel(title: "A · All sessions — annunciator", spacing: 26) {
            // 11: nine rows of windows packed as an annunciator is, to leave the buzzer room.
            Grid(horizontalSpacing: 8, verticalSpacing: 11) {
                GridRow {
                    Plate(text: "Session", width: 190)
                    ForEach(PK4.slots, id: \.self) { slot in
                        Text(String(slot)).font(PK4Type.label(30, bold: true))
                            .mark("numeral", "", ["text": String(slot)])
                            .frame(width: PK4Size.windowWidth)
                            .accessibilityHidden(true)
                    }
                }
                GridRow {
                    Plate(text: "Project · pencil", width: 190)
                    ForEach(PK4.slots, id: \.self) { slot in
                        PencilStrip(slot: slot, text: s.pencil(slot: slot))
                    }
                }
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        Plate(text: row.1, width: 190)
                        ForEach(PK4.slots, id: \.self) { slot in
                            let id = PK4.annunciator(row.0, slot: slot)
                            LampWindow(
                                label: row.2, color: row.3, state: s.lamp(id),
                                // HL33 on went to panel B first: LOW CONTEXT is HL76 to HL79.
                                code: "HL\(index < 8 ? index * 4 + slot : 75 + slot)",
                                id: id.rawValue
                            )
                            .equatable()
                            .accessibilityElement()
                            .accessibilityLabel("\(row.1), session \(slot)")
                            .accessibilityValue(PK4Words.lamp(s.lamp(id)))
                        }
                    }
                }
            }
            InstructionPlate(
                text:
                    "New alarm flashes until acknowledged, then burns steady until cause clears. SIL silences every signal"
            )
            HStack(alignment: .top) {
                NixieReadout(
                    label: "Sessions running", template: "0", value: s.nixie(PK4.sessionsRunning),
                    labelWidth: 170, code: "HG1", id: PK4.sessionsRunning.rawValue
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sessions running")
                .accessibilityValue(PK4Words.digits(s.nixie(PK4.sessionsRunning)))
                Spacer()
                NixieReadout(
                    label: "Sessions busy", template: "0", value: s.nixie(PK4.sessionsBusy),
                    labelWidth: 150, code: "HG2", id: PK4.sessionsBusy.rawValue
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sessions busy")
                .accessibilityValue(PK4Words.digits(s.nixie(PK4.sessionsBusy)))
            }
            HStack(alignment: .top) {
                VStack(spacing: 14) {
                    Labelled(label: "Buzzer", tag: "HA1") { BuzzerGrille(sounding: s.buzzer) }
                    // Burns while an alarm would go unheard: silenced, or muted in Settings.
                    LampWindow(
                        label: "Silenced", color: .amber, state: s.lamp(PK4.silenced),
                        code: "HL75", id: PK4.silenced.rawValue
                    )
                    .equatable()
                    .accessibilityElement()
                    .accessibilityLabel("Silenced")
                    .accessibilityValue(PK4Words.lamp(s.lamp(PK4.silenced)))
                }
                Spacer()
                PushButton(
                    id: PK4.silence, cap: "Sil", label: "Silence", face: s.button(PK4.silence),
                    code: "SB1")
                Spacer()
                PushButton(
                    id: PK4.acknowledge, cap: "Ack", label: "Acknowledge", tone: .amber,
                    face: s.button(PK4.acknowledge), code: "SB2")
                Spacer()
                PushButton(
                    id: PK4.lampTest, cap: "Test", label: "Lamp test", face: s.button(PK4.lampTest),
                    code: "SB3")
                Spacer()
                PushButton(
                    id: PK4.buzzerTest, cap: "Bzr", label: "Buzzer test",
                    face: s.button(PK4.buzzerTest), code: "SB19")
            }
        }
    }
}

/// The buzzer behind its grille. It trembles while it sounds.
private struct BuzzerGrille: View {
    var sounding: Bool

    @State private var shake = false
    @Environment(\.pk4) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, box in
            var y: CGFloat = 0
            while y < box.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: box.width, height: 5)),
                    with: .color(palette.bakelite))
                context.fill(
                    Path(CGRect(x: 0, y: y + 5, width: box.width, height: 5)),
                    with: .color(palette.enamelRecess))
                y += 10
            }
        }
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color(hex: 0x1C1C1A), lineWidth: 4) }
        .overlay {
            Circle().fill(
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear], startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.2)))
        }
        .background {
            Circle().fill(Color(hex: 0x3B3B37)).padding(-3).shadow(
                color: .black.opacity(0.4), radius: 2, y: 2)
        }
        .frame(width: 96, height: 96)
        .mark("buzzer")
        .offset(x: shake ? 0.6 : 0)
        .onChange(of: sounding, initial: true) { _, now in
            guard !reduceMotion else { return }
            if now {
                withAnimation(.linear(duration: 0.02).repeatForever(autoreverses: true)) {
                    shake = true
                }
            } else {
                withAnimation(.linear(duration: 0)) { shake = false }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Buzzer")
        .accessibilityValue(sounding ? "sounding" : "silent")
    }
}

// MARK: - Panel B · selected session

private struct PanelB: View {
    let s: ConsoleSnapshot

    var body: some View {
        PK4Panel(
            // 44: the 56 units the context window lamps took, spread over its four gaps.
            title: "B · Selected session — instruments", spacing: 44,
            padding: EdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26),
            tightBottom: true
        ) {
            HStack(alignment: .top, spacing: 30) {
                VStack(spacing: 18) {
                    // Which session feeds the panel, over the knob that chooses it.
                    Labelled(label: "Selected", tag: "HG4") {
                        NixieReadout(
                            template: "0", value: s.nixie(PK4.selected), xl: true,
                            id: PK4.selected.rawValue)
                    }
                    .accessibilityHidden(true)
                    Labelled(label: "Session selector", tag: "SA1") {
                        RotarySelector(position: s.selector)
                    }
                    PushButton(
                        id: PK4.printText, cap: "Prt", label: "Print text",
                        face: s.button(PK4.printText), code: "SB7")
                }
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .top, spacing: 36) {
                        meter("Context remaining", PK4.contextMeter, red: 0...0.2, code: "PA1")
                        meter("API share of time", PK4.apiShareMeter, code: "PA2")
                        meter("Tool share of time", PK4.toolShareMeter, code: "PA3")
                    }
                    HStack(alignment: .top, spacing: 30) {
                        VStack(alignment: .leading, spacing: 16) {
                            nixie("Context used", PK4.contextUsed, "tok", "HG5", unitWidth: 34)
                            nixie("Input tokens", PK4.inputTokens, "tok", "HG6", unitWidth: 34)
                            nixie("Output tokens", PK4.outputTokens, "tok", "HG7", unitWidth: 34)
                            nixie(
                                "Thinking tokens", PK4.thinkingTokens, "tok", "HG8", unitWidth: 34)
                            nixie("Cache read", PK4.cacheRead, "×1000", "HG9", unitWidth: 34)
                            nixie("Cache written", PK4.cacheWritten, "×1000", "HG10", unitWidth: 34)
                        }
                        // Left-aligned, so these tubes line up whatever their units say.
                        VStack(alignment: .leading, spacing: 16) {
                            let span = PK4.nixies[PK4.cost]
                            nixie("Queue depth", PK4.queueDepth, nil, "HG11", span: span)
                            nixie("Tool calls", PK4.toolCalls, nil, "HG12", span: span)
                            nixie("Last turn", PK4.lastTurn, "min:s", "HG13", span: span)
                            nixie("Turn messages", PK4.turnMessages, nil, "HG14", span: span)
                            nixie("Session uptime", PK4.uptime, "h:min", "HG15", span: span)
                            nixie("Cost, last checkpoint", PK4.cost, "$", "HG16", span: span)
                        }
                    }
                }
            }

            Grid(alignment: .topLeading, horizontalSpacing: 40, verticalSpacing: 26) {
                GridRow {
                    LampGroup(
                        title: "Permission mode",
                        windows: [
                            ("Default", .white, PK4.permission(.default), "HL35"),
                            ("Accept\nedits", .white, PK4.permission(.acceptEdits), "HL36"),
                            ("Plan", .white, PK4.permission(.plan), "HL37"),
                            ("Auto", .amber, PK4.permission(.auto), "HL38"),
                            ("Bypass", .red, PK4.permission(.bypass), "HL39"),
                        ], s: s)
                    LampGroup(
                        title: "Effort",
                        windows: [
                            ("Low", .green, PK4.effort(.low), "HL40"),
                            ("Medium", .green, PK4.effort(.medium), "HL41"),
                            ("High", .amber, PK4.effort(.high), "HL42"),
                            ("X-high", .amber, PK4.effort(.xhigh), "HL43"),
                            ("Max", .amber, PK4.effort(.max), "HL72"),
                            ("Ultra\ncode", .red, PK4.effort(.ultracode), "HL73"),
                        ], s: s)
                    LampGroup(
                        title: "Model",
                        windows: [
                            ("Opus 200K", .white, PK4.model(.opus200k), "HL44"),
                            ("Opus 1M", .white, PK4.model(.opus1m), "HL74"),
                            ("Sonnet", .white, PK4.model(.sonnet), "HL45"),
                            ("Haiku", .white, PK4.model(.haiku), "HL46"),
                            ("Fable", .white, PK4.model(.fable), "HL71"),
                            ("Other", .amber, PK4.model(.other), "HL47"),
                        ], s: s)
                }
                GridRow {
                    VStack(alignment: .leading, spacing: 10) {
                        LampGroup(
                            title: "Mode",
                            windows: [
                                ("Normal", .white, PK4.mode(.normal), "HL48"),
                                ("Other mode", .amber, PK4.mode(.other), "HL49"),
                            ], s: s)
                        LampGroup(
                            title: "Kind",
                            windows: [
                                ("Interactive", .white, PK4.kind(.interactive), "HL50"),
                                ("Detached", .white, PK4.kind(.detached), "HL51"),
                            ], s: s)
                    }
                    LampGroup(
                        title: "Service tier",
                        windows: [
                            ("Standard", .white, PK4.tier(.standard), "HL52"),
                            ("Other tier", .amber, PK4.tier(.other), "HL53"),
                        ], s: s)
                    LampGroup(
                        title: "Warnings",
                        windows: [
                            ("Price\nunknown", .red, PK4.warning(.price), "HL54"),
                            ("Data stale", .red, PK4.warning(.stale), "HL55"),
                            ("Subagent\nactive", .white, PK4.warning(.subagent), "HL56"),
                            ("Pre-compact", .amber, PK4.warning(.precompact), "HL57"),
                        ], s: s)
                }
            }

            VStack(spacing: 16) {
                Plate(text: "Electromechanical totals · hold reading on power loss")
                HStack(alignment: .top) {
                    DrumCounter(
                        label: "Total cost", value: s.drum(PK4.totalCost), unit: "$", code: "PC1",
                        id: PK4.totalCost.rawValue)
                    Spacer()
                    DrumCounter(
                        label: "Total output", value: s.drum(PK4.totalOutput), unit: "×1000 tok",
                        code: "PC2", id: PK4.totalOutput.rawValue)
                    Spacer()
                    DrumCounter(
                        label: "Lines added", value: s.drum(PK4.linesAdded), code: "PC3",
                        id: PK4.linesAdded.rawValue)
                    Spacer()
                    DrumCounter(
                        label: "Lines removed", value: s.drum(PK4.linesRemoved), code: "PC4",
                        id: PK4.linesRemoved.rawValue)
                    Spacer()
                    BlankingPlate(text: "Reserved", size: CGSize(width: 200, height: 84))
                    Spacer()
                    BlankingPlate(text: "Reserved", size: CGSize(width: 200, height: 84))
                }
            }

            VStack(spacing: 16) {
                Plate(text: "Disruptive commands")
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 20) {
                        NixieReadout(
                            label: "Command goes to session", template: "0",
                            value: s.nixie(PK4.targetB),
                            labelWidth: 220, code: "HG3", id: PK4.targetB.rawValue
                        )
                        .accessibilityHidden(true)
                        InstructionPlate(
                            text: "Lift guard, press and hold 2 s. Acts on the selected session")
                    }
                    .frame(width: 470)
                    Spacer()
                    HStack(alignment: .top, spacing: 36) {
                        guarded(PK4.f10, "F10", "[Function 10]", keyed: false, code: "SB4")
                        guarded(PK4.f11, "F11", "[Function 11]", keyed: false, code: "SB5")
                        guarded(PK4.f12, "F12", "End session", keyed: true, code: "SB6")
                    }
                    Spacer()
                }
            }
        }
    }

    private func meter(
        _ label: String, _ id: InstrumentID, red: ClosedRange<Double>? = nil, code: String
    ) -> some View {
        MovingCoilMeter(
            label: label, value: s.meter(id), red: red, powered: s.mains, code: code,
            id: id.rawValue
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(PK4Words.meter(s.meter(id)))
    }

    private func nixie(
        _ label: String, _ id: InstrumentID, _ unit: String?, _ code: String,
        unitWidth: CGFloat? = nil, span: String? = nil
    ) -> some View {
        NixieReadout(
            label: label, template: PK4.nixies[id] ?? "", value: s.nixie(id), unit: unit,
            labelWidth: 150, code: code, unitWidth: unitWidth, span: span, id: id.rawValue
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(PK4Words.digits(s.nixie(id)))
    }

    private func guarded(
        _ id: InstrumentID, _ cap: String, _ label: String, keyed: Bool, code: String
    ) -> some View {
        GuardedButton(
            id: id, cap: cap, label: label, keyed: keyed, face: s.button(id),
            open: s.guardsOpen.contains(id), armed: s.keysArmed.contains(id), code: code)
    }
}

/// A plate and its windows, three to a row, `space-2` apart.
private struct LampGroup: View {
    var title: String
    var windows: [(String, LampColor, InstrumentID, String)]
    let s: ConsoleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Plate(text: title)
            let rows = stride(from: 0, to: windows.count, by: 3).map {
                Array(windows[$0..<min($0 + 3, windows.count)])
            }
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ForEach(rows[index], id: \.2) { window in
                        LampWindow(
                            label: window.0, color: window.1, state: s.lamp(window.2),
                            code: window.3, id: window.2.rawValue
                        )
                        .equatable()
                        .accessibilityElement()
                        .accessibilityLabel(
                            "\(title), \(window.0.replacingOccurrences(of: "\n", with: " "))"
                        )
                        .accessibilityValue(PK4Words.lamp(s.lamp(window.2)))
                    }
                }
            }
        }
    }
}

// MARK: - Panel C · control

private struct PanelC: View {
    let s: ConsoleSnapshot

    /// What the routine keys do, on their plates. F6 to F9 keep the placeholder until
    /// they have a job: a key labelled with a promise it cannot keep is worse.
    static let functions: [Int: String] = [
        1: "Open folder", 2: "Terminal here", 3: "Copy resume", 4: "Safety log",
        5: "Show transcript",
    ]

    var body: some View {
        PK4Panel(title: "C · Control — selected session", spacing: 26) {
            NixieReadout(
                label: "Command goes to session", template: "0", value: s.nixie(PK4.targetC),
                xl: true,
                code: "HG17", id: PK4.targetC.rawValue
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Command goes to session")
            .accessibilityValue(PK4Words.digits(s.nixie(PK4.targetC)))
            Plate(text: "Routine commands")
            Grid(horizontalSpacing: 18, verticalSpacing: 22) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let number = row * 3 + column + 1
                            // SB8 to SB14 for F1 to F7; SB15 on went to panel D first.
                            PushButton(
                                id: PK4.function(number), cap: "F\(number)",
                                label: Self.functions[number] ?? "[Function \(number)]",
                                face: s.button(PK4.function(number)),
                                code: "SB\(number <= 7 ? 7 + number : 12 + number)")
                        }
                    }
                }
            }
            InstructionPlate(
                text: "Button lamp lights on confirmation from the machine, not on press")
        }
    }
}

// MARK: - Panel D · computer controls

private struct PanelD: View {
    let s: ConsoleSnapshot

    var body: some View {
        PK4Panel(title: "D · Computer controls", spacing: 30) {
            HStack(alignment: .top) {
                round(PK4.sleepMode, "Slp", "Sleep\nmode", codes: ("HL63", "HL64", "SB15"))
                Spacer()
                round(PK4.monitorOff, "Mon", "Turn off monitor", codes: ("HL65", "HL66", "SB16"))
                Spacer()
                round(PK4.fc1, "FC1", "Awake · display on", codes: ("HL67", "HL68", "SB17"))
                Spacer()
                round(PK4.fc2, "FC2", "Awake · display off", codes: ("HL69", "HL70", "SB18"))
            }
            InstructionPlate(
                text: "Green = on, white = off. Both dark = no answer from the machine")
            HStack(alignment: .center, spacing: 22) {
                EdgewiseMeter(
                    label: "Battery %", value: s.meter(PK4.batteryMeter), code: "PA4",
                    id: PK4.batteryMeter.rawValue
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery")
                .accessibilityValue(PK4Words.meter(s.meter(PK4.batteryMeter)))
                VStack(alignment: .leading, spacing: 10) {
                    Plate(text: "Power source")
                    HStack(spacing: 8) {
                        window("On mains", .green, PK4.onMains, "HL59")
                        window("On battery", .amber, PK4.onBattery, "HL60")
                    }
                    HStack(spacing: 8) {
                        window("Charging", .white, PK4.charging, "HL61")
                        window("Batt low", .red, PK4.batteryLow, "HL62")
                    }
                }
                // The desk's own supply, beside the Mac's.
                ToggleSwitch(label: "Mains 220 V\n50 Hz", on: s.mains, code: "SA2")
            }
        }
    }

    private func round(
        _ id: InstrumentID, _ cap: String, _ label: String, codes: (String, String, String)
    ) -> some View {
        RoundPushButton(
            id: id, cap: cap, label: label, face: s.button(id), on: s.lamp(PK4.lensOn(id)),
            off: s.lamp(PK4.lensOff(id)), codes: codes)
    }

    private func window(
        _ label: String, _ color: LampColor, _ id: InstrumentID, _ code: String
    ) -> some View {
        LampWindow(label: label, color: color, state: s.lamp(id), code: code, id: id.rawValue)
            .equatable()
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(PK4Words.lamp(s.lamp(id)))
    }
}

// MARK: - Panel E · power and service

private struct PanelE: View {
    let s: ConsoleSnapshot

    @Environment(\.pk4) private var palette

    var body: some View {
        PK4Panel(title: "E · Power and service", spacing: 6) {
            // The two plan windows side by side, well apart: each its meter, how long until
            // it resets, and its two warning lamps under them.
            HStack(alignment: .top, spacing: 0) {
                quota(.session, "Quota · 5 h", meter: "PA5", lamps: ("HL80", "HL81")) {
                    Labelled(label: "Resets in", tag: "HG18") {
                        NixieReadout(
                            template: PK4.nixies[PK4.sessionResets] ?? "",
                            value: s.nixie(PK4.sessionResets), unit: "h:min",
                            id: PK4.sessionResets.rawValue)
                    }
                }
                Spacer()
                quota(.week, "Quota · week", meter: "PA6", lamps: ("HL82", "HL83")) {
                    Labelled(label: "Resets in", tag: "HG19") {
                        HStack(spacing: 14) {
                            NixieReadout(
                                template: PK4.nixies[PK4.weekResetDays] ?? "",
                                value: s.nixie(PK4.weekResetDays), unit: "d",
                                id: PK4.weekResetDays.rawValue)
                            NixieReadout(
                                template: PK4.nixies[PK4.weekResetHours] ?? "",
                                value: s.nixie(PK4.weekResetHours), unit: "h",
                                id: PK4.weekResetHours.rawValue)
                        }
                    }
                }
            }
            // No unit under it: the plate says hours. The point above keeps panel E at its
            // height, and A at its own.
            DrumCounter(
                label: "Hours in service", value: s.drum(PK4.hoursInService), code: "PC5",
                id: PK4.hoursInService.rawValue
            )
            .padding(.top, 1)
        }
    }

    /// One of the plan's usage windows, top to bottom: how much is used, how long until it
    /// resets, and the lamps that warn at 80% and 95%, side by side.
    private func quota<Readout: View>(
        _ quota: PK4.Quota, _ label: String, meter: String, lamps: (String, String),
        @ViewBuilder readout: () -> Readout
    ) -> some View {
        VStack(spacing: 6) {
            HorizontalEdgewiseMeter(
                label: label, value: s.meter(PK4.quotaMeter(quota)), code: meter,
                id: PK4.quotaMeter(quota).rawValue
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(PK4Words.meter(s.meter(PK4.quotaMeter(quota))))
            readout()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label), resets in")
            HStack(spacing: 8) {
                window("Near limit", .amber, PK4.quotaNear(quota), lamps.0)
                window("At limit", .red, PK4.quotaLimit(quota), lamps.1)
            }
        }
    }

    private func window(
        _ label: String, _ color: LampColor, _ id: InstrumentID, _ code: String
    ) -> some View {
        LampWindow(label: label, color: color, state: s.lamp(id), code: code, id: id.rawValue)
            .equatable()
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(PK4Words.lamp(s.lamp(id)))
    }
}

// MARK: - Words

/// What each instrument says to VoiceOver: its plate, and its value in words.
enum PK4Words {
    static func lamp(_ state: LampState) -> String {
        switch state {
        case .off: "dark"
        case .on: "lit"
        case .flash: "alarm, unacknowledged"
        case .test: "lamp test"
        }
    }

    static func digits(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? "dark" : text
    }

    static func meter(_ value: Double) -> String {
        value < 0 ? "no reading" : "\(Int((value * 100).rounded())) percent"
    }

    /// Spoken when an alarm is raised.
    static func alarm(_ id: InstrumentID, selector: Int) -> String? {
        for slot in PK4.slots {
            if id == PK4.annunciator(.wait, slot: slot) {
                return "Waiting for operator, session \(slot), alarm"
            }
            if id == PK4.annunciator(.block, slot: slot) {
                return "Blocked, session \(slot), alarm"
            }
        }
        if id == PK4.warning(.stale) { return "Data stale, session \(selector), alarm" }
        if id == PK4.batteryLow { return "Battery low, alarm" }
        return nil
    }
}
