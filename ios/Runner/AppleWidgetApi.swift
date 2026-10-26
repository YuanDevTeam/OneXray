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
}
