import CoreAudio
import Testing

@testable import ConsoleRuntime

/// Which device SPEAKERS switches to, on devices made up for it: switching the Mac's real
/// output would be a test that changes where the operator's sound goes.
@MainActor
@Suite struct SpeakerSwitchTests {

    func device(
        _ id: AudioObjectID, _ uid: String, builtIn: Bool, outputs: Int = 1, source: String? = nil
    ) -> SpeakerSwitch.Device {
        SpeakerSwitch.Device(
            id: id, uid: uid, builtIn: builtIn, outputs: outputs,
            source: source.map(SpeakerSwitch.fourCC))
    }

    @Test func theSpeakersAreTheBuiltInSpeakersNeverAJackOrAMicrophone() {
        let headphones = device(90, "E8-EE-CC-91-46-AD:output", builtIn: false)
        let microphone = device(50, "BuiltInMicrophoneDevice", builtIn: true, outputs: 0)
        let jack = device(60, "BuiltInHeadphoneOutputDevice", builtIn: true, source: "hdpn")
        let speakers = device(70, "BuiltInSpeakerDevice", builtIn: true, source: "ispk")
        #expect(SpeakerSwitch.speaker(among: [headphones, microphone, jack, speakers]) == speakers)
        #expect(SpeakerSwitch.speaker(among: [headphones, microphone, jack]) == nil)
        // Speakers that report no source are known by the name Apple Silicon gives them.
        let unsourced = device(71, "BuiltInSpeakerDevice", builtIn: true)
        #expect(SpeakerSwitch.speaker(among: [headphones, unsourced]) == unsourced)
    }
}
