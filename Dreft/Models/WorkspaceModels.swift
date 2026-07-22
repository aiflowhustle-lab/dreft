import Foundation
import CoreGraphics

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

// MARK: - Nested editor splits (Obsidian-style pane tree)

/// Shell-level split axis (Obsidian-style editor groups).
enum EditorSplitAxis: Equatable {
    /// Panes side by side — Split right.
    case horizontal
    /// Panes stacked — Split down.
    case vertical
}

indirect enum EditorSplitNode: Equatable {
    case pane(String)
    case split(
        axis: EditorSplitAxis,
        ratio: CGFloat,
        first: EditorSplitNode,
        second: EditorSplitNode
    )
}

struct EditorAuxiliaryPane: Equatable {
    var tabs: [WorkspaceTab]
    var activeTabID: String
}

struct EditorPaneUIState: Equatable {
    var isReading = false
    var showFindBar = false
}

enum EditorSplitTree {
    static let rootPaneID = "root"
    static let defaultRatio: CGFloat = 0.5

    static func newPaneID() -> String {
        "p" + UUID().uuidString.prefix(8).lowercased()
    }

    static func newTabID() -> String {
        "t" + UUID().uuidString.prefix(8).lowercased()
    }

    /// Replaces `paneID` with a new split of the requested axis. Returns the new sibling pane id.
    static func splitPane(
        _ paneID: String,
        axis: EditorSplitAxis,
        in node: EditorSplitNode
    ) -> (node: EditorSplitNode, newPaneID: String)? {
        switch axis {
        case .horizontal:
            if let panes = horizontalPaneOrder(in: node), panes.contains(paneID) {
                let newID = newPaneID()
                var updated = panes
                if let index = updated.firstIndex(of: paneID) {
                    updated.insert(newID, at: index + 1)
                } else {
                    updated.append(newID)
                }
                return (buildEqualHorizontal(updated), newID)
            }
        case .vertical:
            if let panes = verticalPaneOrder(in: node), panes.contains(paneID) {
                let newID = newPaneID()
                var updated = panes
                if let index = updated.firstIndex(of: paneID) {
                    updated.insert(newID, at: index + 1)
                } else {
                    updated.append(newID)
                }
                return (buildEqualVertical(updated), newID)
            }
        }

        switch node {
        case .pane(let id) where id == paneID:
            let newID = newPaneID()
            let split: EditorSplitNode = switch axis {
            case .horizontal:
                buildEqualHorizontal([paneID, newID])
            case .vertical:
                buildEqualVertical([paneID, newID])
            }
            return (split, newID)
        case .pane:
            return nil
        case .split(let parentAxis, let ratio, let first, let second):
            if let (updatedFirst, newID) = splitPane(paneID, axis: axis, in: first) {
                return (
                    .split(axis: parentAxis, ratio: ratio, first: updatedFirst, second: second),
                    newID
                )
            }
            if let (updatedSecond, newID) = splitPane(paneID, axis: axis, in: second) {
                return (
                    .split(axis: parentAxis, ratio: ratio, first: first, second: updatedSecond),
                    newID
                )
            }
            return nil
        }
    }

    /// Rebalances same-axis split chains so every sibling pane gets equal space (Obsidian-style).
    static func normalizedEqualSplits(_ node: EditorSplitNode) -> EditorSplitNode {
        switch node {
        case .pane:
            return node
        case .split(.horizontal, _, let first, let second):
            let normalized: EditorSplitNode = .split(
                axis: .horizontal,
                ratio: defaultRatio,
                first: normalizedEqualSplits(first),
                second: normalizedEqualSplits(second)
            )
            if let panes = horizontalPaneOrder(in: normalized) {
                return buildEqualHorizontal(panes)
            }
            return normalized
        case .split(.vertical, let ratio, let first, let second):
            let normalized: EditorSplitNode = .split(
                axis: .vertical,
                ratio: ratio,
                first: normalizedEqualSplits(first),
                second: normalizedEqualSplits(second)
            )
            if let panes = verticalPaneOrder(in: normalized) {
                return buildEqualVertical(panes)
            }
            return normalized
        }
    }

