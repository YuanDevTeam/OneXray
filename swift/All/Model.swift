import Foundation
import LibXray

enum JsonTool {
    static let decoder = JSONDecoder()
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }()

    private static let writingOptions: JSONSerialization.WritingOptions = [
        .prettyPrinted,
        .withoutEscapingSlashes,
    ]

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try decode(type, from: Data(text.utf8))
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func encodeText<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decodeObject(from data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    static func encodeObject(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: writingOptions)
    }
}

enum OnDemandRuleMode: String, Codable {
    case connect
    case disconnect
    case ignore
}

enum OnDemandRuleInterfaceType: String, Codable {
    case any
    case cellular
    case wifi
    case ethernet
}

struct OnDemandRule: Codable {
    var mode: OnDemandRuleMode?
    var interfaceType: OnDemandRuleInterfaceType?
    var ssid: [String]?
}

struct TunJson: Codable {
    var tunIPv4: String?
    var tunIPv6: String?
    var tunDnsIPv4: String?
    var tunDnsIPv6: String?
    var enableDot: Bool?
    var dnsServerName: String?
    var enableIPv6: Bool?
    var autoOutboundsInterface: String?
    var includeAllNetworks: Bool?
    var excludeLocalNetworks: Bool?
    var excludeCellularServices: Bool?
    var excludeAPNs: Bool?
    var excludeDeviceCommunication: Bool?
    var excludedRoutes: [String]?
    var hideVpnIcon: Bool?
    var onDemandEnabled: Bool?
    var onDemandRules: [OnDemandRule]?
    var perAppVPNMode: String?
    var allowAppList: [String]?
    var disallowAppList: [String]?
}

struct StartVpnRequest: Codable {
    var tun: TunJson?
    var socksPort: String?
    var metricsPort: String?
    var coreInvokeText: String?
    var snapshotToken: String?
    var metadataJson: String?

    private static func fromUrl(_ url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        let request = try JsonTool.decode(self, from: data)
        return request
    }

    static var startModel: StartVpnRequest? {
        YGLog("tunnel appGroupId=\(appGroupId())")
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId()) {
            YGLog("tunnel groupURL=\(groupURL)")
            let requestUrl = groupURL.appending(path: StartModelFile)
            do {
                let request = try fromUrl(requestUrl)
                return request
            } catch {}
        }
        return nil
    }
}


enum LibXrayMethod: String, Codable {
    case getFreePorts
    case convertShareLinksToXrayJson
    case convertXrayJsonToShareLinks
    case countGeoData
    case pingBatch
    case testXray
    case runXray
    case stopXray
    case xrayVersion
    case getXrayState
}

struct RunXrayRequest: Codable, Hashable {
    var xrayJson: String?
}

struct XrayEnv: Codable, Hashable {
    var assetLocation: String?
    var certLocation: String?
    var tunFd: String?

    enum CodingKeys: String, CodingKey {
        case assetLocation = "xray.location.asset"
        case certLocation = "xray.location.cert"
        case tunFd = "xray.tun.fd"
    }

    static func fromObject(_ object: Any?) throws -> Self {
        guard let object, !(object is NSNull) else {
            return Self()
        }
        return try JsonTool.decode(Self.self, from: JsonTool.encodeObject(object))
    }

    func toObject() throws -> [String: Any] {
        try JsonTool.decodeObject(from: JsonTool.encode(self))
    }
}

struct LibXrayInvokeRequest: Codable, Hashable {
    var apiVersion: Int?
    var method: LibXrayMethod?
    var payload: RunXrayRequest?

    init(
        apiVersion: Int? = 3,
        method: LibXrayMethod? = nil,
        payload: RunXrayRequest? = nil
    ) {
        self.apiVersion = apiVersion
        self.method = method
        self.payload = payload
    }

    static func fromText(_ text: String) throws -> Self {
        try JsonTool.decode(Self.self, from: text)
    }

    func toText() throws -> String {
        try JsonTool.encodeText(self)
    }
}

struct LibXrayInvokeResponse: Codable, Hashable {
    var success: Bool
    var error: String

    var isSuccess: Bool {
        success
    }

    static func fromResponse(_ res: UnsafeMutablePointer<CChar>?) -> Self {
        if let res = res {
            let text = String(cString: res)
            CGoFree(res)
            return fromText(text)
        }
        return invalidResponse
    }

    static func fromText(_ text: String?) -> Self {
        if let text, let data = text.data(using: .utf8) {
            do {
                return try JsonTool.decode(self, from: data)
            } catch {}
        }
        return invalidResponse
    }

    private static let invalidResponse = LibXrayInvokeResponse(
        success: false,
        error: "invalid response"
    )
}

enum RuntimeStateError: String, Error {
    case unsupported = "runtimeStateUnsupported"
    case unavailable = "runtimeStateUnavailable"
    case invalid = "runtimeStateInvalid"
    case timeout = "runtimeStateTimeout"
}
