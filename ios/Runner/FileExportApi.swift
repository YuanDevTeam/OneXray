import Flutter
import UIKit

/// Presents a file URL directly; log contents never cross the Flutter channel.
@MainActor
final class FileExportApi: NSObject, @preconcurrency FileExportHostApi,
                           UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private var completion: ((Result<Bool, Error>) -> Void)?

    func saveFile(path: String, name: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard self.completion == nil else {
            completion(.failure(NSError(domain: "OneXray.FileExport", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "A document picker is already open."])))
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var presenter = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = presenter?.presentedViewController { presenter = presented }
        guard let presenter else {
            completion(.failure(NSError(domain: "OneXray.FileExport", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "No window is available."])))
            return
        }
        self.completion = completion
        let picker = UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: path)], asCopy: true)
        picker.delegate = self
        presenter.present(picker, animated: true)
        picker.presentationController?.delegate = self
    }

    private func finish(_ result: Result<Bool, Error>) {
        let callback = completion
        completion = nil
        callback?(result)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(.success(!urls.isEmpty))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(.success(false))
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(.success(false))
    }
}
