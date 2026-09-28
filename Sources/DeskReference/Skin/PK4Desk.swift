import AppKit
import ConsoleKit
import SwiftUI

/// The assembled PK-4 desk, scaled to its window.
///
/// The desk is one fixed drawing 3352 units wide and 1800 tall, scaled uniformly with a
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
            panel("F · Computer load", PanelF(s: s))
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

/// Four columns, six panels, listed in reading order: A, B, C, D, E, F.
///
/// VoiceOver and the Tab key go through the panels in the order they are listed, not the
/// order they are drawn, and a column of stacks would list E, at the foot of the first
/// column, before B. So the desk is one layout that puts each panel where it belongs: A
/// over E on the left, B in the middle, C over D beside it, and F, the Mac's own load, on
/// the right. A and D take whatever height their column leaves; B and F take it all.
struct DeskLayout: Layout {
    // B as narrow as its lamp groups allow; A and E have the rest. F as wide as A.
    static let columns: [CGFloat] = [836, 1004, 580, 836]
    static let gap: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard subviews.count == 7 else { return }
        let gap = Self.gap
        let widths = Self.columns
        func natural(_ index: Int, width: CGFloat) -> CGFloat {
            subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        func place(_ index: Int, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            subviews[index].place(
                at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: height))
        }

        // The header spans A to D only, so it is whole whether F is shown or not.
        let headerWidth = widths[0] + widths[1] + widths[2] + 2 * gap
        let header = natural(0, width: headerWidth)
        place(0, bounds.minX, bounds.minY, headerWidth, header)
        let top = bounds.minY + header + gap
        let height = bounds.maxY - top
        let left = bounds.minX
        let middle = left + widths[0] + gap
        let right = middle + widths[1] + gap
        let far = right + widths[2] + gap

