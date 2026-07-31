import Foundation

enum CanvasBundleTransfer {
    static let bundleExtension = "dreftcanvas"
    static let manifestFileName = "manifest.json"
    static let canvasFileName = "canvas.json"
    static let assetsFolderName = "assets"

    struct Manifest: Codable {
        var format: String = "dreft-canvas-bundle"
        var formatVersion: Int = 1
        var canvasName: String
        var exportedAt: Date
    }

    struct ImportResult {
        var snapshot: CanvasDocumentSnapshot
        var canvasName: String
    }

    enum TransferError: LocalizedError {
        case invalidBundle
        case missingCanvas
        case missingAsset(String)

        var errorDescription: String? {
            switch self {
            case .invalidBundle:
                "This folder is not a valid Dreft canvas bundle."
            case .missingCanvas:
                "The bundle does not contain a canvas document."
            case .missingAsset(let name):
                "Missing image asset \"\(name)\" in the bundle."
            }
        }
    }

    static func exportBundle(
        snapshot: CanvasDocumentSnapshot,
        canvasName: String,
        vaultURL: URL,
        to bundleURL: URL
    ) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: bundleURL.path) {
            try fm.removeItem(at: bundleURL)
        }
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let assetsURL = bundleURL.appendingPathComponent(assetsFolderName, isDirectory: true)
        try fm.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let vaultAssetPaths = VaultFilesystem.canvasAssetPaths(in: snapshot, vaultURL: vaultURL)
        var pathMap: [String: String] = [:]
        var usedNames = Set<String>()

        for vaultPath in vaultAssetPaths.sorted() {
            guard let data = VaultFilesystem.imageDataForCanvasAsset(relativePath: vaultPath, vaultURL: vaultURL) else {
                continue
            }
            let baseName = uniqueAssetFileName(
                (vaultPath as NSString).lastPathComponent,
                usedNames: &usedNames
            )
            let bundleAssetPath = "\(assetsFolderName)/\(baseName)"
            try data.write(to: assetsURL.appendingPathComponent(baseName), options: .atomic)
            pathMap[vaultPath] = bundleAssetPath
            let embedTarget = (vaultPath as NSString).lastPathComponent
            if embedTarget != vaultPath {
                pathMap[embedTarget] = bundleAssetPath
            }
        }

        let exportedSnapshot = remapSnapshot(snapshot, using: pathMap, toBundlePaths: true)
        let manifest = Manifest(canvasName: canvasName, exportedAt: Date())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: bundleURL.appendingPathComponent(manifestFileName), options: .atomic)
        try CanvasDocumentFormat.encode(exportedSnapshot).write(
            to: bundleURL.appendingPathComponent(canvasFileName),
            options: .atomic
        )
    }

    static func importBundle(from url: URL, vaultURL: URL) throws -> ImportResult {
        let bundleRoot = try resolveBundleRoot(from: url)
        let manifestData = try Data(contentsOf: bundleRoot.appendingPathComponent(manifestFileName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: manifestData)

        let canvasURL = bundleRoot.appendingPathComponent(canvasFileName)
        guard FileManager.default.fileExists(atPath: canvasURL.path) else {
            throw TransferError.missingCanvas
        }
        let canvasData = try Data(contentsOf: canvasURL)
        guard case .success(let snapshot) = CanvasDocumentFormat.read(from: canvasData) else {
            throw TransferError.missingCanvas
        }

        let assetsURL = bundleRoot.appendingPathComponent(assetsFolderName, isDirectory: true)
        var pathMap: [String: String] = [:]

        if FileManager.default.fileExists(atPath: assetsURL.path) {
            let assetFiles = try FileManager.default.contentsOfDirectory(
                at: assetsURL,
                includingPropertiesForKeys: nil
            )
            for assetURL in assetFiles where !assetURL.hasDirectoryPath {
                let data = try Data(contentsOf: assetURL)
                let vaultPath = try VaultFilesystem.saveCanvasImage(
                    data: data,
                    vaultURL: vaultURL,
                    suggestedName: assetURL.deletingPathExtension().lastPathComponent
                )
                let bundlePath = "\(assetsFolderName)/\(assetURL.lastPathComponent)"
                pathMap[bundlePath] = vaultPath
                pathMap[assetURL.lastPathComponent] = vaultPath
            }
        }

        let importedSnapshot = remapSnapshot(snapshot, using: pathMap, toBundlePaths: false)
        return ImportResult(snapshot: importedSnapshot, canvasName: manifest.canvasName)
    }

    static func resolveBundleRoot(from url: URL) throws -> URL {
        var candidate = url
        if candidate.pathExtension == bundleExtension, !candidate.hasDirectoryPath {
            candidate = candidate.deletingPathExtension()
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw TransferError.invalidBundle
        }
        guard FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent(manifestFileName).path
        ) else {
            throw TransferError.invalidBundle
        }
        return candidate
    }

    private static func uniqueAssetFileName(_ baseName: String, usedNames: inout Set<String>) -> String {
        guard !baseName.isEmpty else { return "image.png" }
        var candidate = baseName
        var counter = 2
        while usedNames.contains(candidate) {
            let ext = (baseName as NSString).pathExtension
            let stem = (baseName as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            counter += 1
        }
        usedNames.insert(candidate)
        return candidate
    }

    private static func remapSnapshot(
        _ snapshot: CanvasDocumentSnapshot,
        using pathMap: [String: String],
        toBundlePaths: Bool
    ) -> CanvasDocumentSnapshot {
        guard !pathMap.isEmpty else { return snapshot }
        var result = snapshot
        for index in result.cards.indices {
            switch result.cards[index].kind {
            case .image:
                result.cards[index].content = remapPath(
                    result.cards[index].content,
                    using: pathMap,
                    toBundlePaths: toBundlePaths
                )
            case .note, .text:
                var content = result.cards[index].content
                for (source, destination) in pathMap.sorted(by: { $0.key.count > $1.key.count }) {
                    content = content.replacingOccurrences(of: source, with: destination)
                    let sourceBase = (source as NSString).lastPathComponent
                    let destinationBase = (destination as NSString).lastPathComponent
                    if sourceBase != destinationBase {
                        content = replaceWikiEmbedTarget(in: content, from: sourceBase, to: destinationBase)
                    }
                }
                result.cards[index].content = content
            }
        }
        return result
    }

    private static func remapPath(
        _ path: String,
        using pathMap: [String: String],
        toBundlePaths: Bool
    ) -> String {
        if let mapped = pathMap[path] { return mapped }
        let base = (path as NSString).lastPathComponent
        if let mapped = pathMap[base] { return mapped }
        if toBundlePaths, path.hasPrefix(VaultFilesystem.canvasAssetsFolder + "/") {
            return "\(assetsFolderName)/\(base)"
        }
        return path
    }

    private static func replaceWikiEmbedTarget(in content: String, from oldTarget: String, to newTarget: String) -> String {
        let patterns = [
            "![[\(oldTarget)]]",
            "![[\(oldTarget)|",
        ]
        var updated = content
        for pattern in patterns {
            if pattern.hasSuffix("|") {
                updated = updated.replacingOccurrences(
                    of: pattern,
                    with: "![[\(newTarget)|"
                )
            } else {
                updated = updated.replacingOccurrences(
                    of: pattern,
                    with: "![[\(newTarget)]]"
                )
            }
        }
        return updated
    }
}
