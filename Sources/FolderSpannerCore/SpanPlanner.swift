import Foundation

public enum TransferMode: String, CaseIterable, Identifiable, Sendable {
    case move = "Sposta"
    case copy = "Copia"
    public var id: String { rawValue }
}

public enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case ascending = "Nome A → Z"
    case descending = "Nome Z → A"
    case smallestFirst = "Dimensione crescente"
    case largestFirst = "Dimensione decrescente"
    public var id: String { rawValue }
}

public struct SpanOptions: Sendable {
    public var source: URL
    public var destinationRoot: URL
    public var maximumFiles: Int
    public var maximumBytes: Int64?
    public var folderPattern: String
    public var startingIndex: Int
    public var sortOrder: SortOrder
    public var includeHidden: Bool
    public var recursive: Bool

    public init(source: URL, destinationRoot: URL, maximumFiles: Int = 200,
                maximumBytes: Int64? = nil, folderPattern: String = "{n}",
                startingIndex: Int = 1, sortOrder: SortOrder = .ascending,
                includeHidden: Bool = false, recursive: Bool = false) {
        self.source = source
        self.destinationRoot = destinationRoot
        self.maximumFiles = maximumFiles
        self.maximumBytes = maximumBytes
        self.folderPattern = folderPattern
        self.startingIndex = startingIndex
        self.sortOrder = sortOrder
        self.includeHidden = includeHidden
        self.recursive = recursive
    }
}

public struct PlannedFile: Sendable, Identifiable {
    public let source: URL
    public let destination: URL
    public let bytes: Int64
    public var id: String { source.path }
}

public struct PlannedFolder: Sendable, Identifiable {
    public let name: String
    public let newFileCount: Int
    public let newBytes: Int64
    public let existingFileCount: Int
    public var id: String { name }
}

public struct SpanPlan: Sendable {
    public let files: [PlannedFile]
    public let folders: [PlannedFolder]
    public let totalBytes: Int64
}

public struct SpannerError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private struct Candidate {
    let url: URL
    let bytes: Int64
}

private struct FolderState {
    var name: String
    var count = 0
    var bytes: Int64 = 0
    var existingCount = 0
    var newCount = 0
    var newBytes: Int64 = 0
    var filenames: Set<String> = []
}

public enum SpanPlanner {
    private static let folderToken = try! NSRegularExpression(pattern: #"\{n(?::(0*[1-9][0-9]*))?\}"#)

    public static func folderName(pattern: String, index: Int) throws -> String {
        let text = pattern as NSString
        let matches = folderToken.matches(in: pattern, range: NSRange(location: 0, length: text.length))
        guard matches.count == 1, let match = matches.first else {
            throw SpannerError("Il modello deve contenere esattamente un segnaposto {n} oppure {n:03}.")
        }
        let width: Int
        if match.range(at: 1).location != NSNotFound {
            let rawWidth = text.substring(with: match.range(at: 1))
            guard let parsed = Int(rawWidth), parsed <= 12 else {
                throw SpannerError("La larghezza della numerazione deve essere tra 1 e 12.")
            }
            width = parsed
        } else {
            width = 0
        }
        let prefix = text.substring(to: match.range.location)
        let suffix = text.substring(from: NSMaxRange(match.range))
        let value = String(repeating: "0", count: max(0, width - String(index).count)) + String(index)
        let name = prefix + value + suffix
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":"), !name.contains("\\"),
              !name.contains("{"), !name.contains("}") else {
            throw SpannerError("Il modello produce un nome cartella non valido: \(name)")
        }
        return name
    }

