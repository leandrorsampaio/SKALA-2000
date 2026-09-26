import AppKit

/// The text log PRINT TEXT writes to, in an ordinary window: the console itself has no way
/// to show a string. Read-only, monospaced, scrolled to the end.
@MainActor
final class TextLogWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var textView: NSTextView?
    private let read: () -> String

    init(read: @escaping () -> String) {
        self.read = read
        super.init()
    }

    func show() {
        let text = read()
        if let window, let textView {
            textView.string = text.isEmpty ? "Nothing printed yet." : text
            textView.scrollToEndOfDocument(nil)
            window.orderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
            defer: false)
        window.title = "SKALA-2000 · Text Log"
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.string = text.isEmpty ? "Nothing printed yet." : text
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("SKALA2000TextLog")
        if !window.setFrameUsingName("SKALA2000TextLog") { window.center() }
        self.window = window
        self.textView = textView
        textView.scrollToEndOfDocument(nil)
        window.orderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        textView = nil
    }
}
