import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct CatalogOptions: Sendable {
    public var root: URL
    public var recursive: Bool
    public var includeHidden: Bool
    public var overwriteExisting: Bool

    public init(root: URL, recursive: Bool = true, includeHidden: Bool = false,
                overwriteExisting: Bool = false) {
        self.root = root
        self.recursive = recursive
        self.includeHidden = includeHidden
        self.overwriteExisting = overwriteExisting
    }
}

public struct CatalogReport: Sendable {
    public let url: URL
    public let fileCount: Int
    public let folderCount: Int
    public let totalBytes: Int64
}

/// Writes a readable catalog with an atomic final publish. Never reads file contents.
/// Only one directory is sorted at a time, to reduce memory for large collections.
public enum SpanCatalog {
    public static let fileName = "FolderSpanner-catalog.md"

    public static func generate(
        _ options: CatalogOptions,
        fileManager fm: FileManager = .default,
        shouldCancel: @Sendable () -> Bool = { false },
        progress: @Sendable (Int) -> Void = { _ in }
    ) throws -> CatalogReport {
        let root = options.root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SpannerError("La cartella da catalogare non esiste.")
        }
        let output = root.appendingPathComponent(fileName)
        if fm.fileExists(atPath: output.path) && !options.overwriteExisting {
            throw SpannerError("Esiste già un catalogo. Conferma la sostituzione per continuare.")
        }
        let existing = try? output.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if existing?.isSymbolicLink == true || existing?.isDirectory == true {
            throw SpannerError("Il catalogo esistente non è un file regolare: operazione annullata.")
        }

        let temporary = root.appendingPathComponent(".FolderSpanner-catalog-" + UUID().uuidString + ".tmp")
        guard fm.createFile(atPath: temporary.path, contents: nil) else {
            throw SpannerError("Impossibile creare il catalogo temporaneo.")
        }
        let handle: FileHandle
        do { handle = try FileHandle(forWritingTo: temporary) }
        catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
        defer {
            try? handle.close()
            try? fm.removeItem(at: temporary)
        }

        func checkCancel() throws {
            if shouldCancel() { throw CancellationError() }
        }
        func write(_ text: String) throws {
            try handle.write(contentsOf: Data(text.utf8))
        }
        func markdown(_ name: String) -> String {
            name.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\u{0000}", with: "")
        }
        let quote = String(UnicodeScalar(96)!)
        let formatter = ISO8601DateFormatter()
        try write("# FolderSpanner — File catalog\n\n")
        try write("- Root: " + quote + markdown(root.path) + quote + "\n")
        try write("- Generated (UTC): " + formatter.string(from: Date()) + "\n")
        try write("- Recursive: " + (options.recursive ? "yes" : "no") + "\n")
        try write("- Hidden files: " + (options.includeHidden ? "included" : "excluded") + "\n")
        try write("- Sizes: exact bytes (metadata only; no file contents read)\n\n")

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .isHiddenKey, .fileSizeKey
        ]
        var fileCount = 0
        var folderCount = 0
        var byteCount: Int64 = 0

        func visit(_ directory: URL, relative: String) throws {
            try checkCancel()
            let children = try fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys),
                options: [])
                .sorted { a, b in
                    let order = a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
                    return order == .orderedSame
                        ? a.lastPathComponent < b.lastPathComponent : order == .orderedAscending
                }

            var folders: [URL] = []
            var wroteHeading = false
            for item in children {
                try checkCancel()
                if item.standardizedFileURL == output || item.standardizedFileURL == temporary { continue }
                let values = try item.resourceValues(forKeys: keys)
                if !options.includeHidden &&
                   (item.lastPathComponent.hasPrefix(".") || values.isHidden == true) { continue }
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    if options.recursive && !["app", "bundle", "framework", "pkg", "photoslibrary"]
                        .contains(item.pathExtension.lowercased()) {
                        folders.append(item)
                    }
                    continue
                }
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.fileSize ?? 0)
                let (sum, overflow) = byteCount.addingReportingOverflow(size)
                guard !overflow else { throw SpannerError("Dimensione totale dei file troppo grande.") }
                byteCount = sum
                if !wroteHeading {
                    try write("## " + quote + (relative.isEmpty ? "." : markdown(relative)) + quote + "\n\n")
                    try write("| File | Relative path | Bytes |\n| --- | --- | ---: |\n")
                    wroteHeading = true
                    folderCount += 1
                }
                let rel = relative.isEmpty ? item.lastPathComponent : relative + "/" + item.lastPathComponent
                try write("| " + markdown(item.lastPathComponent) + " | " + markdown(rel) + " | " + String(size) + " |\n")
                fileCount += 1
                if fileCount % 128 == 0 { progress(fileCount) }
            }
            if wroteHeading { try write("\n") }
            for subfolder in folders {
                let next = relative.isEmpty ? subfolder.lastPathComponent : relative + "/" + subfolder.lastPathComponent
                try visit(subfolder, relative: next)
            }
        }

        progress(0)
        try visit(root, relative: "")
        try checkCancel()
        try write("## Summary\n\n")
        try write("- Files: " + String(fileCount) + "\n")
        try write("- Folders containing files: " + String(folderCount) + "\n")
        try write("- Total bytes: " + String(byteCount) + "\n")
        try handle.synchronize()
        try handle.close()
        try checkCancel()

        // Same-volume publication: moveItem refuses existing targets and works
        // on FAT/exFAT too (hard links are not available on those disks).
        // Explicit overwrite uses rename, preserving the prior file on failed scan.
        if options.overwriteExisting {
            if rename(temporary.path, output.path) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } else {
            try fm.moveItem(at: temporary, to: output)
        }
        progress(fileCount)
        return CatalogReport(url: output, fileCount: fileCount,
                             folderCount: folderCount, totalBytes: byteCount)
    }
}
