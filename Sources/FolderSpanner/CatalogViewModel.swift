import AppKit
import Combine
import Foundation
import FolderSpannerCore

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var root: URL?
    @Published var recursive = true
    @Published var includeHidden = false
    @Published private(set) var isRunning = false
    @Published private(set) var scannedFiles = 0
    @Published private(set) var generatedURL: URL?
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var showOverwriteConfirmation = false

    private var workTask: Task<Void, Never>?

    func chooseFolder() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("Seleziona")
        if panel.runModal() == .OK, let url = panel.url {
            root = url
            generatedURL = nil
            status = ""
        }
    }

    func prepareGeneration() {
        guard !isRunning, let root else { return }
        let output = root.appendingPathComponent(SpanCatalog.fileName)
        if FileManager.default.fileExists(atPath: output.path) {
            showOverwriteConfirmation = true
        } else {
            generate(overwrite: false)
        }
    }

    func generate(overwrite: Bool) {
        guard !isRunning, let root else { return }
        let options = CatalogOptions(root: root, recursive: recursive,
                                     includeHidden: includeHidden, overwriteExisting: overwrite)
        isRunning = true
        generatedURL = nil
        scannedFiles = 0
        status = L10n.tr("Scansione del catalogo in corso…")
        workTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try SpanCatalog.generate(
                    options,
                    shouldCancel: { Task<Never, Never>.isCancelled },
                    progress: { count in
                        Task { @MainActor [weak self] in self?.scannedFiles = count }
                    }
                )
                await self?.completed(report: result)
            } catch {
                await self?.failed(error)
            }
        }
    }

    func cancel() { workTask?.cancel() }

    func openCatalog() {
        guard let generatedURL else { return }
        NSWorkspace.shared.open(generatedURL)
    }

    private func completed(report: CatalogReport) {
        isRunning = false
        workTask = nil
        scannedFiles = report.fileCount
        generatedURL = report.url
        status = L10n.tr("Catalogo creato: %ld file, %ld cartelle.", report.fileCount, report.folderCount)
    }

    private func failed(_ error: Error) {
        isRunning = false
        workTask = nil
        if error is CancellationError {
            status = L10n.tr("Catalogazione annullata: nessun catalogo parziale salvato.")
        } else {
            status = L10n.tr("Impossibile generare il catalogo.")
            errorMessage = error.localizedDescription
        }
    }
}
