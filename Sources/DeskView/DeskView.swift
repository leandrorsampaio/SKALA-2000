import AppKit
import ConsoleKit
import DeskArt
import QuartzCore
import os

/// The console's one view: a layer-hosting `NSView` that renders a `ConsoleSnapshot` and
/// turns the operator's hand and keyboard into `ConsoleIntent`s.
///
/// - **Scaling is a transform.** The desk is 2500 × 1800 units, fitted and centred in the
///   view. A size change sets one scale on the desk layer and draws nothing; the art is
///   re-rendered at the exact new pixel size off the main thread when the resize ends.
/// - **Nothing draws on the main thread.** `drawRect` is never called; every image is
///   rendered once into an `ArtSet` in the background.
/// - **Hit testing is a table**, never derived from drawing: see `HitTable`.
@MainActor
public final class DeskView: NSView {

    /// Where the operator's acts go.
    public var send: (ConsoleIntent) -> Void = { _ in }
    /// A button's contact click, down and up: the button's own sound, not the machine's.
    public var click: () -> Void = {}
    /// A selector at its stop clicks dully.
    public var stopClick: () -> Void = {}
    /// Told when a set of art has been rendered, with how long it took.
    public var artRendered: (ArtSet) -> Void = { _ in }

    public var finish: Finish = .greyGreen {
        didSet { if finish != oldValue { styleChanged() } }
    }
    public var lampCodes = true {
        didSet { if lampCodes != oldValue { styleChanged() } }
    }

    let layers = DeskLayers()
    private let root = CALayer()
    private(set) var snapshot = ConsoleSnapshot()
    private var style = ArtStyle()
    /// The size and style of the art on screen, or of the render on its way there.
    private var requested: (scale: CGFloat, style: ArtStyle)?
    private var generation = 0
    private var pendingRender: DispatchWorkItem?
    private static let renderQueue = DispatchQueue(label: "skala2000.art", qos: .userInitiated)
    static let signposts = OSSignposter(
        subsystem: "com.leandrorossisampaio.skala2000", category: "view")

    let hitTable = HitTable()
    var pressed: InstrumentID?
    var keyboardFocus: HitTable.Control?
    var focusFromKeyboard = false
    var pencilField: PencilField?
    lazy var accessibility = DeskAccessibility(view: self)

    public override init(frame: NSRect) {
        super.init(frame: frame)
        root.backgroundColor = Palette.surround
        root.isOpaque = true
        root.isGeometryFlipped = true
        root.actions = DeskLayers.noActions
        root.addSublayer(layers.desk)
        layer = root
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        style = ArtStyle(
            night: Self.isDark(effectiveAppearance), finish: finish,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            lampCodes: lampCodes)
        layers.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override var isFlipped: Bool { true }
    public override var wantsUpdateLayer: Bool { true }
    public override func updateLayer() {}
    /// The console usually lives on another display: the click that brings the window
    /// forward also presses what it lands on.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Snapshot

    /// Main-thread time per snapshot applied, for the benches.
    public nonisolated(unsafe) static var applySeconds: [(at: Double, seconds: Double)] = []
    /// Whether the timings above are kept: only for the benches, or they would grow for as
    /// long as the app runs.
    public nonisolated(unsafe) static var recordsTimings = false

    public func apply(_ snapshot: ConsoleSnapshot) {
        let started = CACurrentMediaTime()
        defer {
            if Self.recordsTimings {
                Self.applySeconds.append((started, CACurrentMediaTime() - started))
            }
        }
        let state = Self.signposts.beginInterval("apply snapshot")
        self.snapshot = snapshot
        if snapshot.finish != finish { finish = snapshot.finish }
        // A guard that fell takes the keyboard focus off the button it now covers.
        refreshFocus()
        layers.apply(snapshot, animated: layers.art != nil)
        accessibility.update(snapshot)
        Self.signposts.endInterval("apply snapshot", state)
    }

    // MARK: - Scaling

    /// Desk units to view points.
    var deskScale: CGFloat {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / DeskLayout.size.width, size.height / DeskLayout.size.height)
    }

