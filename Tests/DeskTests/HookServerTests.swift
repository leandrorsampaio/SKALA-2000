import Darwin
import Foundation
import Testing

@testable import HookServer

/// The hook receiver's rules, exercised with the real `curl` the hooks use.
@Suite(.serialized)
struct HookServerTests {

    init() {
        // The server refuses and closes while curl, or a test, may still be writing.
        signal(SIGPIPE, SIG_IGN)
    }

    final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Data] = []
        private var refusals: [String] = []
        func add(_ data: Data) { lock.withLock { items.append(data) } }
        func refuse(_ reason: String) { lock.withLock { refusals.append(reason) } }
        var bodies: [Data] { lock.withLock { items } }
        var refused: [String] { lock.withLock { refusals } }
    }

    static func socketURL() -> URL {
        // Unix socket paths are short: /tmp, not the per-user temporary folder.
        URL(
            fileURLWithPath: "/tmp/skala-test-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
        )
    }

    /// Runs curl against the socket and returns its HTTP status.
    @discardableResult
    static func curl(
        _ socket: URL, _ arguments: [String], body: Data = Data("{}".utf8)
    ) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments =
            [
                "-sS", "-m", "5", "-o", "/dev/null", "-w", "%{http_code}", "--unix-socket",
                socket.path,
            ]
            + arguments
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(body)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let code = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Int(code) ?? -1
    }

    static let valid = [
        "-H", "X-SKALA-Client: 1", "-H", "Content-Type: application/json", "--data-binary", "@-",
        "http://localhost/v1/events/claude",
    ]

    func running() throws -> (HookServer, Inbox) {
        let inbox = Inbox()
        let server = HookServer(socketURL: Self.socketURL()) { inbox.add($0) }
        server.refused = { inbox.refuse($0) }
        try server.start()
        return (server, inbox)
    }

    func settle() { Thread.sleep(forTimeInterval: 0.2) }

    @Test func aHookEventIsAcceptedAndDelivered() throws {
        let (server, inbox) = try running()
        defer { server.stop() }
        let body = Data(#"{"hook_event_name":"Stop","session_id":"abc"}"#.utf8)
        #expect(try Self.curl(server.socketURL, Self.valid, body: body) == 204)
        settle()
        #expect(inbox.bodies == [body])
    }

    @Test func theSocketIsForThisUserOnly() throws {
        let (server, _) = try running()
        defer { server.stop() }
        let attributes = try FileManager.default.attributesOfItem(atPath: server.socketURL.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func withoutTheHeaderNothingIsDelivered() throws {
        let (server, inbox) = try running()
        defer { server.stop() }
        let arguments = ["--data-binary", "@-", "http://localhost/v1/events/claude"]
        #expect(try Self.curl(server.socketURL, arguments) == 403)
        settle()
        #expect(inbox.bodies.isEmpty)
    }

    /// A browser always sends Origin; nothing that does is welcome.
    @Test func aRequestWithAnOriginIsRefused() throws {
        let (server, inbox) = try running()
        defer { server.stop() }
        #expect(
            try Self.curl(server.socketURL, ["-H", "Origin: https://example.com"] + Self.valid)
                == 403)
        settle()
        #expect(inbox.bodies.isEmpty)
        #expect(inbox.refused.contains { $0.contains("Origin") })
    }

    @Test func aBodyOverEightMegabytesIsRefused() throws {
        let (server, inbox) = try running()
        defer { server.stop() }
        let big = Data(repeating: 0x20, count: HookServer.maximumBody + 1)
        #expect(try Self.curl(server.socketURL, Self.valid, body: big) == 413)
        settle()
        #expect(inbox.bodies.isEmpty)
    }

    @Test func onlyThePostOfEventsIsServed() throws {
        let (server, _) = try running()
        defer { server.stop() }
        #expect(
            try Self.curl(
                server.socketURL,
                ["-H", "X-SKALA-Client: 1", "--data-binary", "@-", "http://localhost/v1/other"])
                == 404)
        #expect(
            try Self.curl(
                server.socketURL, ["-H", "X-SKALA-Client: 1", "http://localhost/v1/events/claude"])
                == 405)
    }

    @Test func aDeadInstancesSocketIsReplacedAndALiveOneIsNot() throws {
        let url = Self.socketURL()
        // What a crash leaves: a socket file nobody listens on.
        let dead = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: url.path.utf8) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(dead, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(dead)
        #expect(bound == 0)
        let first = HookServer(socketURL: url) { _ in }
        try first.start()
        defer { first.stop() }
        let second = HookServer(socketURL: url) { _ in }
        #expect(throws: HookServer.Failure.anotherServerIsListening) { try second.start() }
    }

    /// A dangling link where the socket goes is cleared; a file that is not a socket is
    /// not the receiver's to delete.
    @Test func onlyASocketOrALinkIsClearedFromThePath() throws {
        let url = Self.socketURL()
        try FileManager.default.createSymbolicLink(
            atPath: url.path, withDestinationPath: "/tmp/skala-nowhere-\(getpid())")
        let server = HookServer(socketURL: url) { _ in }
        try server.start()
        server.stop()

        try Data("mine".utf8).write(to: url)
        defer { unlink(url.path) }
        #expect(throws: HookServer.Failure.pathTaken) { try server.start() }
        #expect(try Data(contentsOf: url) == Data("mine".utf8))
    }

    @Test func garbageCostsAConnectionAndNothingElse() throws {
        let (server, inbox) = try running()
        defer { server.stop() }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = HookServer.address(server.socketURL.path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(connected == 0)
        let junk = "this is not http\r\n\r\n"
        _ = junk.withCString { write(fd, $0, strlen($0)) }
        var reply = [UInt8](repeating: 0, count: 64)
        let count = read(fd, &reply, reply.count)
        close(fd)
        #expect(
            String(decoding: reply.prefix(max(0, count)), as: UTF8.self).hasPrefix("HTTP/1.1 400"))
        #expect(try Self.curl(server.socketURL, Self.valid) == 204)
        settle()
        #expect(inbox.bodies.count == 1)
    }
}

