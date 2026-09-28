import Darwin
import Foundation

/// Receives Claude Code hook events on a Unix domain socket in the app's data folder.
///
/// Each hook pipes its JSON to `curl --unix-socket <path> … http://localhost/v1/events/claude`.
/// A socket rather than a port: no browser can reach it, it cannot collide with Mac
/// Command Center's hooks on 127.0.0.1:8787, and only this user can connect.
///
/// The rules, from the handover's security section:
/// - the socket file is mode 0600, and the peer's uid must be ours;
/// - a request must carry `X-SKALA-Client: 1` and must not carry `Origin`;
/// - a body over 8 MB is refused, and a request that takes longer than 5 s is dropped;
/// - anything malformed costs one closed connection and nothing else.
///
/// Bodies are handed over on a background queue: a PostToolUse body can be megabytes, and
/// parsing it is no work for the main thread.
public final class HookServer: @unchecked Sendable {

    public static let header = "X-SKALA-Client"
    public static let path = "/v1/events/claude"
    /// Where Claude Code's status line command posts its JSON, and reads back its line.
    public static let statuslinePath = "/v1/statusline"
    public static let maximumBody = 8 * 1024 * 1024

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case pathTooLong
        case socket(Int32)
        case anotherServerIsListening
        /// Something that is not a socket, and not ours to delete, has the socket's name.
        case pathTaken

