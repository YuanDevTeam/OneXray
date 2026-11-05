import Foundation
import LibXray

enum LibXrayInvoker {
    enum Failure: Error {
        case cgoFailed
    }

    private static let lock = NSLock()

    static func invoke(_ requestJson: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try perform(requestJson)
        }.value
    }

    private static func perform(_ requestJson: String) throws -> String {
        // App invocations share process-global Xray state, including the simulator core.
        lock.lock()
        defer { lock.unlock() }
        let response = requestJson.withCString { pointer in
            CGoInvoke(UnsafeMutablePointer(mutating: pointer))
        }
        guard let response else { throw Failure.cgoFailed }
        defer { CGoFree(response) }
        return String(cString: response)
    }
}
