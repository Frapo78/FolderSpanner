import SwiftUI
import FolderSpannerCore

struct ContentView: View {
    @StateObject private var model = SpannerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            locationSection
            rulesSection
            previewSection
            statusSection
            actionSection
        }
        .padding(22)
        .frame(minWidth: 810, minHeight: 620)
        .confirmationDialog(
            "Confermi l'operazione sui file?",
            isPresented: $model.showConfirmation
        ) {
            Button(
                model.mode == .move ? "Conferma spostamento" : "Conferma copia",
                role: model.mode == .move ? .destructive : nil
            ) {
                model.executeConfirmed()
            }
        } message: {
            Text("\(model.plan?.files.count ?? 0) file. Questa operazione modifica il filesystem e non prevede un annullamento automatico.")
        }
        .alert(
            "Errore",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Errore sconosciuto")
        }
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("FolderSpanner").font(.title.bold())
                Text("Suddividi grandi collezioni di file in cartelle ordinate")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Preview").foregroundStyle(.secondary).font(.caption)
        }
    }

    private var locationSection: some View {
        GroupBox("Posizioni") {
            VStack(spacing: 10) {
                folderRow("Origine", url: model.source, select: model.selectSource)
                folderRow("Destinazione", url: model.destination, select: model.selectDestination)
            }.padding(5)
        }
        .disabled(model.isPlanning || model.isRunning)
    }

    private var rulesSection: some View {
        GroupBox("Regole di suddivisione") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Massimo file/cartella").frame(width: 155, alignment: .leading)
                    TextField("0 = nessun limite", text: $model.maxFilesText).frame(width: 120)
                    Spacer()
                    Text("Massimo MB/cartella")
                    TextField("0 = nessun limite", text: $model.maxMBText).frame(width: 120)
                }
                HStack(spacing: 12) {
                    Text("Modello nome cartella").frame(width: 155, alignment: .leading)
                    TextField("{n} oppure Batch_{n:03}", text: $model.pattern).frame(width: 180)
                    Spacer()
                    Text("Numero iniziale")
                    TextField("1", text: $model.startingIndexText).frame(width: 120)
                }
                HStack(spacing: 12) {
                    Text("Ordinamento").frame(width: 155, alignment: .leading)
                    Picker("Ordinamento", selection: $model.order) {
                        ForEach(FolderSpannerCore.SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Spacer()
                    Text("Operazione")
                    Picker("Operazione", selection: $model.mode) {
                        ForEach(TransferMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                HStack {
                    Toggle("Includi file nascosti", isOn: $model.includeHidden)
                    Toggle("Includi sottocartelle", isOn: $model.recursive)
                    Spacer()
                    Button("Preset Amiga (da 2)") { model.prepareExample() }
                }
            }
            .padding(5)
        }
        .disabled(model.isPlanning || model.isRunning)
    }

    private var previewSection: some View {
        GroupBox("Anteprima · nessuna modifica ai file") {
            VStack(alignment: .leading, spacing: 8) {
                if let plan = model.plan {
                    Text("\(plan.files.count) file · \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)) · \(plan.folders.count) cartelle da creare/riempire")
                        .font(.headline)
                    List(plan.folders) { folder in
                        folderListRow(folder)
                    }
                    .frame(minHeight: 115)
                } else {
                    Text("Genera un'anteprima per vedere quali cartelle riceveranno i file.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 115)
                }
            }
            .padding(4)
        }
    }

    private func folderListRow(_ folder: SpanFolder) -> some View {
        HStack {
            Image(systemName: "folder")
            Text(folder.name).fontWeight(.medium)
            Spacer()
            Text("+\(folder.newFileCount) file")
            Text(ByteCountFormatter.string(fromByteCount: folder.newBytes, countStyle: .file))
                .foregroundStyle(.secondary)
            if folder.existingFileCount > 0 {
                Text("(\(folder.existingFileCount) già presenti)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading) {
            Text(model.status).foregroundStyle(.secondary).font(.callout)
            if model.isRunning {
                ProgressView(
                    value: Double(model.completed),
                    total: Double(max(model.plan?.files.count ?? 1, 1))
                )
                .accessibilityLabel("Avanzamento spostamento o copia")
            }
        }
    }

    private var actionSection: some View {
        HStack {
            Text("I file esistenti non vengono sovrascritti. Nessuna modifica prima della conferma.")
                .foregroundStyle(.secondary).font(.caption)
            Spacer()
            if model.isRunning {
                Button("Interrompi") { model.cancel() }
            } else {
                Button("Simula") { model.preview() }
                    .disabled(!model.canPreview)
                Button(model.mode == .move ? "Sposta file…" : "Copia file…") {
                    model.showConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExecute || model.plan?.files.isEmpty != false)
            }
        }
    }

    private func folderRow(_ label: String, url: URL?, select: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 90, alignment: .leading)
            Text(url?.path ?? "Nessuna cartella selezionata")
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button("Scegli…", action: select)
        }
    }
}
