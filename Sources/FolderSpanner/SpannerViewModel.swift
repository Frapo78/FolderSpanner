import AppKit
import Combine
import Foundation
import FolderSpannerCore

enum NamingPreset: String, CaseIterable, Identifiable {
    case simple = "Numerico (1, 2, 3…)"
    case threeDigits = "Tre cifre (001, 002…)"
    case fourDigits = "Quattro cifre (0001, 0002…)"
    case batch = "Batch (Batch_001…)"
    case parts = "Parti (Parte_001…)"
    case folders = "Cartelle (Cartella_001…)"
    case dated = "Con data (AAAA-MM-GG_001…)"
    case custom = "Personalizzato"
    var id: String { rawValue }
    var pattern: String {
        switch self {
        case .simple: return "{n}"
        case .threeDigits: return "{n:03}"
        case .fourDigits: return "{n:04}"
        case .batch: return "Batch_{n:03}"
        case .parts: return "Parte_{n:03}"
        case .folders: return "Cartella_{n:03}"
        case .dated:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date()) + "_{n:03}"
        case .custom: return ""
        }
    }
}

@MainActor
final class SpannerViewModel: ObservableObject {
    @Published var source: URL? { didSet { invalidate() } }
    @Published var destination: URL? { didSet { invalidate() } }
    @Published var maxFilesText = "200" { didSet { invalidate() } }
    @Published var maxMBText = "0" { didSet { invalidate() } }
    @Published var pattern = "{n}" { didSet { invalidate() } }
    @Published var startingIndexText = "1" { didSet { invalidate() } }
    @Published var namingPreset: NamingPreset = .simple { didSet { choosePreset() } }
    @Published var order: FolderSpannerCore.SortOrder = .ascending { didSet { invalidate() } }
    @Published var mode: TransferMode = .move { didSet { invalidate() } }
    @Published var includeHidden = false { didSet { invalidate() } }
    @Published var recursive = false { didSet { invalidate() } }
    @Published var disasterRecovery = true { didSet { invalidate() } }

    @Published private(set) var plan: SpanPlan?
    @Published private(set) var isPlanning = false
    @Published private(set) var isRunning = false
    @Published private(set) var isRecovering = false
    @Published private(set) var pendingRecovery = SpanRecovery.hasPendingRecovery()
    @Published private(set) var previewProcessed = 0
    @Published private(set) var previewTotal = 0
    @Published private(set) var completed = 0
    @Published var status = "Scegli origine e destinazione, poi genera l'anteprima."
    @Published var errorMessage: String?
    @Published var showConfirmation = false

    private var revision = 0
    private var workTask: Task<Void, Never>?

    var canPreview: Bool { source != nil && destination != nil && !isPlanning && !isRunning && !isRecovering }
    var canExecute: Bool { plan != nil && !isRunning && !isPlanning && !isRecovering && !pendingRecovery }

    private func invalidate() {
        revision += 1
        plan = nil
    }

    private func choosePreset() {
        if namingPreset != .custom {
            pattern = namingPreset.pattern
            startingIndexText = "1"
        }
    }

    func selectSource() { selectFolder { [weak self] url in self?.source = url } }
    func selectDestination() { selectFolder { [weak self] url in self?.destination = url } }

    private func selectFolder(_ save: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seleziona"
        if panel.runModal() == .OK, let url = panel.url { save(url) }
    }

    func prepareThreeDigits() {
        namingPreset = .threeDigits
        pattern = "{n:03}"
        startingIndexText = "1"
        maxFilesText = "200"
        maxMBText = "0"
        order = .ascending
    }

    private func options() throws -> SpanOptions {
        guard let source, let destination else { throw SpannerError("Seleziona entrambe le cartelle.") }
        guard let maximumFiles = Int(maxFilesText), maximumFiles >= 0,
              let start = Int(startingIndexText), start >= 0,
              let mb = Int64(maxMBText), mb >= 0 else {
            throw SpannerError("Numero file, MB e indice iniziale devono essere numeri interi non negativi.")
        }
        let limit: Int64?
        if mb == 0 {
            limit = nil
        } else {
            let (bytes, overflow) = mb.multipliedReportingOverflow(by: 1_048_576)
            guard !overflow else { throw SpannerError("Dimensione massima troppo grande.") }
            limit = bytes
        }
        return SpanOptions(source: source, destinationRoot: destination,
                           maximumFiles: maximumFiles, maximumBytes: limit,
                           folderPattern: pattern, startingIndex: start,
                           sortOrder: order, includeHidden: includeHidden, recursive: recursive)
    }

