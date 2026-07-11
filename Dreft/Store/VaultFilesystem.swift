import Foundation

/// Reads and writes vault contents as real files on disk.
/// Notes → `.md`, canvases → `.canvas` JSON, folders → directories, images → copied as-is.
enum VaultFilesystem {
    static let noteExtensions: Set<String> = ["md", "markdown"]
    static let canvasExtension = "canvas"
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tiff"]

    static let welcomeNoteContent = """
    This is your new vault.

    Make a note of something, create a link, or try the Importer!

    When you're ready, delete this note and make the vault your own.
    """

    // MARK: - Vault lifecycle

    /// Sandbox-safe location for built-in vaults created by Dreft.
    static func appContainerVaultsDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dreft/Vaults", isDirectory: true)
    }

    static func defaultVaultURL() -> URL {
        appContainerVaultsDirectory().appendingPathComponent("Dreft", isDirectory: true)
    }

    /// Creates the vault folder and a starter Welcome note.
    @discardableResult
    static func createVault(at vaultURL: URL, name: String) throws -> WorkspaceVault {
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let welcomeURL = vaultURL.appendingPathComponent("Welcome.md")
        if !FileManager.default.fileExists(atPath: welcomeURL.path) {
            try welcomeNoteContent.write(to: welcomeURL, atomically: true, encoding: .utf8)
        }
        return WorkspaceVault(name: name, path: vaultURL.path)
    }

    /// Ensures the default Documents/Dreft vault exists.
    static func bootstrapDefaultVault() throws -> WorkspaceVault {
        let url = defaultVaultURL()
        return try createVault(at: url, name: url.lastPathComponent)
    }

    // MARK: - Scan

    struct ScanResult {
        var files: [WorkspaceFileEntry]
        var canvasSnapshots: [String: CanvasDocumentSnapshot]
        var issues: [VaultScanIssue]
    }

    struct ScanOptions {
        var existingFilesByPath: [String: WorkspaceFileEntry] = [:]
        var existingCanvasSnapshots: [String: CanvasDocumentSnapshot] = [:]
    }

    static func scan(vaultURL: URL, options: ScanOptions = ScanOptions()) -> ScanResult {
        var files: [WorkspaceFileEntry] = []
        var canvasSnapshots: [String: CanvasDocumentSnapshot] = [:]
        var issues: [VaultScanIssue] = []
        scanDirectory(
            vaultURL,
            vaultRoot: vaultURL,
            parentRelativePath: nil,
            options: options,
            into: &files,
            canvasSnapshots: &canvasSnapshots,
            issues: &issues
        )
        return ScanResult(files: files, canvasSnapshots: canvasSnapshots, issues: issues)
    }

    private static func scanDirectory(
        _ directoryURL: URL,
        vaultRoot: URL,
        parentRelativePath: String?,
        options: ScanOptions,
        into files: inout [WorkspaceFileEntry],
        canvasSnapshots: inout [String: CanvasDocumentSnapshot],
        issues: inout [VaultScanIssue]
    ) {
        let directoryPath = relativePath(for: directoryURL, vaultRoot: vaultRoot)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            issues.append(VaultScanIssue(
                path: directoryPath.isEmpty ? vaultRoot.lastPathComponent : directoryPath,
                message: "Couldn't read this folder."
            ))
            return
        }

        let sorted = items.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        for itemURL in sorted {
            let name = itemURL.lastPathComponent
            guard !name.hasPrefix(".") else { continue }

            let relativePath = relativePath(for: itemURL, vaultRoot: vaultRoot)
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let modifiedAt = resourceValues?.contentModificationDate ?? Date()
            let createdAt = resourceValues?.creationDate ?? modifiedAt

            if isDirectory {
                files.append(WorkspaceFileEntry(
                    id: relativePath,
                    name: name,
                    kind: .folder,
                    parentFolderID: parentRelativePath,
                    relativePath: relativePath,
                    createdAt: createdAt,
                    modifiedAt: modifiedAt
                ))
                scanDirectory(
                    itemURL,
                    vaultRoot: vaultRoot,
                    parentRelativePath: relativePath,
                    options: options,
                    into: &files,
                    canvasSnapshots: &canvasSnapshots,
                    issues: &issues
                )
                continue
            }

            let ext = itemURL.pathExtension.lowercased()
            if noteExtensions.contains(ext) {
                let content: String
                if let existing = options.existingFilesByPath[relativePath],
                   existing.kind == .note,
                   timestampsMatch(existing.modifiedAt, modifiedAt) {
                    content = existing.noteContent
                } else {
                    do {
                        content = try String(contentsOf: itemURL, encoding: .utf8)
                    } catch {
                        issues.append(VaultScanIssue(path: relativePath, message: "Couldn't read this note."))
                        content = ""
                    }
                }
                let displayName = itemURL.deletingPathExtension().lastPathComponent
                files.append(WorkspaceFileEntry(
                    id: relativePath,
                    name: displayName,
                    kind: .note,
                    parentFolderID: parentRelativePath,
                    noteContent: content,
                    relativePath: relativePath,
                    createdAt: createdAt,
                    modifiedAt: modifiedAt
                ))
            } else if ext == canvasExtension {
                let displayName = itemURL.deletingPathExtension().lastPathComponent
                files.append(WorkspaceFileEntry(
                    id: relativePath,
                    name: displayName,
                    kind: .canvas,
                    parentFolderID: parentRelativePath,
                    relativePath: relativePath,
                    createdAt: createdAt,
                    modifiedAt: modifiedAt
                ))
                if let existing = options.existingFilesByPath[relativePath],
                   existing.kind == .canvas,
                   timestampsMatch(existing.modifiedAt, modifiedAt),
                   let cached = options.existingCanvasSnapshots[relativePath] {
                    canvasSnapshots[relativePath] = cached
                } else if let snapshot = readCanvas(at: itemURL) {
                    canvasSnapshots[relativePath] = snapshot
                } else {
                    issues.append(VaultScanIssue(
                        path: relativePath,
                        message: canvasReadIssue(at: itemURL)
                    ))
                }
            } else if imageExtensions.contains(ext) {
                files.append(WorkspaceFileEntry(
                    id: relativePath,
                    name: name,
                    kind: .image,
                    parentFolderID: parentRelativePath,
                    relativePath: relativePath,
                    createdAt: createdAt,
                    modifiedAt: modifiedAt
                ))
            }
        }
    }

    // MARK: - Write

    static func writeNote(_ file: WorkspaceFileEntry, vaultURL: URL) throws {
        guard file.kind == .note else { return }
        let url = vaultURL.appendingPathComponent(file.relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.noteContent.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeCanvas(_ snapshot: CanvasDocumentSnapshot, relativePath: String, vaultURL: URL) throws {
        let url = vaultURL.appendingPathComponent(relativePath)
        guard CanvasDocumentFormat.shouldOverwriteExistingFile(at: url, with: snapshot) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try CanvasDocumentFormat.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    static func writeNotes(_ files: [WorkspaceFileEntry], vaultURL: URL) -> VaultBatchWriteResult {
        var result = VaultBatchWriteResult()
        for file in files where file.kind == .note {
            do {
                try writeNote(file, vaultURL: vaultURL)
            } catch {
                result.failures.append((file.relativePath, error))
            }
        }
        return result
    }

    static let canvasAssetsFolder = ".dreft/assets"

    /// Saves image bytes for a canvas card and returns the vault-relative path.
    static func saveCanvasImage(
        data: Data,
        vaultURL: URL,
        suggestedName: String? = nil
    ) throws -> String {
        let ext = preferredImageExtension(for: data)
        let base = sanitizedFilename(suggestedName) ?? "image"
        let fileName = "\(base)-\(UUID().uuidString.prefix(8)).\(ext)"
        let relativePath = "\(canvasAssetsFolder)/\(fileName)"
        let url = vaultURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return relativePath
    }

    static func imageData(at relativePath: String, vaultURL: URL) -> Data? {
        let url = vaultURL.appendingPathComponent(relativePath)
        return try? Data(contentsOf: url)
    }

    static func readNoteContent(relativePath: String, vaultURL: URL) -> String? {
        let url = vaultURL.appendingPathComponent(relativePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func deleteCanvasAsset(at relativePath: String, vaultURL: URL) {
        let url = vaultURL.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    /// True when `content` holds inline base64 rather than a vault-relative file path.
    static func isEmbeddedImageContent(_ content: String) -> Bool {
        guard !content.isEmpty else { return false }
        if content.hasPrefix("\(canvasAssetsFolder)/") { return false }
        if content.contains("/") { return false }
        if content.count < 512,
           content.contains(".") {
            let ext = (content as NSString).pathExtension.lowercased()
            if imageExtensions.contains(ext) { return false }
        }
        return Data(base64Encoded: content, options: .ignoreUnknownCharacters) != nil
    }

    static func migrateEmbeddedImages(in snapshot: inout CanvasDocumentSnapshot, vaultURL: URL) {
        for index in snapshot.cards.indices {
            guard snapshot.cards[index].kind == .image else { continue }
            let content = snapshot.cards[index].content
            guard isEmbeddedImageContent(content),
                  let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else { continue }
            if let path = try? saveCanvasImage(
                data: data,
                vaultURL: vaultURL,
                suggestedName: snapshot.cards[index].title
            ) {
                snapshot.cards[index].content = path
            }
        }
    }

    static func preferredImageExtension(for data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if data.count >= 12,
           data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
           data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50 { return "webp" }
        return "png"
    }

    private static func sanitizedFilename(_ name: String?) -> String? {
        guard var name, !name.isEmpty else { return nil }
        name = (name as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? nil : result.lowercased()
    }

    static func writeCanvases(
        _ snapshots: [String: CanvasDocumentSnapshot],
        vaultURL: URL
    ) -> VaultBatchWriteResult {
        var result = VaultBatchWriteResult()
        for (relativePath, var snapshot) in snapshots {
            migrateEmbeddedImages(in: &snapshot, vaultURL: vaultURL)
            do {
                try writeCanvas(snapshot, relativePath: relativePath, vaultURL: vaultURL)
            } catch {
                result.failures.append((relativePath, error))
            }
        }
        if !result.hasFailures {
            pruneOrphanedCanvasAssets(vaultURL: vaultURL, pendingSnapshots: snapshots)
        }
        return result
    }

    /// Asset paths referenced by image cards across on-disk and pending canvas documents.
    static func referencedCanvasAssetPaths(
        vaultURL: URL,
        pendingSnapshots: [String: CanvasDocumentSnapshot] = [:]
    ) -> Set<String> {
        var referenced = Set<String>()
        enumerateCanvasFiles(vaultURL: vaultURL) { url in
            guard let snapshot = readCanvas(at: url) else { return }
            referenced.formUnion(canvasAssetPaths(in: snapshot))
        }
        for snapshot in pendingSnapshots.values {
            referenced.formUnion(canvasAssetPaths(in: snapshot))
        }
        return referenced
    }

    static func canvasAssetPaths(in snapshot: CanvasDocumentSnapshot) -> Set<String> {
        Set(snapshot.cards.compactMap { card in
            guard card.kind == .image else { return nil }
            let content = card.content
            guard content.hasPrefix("\(canvasAssetsFolder)/") else { return nil }
            return content
        })
    }

    /// Deletes files in `.dreft/assets/` that no canvas document references.
    static func pruneOrphanedCanvasAssets(
        vaultURL: URL,
        pendingSnapshots: [String: CanvasDocumentSnapshot] = [:]
    ) {
        if hasUnreadableCanvasFiles(vaultURL: vaultURL) {
            return
        }
        let referenced = referencedCanvasAssetPaths(vaultURL: vaultURL, pendingSnapshots: pendingSnapshots)
        let assetsDirectory = vaultURL.appendingPathComponent(canvasAssetsFolder, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: assetsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in files {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            let relativePath = relativePath(for: fileURL, vaultRoot: vaultURL)
            if !referenced.contains(relativePath) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private static func hasUnreadableCanvasFiles(vaultURL: URL) -> Bool {
        var foundUnreadable = false
        enumerateCanvasFiles(vaultURL: vaultURL) { url in
            if readCanvas(at: url) == nil {
                foundUnreadable = true
            }
        }
        return foundUnreadable
    }

    private static func enumerateCanvasFiles(vaultURL: URL, _ body: (URL) -> Void) {
        enumerateCanvasFiles(in: vaultURL, vaultRoot: vaultURL, body: body)
    }

    private static func enumerateCanvasFiles(in directoryURL: URL, vaultRoot: URL, body: (URL) -> Void) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for itemURL in items {
            if (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerateCanvasFiles(in: itemURL, vaultRoot: vaultRoot, body: body)
            } else if itemURL.pathExtension.lowercased() == canvasExtension {
                body(itemURL)
            }
        }
    }

    // MARK: - Create

    static func makeRelativePath(name: String, kind: WorkspaceFileKind, parentRelativePath: String?) -> String {
        let fileName: String = switch kind {
        case .note: "\(name).md"
        case .canvas: "\(name).canvas"
        case .folder: name
        case .image: name
        }
        if let parent = parentRelativePath, !parent.isEmpty {
            return "\(parent)/\(fileName)"
        }
        return fileName
    }

    static func createNote(relativePath: String, vaultURL: URL, content: String = "") throws {
        let url = vaultURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func createCanvas(relativePath: String, vaultURL: URL) throws {
        let url = vaultURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            let empty = CanvasDocumentSnapshot(cards: [], edges: [], transform: CanvasViewTransform())
            try writeCanvas(empty, relativePath: relativePath, vaultURL: vaultURL)
        }
    }

    static func createFolder(relativePath: String, vaultURL: URL) throws {
        let url = vaultURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Rename / move / delete

    static func renameOnDisk(
        from oldRelativePath: String,
        to newRelativePath: String,
        vaultURL: URL
    ) throws {
        let source = vaultURL.appendingPathComponent(oldRelativePath)
        let destination = vaultURL.appendingPathComponent(newRelativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
    }

    static func delete(relativePath: String, vaultURL: URL) throws {
        let url = vaultURL.appendingPathComponent(relativePath)
        try FileManager.default.removeItem(at: url)
    }

    static func duplicate(relativePath: String, newRelativePath: String, vaultURL: URL) throws {
        let source = vaultURL.appendingPathComponent(relativePath)
        let destination = vaultURL.appendingPathComponent(newRelativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    // MARK: - Helpers

    private static func timestampsMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 0.001
    }

    static func fileURL(relativePath: String, vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent(relativePath)
    }

    static func relativePath(for fileURL: URL, vaultRoot: URL) -> String {
        let root = vaultRoot.standardizedFileURL.path
        let full = fileURL.standardizedFileURL.path
        guard full.hasPrefix(root) else { return fileURL.lastPathComponent }
        var relative = String(full.dropFirst(root.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    static func readCanvas(at url: URL) -> CanvasDocumentSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if case .success(let snapshot) = CanvasDocumentFormat.read(from: data) {
            return snapshot
        }
        return nil
    }

    static func canvasReadIssue(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return "Canvas file is missing or invalid."
        }
        switch CanvasDocumentFormat.read(from: data) {
        case .success:
            return "Canvas file is missing or invalid."
        case .unsupportedVersion(let version):
            return "This canvas uses an unsupported format (version \(version))."
        case .invalid:
            return "Canvas file is missing or invalid."
        }
    }

    static func uniqueRelativePath(
        baseName: String,
        kind: WorkspaceFileKind,
        parentRelativePath: String?,
        vaultURL: URL
    ) -> String {
        var candidate = makeRelativePath(name: baseName, kind: kind, parentRelativePath: parentRelativePath)
        var index = 1
        while FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent(candidate).path) {
            let numbered = kind == .folder ? "\(baseName) \(index)" : "\(baseName) \(index)"
            candidate = makeRelativePath(name: numbered, kind: kind, parentRelativePath: parentRelativePath)
            index += 1
        }
        return candidate
    }

    static func renamedRelativePath(
        file: WorkspaceFileEntry,
        newDisplayName: String
    ) -> String {
        let parent = (file.relativePath as NSString).deletingLastPathComponent
        let parentPrefix = parent.isEmpty ? "" : parent + "/"
        let ext: String = switch file.kind {
        case .note: ".md"
        case .canvas: ".canvas"
        case .folder: ""
        case .image: (file.relativePath as NSString).pathExtension.isEmpty
            ? ""
            : ".\((file.relativePath as NSString).pathExtension)"
        }
        if file.kind == .folder {
            return parentPrefix + newDisplayName
        }
        return parentPrefix + newDisplayName + ext
    }
}
