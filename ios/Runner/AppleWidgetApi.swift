import Foundation

@MainActor
final class AppleWidgetApi: NSObject, @preconcurrency AppleWidgetHostApi {
    private let flutterApi: AppFlutterApi

    init(flutterApi: AppFlutterApi) {
        self.flutterApi = flutterApi
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(actionAvailable),
            name: AppleWidgetActionInbox.actionAvailable, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func actionAvailable() {
        // This is only a wake-up signal. Dart also pulls before startup, so an
        // intent received before the engine/receiver exists is still delivered.
        flutterApi.appleWidgetActionAvailable()
    }

    func takeAction(completion: @escaping (Result<String?, Error>) -> Void) {
        completion(.success(AppleWidgetActionInbox.shared.takeAction()))
    }

    func setLanguage(languageCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try AppleWidgetPublisher.setLanguage(languageCode)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    func beginPreparation(completion: @escaping (Result<String, Error>) -> Void) {
        do {
            completion(.success(try VPNManager.shared.beginDartPreparation()))
        } catch is CancellationError {
            completion(.failure(PigeonError(code: "apple-preparation-cancelled", message: nil, details: nil)))
        } catch {
            completion(.failure(error))
        }
    }

    func finishPreparation(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        VPNManager.shared.finishDartPreparation(token: token)
        completion(.success(()))
    }

    func startPreparedVpn(token: String, requestJson: String, completion: @escaping (Result<NativeVpnCommandResult, Error>) -> Void) {
        Task { @MainActor in
            do {
                completion(.success(try await VPNManager.shared.startPreparedVpn(token: token, requestJson: requestJson)))
            } catch is CancellationError {
                completion(.failure(PigeonError(code: "apple-preparation-cancelled", message: nil, details: nil)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func connectedAtMilliseconds(completion: @escaping (Result<Int64?, Error>) -> Void) {
        completion(.success(VPNManager.shared.connectedAtMilliseconds()))
    }

    func setStartBlocked(blocked: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try VPNManager.shared.setStartBlocked(blocked)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
}