    var deskOrigin: CGPoint {
        let k = deskScale
        return CGPoint(
            x: ((bounds.width - DeskLayout.size.width * k) / 2).rounded(),
            y: ((bounds.height - DeskLayout.size.height * k) / 2).rounded())
    }

    /// Main-thread time spent in `setFrameSize`, for the resize bench.
    public nonisolated(unsafe) static var resizeSeconds: [Double] = []

    public override func setFrameSize(_ newSize: NSSize) {
        let started = CACurrentMediaTime()
        defer {
            if Self.recordsTimings { Self.resizeSeconds.append(CACurrentMediaTime() - started) }
        }
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let k = deskScale
        layers.desk.setAffineTransform(CGAffineTransform(scaleX: k, y: k))
        layers.desk.position = deskOrigin
        CATransaction.commit()
        // During a live resize the old bitmap is scaled by the GPU; it's redrawn sharp
        // when the resize ends, or 150 ms after the last change.
        scheduleRender(after: inLiveResize ? nil : 0.15)
    }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        scheduleRender(after: 0)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        root.contentsScale = window?.backingScaleFactor ?? 2
        scheduleRender(after: 0)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleRender(after: 0)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        styleChanged()
    }

    @objc private func accessibilityDisplayChanged() {
        layers.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        styleChanged()
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func styleChanged() {
        let next = ArtStyle(
            night: Self.isDark(effectiveAppearance), finish: finish,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            lampCodes: lampCodes)
        guard next != style else { return }
        style = next
        scheduleRender(after: 0)
    }

    /// Device pixels per desk unit at the current size.
    var pixelScale: CGFloat {
        deskScale * (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }

    private func scheduleRender(after delay: TimeInterval?) {
        pendingRender?.cancel()
        guard let delay, window != nil else { return }
        let target = pixelScale
        // Close enough: redrawing for a 1% change is work nobody would see. Measured
        // against the render still on its way too, not only the art installed: a size
        // dragged back while one draws must not leave that one's size up.
        if let requested, requested.style == style,
            abs(target - requested.scale) / requested.scale < 0.01
        {
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.render(scale: target) }
        pendingRender = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func render(scale: CGFloat) {
        generation += 1
        let ticket = generation
        let style = self.style
        requested = (scale, style)
        let first = layers.art == nil
        let styleSwap = layers.art.map { $0.style != style } ?? false
        Self.renderQueue.async {
            let art = ArtCache.shared.art(style: style, scale: scale)
            DispatchQueue.main.async { [weak self] in
                guard let self, ticket == self.generation else { return }
                // Not drawn, for want of memory: the art on screen stays, and the next
                // change of size or style asks again.
                guard let art else {
                    self.requested = self.layers.art.map { (scale: $0.scale, style: $0.style) }
                    return
                }
                let installStarted = CACurrentMediaTime()
                defer {
                    if Self.recordsTimings {
                        Self.installSeconds.append(CACurrentMediaTime() - installStarted)
                    }
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if styleSwap {
                    // Day to night, or a new paint: a short crossfade, as a room's lights dim.
                    let fade = CATransition()
                    fade.type = .fade
                    fade.duration = 0.25
                    self.layers.desk.add(fade, forKey: "style")
                }
                self.layers.install(art)
                CATransaction.commit()
                if first { self.layers.apply(self.snapshot, animated: false) }
                self.artRendered(art)
            }
        }
    }

    public nonisolated(unsafe) static var installSeconds: [Double] = []

    // MARK: - Geometry for input

    /// A point in this view, in desk units.
    func deskPoint(_ point: CGPoint) -> CGPoint {
        let k = deskScale
        let origin = deskOrigin
        return CGPoint(x: (point.x - origin.x) / k, y: (point.y - origin.y) / k)
    }

    /// A rect in desk units, in this view's coordinates.
    func viewRect(_ rect: CGRect) -> CGRect {
        let k = deskScale
        let origin = deskOrigin
        return CGRect(
            x: origin.x + rect.minX * k, y: origin.y + rect.minY * k, width: rect.width * k,
            height: rect.height * k)
    }
}