    static func buildEqualHorizontal(_ panes: [String]) -> EditorSplitNode {
        guard let first = panes.first else {
            return .pane(rootPaneID)
        }
        guard panes.count > 1 else {
            return .pane(first)
        }
        let ratio = 1 / CGFloat(panes.count)
        return .split(
            axis: .horizontal,
            ratio: ratio,
            first: .pane(first),
            second: buildEqualHorizontal(Array(panes.dropFirst()))
        )
    }

    static func buildEqualVertical(_ panes: [String]) -> EditorSplitNode {
        guard let first = panes.first else {
            return .pane(rootPaneID)
        }
        guard panes.count > 1 else {
            return .pane(first)
        }
        let ratio = 1 / CGFloat(panes.count)
        return .split(
            axis: .vertical,
            ratio: ratio,
            first: .pane(first),
            second: buildEqualVertical(Array(panes.dropFirst()))
        )
    }

    static func horizontalPaneOrder(in node: EditorSplitNode) -> [String]? {
        switch node {
        case .pane(let id):
            return [id]
        case .split(.horizontal, _, let first, let second):
            guard let left = horizontalPaneOrder(in: first),
                  let right = horizontalPaneOrder(in: second) else { return nil }
            return left + right
        case .split(.vertical, _, _, _):
            return nil
        }
    }

    static func verticalPaneOrder(in node: EditorSplitNode) -> [String]? {
        switch node {
        case .pane(let id):
            return [id]
        case .split(.vertical, _, let first, let second):
            guard let top = verticalPaneOrder(in: first),
                  let bottom = verticalPaneOrder(in: second) else { return nil }
            return top + bottom
        case .split(.horizontal, _, _, _):
            return nil
        }
    }

    /// Removes a pane and collapses its parent split when possible.
    static func removePane(_ paneID: String, from node: EditorSplitNode) -> EditorSplitNode? {
        switch node {
        case .pane(let id):
            return id == paneID ? nil : node
        case .split(let axis, let ratio, let first, let second):
            let prunedFirst = removePane(paneID, from: first)
            let prunedSecond = removePane(paneID, from: second)
            let collapsed: EditorSplitNode? = switch (prunedFirst, prunedSecond) {
            case (nil, nil):
                nil
            case (nil, let sibling?):
                sibling
            case (let sibling?, nil):
                sibling
            case (let left?, let right?):
                .split(axis: axis, ratio: ratio, first: left, second: right)
            }
            guard let collapsed else { return nil }
            return normalizedEqualSplits(collapsed)
        }
    }

    static func leftmostPane(in node: EditorSplitNode) -> String? {
        switch node {
        case .pane(let id):
            return id
        case .split(.horizontal, _, let first, let second):
            return leftmostPane(in: first) ?? leftmostPane(in: second)
        case .split(.vertical, _, let first, let second):
            return leftmostPane(in: first) ?? leftmostPane(in: second)
        }
    }

    /// Right-edge pane that should show the right-sidebar tab-bar toggle (top-right in grids).
    static func rightmostPaneForChrome(in node: EditorSplitNode) -> String? {
        switch node {
        case .pane(let id):
            return id
        case .split(.horizontal, _, let first, let second):
            return rightmostPaneForChrome(in: second) ?? rightmostPaneForChrome(in: first)
        case .split(.vertical, _, let first, let second):
            return rightmostPaneForChrome(in: first) ?? rightmostPaneForChrome(in: second)
        }
    }

    /// Whether the right-sidebar toggle should appear on this pane's tab bar.
    static func paneShowsRightSidebarChrome(_ paneID: String, in splitRoot: EditorSplitNode?) -> Bool {
        guard let splitRoot else { return true }
        return rightmostPaneForChrome(in: splitRoot) == paneID
    }

    /// Whether the left-sidebar toggle belongs on this pane's tab bar.
    static func paneShowsLeftSidebarChrome(_ paneID: String, in splitRoot: EditorSplitNode?) -> Bool {
        guard let splitRoot else { return paneID == rootPaneID }
        return leftmostPane(in: splitRoot) == paneID
    }

    static func allPaneIDs(in node: EditorSplitNode) -> [String] {
        switch node {
        case .pane(let id):
            return [id]
        case .split(_, _, let first, let second):
            return allPaneIDs(in: first) + allPaneIDs(in: second)
        }
    }
}
