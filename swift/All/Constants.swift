import Foundation

public let ProxyHost = "127.0.0.1"
public let TunMtu: NSNumber = 1500

public let StartModelFile = "run/start.json"
public let ProxyStartModelFile = "run/proxy-start.json"

enum ApnsPresetStartGate {
    static let preparedTokenOption = "onexray-apns-prepared-token"
    private static let markerPath = "run/apns-preset-pending"

    static func isPending(in container: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(
                atPath: container.appendingPathComponent(markerPath).path
            )
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return false
        }
    }

    static func permitsSnapshot(
        in container: URL, snapshotToken: String?, preparedToken: String?
    ) throws -> Bool {
        guard try isPending(in: container) else { return true }
        // A prepared App start may try its candidate before the settings commit.
        // Widget and system-initiated starts have no token and wait for the commit.
        guard let preparedToken, !preparedToken.isEmpty else { return false }
        return preparedToken == snapshotToken
    }
}

enum StartRequestKind {
    case tunnel
    case proxy

    init(captureMode: String?) throws {
        switch captureMode {
        case nil, "tun": self = .tunnel
        case "proxy": self = .proxy
        default: throw StartRequestKindError.unsupportedMode
        }
    }

    var relativePath: String {
        switch self {
        case .tunnel: return StartModelFile
        case .proxy: return ProxyStartModelFile
        }
    }

    func requireTunnel() throws {
        guard self == .tunnel else { throw StartRequestKindError.notTunnel }
    }

    func writeSnapshot(_ data: Data, in container: URL) throws {
        let file = container.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

enum StartRequestKindError: LocalizedError {
    case unsupportedMode
    case notTunnel

    var errorDescription: String? {
        switch self {
        case .unsupportedMode: return "Unsupported connection capture mode."
        case .notTunnel: return "A local proxy configuration cannot start a VPN tunnel."
        }
    }
}

public enum Constants {
    #if SYSTEM_EXTENSION
    public static let useSystemExtension = true
    #else
    public static let useSystemExtension = false
    #endif
}

private let teamAppGroupId = "2CKAULFA9J.net.yuandev.onexray"
private let groupAppGroupId = "group.net.yuandev.onexray"
private let seGroupAppGroupId = "group.net.yuandev.onexray.se"

public func appGroupId() -> String {
    #if os(iOS)
        return groupAppGroupId
    #elseif os(macOS)
        if Constants.useSystemExtension {
            return seGroupAppGroupId
        } else {
            return teamAppGroupId
        }
    #endif
}

private let tunId = "net.yuandev.onexray.tun"
private let seTunId = "net.yuandev.onexray.se.tun"

public func packetTunnelId() -> String {
    #if os(iOS)
        return tunId
    #elseif os(macOS)
        if Constants.useSystemExtension {
            return seTunId
        } else {
            return tunId
        }
    #endif
}

private let serverAddress = "OneXray"
private let seServerAddress = "OneXraySE"

public func vpnServerAddress() -> String {
    #if os(iOS)
        return serverAddress
    #elseif os(macOS)
        if Constants.useSystemExtension {
            return seServerAddress
        } else {
            return serverAddress
        }
    #endif
}

public func extensionGroupContainerURL() -> URL? {
    #if os(macOS)
    if Constants.useSystemExtension {
        return URL(fileURLWithPath: "/private/var/root/Library/Group Containers/\(appGroupId())")
    }
    #endif
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId())
}
