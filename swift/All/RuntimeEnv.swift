import Foundation

/// Preserve Core-owned environment entries while installing the platform FD.
/// Resource paths for the System Extension are applied by its caller afterwards.
func xrayRuntimeEnvWithTunFd(_ object: Any?, fd: Int32) throws -> [String: Any] {
    var env: [String: Any]
    if let object, !(object is NSNull) {
        guard let existing = object as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        env = existing
    } else {
        env = [:]
    }
    env["xray.tun.fd"] = "\(fd)"
    return env
}