    public static func plan(_ options: SpanOptions, fileManager fm: FileManager = .default) throws -> SpanPlan {
        guard options.startingIndex >= 0, options.maximumFiles >= 0,
              options.maximumFiles > 0 || options.maximumBytes != nil,
              options.maximumBytes == nil || options.maximumBytes! > 0 else {
            throw SpannerError("Imposta un limite valido: numero di file e/o dimensione maggiore di zero.")
        }
        _ = try folderName(pattern: options.folderPattern, index: options.startingIndex)

        let source = options.source.standardizedFileURL.resolvingSymlinksInPath()
        let root = options.destinationRoot.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue else {
            throw SpannerError("La cartella origine non esiste.")
        }
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw SpannerError("La cartella destinazione non esiste.")
        }
        guard source.path != root.path,
              !root.path.hasPrefix(source.path + "/") else {
            throw SpannerError("La destinazione non può coincidere con l'origine o trovarsi al suo interno.")
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey,
                                         .isDirectoryKey, .isHiddenKey, .fileSizeKey]
        var candidates: [Candidate] = []
        func visit(_ directory: URL) throws {
            let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            for item in contents {
                let values = try item.resourceValues(forKeys: keys)
                if !options.includeHidden && (item.lastPathComponent.hasPrefix(".") || values.isHidden == true) {
                    continue
                }
                if values.isSymbolicLink == true { continue }
                if values.isRegularFile == true {
                    candidates.append(Candidate(url: item, bytes: Int64(values.fileSize ?? 0)))
                } else if options.recursive && values.isDirectory == true && !isPackage(item) {
                    try visit(item)
                }
            }
        }
        try visit(source)
        let nameKey: (String) -> String = { $0.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        candidates.sort { a, b in
            let result: ComparisonResult
            switch options.sortOrder {
            case .ascending, .descending:
                result = nameKey(a.url.lastPathComponent).compare(nameKey(b.url.lastPathComponent))
            case .smallestFirst, .largestFirst:
                if a.bytes != b.bytes {
                    return options.sortOrder == .smallestFirst ? a.bytes < b.bytes : a.bytes > b.bytes
                }
                result = nameKey(a.url.lastPathComponent).compare(nameKey(b.url.lastPathComponent))
            }
            if result == .orderedSame { return a.url.path < b.url.path }
            return options.sortOrder == .descending ? result == .orderedDescending : result == .orderedAscending
        }

        var stateCache: [Int: FolderState] = [:]
        var usedFolderNames: Set<String> = []
        func state(for index: Int) throws -> FolderState {
            if let cached = stateCache[index] { return cached }
            let name = try folderName(pattern: options.folderPattern, index: index)
            let canonicalName = nameKey(name)
            guard !usedFolderNames.contains(canonicalName) else {
                throw SpannerError("Il modello genera cartelle con nomi duplicati.")
            }
            usedFolderNames.insert(canonicalName)
            let dir = root.appendingPathComponent(name, isDirectory: true)
            var result = FolderState(name: name)
            var existsAsDirectory: ObjCBool = false
            if (try? dir.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw SpannerError("La cartella di destinazione \(name) è un collegamento simbolico.")
            }
            if fm.fileExists(atPath: dir.path, isDirectory: &existsAsDirectory) {
                guard existsAsDirectory.boolValue else { throw SpannerError("Esiste già un file chiamato \(name).") }
                let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys))
                for item in items {
                    let values = try item.resourceValues(forKeys: keys)
                    guard values.isRegularFile == true && values.isSymbolicLink != true else {
                        throw SpannerError("La cartella \(name) contiene sottocartelle o collegamenti: non verrà riutilizzata.")
                    }
                    result.count += 1
                    result.existingCount += 1
                    result.bytes += Int64(values.fileSize ?? 0)
                    result.filenames.insert(nameKey(item.lastPathComponent))
                }
            }
            stateCache[index] = result
            return result
        }

        var index = options.startingIndex
        var planned: [PlannedFile] = []
        for file in candidates {
            if let limit = options.maximumBytes, file.bytes > limit {
                throw SpannerError("Il file \(file.url.lastPathComponent) supera da solo il limite in byte.")
            }
            while true {
                var folder = try state(for: index)
                let tooMany = options.maximumFiles > 0 && folder.count >= options.maximumFiles
                let tooLarge = options.maximumBytes.map { folder.bytes > $0 - file.bytes } ?? false
                if tooMany || tooLarge {
                    guard index < Int.max else { throw SpannerError("Numerazione cartelle esaurita.") }
                    index += 1
                    continue
                }
                let name = file.url.lastPathComponent
                guard !folder.filenames.contains(nameKey(name)) else {
                    throw SpannerError("Conflitto nella cartella \(folder.name): \(name). Nessun file è stato spostato.")
                }
                let destination = root.appendingPathComponent(folder.name, isDirectory: true)
                    .appendingPathComponent(name)
                planned.append(PlannedFile(source: file.url, destination: destination, bytes: file.bytes))
                folder.count += 1
                folder.bytes += file.bytes
                folder.newCount += 1
                folder.newBytes += file.bytes
                folder.filenames.insert(nameKey(name))
                stateCache[index] = folder
                break
            }
        }
        let groups = stateCache.sorted { $0.key < $1.key }.compactMap { _, state -> PlannedFolder? in
            guard state.newCount > 0 else { return nil }
            return PlannedFolder(name: state.name, newFileCount: state.newCount,
                                 newBytes: state.newBytes, existingFileCount: state.existingCount)
        }
        return SpanPlan(files: planned, folders: groups, totalBytes: planned.reduce(0) { $0 + $1.bytes })
    }

    private static func isPackage(_ url: URL) -> Bool {
        // Avoid traversing macOS app bundles and similar packages in recursive mode.
        ["app", "bundle", "framework", "pkg", "photoslibrary"].contains(url.pathExtension.lowercased())
    }
}

public enum SpanExecutor {
    public static func transfer(_ item: PlannedFile, mode: TransferMode,
                                fileManager fm: FileManager = .default) throws {
        // Double-check before every destructive operation (no overwrite policy).
        let values = try item.source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == item.bytes else {
            throw SpannerError("Il file origine è cambiato dall'anteprima: \(item.source.lastPathComponent)")
        }
        let folder = item.destination.deletingLastPathComponent()
        if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw SpannerError("La cartella di destinazione è un collegamento simbolico.")
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let existingNames = try fm.contentsOfDirectory(atPath: folder.path)
        guard !existingNames.contains(where: {
            $0.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) ==
            item.destination.lastPathComponent.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }) else {
            throw SpannerError("Il file di destinazione esiste già: \(item.destination.path)")
        }
        switch mode {
        case .move: try fm.moveItem(at: item.source, to: item.destination)
        case .copy: try fm.copyItem(at: item.source, to: item.destination)
        }
    }
}
