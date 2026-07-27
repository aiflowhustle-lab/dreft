import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum NoteImageDropSupport {
    static func loadData(from provider: NSItemProvider, completion: @escaping (Data, String?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, !data.isEmpty else { return }
                DispatchQueue.main.async {
                    completion(data, nil)
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let payload = imagePayload(fromFileDropItem: item) else { return }
                DispatchQueue.main.async {
                    completion(payload.data, payload.name)
                }
            }
        }
    }

    static func imagePayload(fromFileDropItem item: NSSecureCoding?) -> (data: Data, name: String?)? {
        if let url = item as? URL {
            return payload(fromFileURL: url)
        }
        if let nsURL = item as? NSURL, let url = nsURL as URL? {
            return payload(fromFileURL: url)
        }
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            return payload(fromFileURL: url)
        }
        if let string = item as? String {
            if let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return payload(fromFileURL: url)
            }
            if string.hasPrefix("/") {
                return payload(fromFileURL: URL(fileURLWithPath: string))
            }
        }
        return nil
    }

    static func payload(fromFileURL url: URL) -> (data: Data, name: String?)? {
        guard VaultFilesystem.isImageEmbedTarget(url.lastPathComponent),
              let data = try? Data(contentsOf: url) else { return nil }
        return (data, url.lastPathComponent)
    }

    #if os(macOS)
    static func imagePayload(from pasteboard: NSPasteboard) -> (data: Data, name: String?)? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let payload = payload(fromFileURL: url) { return payload }
            }
        }

        let fileURLTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ]

        for type in fileURLTypes {
            if type.rawValue == "NSFilenamesPboardType",
               let paths = pasteboard.propertyList(forType: type) as? [String] {
                for path in paths {
                    if let payload = payload(fromFileURL: URL(fileURLWithPath: path)) { return payload }
                }
                continue
            }
            if let urlString = pasteboard.string(forType: type),
               let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
               let payload = payload(fromFileURL: url) {
                return payload
            }
        }

        if let string = pasteboard.string(forType: .string),
           let url = extractFilePath(from: string),
           let payload = payload(fromFileURL: url) {
            return payload
        }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png, .tiff,
            NSPasteboard.PasteboardType(UTType.image.identifier),
        ]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return (data, suggestedName(forImageData: data))
            }
        }

        return nil
    }

    static func pasteboardContainsImageFile(_ pasteboard: NSPasteboard) -> Bool {
        imagePayload(from: pasteboard) != nil
    }

    private static func extractFilePath(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            let url = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let pattern = #"(/[^\s]+?\.(?:jpe?g|png|gif|webp|heic|heif|tiff?))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range(at: 1), in: trimmed) else { return nil }
        let url = URL(fileURLWithPath: String(trimmed[range]))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func suggestedName(forImageData data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "photo.png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "photo.jpg" }
        return "photo.png"
    }
    #endif
}
