import Foundation

enum WorkspaceTabKind: String, Codable, Equatable {
    case canvas
    case note
    case graph
    case newTab
}

struct WorkspaceTab: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var kind: WorkspaceTabKind
    var fileID: String?
}

enum WorkspaceFileKind: String, Codable, Equatable {
    case canvas
    case note
    case folder
    case image
}

enum SidebarSortOrder: String, CaseIterable, Codable {
    case nameAscending
    case nameDescending
    case modifiedNewToOld
    case modifiedOldToNew
    case createdNewToOld
    case createdOldToNew

    var label: String {
        switch self {
        case .nameAscending: "File name (A to Z)"
        case .nameDescending: "File name (Z to A)"
        case .modifiedNewToOld: "Modified time (new to old)"
        case .modifiedOldToNew: "Modified time (old to new)"
        case .createdNewToOld: "Created time (new to old)"
        case .createdOldToNew: "Created time (old to new)"
        }
    }
}

struct WorkspaceVault: Identifiable, Equatable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var path: String
    /// Security-scoped bookmark for user-picked vault folders on iOS/iPadOS.
    var securityScopedBookmark: Data?
}

struct WorkspaceBookmark: Identifiable, Equatable, Codable {
    var fileID: String
    var title: String
    var group: String

    var id: String { fileID }
}

struct WorkspaceBookmarkEntry: Identifiable, Equatable {
    let bookmark: WorkspaceBookmark
    let file: WorkspaceFileEntry

    var id: String { bookmark.fileID }
}

struct WorkspaceFileEntry: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var kind: WorkspaceFileKind
    var parentFolderID: String?
    var noteContent: String
    /// Path relative to the vault root, e.g. `Welcome.md` or `Characters/Eris.canvas`.
    var relativePath: String
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: WorkspaceFileKind,
        parentFolderID: String? = nil,
        noteContent: String = "",
        relativePath: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parentFolderID = parentFolderID
        self.noteContent = noteContent
        self.relativePath = relativePath ?? id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    var isMovable: Bool {
        switch kind {
        case .canvas, .note, .folder, .image: true
        }
    }

    var badge: String? {
        switch kind {
        case .canvas: "CANVAS"
        case .note: nil
        case .folder: nil
        case .image: "JPEG"
        }
    }

    static let defaultFiles: [WorkspaceFileEntry] = []
}

struct VaultFile: Identifiable, Hashable {
    let id: String
    let name: String
    let badge: String
    let kind: WorkspaceFileKind
    let relativePath: String
    var noteContent: String?

    init(
        name: String,
        badge: String,
        kind: WorkspaceFileKind = .note,
        relativePath: String? = nil,
        noteContent: String? = nil
    ) {
        let path = relativePath ?? name
        self.id = path
        self.name = name
        self.badge = badge
        self.kind = kind
        self.relativePath = path
        self.noteContent = noteContent
    }

    init(file: WorkspaceFileEntry) {
        id = file.id
        name = file.name
        badge = Self.badge(for: file)
        kind = file.kind
        relativePath = file.relativePath
        noteContent = file.kind == .note ? file.noteContent : nil
    }

    static func badge(for file: WorkspaceFileEntry) -> String {
        if let badge = file.badge { return badge }
        switch file.kind {
        case .note: return "MD"
        case .canvas: return "CANVAS"
        case .folder: return "FOLDER"
        case .image:
            let ext = (file.relativePath as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "IMAGE" : ext
        }
    }

    static func openableFiles(from entries: [WorkspaceFileEntry]) -> [VaultFile] {
        entries
            .filter { $0.kind != .folder && !$0.relativePath.hasPrefix(".dreft/") }
            .map(VaultFile.init(file:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func filtered(_ files: [VaultFile], matching query: String) -> [VaultFile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return files }
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.relativePath.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

enum WorkspaceFileItem: Identifiable, Hashable {
    case vault(VaultFile)

    var id: String {
        switch self {
        case .vault(let file): file.name
        }
    }

    var name: String {
        switch self {
        case .vault(let file): file.name
        }
    }

    var badge: String {
        switch self {
        case .vault(let file): file.badge
        }
    }
}

extension WorkspaceFileItem {
    static let sampleFiles: [WorkspaceFileItem] = [
        .vault(VaultFile(name: "_ (33)", badge: "JPEG", kind: .image)),
        .vault(VaultFile(name: "characters", badge: "CANVAS", kind: .canvas)),
        .vault(VaultFile(name: "Suo (@SuonikoArt) on X", badge: "JPEG", kind: .image)),
        .vault(VaultFile(name: "Suo (@SuonikoArt) on X 1", badge: "JPEG", kind: .image)),
    ]
}

extension VaultFile {
    static let sampleVault: [VaultFile] = [
        VaultFile(name: "Untitled.canvas", badge: "CANVAS"),
        VaultFile(name: "Suo (@SuonikoArt) on X.jpeg", badge: "JPEG"),
        VaultFile(name: "Suo (@SuonikoArt) on X 1.jpeg", badge: "JPEG"),
        VaultFile(name: "Welcome.md", badge: "MD"),
        VaultFile(name: "Daily note.md", badge: "MD"),
    ]
}
