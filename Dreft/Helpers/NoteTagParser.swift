import Foundation

/// Obsidian-style `#tags` and YAML frontmatter `tags:` extraction from notes.
enum NoteTagParser {
    private static let inlineTagPattern = #"(?<![\w/])#([a-zA-Z][\w/-]*)"#

    static func tags(in content: String) -> Set<String> {
        var found = Set<String>()
        for tag in frontmatterTags(in: content) {
            found.insert(normalize(tag))
        }
        for tag in inlineTags(in: searchableBody(in: content)) {
            found.insert(tag)
        }
        return found
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }

    private static func searchableBody(in content: String) -> String {
        guard content.hasPrefix("---") else { return stripFencedCodeBlocks(from: content) }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3 else { return stripFencedCodeBlocks(from: content) }

        var endIndex: Int?
        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = index
                break
            }
        }
        guard let endIndex else { return stripFencedCodeBlocks(from: content) }
        let body = lines[(endIndex + 1)...].joined(separator: "\n")
        return stripFencedCodeBlocks(from: body)
    }

    private static func frontmatterTags(in content: String) -> [String] {
        guard content.hasPrefix("---") else { return [] }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3 else { return [] }

        var tags: [String] = []
        var inFrontmatter = false
        var collectingList = false

        for lineSub in lines.dropFirst() {
            let line = String(lineSub)
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }

            if collectingList {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    tags.append(String(trimmed.dropFirst(2)))
                    continue
                }
                if trimmed.isEmpty { continue }
                collectingList = false
            }

            let lower = line.lowercased()
            if lower.hasPrefix("tags:") {
                let value = line.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
                if value.isEmpty {
                    collectingList = true
                } else if value.hasPrefix("[") && value.hasSuffix("]") {
                    let inner = value.dropFirst().dropLast()
                    tags.append(contentsOf: splitTagList(String(inner)))
                } else {
                    tags.append(contentsOf: splitTagList(String(value)))
                }
            }
            inFrontmatter = true
            if inFrontmatter, line.contains(":"), !lower.hasPrefix("tags:") {
                collectingList = false
            }
        }

        return tags
    }

    private static func splitTagList(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func inlineTags(in content: String) -> Set<String> {
        guard !content.isEmpty,
              let regex = try? NSRegularExpression(pattern: inlineTagPattern) else {
            return []
        }

        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        var tags = Set<String>()

        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let raw = nsContent.substring(with: match.range(at: 1))
            let normalized = normalize(raw)
            guard !normalized.isEmpty else { return }
            tags.insert(normalized)
        }

        return tags
    }

    private static func stripFencedCodeBlocks(from content: String) -> String {
        content.replacingOccurrences(
            of: #"```[^\n]*\n[\s\S]*?\n```"#,
            with: "\n",
            options: .regularExpression
        )
    }
}

struct VaultTagRecord: Identifiable, Equatable {
    let tag: String
    let fileIDs: [String]

    var id: String { tag }
    var count: Int { fileIDs.count }
}

enum VaultTagIndex {
    static func records(from files: [WorkspaceFileEntry]) -> [VaultTagRecord] {
        var byTag: [String: Set<String>] = [:]

        for file in files where file.kind == .note {
            for tag in NoteTagParser.tags(in: file.noteContent) {
                byTag[tag, default: []].insert(file.id)
            }
        }

        return byTag
            .map { VaultTagRecord(tag: $0.key, fileIDs: Array($0.value).sorted()) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending
            }
    }

    static func files(withTag tag: String, in files: [WorkspaceFileEntry], matchCase: Bool = false) -> [WorkspaceFileEntry] {
        let normalized = NoteTagParser.normalize(tag)
        guard !normalized.isEmpty else { return [] }

        return files.filter { file in
            guard file.kind == .note else { return false }
            let tags = NoteTagParser.tags(in: file.noteContent)
            if matchCase {
                return tags.contains { $0 == normalized }
            }
            return tags.contains { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        }
    }

    static func tags(for file: WorkspaceFileEntry) -> [String] {
        guard file.kind == .note else { return [] }
        return NoteTagParser.tags(in: file.noteContent).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
