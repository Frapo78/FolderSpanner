import AppKit
import SwiftUI
import FolderSpannerCore

/// Independent tool: catalog any selected folder without copying or moving files.
struct CatalogPanel: View {
    @ObservedObject var model: CatalogViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Catalogo indipendente") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scansiona una cartella e genera un indice Markdown, senza spostare o copiare alcun file.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("Cartella da catalogare").frame(width: 165, alignment: .leading)
                        Text(model.root?.path ?? L10n.tr("Nessuna cartella selezionata"))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button("Scegli…") { model.chooseFolder() }
                            .disabled(model.isRunning)
                    }
                    Toggle("Scansione ricorsiva delle sottocartelle", isOn: $model.recursive)
                        .disabled(model.isRunning)
                    Toggle("Includi file nascosti", isOn: $model.includeHidden)
                        .disabled(model.isRunning)
                    Text("Il file FolderSpanner-catalog.md sarà creato nella cartella selezionata.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            if model.isRunning {
                GroupBox("Scansione del catalogo") {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView().controlSize(.regular)
                        Text(L10n.tr("%ld file analizzati", model.scannedFiles))
                            .font(.callout.monospacedDigit())
                        Button("Annulla") { model.cancel() }
                    }.padding(8)
                }
            }
            Text(model.status).foregroundStyle(.secondary)
            HStack {
                Spacer()
                if model.generatedURL != nil {
                    Button("Apri catalogo") { model.openCatalog() }
                }
                Button("Genera catalogo") { model.prepareGeneration() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.root == nil || model.isRunning)
            }
        }
        .confirmationDialog(
            "Esiste già un catalogo nella cartella selezionata.",
            isPresented: $model.showOverwriteConfirmation
        ) {
            Button("Sostituisci il catalogo", role: .destructive) {
                model.generate(overwrite: true)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il catalogo precedente resterà intatto fino al completamento del nuovo file.")
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
    }
}
