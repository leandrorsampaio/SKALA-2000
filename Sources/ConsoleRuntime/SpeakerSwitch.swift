import CoreAudio
import Foundation

/// SPEAKERS: the Mac's sound to its own speakers, and back to wherever it went before.
///
/// Pressed while the sound goes elsewhere, it notes that device — headphones, a display, a
/// Bluetooth speaker — by its UID, which survives a relaunch, and makes the built-in
/// speakers the default output. Pressed again, it makes the noted device the default once
/// more, if it is still there. The system's default output is only ever switched between
/// devices the Mac already has; nothing is installed and no device is changed.
@MainActor
public final class SpeakerSwitch {

    /// An output device, as much of it as choosing the speakers needs.
    public struct Device: Equatable, Sendable {
        public var id: AudioObjectID
        public var uid: String
        public var builtIn: Bool
        public var outputs: Int
        /// The built-in device's data source: `ispk` for the speakers, `hdpn` for a jack.
        public var source: UInt32?
    }

    /// Told when the default output changes, whoever changed it.
    public var onChange: () -> Void = {}

    private let defaults: UserDefaults
    private static let returnKey = "speakers.returnTo"
    private var listener: AudioObjectPropertyListenerBlock?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr
        {
            listener = block
        }
    }

    /// Stops listening. Call before letting go of it.
    public func stop() {
        guard let listener else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }

    /// Whether the Mac's sound goes to its own speakers.
    public var isOnSpeakers: Bool {
        guard let current = Self.defaultOutput(), let device = Self.device(current) else {
            return false
        }
        return Self.speaker(among: [device]) != nil
    }

    /// Switches, and says whether it could: to the speakers, noting where the sound went;
    /// or back to the noted device. Back is refused when nothing was noted or the device
    /// has gone, and the speakers are kept.
    public func toggle() -> Bool {
        let devices = Self.devices()
        guard let speaker = Self.speaker(among: devices), let current = Self.defaultOutput()
        else { return false }
        if current == speaker.id {
            guard let uid = defaults.string(forKey: Self.returnKey),
                let back = devices.first(where: { $0.uid == uid && $0.id != speaker.id }),
                Self.setDefaultOutput(back.id)
            else { return false }
            defaults.removeObject(forKey: Self.returnKey)
            return true
        }
        if let before = devices.first(where: { $0.id == current }) {
            defaults.set(before.uid, forKey: Self.returnKey)
        }
        return Self.setDefaultOutput(speaker.id)
    }

    /// The built-in speakers among the Mac's devices: a built-in device with outputs whose
    /// source is the internal speaker; failing a source, the built-in output named for
    /// speakers, as Apple Silicon names it. Never a headphone jack.
    public static func speaker(among devices: [Device]) -> Device? {
        let builtIn = devices.filter { $0.builtIn && $0.outputs > 0 }
        return builtIn.first { $0.source == fourCC("ispk") }
            ?? builtIn.first { $0.source == nil && $0.uid.localizedCaseInsensitiveContains("speaker") }
    }

    static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    // MARK: - Core Audio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// A 32-bit property: a device id, a transport type, a data source.
    private static func read(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = address(selector, scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
            ? value : nil
    }

    static func defaultOutput() -> AudioObjectID? {
        read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
            .flatMap { $0 == 0 ? nil : $0 }
    }

    private static func setDefaultOutput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr
    }

    static func devices() -> [Device] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap(device)
    }

    static func device(_ id: AudioObjectID) -> Device? {
        guard let uid = uid(id) else { return nil }
        var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
        var bytes: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes)
        let transport = read(id, kAudioDevicePropertyTransportType)
        return Device(
            id: id, uid: uid, builtIn: transport == kAudioDeviceTransportTypeBuiltIn,
            outputs: Int(bytes) / MemoryLayout<AudioStreamID>.size,
            source: read(id, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput))
    }

    /// A device's UID, which Core Audio hands over retained: taken, so it is let go.
    private static func uid(_ id: AudioObjectID) -> String? {
        var address = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
