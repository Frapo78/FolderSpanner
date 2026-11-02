import Foundation

/// Durable same-volume recovery manifest. Created only when Disaster Recovery is enabled.
/// Rollback is conservative: it never overwrites a path or restores a different inode.
/// External edits, device failure or a missing volume can prevent perfect restoration.
public enum SpanRecovery {
    public struct RecoveryReport: Sendable {
        public let restored: Int
        public let issues: [String]
        public var complete: Bool { issues.isEmpty }
    }

    private struct Entry: Codable {
        let source: String
        let destination: String
        let originalSize: Int64
        let fileNumber: UInt64
    }

    private struct Manifest: Codable {
        let version: Int
        let id: UUID
        let sourceRoot: String
        let destinationRoot: String
        let createdFolders: [String]
        let entries: [Entry]
    }

    public static func manifestURL(fileManager fm: FileManager = .default) throws -> URL {
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SpannerError("Cartella Application Support non disponibile.")
        }
        return dir.appendingPathComponent("FolderSpanner", isDirectory: true)
            .appendingPathComponent("pending-recovery.json")
    }

    public static func hasPendingRecovery(fileManager fm: FileManager = .default) -> Bool {
        guard let path = try? manifestURL(fileManager: fm) else { return false }
        return fm.fileExists(atPath: path.path)
    }

    private static func deviceNumber(of path: String, fileManager fm: FileManager) throws -> NSNumber {
        let attributes = try fm.attributesOfFileSystem(forPath: path)
        guard let value = attributes[.systemNumber] as? NSNumber else {
            throw SpannerError("Impossibile verificare il volume del disco.")
        }
        return value
    }

    /// Preflights every source and writes the manifest before any move.
    /// No journal, snapshot or additional file allocation occurs with recovery disabled.
    @discardableResult
    public static func prepare(_ plan: SpanPlan, fileManager fm: FileManager = .default) throws -> URL {
        let url = try manifestURL(fileManager: fm)
        guard !fm.fileExists(atPath: url.path) else {
            throw SpannerError("Esiste un precedente recupero in sospeso. Ripristinalo prima di iniziare un altro spostamento.")
        }
        guard let first = plan.files.first else { return url }

        let sourceDevice = try deviceNumber(of: first.source.deletingLastPathComponent().path, fileManager: fm)
        let destinationDevice = try deviceNumber(of: first.destination.deletingLastPathComponent().deletingLastPathComponent().path, fileManager: fm)
        guard sourceDevice == destinationDevice else {
            throw SpannerError("Disaster Recovery richiede origine e destinazione sullo stesso volume. Disattivalo per operazioni tra dischi diversi, oppure scegli una destinazione sullo stesso disco.")
        }

        var entries: [Entry] = []
        var folders: Set<String> = []
        for file in plan.files {
            let attributes = try fm.attributesOfItem(atPath: file.source.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value == file.bytes,
                  let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
                throw SpannerError("Il file origine è cambiato durante la preparazione: \(file.source.lastPathComponent)")
            }
            guard try deviceNumber(of: file.source.deletingLastPathComponent().path, fileManager: fm) == sourceDevice else {
                throw SpannerError("Lo spostamento include file su volumi differenti.")
            }
            guard !fm.fileExists(atPath: file.destination.path) else {
                throw SpannerError("Destinazione occupata: \(file.destination.path)")
            }
            let parent = file.destination.deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) { folders.insert(parent.path) }
            entries.append(Entry(source: file.source.path, destination: file.destination.path,
                                 originalSize: file.bytes, fileNumber: inode))
        }

        let manifest = Manifest(version: 1, id: UUID(),
                                sourceRoot: first.source.deletingLastPathComponent().path,
                                destinationRoot: first.destination.deletingLastPathComponent().deletingLastPathComponent().path,
                                createdFolders: folders.sorted(), entries: entries)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        // .atomic writes a complete recovery plan before the first file is moved.
        try data.write(to: url, options: .atomic)
        return url
    }

    public static func discardCompletedManifest(fileManager fm: FileManager = .default) throws {
        let url = try manifestURL(fileManager: fm)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    /// Can also run on the next launch if the app terminated unexpectedly.
    /// The manifest remains on disk until every item is safely restored.
    @discardableResult
    public static func restore(fileManager fm: FileManager = .default) throws -> RecoveryReport {
        let url = try manifestURL(fileManager: fm)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        guard manifest.version == 1 else { throw SpannerError("Versione del registro di recupero non supportata.") }
        var restored = 0
        var issues: [String] = []

        for entry in manifest.entries.reversed() {
            let source = URL(fileURLWithPath: entry.source)
            let dest = URL(fileURLWithPath: entry.destination)
            let sourceExists = fm.fileExists(atPath: source.path)
            let targetExists = fm.fileExists(atPath: dest.path)
            if sourceExists && !targetExists { continue } // File not yet transferred.
            if sourceExists && targetExists {
                issues.append("Conflitto: esistono sia origine sia destinazione per \(source.lastPathComponent)")
                continue
            }
            if !sourceExists && !targetExists {
                issues.append("File non trovato: \(source.lastPathComponent)")
                continue
            }
            do {
                let attrs = try fm.attributesOfItem(atPath: dest.path)
                guard attrs[.type] as? FileAttributeType == .typeRegular,
                      (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == entry.fileNumber,
                      (attrs[.size] as? NSNumber)?.int64Value == entry.originalSize else {
                    issues.append("File modificato o sostituito: \(dest.path)")
                    continue
                }
                guard fm.fileExists(atPath: source.deletingLastPathComponent().path) else {
                    issues.append("Cartella originale mancante: \(source.deletingLastPathComponent().path)")
                    continue
                }
                try fm.moveItem(at: dest, to: source)
                restored += 1
            } catch { issues.append("\(source.lastPathComponent): \(error.localizedDescription)") }
        }

        for folder in manifest.createdFolders.sorted(by: { $0.count > $1.count }) {
            if fm.fileExists(atPath: folder) {
                do {
                    if try fm.contentsOfDirectory(atPath: folder).isEmpty {
                        try fm.removeItem(atPath: folder)
                    }
                } catch { issues.append("Impossibile rimuovere la cartella \(folder): \(error.localizedDescription)") }
            }
        }
        if issues.isEmpty { try fm.removeItem(at: url) }
        return RecoveryReport(restored: restored, issues: issues)
    }
}