    func preview() {
        guard !isPlanning && !isRunning else { return }
        do {
            let config = try options()
            plan = nil
            isPlanning = true
            previewProcessed = 0
            previewTotal = 0
            status = "Analisi in corso: nessun file viene modificato…"
            let startRevision = revision
            workTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let result = try SpanPlanner.plan(config, shouldCancel: {
                        Task<Void, Never>.isCancelled
                    }, progress: { done, total in
                        Task { @MainActor [weak self] in
                            self?.updatePreviewProgress(done: done, total: total, revision: startRevision)
                        }
                    })
                    try Task.checkCancellation()
                    await self?.finishPreview(result, revision: startRevision)
                } catch {
                    await self?.failPreview(error, revision: startRevision)
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func updatePreviewProgress(done: Int, total: Int, revision startRevision: Int) {
        guard revision == startRevision, isPlanning else { return }
        previewProcessed = done
        previewTotal = total
    }

    private func finishPreview(_ result: SpanPlan, revision startRevision: Int) {
        isPlanning = false
        workTask = nil
        guard revision == startRevision else { return }
        previewProcessed = result.files.count
        previewTotal = result.files.count
        plan = result
        status = "Simulazione pronta: \(result.files.count) file in \(result.folders.count) cartelle."
    }

    private func failPreview(_ error: Error, revision startRevision: Int) {
        isPlanning = false
        workTask = nil
        guard revision == startRevision else { return }
        if error is CancellationError {
            status = "Anteprima annullata. Nessun file è stato modificato."
        } else {
            errorMessage = error.localizedDescription
        }
    }

    func executeConfirmed() {
        guard let plan, canExecute else { return }
        let selectedMode = mode
        let useRecovery = disasterRecovery && selectedMode == .move
        isRunning = true
        completed = 0
        status = useRecovery ? "Preparo il registro di recupero…" : "Operazione in corso…"

        workTask = Task.detached(priority: .userInitiated) { [weak self] in
            var recoveryPrepared = false
            do {
                // Without disaster recovery no manifest is allocated or updated.
                if useRecovery {
                    try SpanRecovery.prepare(plan)
                    recoveryPrepared = true
                }
                for file in plan.files {
                    try Task.checkCancellation()
                    try SpanExecutor.transfer(file, mode: selectedMode)
                    await self?.didTransferFile()
                }
                if recoveryPrepared { try SpanRecovery.discardCompletedManifest() }
                await self?.finishTransfer(mode: selectedMode)
            } catch {
                if recoveryPrepared {
                    await self?.markRestoring()
                    do {
                        let report = try SpanRecovery.restore()
                        await self?.failTransfer(error, recovery: report)
                    } catch {
                        await self?.failTransfer(error, recovery: nil)
                    }
                } else {
                    await self?.failTransfer(error, recovery: nil)
                }
            }
        }
    }

    private func didTransferFile() { completed += 1 }

    private func markRestoring() {
        isRecovering = true
        status = "Interruzione: ripristino dei file originali in corso…"
    }

    private func finishTransfer(mode selectedMode: TransferMode) {
        isRunning = false
        isRecovering = false
        workTask = nil
        pendingRecovery = SpanRecovery.hasPendingRecovery()
        status = "Completato: \(completed) file \(selectedMode == .move ? "spostati" : "copiati")."
        plan = nil
    }

    private func failTransfer(_ error: Error, recovery report: SpanRecovery.RecoveryReport?) {
        isRunning = false
        isRecovering = false
        workTask = nil
        pendingRecovery = SpanRecovery.hasPendingRecovery()
        plan = nil
        if let report, report.complete {
            status = "Interrotto. Ripristinati \(report.restored) file; stato precedente recuperato."
        } else if pendingRecovery {
            status = "Attenzione: ripristino incompleto. Registro conservato."
            let details = report?.issues.prefix(5).joined(separator: "\n") ?? error.localizedDescription
            errorMessage = "Alcuni file richiedono verifica manuale:\n\(details)"
        } else {
            status = "Interrotto dopo \(completed) file. Nessun rollback disponibile."
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    func restorePendingRecovery() {
        guard pendingRecovery && !isRunning && !isPlanning && !isRecovering else { return }
        isRecovering = true
        status = "Ripristino del registro precedente…"
        workTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let report = try SpanRecovery.restore()
                await self?.finishPendingRecovery(report: report)
            } catch {
                await self?.finishPendingRecovery(error: error)
            }
        }
    }

    private func finishPendingRecovery(report: SpanRecovery.RecoveryReport) {
        pendingRecovery = SpanRecovery.hasPendingRecovery()
        isRecovering = false
        workTask = nil
        status = report.complete ? "Ripristino completato: \(report.restored) file." : "Ripristino incompleto: controlla il registro."
        if !report.complete { errorMessage = report.issues.prefix(6).joined(separator: "\n") }
    }

    private func finishPendingRecovery(error: Error) {
        pendingRecovery = SpanRecovery.hasPendingRecovery()
        isRecovering = false
        workTask = nil
        errorMessage = error.localizedDescription
    }

    func cancel() {
        // Cancellation is cooperative; recovery itself is never cancellable.
        if isPlanning || (isRunning && !isRecovering) { workTask?.cancel() }
    }
}
