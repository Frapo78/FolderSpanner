import AppKit
import Combine
import CryptoKit
import Foundation

/// User-initiated updater for official Frapo78/FolderSpanner GitHub Releases.
/// Checks ZIP SHA-256 and ad-hoc code integrity; ad-hoc signatures do NOT
/// authenticate the publisher. Release accounts and HTTPS must be trusted.
@MainActor
final class GitHubUpdater: ObservableObject {
    struct Release: Decodable, Identifiable, Sendable {
        struct Asset: Decodable, Sendable {
            let name: String
            let browser_download_url: URL
        }
        let id: Int
        let name: String
        let tag_name: String
        let draft: Bool
        let assets: [Asset]

        var zipAsset: Asset? { assets.first { $0.name.hasSuffix(".zip") && $0.name.hasPrefix("FolderSpanner-macOS-arm64-") } }
        var checksumAsset: Asset? { assets.first { $0.name == "SHA256SUMS.txt" } }
    }

    @Published var availableRelease: Release?
    @Published var isWorking = false
    @Published var status = ""

    private var actionTask: Task<Void, Never>?
    private static let releasesURL = URL(string: "https://api.github.com/repos/Frapo78/FolderSpanner/releases?per_page=15")!

    func checkForUpdates() {
        guard !isWorking else { return }
        isWorking = true
        status = L10n.tr("Controllo GitHub Releases…")
        actionTask = Task {
            do {
                var request = URLRequest(url: Self.releasesURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("FolderSpanner-Updater", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdaterError("Impossibile leggere le release pubbliche su GitHub.")
                }
                let releases = try JSONDecoder().decode([Release].self, from: data)
                guard let latest = releases.first(where: { !$0.draft && $0.zipAsset != nil && $0.checksumAsset != nil }) else {
                    throw UpdaterError("Non sono disponibili release ZIP verificabili.")
                }
                let currentSHA = Bundle.main.object(forInfoDictionaryKey: "FSGitSHA") as? String ?? ""
                let sameCommit = !currentSHA.isEmpty && latest.tag_name.contains(String(currentSHA.prefix(7)))
                if sameCommit {
                    status = L10n.tr("FolderSpanner è già aggiornato (%@).", latest.tag_name)
                } else {
                    status = L10n.tr("Disponibile: %@.", latest.tag_name)
                    availableRelease = latest
                }
            } catch {
                status = L10n.tr("Verifica aggiornamenti non riuscita: %@", error.localizedDescription)
            }
            isWorking = false
        }
    }

    func cancel() {
        actionTask?.cancel()
        status = L10n.tr("Operazione annullata.")
        isWorking = false
    }

    func install(_ release: Release) {
        guard !isWorking else { return }
        isWorking = true
        status = L10n.tr("Scaricamento e verifica in corso…")
        actionTask = Task {
            do {
                let installed = Bundle.main.bundleURL.standardizedFileURL
                guard installed.pathExtension == "app",
                      Bundle.main.bundleIdentifier == "it.frapo.folder-spanner" else {
                    throw UpdaterError("Per aggiornare, avvia FolderSpanner dalla sua cartella .app.")
                }
                let parent = installed.deletingLastPathComponent()
                guard FileManager.default.isWritableFile(atPath: parent.path) else {
                    throw UpdaterError("La cartella dell'app non è scrivibile. Installa l'app in ~/Applications oppure aggiorna manualmente.")
                }
                let prepared = try await Self.prepareUpdate(release: release)
                try Task.checkCancellation()
                try Self.launchReplacementHelper(existing: installed, prepared: prepared)
                status = L10n.tr("Aggiornamento pronto. FolderSpanner viene riavviato.")
                NSApp.terminate(nil)
            } catch {
                status = L10n.tr("Aggiornamento non installato: %@", error.localizedDescription)
                isWorking = false
            }
        }
    }

    private struct UpdaterError: LocalizedError {
        let message: String
        init(_ value: String) { message = L10n.tr(value) }
        var errorDescription: String? { message }
    }

    private static func prepareUpdate(release: Release) async throws -> URL {
        guard let zip = release.zipAsset, let sums = release.checksumAsset else {
            throw UpdaterError("Asset ZIP o SHA256SUMS.txt mancante.")
        }
        guard zip.browser_download_url.host == "github.com",
              sums.browser_download_url.host == "github.com",
              zip.browser_download_url.path.hasPrefix("/Frapo78/FolderSpanner/releases/download/"),
              sums.browser_download_url.path.hasPrefix("/Frapo78/FolderSpanner/releases/download/") else {
            throw UpdaterError("Gli asset non appartengono al repository ufficiale.")
        }
        let (checksumData, checksumResponse) = try await URLSession.shared.data(from: sums.browser_download_url)
        guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200,
              let checksumText = String(data: checksumData, encoding: .utf8) else {
            throw UpdaterError("Impossibile verificare il checksum della release.")
        }
        let expected: String? = checksumText.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let pieces = line.split(whereSeparator: \.isWhitespace)
            guard pieces.count == 2, String(pieces[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*")) == zip.name else { return nil }
            let hash = String(pieces[0]).lowercased()
            guard hash.count == 64 && hash.allSatisfy({ $0.isHexDigit }) else { return nil }
            return hash
        }.first
        guard let expected else { throw UpdaterError("Checksum mancante o non valido per lo ZIP scelto.") }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderSpannerUpdate-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let localZip = staging.appendingPathComponent(zip.name)
        let (temporaryFile, zipResponse) = try await URLSession.shared.download(from: zip.browser_download_url)
        guard (zipResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdaterError("Download dell'archivio non riuscito.")
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporaryFile, to: localZip)
        let reader = try FileHandle(forReadingFrom: localZip)
        defer { try? reader.close() }
        var digest = SHA256()
        while let chunk = try reader.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk)
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdaterError("SHA-256 non corrispondente: installazione bloccata.") }

        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", localZip.path, unpacked.path])
        let candidate = unpacked.appendingPathComponent("FolderSpanner.app", isDirectory: true)
        guard let bundle = Bundle(url: candidate),
              bundle.bundleIdentifier == "it.frapo.folder-spanner",
              FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Contents/MacOS/FolderSpanner").path) else {
            throw UpdaterError("Il pacchetto scaricato non contiene FolderSpanner.app valida.")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
        try run("/usr/bin/lipo", ["-verify_arch", "arm64", candidate.appendingPathComponent("Contents/MacOS/FolderSpanner").path])
        return candidate
    }

    private static func run(_ executable: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdaterError(L10n.tr("La verifica %@ è fallita.", URL(fileURLWithPath: executable).lastPathComponent))
        }
    }

    private static func launchReplacementHelper(existing: URL, prepared: URL) throws {
        let stageDir = prepared.deletingLastPathComponent().deletingLastPathComponent()
        let script = stageDir.appendingPathComponent("install-update.sh")
        let source = """
        #!/bin/bash
        set -euo pipefail
        old="$1"
        fresh="$2"
        pid="$3"
        for attempt in {1..60}; do
          if ! kill -0 "$pid" 2>/dev/null; then break; fi
          sleep 1
        done
        if kill -0 "$pid" 2>/dev/null; then exit 1; fi
        backup="$(dirname "$old")/.FolderSpanner-backup-$(date +%s)-$$.app"
        test -d "$old" && test -d "$fresh"
        /bin/mv "$old" "$backup"
        if /bin/mv "$fresh" "$old"; then
          /usr/bin/open "$old"
        else
          /bin/mv "$backup" "$old" || true
          exit 1
        fi
        # Backup retained intentionally for manual recovery.
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [script.path, existing.path, prepared.path, String(ProcessInfo.processInfo.processIdentifier)]
        try helper.run()
    }
}
