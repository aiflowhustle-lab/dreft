import Foundation

enum WikilinkParser {
    /// Targets inside `[[wikilinks]]`, ignoring display aliases (`[[Note|Alias]]`).
    static func linkTargets(in content: String) -> [String] {
        guard !content.isEmpty else { return [] }

        let pattern = #"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        var targets: [String] = []
        var seen = Set<String>()

        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound else { return }
            let target = nsContent.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, seen.insert(target).inserted else { return }
            targets.append(target)
        }

        return targets
    }

    /// Resolves a wikilink target to a vault file id (relative path).
    static func resolveLinkTarget(_ target: String, in files: [WorkspaceFileEntry]) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let searchable = files.filter { $0.kind == .note || $0.kind == .canvas }

        if let exact = searchable.first(where: {
            $0.relativePath.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return exact.id
        }

        let mdCandidate = trimmed.lowercased().hasSuffix(".md") ? trimmed : "\(trimmed).md"
        if let mdMatch = searchable.first(where: {
            $0.relativePath.caseInsensitiveCompare(mdCandidate) == .orderedSame
        }) {
            return mdMatch.id
        }

        let canvasCandidate = trimmed.lowercased().hasSuffix(".canvas") ? trimmed : "\(trimmed).canvas"
        if let canvasMatch = searchable.first(where: {
            $0.relativePath.caseInsensitiveCompare(canvasCandidate) == .orderedSame
        }) {
            return canvasMatch.id
        }

        if let pathMatch = searchable.first(where: {
            ($0.relativePath as NSString).deletingPathExtension
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return pathMatch.id
        }

        let base = ((trimmed as NSString).lastPathComponent as NSString).deletingPathExtension
        let nameMatches = searchable.filter {
            $0.name.caseInsensitiveCompare(base) == .orderedSame
                || ($0.relativePath as NSString).lastPathComponent
                    .caseInsensitiveCompare((trimmed as NSString).lastPathComponent) == .orderedSame
                || normalizedName($0.name) == normalizedName(base)
                || normalizedName(($0.relativePath as NSString).deletingPathExtension)
                    == normalizedName(base)
        }

        if nameMatches.count == 1 {
            return nameMatches[0].id
        }

        let normalizedMatches = searchable.filter {
            normalizedName($0.name) == normalizedName(base)
                || normalizedName(($0.relativePath as NSString).deletingPathExtension)
                    == normalizedName(base)
        }
        if normalizedMatches.count == 1 {
            return normalizedMatches[0].id
        }

        if trimmed.contains("/") {
            return nameMatches.first(where: {
                $0.relativePath.localizedCaseInsensitiveContains(trimmed)
            })?.id
        }

        return nameMatches.first?.id ?? normalizedMatches.first?.id
    }

    /// Compares names loosely: case/spacing/hyphens/underscores ignored.
    static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { Character($0) }
            .reduce(into: String()) { $0.append($1) }
    }

    static func edges(from files: [WorkspaceFileEntry], vaultURL: URL?) -> [(fromID: String, toID: String)] {
        let index = GraphLinkIndex()
        index.rebuild(from: files, vaultURL: vaultURL)
        return index.edges.map { ($0.fromID, $0.toID) }
    }
}