        /// As Settings shows it.
        public var description: String {
            switch self {
            case .pathTooLong: "the socket's path is too long"
            case .socket(let error): String(cString: strerror(error))
            case .anotherServerIsListening: "another copy of SKALA-2000 is listening"
            case .pathTaken: "hooks.sock is taken by a file that is not a socket"
            }
        }
    }

    public let socketURL: URL
    private let deliver: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "skala2000.hooks", qos: .utility)
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    /// Connections served at once. Each holds a worker thread for up to 5 s, and a flood
    /// of hook events must not take every thread the app shares.
    private let slots = DispatchSemaphore(value: 16)
    /// Told when a request is refused, with the reason, for the log.
    public var refused: @Sendable (String) -> Void = { _ in }
    /// Takes a status line's JSON and gives the line to show. Runs on the server's queue.
    public var statusline: @Sendable (Data) -> String = { _ in "" }

    public init(socketURL: URL, deliver: @escaping @Sendable (Data) -> Void) {
        self.socketURL = socketURL
        self.deliver = deliver
    }

    deinit { stop() }

    // MARK: - Lifecycle

    public func start() throws {
        let path = socketURL.path
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw Failure.pathTooLong
        }
        // A socket file left by an instance that died is removed; one that answers belongs
        // to an instance that is running, and is left alone. Looked at without following a
        // link, so a dangling one is seen; anything but a socket or a link is not ours.
        var status = stat()
        if lstat(path, &status) == 0 {
            let type = status.st_mode & S_IFMT
            guard type == S_IFSOCK || type == S_IFLNK else { throw Failure.pathTaken }
            if type == S_IFSOCK, Self.answers(path) { throw Failure.anotherServerIsListening }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        var address = Self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let error = errno
            close(fd)
            throw Failure.socket(error)
        }
        // 0600 straight after bind. Not by narrowing the umask around it: that is the whole
        // process's, and a folder another thread made meanwhile came out 0600, unusable.
        // Until the chmod the socket is as the umask leaves it, 0755 by default, and
        // connecting takes write permission; it sits in ~/Library, which only its owner can
        // enter; and every connection's peer is checked to be this user.
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else {
            let error = errno
            close(fd)
            throw Failure.socket(error)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listener = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        if listener >= 0 {
            unlink(socketURL.path)
            listener = -1
        }
    }

    public var isRunning: Bool { source != nil }

    // MARK: - Connections

    private func accept() {
        while true {
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                refused("a connection from uid \(uid)")
                close(client)
                continue
            }
            // Each connection is short: read the one request, answer, close.
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(
                client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(
                client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            guard slots.wait(timeout: .now()) == .success else {
                respond(client, 503, "too many connections at once")
                close(client)
                continue
            }
            let slots = self.slots
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.serve(client)
                close(client)
                slots.signal()
            }
        }
    }

    private func serve(_ client: Int32) {
        let deadline = Date().addingTimeInterval(5)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        var request: Request?

        while Date() < deadline {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { break }
            buffer.append(chunk, count: count)
            if request == nil {
                switch Request.parse(buffer) {
                case .incomplete:
                    if buffer.count > 64 * 1024 { return respond(client, 431, "headers too large") }
                    continue
                case .invalid(let reason):
                    return respond(client, 400, reason)
                case .head(let head):
                    if let problem = Self.check(head) {
                        return respond(client, problem.status, problem.reason)
                    }
                    request = head
                    // curl asks before sending a body over 1 MiB and, unanswered, waits a
                    // second of the hook's two.
                    if head.headers["expect"]?.lowercased() == "100-continue",
                        buffer.count - head.bodyStart < head.contentLength
                    {
                        let go = "HTTP/1.1 100 Continue\r\n\r\n"
                        _ = go.withCString { write(client, $0, strlen($0)) }
                    }
                }
            }
            if let request, buffer.count - request.bodyStart >= request.contentLength { break }
        }
        guard let request, buffer.count - request.bodyStart >= request.contentLength else {
            return respond(client, 408, "incomplete request")
        }
        let body = buffer.subdata(in: request.bodyStart..<request.bodyStart + request.contentLength)
        if request.target == Self.statuslinePath {
            respond(client, 200, nil, body: Data(statusline(body).utf8))
            return
        }
        respond(client, 204, nil)
        deliver(body)
    }

    static func check(_ head: Request) -> (status: Int, reason: String)? {
        guard head.method == "POST" else { return (405, "method \(head.method)") }
        guard head.target == path || head.target == statuslinePath else {
            return (404, "path \(head.target)")
        }
        // Nothing a browser sends is welcome.
        guard head.headers["origin"] == nil else { return (403, "a request with Origin") }
        guard head.headers[header.lowercased()] == "1" else { return (403, "no \(header) header") }
        guard head.contentLength >= 0 else { return (411, "no Content-Length") }
        guard head.contentLength <= maximumBody else {
            return (413, "a body of \(head.contentLength) bytes")
        }
        return nil
    }

    private func respond(_ client: Int32, _ status: Int, _ refusal: String?, body: Data = Data()) {
        if let refusal { refused(refusal) }
        let reason =
            [
                200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
                404: "Not Found",
                405: "Method Not Allowed", 408: "Request Timeout", 411: "Length Required",
                413: "Payload Too Large", 431: "Request Header Fields Too Large",
                503: "Service Unavailable",
            ][status] ?? "Error"
        var response = Data(
            "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                .utf8)
        response.append(body)
        _ = response.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }

    // MARK: - HTTP, as little as curl needs

    struct Request {
        var method: String
        var target: String
        var headers: [String: String]
        var contentLength: Int
        var bodyStart: Int

        enum Parse {
            case incomplete
            case invalid(String)
            case head(Request)
        }

        static func parse(_ data: Data) -> Parse {
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
            guard let text = String(data: data.subdata(in: 0..<end.lowerBound), encoding: .utf8)
            else {
                return .invalid("headers are not UTF-8")
            }
            var lines = text.components(separatedBy: "\r\n")
            let first = lines.removeFirst().split(separator: " ")
            guard first.count == 3, first[2].hasPrefix("HTTP/1.") else {
                return .invalid("request line")
            }
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { return .invalid("header line") }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                headers[name] = line[line.index(after: colon)...].trimmingCharacters(
                    in: .whitespaces)
            }
            if headers["transfer-encoding"] != nil {
                return .invalid("chunked bodies are not accepted")
            }
            let length = headers["content-length"].flatMap { Int($0) } ?? -1
            return .head(
                Request(
                    method: String(first[0]), target: String(first[1]), headers: headers,
                    contentLength: length, bodyStart: end.upperBound))
        }
    }

    // MARK: - Helpers

    static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    /// Whether something is listening on the socket at `path`.
    static func answers(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = address(path)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }
}