struct HookInstallerTests {

    static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "Stop", "SubagentStart", "SubagentStop",
        "Notification", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "PreCompact",
        "PostCompact",
    ]

    func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "skala-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("settings.json")
    }

    func read(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// Settings kept with someone's dotfiles, linked from ~/.claude: the link stays a link,
    /// the file it points at gets the hooks, and the backup is a copy, not another link.
    @Test func aLinkedSettingsFileStaysLinked() throws {
        let url = try scratch()
        let dotfiles = url.deletingLastPathComponent().appendingPathComponent("dotfiles.json")
        try Data(#"{"model": "opus"}"#.utf8).write(to: dotfiles)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: dotfiles)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: dotfiles.path)

        let installer = HookInstaller(settings: url, events: Self.events)
        try installer.install()
        #expect(installer.status() == .installed)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        #expect(link == dotfiles.path)
        #expect(try read(dotfiles)["hooks"] != nil)
        let mode = try FileManager.default.attributesOfItem(atPath: dotfiles.path)[
            .posixPermissions]
        #expect((mode as? NSNumber)?.intValue == 0o600)
        let backup = try FileManager.default.attributesOfItem(atPath: installer.backup.path)
        #expect(backup[.type] as? FileAttributeType == .typeRegular)
        #expect(try read(installer.backup)["hooks"] == nil)
    }

    /// Mac Command Center's hooks and the owner's own stay exactly where they are.
    @Test func installingLeavesEveryOtherHookAlone() throws {
        let url = try scratch()
        let existing = """
            {"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command",
            "command": "curl -H 'X-MCC-Client: 1' http://127.0.0.1:8787/v1/events/claude", "async": true}]}],
            "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo mine"}]}]}}
            """
        try Data(existing.utf8).write(to: url)
        let installer = HookInstaller(settings: url, events: Self.events)
        #expect(installer.status() == .notInstalled)
        try installer.install()
        #expect(installer.status() == .installed)

        let settings = try read(url)
        #expect(settings["model"] as? String == "opus")
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect((hooks["Stop"] as? [Any])?.count == 2)
        #expect((hooks["PreToolUse"] as? [Any])?.count == 1)
        #expect(FileManager.default.fileExists(atPath: installer.backup.path))

        // Installing again replaces ours rather than adding a second copy.
        try installer.install()
        #expect(((try read(url)["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 2)

        try installer.remove()
        #expect(installer.status() == .notInstalled)
        let after = try #require(try read(url)["hooks"] as? [String: Any])
        #expect(Set(after.keys) == ["Stop", "PreToolUse"])
    }

    @Test func aSettingsFileThatIsNotJSONIsNeverWritten() throws {
        let url = try scratch()
        try Data("{ not json".utf8).write(to: url)
        let installer = HookInstaller(settings: url, events: Self.events)
        #expect(installer.status() == .unreadable)
        #expect(throws: HookInstaller.Failure.unreadable) { try installer.install() }
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == "{ not json")
    }

    @Test func theCheckedInSnippetIsTheOneTheAppInstalls() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/claude-hooks.json")
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let hooks = try #require(json["hooks"] as? [String: [[String: Any]]])
        for (_, groups) in hooks {
            let command = (groups.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
            #expect(command == HookInstaller.command)
        }
        #expect(HookInstaller.command.contains(HookInstaller.marker))
    }
}
