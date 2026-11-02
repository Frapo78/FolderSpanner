import SwiftUI
import FolderSpannerCore

struct ContentView: View {
    @StateObject private var model = SpannerViewModel()
    @StateObject private var updater = GitHubUpdater()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                locationSection
                rulesSection
                recoverySection
                previewSection
                statusSection
                actionSection
            }
            .padding(22)
            .frame(minWidth: 820)
        }
        .frame(minWidth: 860, minHeight: 680)
        .confirmationDialog(
            "Confermi l'operazione sui file?",
            isPresented: $model.showConfirmation
        ) {
            Button(
                model.mode == .move ? L10n.tr("Conferma spostamento") : L10n.tr("Conferma copia"),
                role: model.mode == .move ? .destructive : nil
            ) { model.executeConfirmed() }
        } message: {
            Text(L10n.tr("%ld file. Prima di procedere conserva un backup indipendente dei dati.", model.plan?.files.count ?? 0))
        }
        .alert(
            "FolderSpanner",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? L10n.tr("Errore sconosciuto"))
        }
        .sheet(item: $updater.availableRelease) { release in
            VStack(alignment: .leading, spacing: 16) {
                Text("Aggiornamento disponibile").font(.title2.bold())
                Text(release.name)
                Text("La nuova versione sarà scaricata da GitHub, verificata con SHA-256 e firma ad hoc e installata dopo la chiusura dell'app. Non è notarizzata da Apple.")
                    .foregroundStyle(.secondary)
                if updater.isWorking {
                    ProgressView("Scaricamento e verifica in corso…")
                    Button("Annulla") { updater.cancel() }
                } else {
                    HStack {
                        Button("Più tardi") { updater.availableRelease = nil }
                        Button("Scarica e sostituisci") { updater.install(release) }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isRunning || model.isPlanning || model.pendingRecovery)
                    }
                }
                Text(updater.status).font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 520)
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 34)).foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                Text("FolderSpanner").font(.title.bold())
                Text("Suddividi grandi collezioni di file in cartelle ordinate")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                updater.checkForUpdates()
            } label: {
                Label("Aggiornamenti", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(updater.isWorking || model.isRunning || model.isPlanning)
        }
    }

    private var locationSection: some View {
        GroupBox("Posizioni") {
            VStack(spacing: 10) {
                folderRow("Origine", url: model.source, select: model.selectSource)
                folderRow("Destinazione", url: model.destination, select: model.selectDestination)
            }.padding(5)
        }
        .disabled(model.isPlanning || model.isRunning || model.isRecovering)
    }

    private var rulesSection: some View {
        GroupBox("Regole di suddivisione") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Preset nome cartelle").frame(width: 180, alignment: .leading)
                    Picker("Preset", selection: $model.namingPreset) {
                        ForEach(NamingPreset.allCases) { preset in
                            Text(L10n.tr(preset.rawValue)).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 350)
                    Spacer()
                    Button("Preset tre cifre") { model.prepareThreeDigits() }
                }
                HStack(spacing: 12) {
                    Text("Modello nome cartella").frame(width: 180, alignment: .leading)
                    TextField("{n:03}, Batch_{n:03}…", text: $model.pattern).frame(width: 220)
                    Spacer()
                    Text("Numero iniziale")
                    TextField("1", text: $model.startingIndexText).frame(width: 100)
                }
                HStack(spacing: 12) {
                    Text("Max file/cartella").frame(width: 180, alignment: .leading)
                    TextField("0 = illimitato", text: $model.maxFilesText).frame(width: 100)
                    Spacer()
                    Text("Max MiB/cartella")
                    TextField("0 = illimitato", text: $model.maxMBText).frame(width: 100)
                }
                HStack(spacing: 12) {
                    Text("Ordinamento").frame(width: 180, alignment: .leading)
                    Picker("Ordinamento", selection: $model.order) {
                        ForEach(FolderSpannerCore.SortOrder.allCases) { order in
                            Text(order.localizedName).tag(order)
                        }
                    }
                    .labelsHidden().frame(width: 210)
                    Spacer()
                    Text("Operazione")
                    Picker("Operazione", selection: $model.mode) {
                        ForEach(TransferMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .labelsHidden().frame(width: 130)
                }
                HStack {
                    Toggle("Includi file nascosti", isOn: $model.includeHidden)
                    Toggle("Includi sottocartelle", isOn: $model.recursive)
                }
            }
            .padding(5)
        }
        .disabled(model.isPlanning || model.isRunning || model.isRecovering)
    }

    private var recoverySection: some View {
        GroupBox("Sicurezza") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Disaster Recovery (attivo per impostazione predefinita)", isOn: $model.disasterRecovery)
                    .disabled(model.mode != .move || model.isRunning || model.isPlanning)
                Text("Se annulli uno spostamento, tenta di ripristinare file e cartelle iniziali. Richiede lo stesso volume e un registro in Application Support. Se disattivato, nessun registro viene creato. Crash, guasti o modifiche esterne possono impedire il recupero.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.pendingRecovery {
                    HStack {
                        Label("Rilevata un'operazione incompleta", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Ripristina file originali") { model.restorePendingRecovery() }
                            .disabled(model.isRecovering || model.isRunning)
                    }
                }
            }
            .padding(5)
        }
    }

    private var previewSection: some View {
        GroupBox("Anteprima · nessuna modifica ai file") {
            VStack(alignment: .leading, spacing: 8) {
                if let plan = model.plan {
                    Text(L10n.tr("%ld file · %@ · %ld cartelle", plan.files.count, ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file), plan.folders.count))
                        .font(.headline)
                    List(plan.folders) { folder in
                        HStack {
                            Image(systemName: "folder")
                            Text(folder.name).fontWeight(.medium)
                            Spacer()
                            Text(L10n.tr("+%ld file", folder.newFileCount))
                            Text(ByteCountFormatter.string(fromByteCount: folder.newBytes, countStyle: .file))
                                .foregroundStyle(.secondary)
                            if folder.existingFileCount > 0 {
                                Text(L10n.tr("(%ld esistenti)", folder.existingFileCount))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 138)
                } else if model.isPlanning {
                    HStack {
                        if model.previewTotal > 0 {
                            ProgressView(value: Double(model.previewProcessed),
                                         total: Double(model.previewTotal))
                            Text("\(model.previewProcessed)/\(model.previewTotal)")
                                .font(.caption.monospacedDigit())
                        } else {
                            ProgressView().controlSize(.small)
                            Text("Scansione file in corso…").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Annulla anteprima") { model.cancel() }
                    }
                    .frame(minHeight: 75)
                } else {
                    Text("Crea un'anteprima per vedere le cartelle da riempire.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 75)
                }
            }.padding(4)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.status).foregroundStyle(.secondary)
            if model.isRunning {
                ProgressView(value: Double(model.completed),
                             total: Double(max(model.plan?.files.count ?? 1, 1)))
                .accessibilityLabel("Avanzamento copia o spostamento")
                HStack {
                    Text(L10n.tr("%ld file completati", model.completed)).font(.caption.monospacedDigit())
                    Spacer()
                    if model.isRecovering {
                        ProgressView("Ripristino in corso…")
                    } else {
                        Button("Annulla operazione") { model.cancel() }
                    }
                }
            } else if model.isRecovering {
                ProgressView("Ripristino in corso…")
            }
            if !updater.status.isEmpty {
                Text(updater.status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var actionSection: some View {
        HStack {
            Text("Controlla sempre l'anteprima prima dello spostamento.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Anteprima") { model.preview() }
                .disabled(!model.canPreview)
            Button(model.mode == .move ? L10n.tr("Sposta file…") : L10n.tr("Copia file…")) {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExecute || model.plan?.files.isEmpty != false)
        }
    }

    private func folderRow(_ label: String, url: URL?, select: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(L10n.tr(label)).frame(width: 110, alignment: .leading)
            Text(url?.path ?? L10n.tr("Nessuna cartella selezionata"))
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button("Scegli…", action: select)
        }
    }
}
