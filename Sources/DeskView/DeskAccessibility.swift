import AppKit
import ConsoleKit
import DeskArt

/// VoiceOver's view of the desk: every instrument one element, labelled with its plate
/// and valued in words, grouped by panel A to E. Written in phase 4.
@MainActor
final class DeskAccessibility {
    weak var view: DeskView?
    init(view: DeskView) { self.view = view }
    func update(_ snapshot: ConsoleSnapshot) {}
}
