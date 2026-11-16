import Darwin
import Foundation

/// Private parent/child IPC. This is separate from the public libXray API.
struct ProxyHelperCommand: Codable {
    let id: UInt64
    let method: String
    var invokeText: String?
    var proxyPort: Int?
}

struct ProxyHelperReply: Codable {
    let id: UInt64
    let success: Bool
    let running: Bool
    var error: String?
}

enum ProxyHelperFailure: LocalizedError {
    case unavailable
    case invalidRequest
    case invalidReply
    case timedOut
    case closed
    case core(String)
    case system(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The local proxy helper is unavailable."
        case .invalidRequest: return "Invalid local proxy start request."
        case .invalidReply: return "Invalid response from the local proxy helper."
        case .timedOut: return "The local proxy helper did not respond in time."
        case .closed: return "The local proxy helper stopped unexpectedly."
        case let .core(message): return message
        case let .system(code): return "Local proxy communication failed (\(code))."
        }
    }
}

enum ProxyHelperWire {
    // The Invoke envelope itself is limited to 16 MiB. JSON string escaping in
    // this private envelope may expand it; this is not a new libXray limit.
    static let maximumFrameBytes = 32 * 1024 * 1024

    static func prepareSocket(_ fd: Int32) throws {
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
            throw ProxyHelperFailure.system(errno)
        }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw ProxyHelperFailure.system(errno)
        }
        var yes: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0 else {
            throw ProxyHelperFailure.system(errno)
        }
    }

    static func write<T: Encodable>(_ value: T, to fd: Int32, timeout: TimeInterval = 10) throws {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maximumFrameBytes else { throw ProxyHelperFailure.invalidRequest }
        var length = UInt32(body.count).bigEndian
        var packet = withUnsafeBytes(of: &length) { Data($0) }
        packet.append(body)
        let deadline = Date().addingTimeInterval(timeout)
        try packet.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                try wait(fd, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if count == -1 && (errno == EINTR || errno == EAGAIN) { continue }
                else if count == 0 || errno == EPIPE || errno == ECONNRESET { throw ProxyHelperFailure.closed }
                else { throw ProxyHelperFailure.system(errno) }
            }
        }
    }

    static func read<T: Decodable>(_ type: T.Type, from fd: Int32, timeout: TimeInterval? = 10) throws -> T {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        let header = try readBytes(4, from: fd, deadline: deadline)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maximumFrameBytes else { throw ProxyHelperFailure.invalidReply }
        return try JSONDecoder().decode(type, from: readBytes(Int(length), from: fd, deadline: deadline))
    }

    private static func readBytes(_ length: Int, from fd: Int32, deadline: Date?) throws -> Data {
        var data = Data(count: length)
        try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < length {
                try wait(fd, events: Int16(POLLIN), deadline: deadline)
                let count = Darwin.read(fd, base.advanced(by: offset), length - offset)
                if count > 0 { offset += count }
                else if count == -1 && (errno == EINTR || errno == EAGAIN) { continue }
                else if count == 0 || errno == ECONNRESET { throw ProxyHelperFailure.closed }
                else { throw ProxyHelperFailure.system(errno) }
            }
        }
        return data
    }

    private static func wait(_ fd: Int32, events: Int16, deadline: Date?) throws {
        while true {
            let milliseconds: Int32
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw ProxyHelperFailure.timedOut }
                milliseconds = Int32(min(remaining * 1000 + 1, Double(Int32.max)))
            } else {
                milliseconds = -1
            }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(&descriptor, 1, milliseconds)
            if result == -1 && errno == EINTR { continue }
            if result == -1 { throw ProxyHelperFailure.system(errno) }
            if result == 0 { throw ProxyHelperFailure.timedOut }
            if descriptor.revents & events != 0 { return }
            throw ProxyHelperFailure.closed
        }
    }
}

enum ProxyHelperEndpoint {
    static func isListening(port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { return false }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&descriptor, 1, 200) > 0 else { return false }
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout.size(ofValue: error))
        return getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 && error == 0
    }
}
