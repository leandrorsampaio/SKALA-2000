#if !APP_STORE

import ConsoleKit
import Foundation
import TelemetryKit

/// SLEEP MODE and TURN OFF MONITOR, carried out with `pmset`.
///
/// `pmset` returning is not the Mac asleep, so a clean exit reports nothing: the lens
/// lights when the workspace says the machine or the display actually went. Only a failure
/// is reported, straight away, as no answer.
///
/// Direct-download only. The sandbox does not let the App Store build ask for sleep, so
/// there these buttons stay unassigned and show no answer.
public enum SystemCommands {

    public static let pmset = URL(fileURLWithPath: "/usr/bin/pmset")

    public static func sleepMode(runner: CommandRunning = ProcessRunner()) -> CommandAction {
        action(["sleepnow"], observes: .systemAsleep, runner: runner)
    }

    public static func monitorOff(runner: CommandRunning = ProcessRunner()) -> CommandAction {
        action(["displaysleepnow"], observes: .displayAsleep, runner: runner)
    }

    static func action(
        _ arguments: [String], observes field: Field, runner: CommandRunning
    ) -> CommandAction {
        CommandAction(observes: field) { _, reply in
            DispatchQueue.global(qos: .userInitiated).async {
                let output = runner.run(pmset, arguments: arguments, timeout: 5)
                guard output?.status != 0 else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { reply(false) }
                }
            }
        }
    }
}

#endif
