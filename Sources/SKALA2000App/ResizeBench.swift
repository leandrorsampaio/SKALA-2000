import AppKit
import DeskView
import QuartzCore

/// For measurements only (`SKALA_BENCH=resize`): drives the window from 1280 points wide to
/// the largest the screen allows and back, a step every frame, and writes how long each
/// step kept the main thread busy and how often the display link missed a frame, to
/// `resize.log` in the data folder.
@MainActor
final class ResizeBench: NSObject {
    private weak var window: NSWindow?
    private let url: URL
    private var steps: [Double] = []
    private var frames: [CFTimeInterval] = []
    private var link: CADisplayLink?
    private var widths: [CGFloat] = []

    init(window: NSWindow, folder: URL) {
        self.window = window
        url = folder.appendingPathComponent("resize.log")
        super.init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.start() }
    }

    private func start() {
        guard let window, let screen = window.screen else { return }
        let ratio = window.contentAspectRatio.height / window.contentAspectRatio.width
        let chrome = window.frame.height - window.contentLayoutRect.height
        let widest = min(screen.visibleFrame.width, (screen.visibleFrame.height - chrome) / ratio)
            .rounded(.down)
        // Out and back twice, in steps of about eight points: a hand dragging a corner.
        let out = stride(from: 1280, through: widest, by: 8).map { CGFloat($0) }
        widths = out + out.reversed() + out + out.reversed()
        window.setFrameOrigin(screen.visibleFrame.origin)
        link = window.contentView?.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        frames.append(link.timestamp)
        guard let window else { return }
        guard !widths.isEmpty else {
            link.invalidate()
            finish(interval: link.targetTimestamp - link.timestamp)
            return
        }
        let width = widths.removeFirst()
        let ratio = window.contentAspectRatio.height / window.contentAspectRatio.width
        var frame = window.frame
        let chrome = frame.height - window.contentLayoutRect.height
        frame.size = NSSize(width: width, height: width * ratio + chrome)
        let started = CACurrentMediaTime()
        window.setFrame(frame, display: true)
        steps.append((CACurrentMediaTime() - started) * 1000)
    }

    private func finish(interval: CFTimeInterval) {
        let sorted = steps.sorted()
        let gaps = zip(frames.dropFirst(), frames).map { $0 - $1 }
        let expected = gaps.sorted()[gaps.count / 2]
        let missed = gaps.filter { $0 > expected * 1.5 }.count
        let line = String(
            format:
                "steps %d, main thread per step: mean %.2f ms, p95 %.2f ms, max %.2f ms; frame %.1f ms, missed %d of %d\n",
            steps.count, steps.reduce(0, +) / Double(max(1, steps.count)),
            sorted[Int(Double(sorted.count) * 0.95)],
            sorted.last ?? 0, expected * 1000, missed, gaps.count)
        let mine = DeskView.resizeSeconds.suffix(steps.count).map { $0 * 1000 }.sorted()
        let own = String(
            format: "  of which DeskView.setFrameSize: mean %.3f ms, max %.3f ms\n",
            mine.reduce(0, +) / Double(max(1, mine.count)), mine.last ?? 0)
        let applies = DeskView.applySeconds.map { $0.seconds * 1000 }.sorted()
        let applied = String(
            format:
                "  snapshots applied %d: mean %.3f ms, p95 %.3f ms, max %.3f ms; art installs %@ ms\n",
            applies.count, applies.reduce(0, +) / Double(max(1, applies.count)),
            applies.isEmpty ? 0 : applies[Int(Double(applies.count) * 0.95)], applies.last ?? 0,
            DeskView.installSeconds.map { String(format: "%.1f", $0 * 1000) }.joined(
                separator: ", "))
        try? Data((line + own + applied).utf8).write(to: url)
        NSApp.terminate(nil)
    }
}