        let e = natural(5, width: widths[0])
        place(1, left, top, widths[0], height - e - gap)
        place(5, left, bounds.maxY - e, widths[0], e)
        place(2, middle, top, widths[1], height)
        let c = natural(3, width: widths[2])
        place(3, right, top, widths[2], c)
        place(4, right, top + c + gap, widths[2], height - c - gap)
        // F is a cabinet of its own beside the desk: the whole height, header row too.
        place(6, far, bounds.minY, widths[3], bounds.maxY - bounds.minY)
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
        (.lowctx, "Low context", "Low ctx", .red), (.remote, "Remote control", "Remote", .white),
    ]

    /// HL33 on went to panel B first: LOW CONTEXT is HL76 to HL79, REMOTE HL84 to HL87.
    private static func code(row index: Int, slot: Int) -> String {
        switch index {
        case ..<8: "HL\(index * 4 + slot)"
        case 8: "HL\(75 + slot)"
        default: "HL\(83 + slot)"
        }
    }

    var body: some View {
        PK4Panel(title: "A · All sessions — annunciator", spacing: 25) {
            // 11: ten rows of windows packed as an annunciator is, to leave the buzzer room.
            Grid(horizontalSpacing: 26, verticalSpacing: 11) {
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
                                code: Self.code(row: index, slot: slot), id: id.rawValue
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
                text: "Red windows flash while their cause holds. SIL silences every signal",
                width: 520)
            HStack(alignment: .top, spacing: 90) {
                NixieReadout(
                    label: "Sessions running", template: "0", value: s.nixie(PK4.sessionsRunning),
                    labelWidth: 170, code: "HG1", id: PK4.sessionsRunning.rawValue
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sessions running")
                .accessibilityValue(PK4Words.digits(s.nixie(PK4.sessionsRunning)))
                NixieReadout(
                    label: "Sessions busy", template: "0", value: s.nixie(PK4.sessionsBusy),
                    labelWidth: 150, code: "HG2", id: PK4.sessionsBusy.rawValue
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sessions busy")
                .accessibilityValue(PK4Words.digits(s.nixie(PK4.sessionsBusy)))
            }
            HStack(alignment: .top, spacing: 0) {
                // SILENCED beside the buzzer rather than under it: the row it gave up is
                // REMOTE's.
                HStack(alignment: .top, spacing: 14) {
                    Labelled(label: "Buzzer", tag: "HA1") { BuzzerGrille(sounding: s.buzzer) }
                    // Burns while an alarm would go unheard: silenced, or muted in Settings.
                    // Level with the grille's middle.
                    LampWindow(
                        label: "Silenced", color: .amber, state: s.lamp(PK4.silenced),
                        code: "HL75", id: PK4.silenced.rawValue
                    )
                    .equatable()
                    .padding(.top, 25)
                    .accessibilityElement()
                    .accessibilityLabel("Silenced")
                    .accessibilityValue(PK4Words.lamp(s.lamp(PK4.silenced)))
                }
                Spacer()
                // What the alarms answer to, and the two tests, each a group of its own.
                VStack(spacing: 14) {
                    Plate(text: "Alarms")
                    HStack(alignment: .top, spacing: 24) {
                        PushButton(
                            id: PK4.silence, cap: "Sil", label: "Silence",
                            face: s.button(PK4.silence), code: "SB1")
                        PushButton(
                            id: PK4.acknowledge, cap: "Ack", label: "Acknowledge", tone: .amber,
                            face: s.button(PK4.acknowledge), code: "SB2")
                    }
                }
                Spacer()
                VStack(spacing: 14) {
                    Plate(text: "Tests")
                    HStack(alignment: .top, spacing: 24) {
                        PushButton(
                            id: PK4.lampTest, cap: "Test", label: "Lamp test",
                            face: s.button(PK4.lampTest), code: "SB3")
                        PushButton(
                            id: PK4.buzzerTest, cap: "Bzr", label: "Buzzer test",
                            face: s.button(PK4.buzzerTest), code: "SB19")
                    }
                }
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
            title: "B · Selected session — instruments", spacing: 36,
            padding: EdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26),
            tightBottom: true
        ) {
            // The knob that chooses the session, which one it chose, PRINT TO LOG, F1 to open
            // its folder, and the one disruptive command: a row, spread from edge to edge.
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 8) {
                    RotarySelector(position: s.selector)
                    Plate(text: "Session selector")
                    Tag(text: "SA1")
                }
                Spacer(minLength: 20)
                NixieReadout(
                    label: "Selected", template: "0", value: s.nixie(PK4.selected), xl: true,
                    code: "HG4", id: PK4.selected.rawValue
                )
                .accessibilityHidden(true)
                Spacer(minLength: 20)
                PushButton(
                    id: PK4.printText, cap: "Prt", label: "Print to log",
                    face: s.button(PK4.printText), code: "SB7")
                Spacer(minLength: 20)
                PushButton(
                    id: PK4.function(1), cap: "F1", label: PanelC.functions[1] ?? "",
                    face: s.button(PK4.function(1)), code: "SB8")
                Spacer(minLength: 20)
                VStack(spacing: 16) {
                    Plate(text: "Disruptive commands")
                    guarded(PK4.f12, "F12", "End session", keyed: true, code: "SB6")
                }
            }
            VStack(spacing: 14) {
                // The meters spread over the width of the tubes below, edge to edge.
                HStack(alignment: .top, spacing: 0) {
                    meter("Context remaining", PK4.contextMeter, red: 0...0.2, code: "PA1")
                    Spacer(minLength: 20)
                    meter("API share of time", PK4.apiShareMeter, code: "PA2")
                    Spacer(minLength: 20)
                    meter("Tool share of time", PK4.toolShareMeter, code: "PA3")
                }
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        nixie("Context used", PK4.contextUsed, "tok", "HG5", unitWidth: 34)
                        nixie("Input tokens", PK4.inputTokens, "tok", "HG6", unitWidth: 34)
                        nixie("Output tokens", PK4.outputTokens, "tok", "HG7", unitWidth: 34)
                        nixie("Thinking tokens", PK4.thinkingTokens, "tok", "HG8", unitWidth: 34)
                        nixie("Cache read", PK4.cacheRead, "×1000", "HG9", unitWidth: 34)
                        nixie("Cache written", PK4.cacheWritten, "×1000", "HG10", unitWidth: 34)
                    }
                    Spacer(minLength: 30)
                    // Left-aligned, so these tubes line up whatever their units say.
                    VStack(alignment: .leading, spacing: 10) {
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

            // Each group on a line of its own, its plate on the left, as panel A's rows are.
            VStack(alignment: .leading, spacing: 10) {
                LampRow(
                    title: "Permission mode",
                    windows: [
                        ("Default", .white, PK4.permission(.default), "HL35"),
                        ("Accept\nedits", .white, PK4.permission(.acceptEdits), "HL36"),
                        ("Plan", .white, PK4.permission(.plan), "HL37"),
                        ("Auto", .amber, PK4.permission(.auto), "HL38"),
                        ("Bypass", .red, PK4.permission(.bypass), "HL39"),
                    ], s: s)
                LampRow(
                    title: "Effort",
                    windows: [
                        ("Low", .green, PK4.effort(.low), "HL40"),
                        ("Medium", .green, PK4.effort(.medium), "HL41"),
                        ("High", .amber, PK4.effort(.high), "HL42"),
                        ("X-high", .amber, PK4.effort(.xhigh), "HL43"),
                        ("Max", .amber, PK4.effort(.max), "HL72"),
                        ("Ultra\ncode", .red, PK4.effort(.ultracode), "HL73"),
                    ], s: s)
                LampRow(
                    title: "Model",
                    windows: [
                        ("Opus 200K", .white, PK4.model(.opus200k), "HL44"),
                        ("Opus 1M", .white, PK4.model(.opus1m), "HL74"),
                        ("Sonnet", .white, PK4.model(.sonnet), "HL45"),
                        ("Haiku", .white, PK4.model(.haiku), "HL46"),
                        ("Fable", .white, PK4.model(.fable), "HL71"),
                        ("Other", .amber, PK4.model(.other), "HL47"),
                    ], s: s)
                LampRow(
                    title: "Mode",
                    windows: [
                        ("Normal", .white, PK4.mode(.normal), "HL48"),
                        ("Other mode", .amber, PK4.mode(.other), "HL49"),
                    ], s: s)
                LampRow(
                    title: "Kind",
                    windows: [
                        ("Interactive", .white, PK4.kind(.interactive), "HL50"),
                        ("Detached", .white, PK4.kind(.detached), "HL51"),
                    ], s: s)
                LampRow(
                    title: "Service tier",
                    windows: [
                        ("Standard", .white, PK4.tier(.standard), "HL52"),
                        ("Other tier", .amber, PK4.tier(.other), "HL53"),
                    ], s: s)
                LampRow(
                    title: "Warnings",
                    windows: [
                        ("Price\nunknown", .red, PK4.warning(.price), "HL54"),
                        ("Data stale", .red, PK4.warning(.stale), "HL55"),
                        ("Subagent\nactive", .white, PK4.warning(.subagent), "HL56"),
                        ("Pre-compact", .amber, PK4.warning(.precompact), "HL57"),
                    ], s: s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Plate(text: "Electromechanical totals · hold reading on power loss")
                HStack(alignment: .top, spacing: 56) {
                    DrumCounter(
                        label: "Total cost", value: s.drum(PK4.totalCost), unit: "$", code: "PC1",
                        id: PK4.totalCost.rawValue)
                    DrumCounter(
                        label: "Total output", value: s.drum(PK4.totalOutput), unit: "×1000 tok",
                        code: "PC2", id: PK4.totalOutput.rawValue)
                    DrumCounter(
                        label: "Lines added", value: s.drum(PK4.linesAdded), code: "PC3",
                        id: PK4.linesAdded.rawValue)
                    DrumCounter(
                        label: "Lines removed", value: s.drum(PK4.linesRemoved), code: "PC4",
                        id: PK4.linesRemoved.rawValue)
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

/// A plate and its windows on one line, the plate on the left.
private struct LampRow: View {
    var title: String
    /// The plates of the first group on each line share a width, so the lamps line up.
    var titleWidth: CGFloat? = 150
    var windows: [(String, LampColor, InstrumentID, String)]
    let s: ConsoleSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Plate(text: title, width: titleWidth)
            HStack(spacing: 8) {
                ForEach(windows, id: \.2) { window in
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

    /// What the routine keys do, on their plates. F6 and F7 keep the placeholder until
    /// they have a job: a key labelled with a promise it cannot keep is worse. F1 stands
    /// on panel B, beside PRINT TO LOG.
    static let functions: [Int: String] = [
        1: "Open folder", 2: "Terminal here", 3: "Copy resume", 4: "Safety log",
        5: "Show transcript",
    ]

    var body: some View {
        PK4Panel(title: "C · Control — selected session", spacing: 26) {
            Plate(text: "Routine commands")
            // F2 to F7, two rows of three: SB9 to SB14.
            Grid(horizontalSpacing: 18, verticalSpacing: 22) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let number = row * 3 + column + 2
                            PushButton(
                                id: PK4.function(number), cap: "F\(number)",
                                label: Self.functions[number] ?? "[Function \(number)]",
                                face: s.button(PK4.function(number)), code: "SB\(7 + number)")
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
        // The screws sit on the bottom padding, as B's and F's do: the two lamp rows take the
        // room the spacer's gaps had.
        PK4Panel(title: "D · Computer controls", spacing: 30, tightBottom: true) {
            HStack(alignment: .top) {
                round(PK4.sleepMode, "Slp", "Sleep\nmode", codes: ("HL63", "HL64", "SB15"))
                Spacer()
                round(PK4.monitorOff, "Mon", "Turn off monitor", codes: ("HL65", "HL66", "SB16"))
                Spacer()
                round(PK4.fc1, "FC1", "Awake · display on", codes: ("HL67", "HL68", "SB17"))
                Spacer()
                round(PK4.fc2, "FC2", "Awake · display off", codes: ("HL69", "HL70", "SB18"))
            }
            // The desk's own window and the Mac's sound. The caps line up; MINIMIZE has no
            // lenses, having no state.
            HStack(alignment: .bottom) {
                round(PK4.onTop, "Top", "Window\non top", codes: ("HL95", "HL96", "SB22"))
                Spacer()
                round(PK4.speakers, "Spk", "Mac\nspeakers", codes: ("HL97", "HL98", "SB23"))
                Spacer()
                round(PK4.computer, "F", "Computer\nstatus", codes: ("HL99", "HL100", "SB24"))
                Spacer()
                round(PK4.minimize, "Min", "Minimize\nwindow", codes: (nil, nil, "SB25"))
            }
            HStack(alignment: .center, spacing: 44) {
                EdgewiseMeter(
                    label: "Battery %", value: s.meter(PK4.batteryMeter), code: "PA4",
                    id: PK4.batteryMeter.rawValue
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery")
                .accessibilityValue(PK4Words.meter(s.meter(PK4.batteryMeter)))
                VStack(alignment: .leading, spacing: 14) {
                    Plate(text: "Power source")
                    HStack(spacing: 14) {
                        window("On mains", .green, PK4.onMains, "HL59")
                        window("On battery", .amber, PK4.onBattery, "HL60")
                    }
                    HStack(spacing: 14) {
                        window("Charging", .white, PK4.charging, "HL61")
                        window("Batt low", .red, PK4.batteryLow, "HL62")
                    }
                }
            }
            // Well clear of the buttons above: a group of its own.
            .padding(.top, 30)

            // How the Mac is coping, under its power: plates on two lines, as SLEEP MODE's,
            // so four lamps fit the panel's width.
            VStack(alignment: .leading, spacing: 10) {
                LampRow(
                    title: "Thermal\nstate", titleWidth: 100,
                    windows: [
                        ("Nominal", .green, PK4.thermal(.nominal), "HL88"),
                        ("Fair", .amber, PK4.thermal(.fair), "HL89"),
                        ("Serious", .red, PK4.thermal(.serious), "HL90"),
                        ("Critical", .red, PK4.thermal(.critical), "HL91"),
                    ], s: s)
                LampRow(
                    title: "Memory\npressure", titleWidth: 100,
                    windows: [
                        ("Normal", .green, PK4.pressure(.normal), "HL92"),
                        ("Warning", .amber, PK4.pressure(.warning), "HL93"),
                        ("Critical", .red, PK4.pressure(.critical), "HL94"),
                    ], s: s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func round(
        _ id: InstrumentID, _ cap: String, _ label: String, codes: (String?, String?, String)
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
        PK4Panel(title: "E · Power and service", spacing: 18) {
            quota(.session, "Quota · 5 h", meter: "PA5", resets: "HG18", lamps: ("HL80", "HL81"))
            // Apart, so the two windows read as two.
            quota(.week, "Quota · week", meter: "PA6", resets: "HG19", lamps: ("HL82", "HL83"))
                .padding(.top, 18)
            // Apart from the two windows, its label on the left like theirs.
            DrumCounter(
                label: "Hours in service", value: s.drum(PK4.hoursInService), code: "PC5",
                id: PK4.hoursInService.rawValue, labelLeading: true
            )
            .padding(.top, 29)
        }
    }

    /// One of the plan's usage windows, in one row: its meter; how long until it resets, in
    /// days, hours and minutes, the label on the left; and the lamps that warn at 80% and
    /// 95%, one above the other.
    private func quota(
        _ quota: PK4.Quota, _ label: String, meter: String, resets code: String,
        lamps: (String, String)
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HorizontalEdgewiseMeter(
                label: label, value: s.meter(PK4.quotaMeter(quota)), code: meter,
                id: PK4.quotaMeter(quota).rawValue
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(PK4Words.meter(s.meter(PK4.quotaMeter(quota))))
            HStack(spacing: 10) {
                tube(quota, .days, "d", label: "Resets in", code: code)
                tube(quota, .hours, "h")
                tube(quota, .minutes, "m")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), resets in")
            VStack(spacing: 8) {
                window("Near limit", .amber, PK4.quotaNear(quota), lamps.0)
                window("At limit", .red, PK4.quotaLimit(quota), lamps.1)
            }
        }
    }

    private func tube(
        _ quota: PK4.Quota, _ part: PK4.ResetPart, _ unit: String, label: String? = nil,
        code: String? = nil
    ) -> some View {
        let id = PK4.quotaReset(quota, part)
        return NixieReadout(
            label: label, template: PK4.nixies[id] ?? "", value: s.nixie(id), unit: unit,
            labelWidth: label == nil ? nil : 84, code: code, unitWidth: 12, id: id.rawValue)
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

// MARK: - Panel F · computer load

/// What the Mac is doing: its processors, GPU, power and memory on meters; temperatures,
/// fans, memory, disk and network on tubes; and each seated session's own processes, in
/// panel A's four columns. Its thermal state and memory pressure are lamps at the foot of
/// panel D.
private struct PanelF: View {
    let s: ConsoleSnapshot

    var body: some View {
        PK4Panel(
            title: "F · Computer — load and heat", spacing: 72,
            padding: EdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26),
            tightBottom: true
        ) {
            // Four meters in a block of their own, two by two.
            Grid(horizontalSpacing: 56, verticalSpacing: 40) {
                GridRow {
                    meter("CPU load", .cpu, code: "PA7")
                    meter("GPU load", .gpu, code: "PA8")
                }
                GridRow {
                    meter("Power drawn", .power, unit: "W", code: "PA9")
                    meter("Memory used", .memory, red: 0.9...1, code: "PA10")
                }
            }

            // Heat, fans and the disk's traffic on the left; memory, the disk's room and the
            // network on the right. Each column's glass the width of its widest readout.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    gauge("SoC temp", .socTemp, "°C", "HG20")
                    gauge("SSD temp", .ssdTemp, "°C", "HG21")
                    gauge("Battery temp", .batteryTemp, "°C", "HG22")
                    gauge("Fan 1", .fan1, "rpm", "HG23")
                    gauge("Fan 2", .fan2, "rpm", "HG24")
                    gauge("Disk read", .diskRead, "MB/s", "HG25")
                    gauge("Disk write", .diskWrite, "MB/s", "HG26")
                }
                Spacer(minLength: 30)
                VStack(alignment: .leading, spacing: 24) {
                    gauge("Memory used", .memoryUsed, "GB", "HG27")
                    gauge("Wired", .memoryWired, "GB", "HG28")
                    gauge("Compressed", .memoryCompressed, "GB", "HG29")
                    gauge("Swap used", .swap, "GB", "HG30")
                    gauge("Disk free", .diskFree, "GB", "HG31")
                    gauge("Network in", .networkIn, "MB/s", "HG32")
                    gauge("Network out", .networkOut, "MB/s", "HG33")
                }
            }

            // Each seated session's processes, in panel A's columns.
            Grid(horizontalSpacing: 22, verticalSpacing: 24) {
                GridRow {
                    Plate(text: "Session", width: 170)
                    ForEach(PK4.slots, id: \.self) { slot in
                        Text(String(slot)).font(PK4Type.label(30, bold: true))
                            .mark("numeral", "", ["text": String(slot)])
                            .accessibilityHidden(true)
                    }
                }
                GridRow {
                    Plate(text: "CPU · % of Mac", width: 170)
                    ForEach(PK4.slots, id: \.self) { slot in
                        session(PK4.sessionCPU(slot: slot), "CPU, session \(slot)")
                    }
                }
                GridRow {
                    Plate(text: "Memory · GB", width: 170)
                    ForEach(PK4.slots, id: \.self) { slot in
                        session(PK4.sessionMemory(slot: slot), "Memory, session \(slot)")
                    }
                }
            }
        }
    }

    private func meter(
        _ label: String, _ load: PK4.Load, unit: String = "%", red: ClosedRange<Double>? = nil,
        code: String
    ) -> some View {
        let id = PK4.loadMeter(load)
        return MovingCoilMeter(
            label: label, value: s.meter(id), red: red, unit: unit, powered: s.mains, code: code,
            id: id.rawValue
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(PK4Words.meter(s.meter(id)))
    }

    private func gauge(
        _ label: String, _ gauge: PK4.Gauge, _ unit: String, _ code: String
    )
        -> some View
    {
        let id = PK4.gauge(gauge)
        return NixieReadout(
            label: label, template: gauge.template, value: s.nixie(id), unit: unit,
            labelWidth: 150, code: code, unitWidth: 40, span: "000.0", id: id.rawValue
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(PK4Words.digits(s.nixie(id)))
    }

    private func session(_ id: InstrumentID, _ label: String) -> some View {
        NixieReadout(
            template: PK4.nixies[id] ?? "", value: s.nixie(id), span: "00.0", id: id.rawValue
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(PK4Words.digits(s.nixie(id)))
    }
}

// MARK: - Words

/// What each instrument says to VoiceOver: its plate, and its value in words.
enum PK4Words {
    static func lamp(_ state: LampState) -> String {
        switch state {
        case .off: "dark"
        case .on: "lit"
        case .flash: "alarm, flashing"
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
