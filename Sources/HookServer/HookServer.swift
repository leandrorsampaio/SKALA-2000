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
    public static let maximumBody = 8 * 1024 * 1024

    public enum Failure: Error, Equatable {
        case pathTooLong
        case socket(Int32)
        case anotherServerIsListening
    }

    public let socketURL: URL
    private let deliver: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "skala2000.hooks", qos: .utility)
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    /// Told when a request is refused, with the reason, for the log.
    public var refused: @Sendable (String) -> Void = { _ in }

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
        // to an instance that is running, and is left alone.
        if FileManager.default.fileExists(atPath: path) {
            if Self.answers(path) { throw Failure.anotherServerIsListening }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        var address = Self.address(path)
        // Created 0600 from the start: no moment in which another user could connect.
        let previous = umask(0o177)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previous)
        guard bound == 0 else {
            let error = errno
            close(fd)
            throw Failure.socket(error)
        }
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
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.serve(client)
                close(client)
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
                }
            }
            if let request, buffer.count - request.bodyStart >= request.contentLength { break }
        }
        guard let request, buffer.count - request.bodyStart >= request.contentLength else {
            return respond(client, 408, "incomplete request")
        }
        let body = buffer.subdata(in: request.bodyStart..<request.bodyStart + request.contentLength)
        respond(client, 204, nil)
        deliver(body)
    }

    static func check(_ head: Request) -> (status: Int, reason: String)? {
        guard head.method == "POST" else { return (405, "method \(head.method)") }
        guard head.target == path else { return (404, "path \(head.target)") }
        // Nothing a browser sends is welcome.
        guard head.headers["origin"] == nil else { return (403, "a request with Origin") }
        guard head.headers[header.lowercased()] == "1" else { return (403, "no \(header) header") }
        guard head.contentLength >= 0 else { return (411, "no Content-Length") }
        guard head.contentLength <= maximumBody else {
            return (413, "a body of \(head.contentLength) bytes")
        }
        return nil
    }

    private func respond(_ client: Int32, _ status: Int, _ refusal: String?) {
        if let refusal { refused(refusal) }
        let reason =
            [
                204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                405: "Method Not Allowed", 408: "Request Timeout", 411: "Length Required",
                413: "Payload Too Large", 431: "Request Header Fields Too Large",
            ][status] ?? "Error"
        let response =
            "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = response.withCString { write(client, $0, strlen($0)) }
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
