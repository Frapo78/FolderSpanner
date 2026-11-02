import AppKit
import Foundation
import FolderSpannerCore

@MainActor
final class SpannerViewModel: ObservableObject {
    @Published var source: URL? { didSet { invalidate() } }
    @Published var destination: URL? { didSet { invalidate() } }
    @Published var maxFilesText = "200" { didSet { invalidate() } }
    @Published var maxMBText = "0" { didSet { invalidate() } }
    @Published var pattern = "{n}" { didSet { invalidate() } }
    @Published var startingIndexText = "1" { didSet { invalidate() } }
    @Published var order: SortOrder = .ascending { didSet { invalidate() } }
    @Published var mode: TransferMode = .move { didSet { invalidate() } }
    @Published var includeHidden = false { didSet { invalidate() } }
    @Published var recursive = false { didSet { invalidate() } }

    @Published private(set) var plan: SpanPlan?
    @Published private(set) var isPlanning = false
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published var status = "Scegli origine e destinazione, poi genera l'anteprima."
    @Published var errorMessage: String?
    @Published var showConfirmation = false

    private var revision = 0
    private var workTask: Task<Void, Never>?

    var canPreview: Bool { source != nil && destination != nil && !isPlanning && !isRunning }
    var canExecute: Bool { plan != nil && !isRunning && !isPlanning }

    private func invalidate() {
        revision += 1
        plan = nil
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

    func prepareExample() {
        // Does not touch the filesystem: an illustrative set of defaults only.
        maxFilesText = "200"
        maxMBText = "0"
        pattern = "{n}"
        startingIndexText = "2"
        order = .ascending
        mode = .move
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
            status = "Analisi in corso: nessun file viene modificato…"
            let startRevision = revision
            workTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let result = try SpanPlanner.plan(config)
                    await MainActor.run {
                        guard let self else { return }
                        self.isPlanning = false
                        guard self.revision == startRevision else { return }
                        self.plan = result
                        self.status = "Simulazione pronta: \(result.files.count) file in \(result.folders.count) cartelle."
                    }
                } catch {
                    await MainActor.run {
                        guard let self else { return }
                        self.isPlanning = false
                        if self.revision == startRevision { self.errorMessage = error.localizedDescription }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func executeConfirmed() {
        guard let plan, !isRunning, !isPlanning else { return }
        let selectedMode = mode
        isRunning = true
        completed = 0
        status = "Operazione in corso…"
        workTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                for file in plan.files {
                    try Task.checkCancellation()
                    try SpanExecutor.transfer(file, mode: selectedMode)
                    await MainActor.run { self?.completed += 1 }
                }
                await MainActor.run {
                    guard let self else { return }
                    self.isRunning = false
                    self.status = "Completato: \(self.completed) file \(selectedMode == .move ? "spostati" : "copiati")."
                    self.plan = nil
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.isRunning = false
                    self.status = "Interrotto dopo \(self.completed) file. Genera una nuova anteprima prima di ripartire."
                    self.plan = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancel() { workTask?.cancel() }
}
