import Foundation
import UniformTypeIdentifiers
#if os(iOS)
import Flutter
import UIKit
#else
import AppKit
import FlutterMacOS
#endif

private actor BackupFileWorker {
    private let store = BackupFileStore()
    func bind(_ file: URL, accessURL: URL?, create: Bool) throws -> String {
        try store.bind(file, accessURL: accessURL, create: create)
    }
    func requireAccess(_ identifier: String) throws { try store.requireAccess(identifier) }
    func release(_ identifier: String) { store.release(identifier) }
    func hasContents(_ identifier: String) throws -> Bool { try store.hasContents(identifier) }
    func read(_ identifier: String) throws -> Data { try store.read(identifier) }
    func write(_ identifier: String, bytes: Data) throws { try store.write(identifier, bytes: bytes) }
}

@MainActor
final class AppleBackupApi: NSObject, @preconcurrency BackupHostApi, @preconcurrency AppleBackupHostApi {
    private let worker = BackupFileWorker()
    private var selection: ((Result<BackupLocation?, Error>) -> Void)?
    #if os(iOS)
    private var creating = false
    #endif

    func selectBackupFile(create: Bool, completion: @escaping (Result<BackupLocation?, Error>) -> Void) {
        guard selection == nil else {
            completion(.failure(NSError(domain: "OneXray.Backup", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "A document picker is already open."])))
            return
        }
        selection = completion
        #if os(iOS)
        creating = create
        // Creating in a chosen folder preserves an existing backup. Exporting
        // an empty document could replace it before the service writes a backup.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: create ? [.folder] : [.json], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var presenter = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = presenter?.presentedViewController { presenter = presented }
        guard let presenter else {
            finishSelection(.failure(NSError(domain: "OneXray.Backup", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: "No window is available."])))
            return
        }
        presenter.present(picker, animated: true)
        picker.presentationController?.delegate = self
        #else
        let panel: NSSavePanel
        if create {
            panel = NSSavePanel()
            panel.nameFieldStringValue = BackupFileStore.fileName
            panel.canCreateDirectories = true
        } else {
            let open = NSOpenPanel()
            open.canChooseFiles = true
            open.canChooseDirectories = false
            open.allowsMultipleSelection = false
            panel = open
        }
        panel.allowedContentTypes = [.json]
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            finishSelection(.success(nil))
            return
        }
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let file = panel.url else {
                finishSelection(.success(nil))
                return
            }
            bind(file, create: create)
        }
        #endif
    }

    private func bind(_ file: URL, accessURL: URL? = nil, create: Bool) {
        execute({ [worker] in
            let identifier = try await worker.bind(file, accessURL: accessURL, create: create)
            return BackupLocation(identifier: identifier, label: file.path)
        }) { [self] result in finishSelection(result.map { $0 }) }
    }

    private func finishSelection(_ result: Result<BackupLocation?, Error>) {
        let callback = selection
        selection = nil
        callback?(result)
    }

    func requireBackupAccess(identifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
        execute({ [worker] in try await worker.requireAccess(identifier) }, completion: completion)
    }

    func releaseBackupFile(identifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
        execute({ [worker] in await worker.release(identifier) }, completion: completion)
    }

    func hasBackupFileContents(identifier: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        execute({ [worker] in try await worker.hasContents(identifier) }, completion: completion)
    }

    func readBackupFile(identifier: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        execute({ [worker] in FlutterStandardTypedData(bytes: try await worker.read(identifier)) }, completion: completion)
    }

    func writeBackupFile(identifier: String, bytes: FlutterStandardTypedData,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        execute({ [worker] in try await worker.write(identifier, bytes: bytes.data) }, completion: completion)
    }

    private func execute<T>(_ operation: @escaping @MainActor () async throws -> T,
                             completion: @escaping (Result<T, Error>) -> Void) {
        Task {
            do { completion(.success(try await operation())) }
            catch { completion(.failure(error)) }
        }
    }
}

#if os(iOS)
extension AppleBackupApi: UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finishSelection(.success(nil))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishSelection(.success(nil))
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            finishSelection(.success(nil))
            return
        }
        if creating {
            bind(url.appendingPathComponent(BackupFileStore.fileName), accessURL: url, create: true)
        } else {
            bind(url, create: false)
        }
    }
}
#endif
