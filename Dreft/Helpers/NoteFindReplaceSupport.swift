import Foundation

struct NoteFindReplaceOptions: OptionSet, Equatable {
    let rawValue: Int

    static let caseInsensitive = NoteFindReplaceOptions(rawValue: 1 << 0)
}

enum NoteFindReplaceSupport {
    static func ranges(
        of query: String,
        in text: String,
        options: NoteFindReplaceOptions = []
    ) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        let ns = text as NSString
        guard ns.length > 0 else { return [] }

        let compareOptions: NSString.CompareOptions = options.contains(.caseInsensitive) ? .caseInsensitive : []
        var matches: [NSRange] = []
        var searchLocation = 0

        while searchLocation < ns.length {
            let searchRange = NSRange(location: searchLocation, length: ns.length - searchLocation)
            let found = ns.range(of: query, options: compareOptions, range: searchRange)
            guard found.location != NSNotFound else { break }
            matches.append(found)
            searchLocation = found.location + max(found.length, 1)
        }

        return matches
    }

    static func matchCount(
        of query: String,
        in text: String,
        options: NoteFindReplaceOptions = []
    ) -> Int {
        ranges(of: query, in: text, options: options).count
    }

    static func findNext(
        in text: String,
        query: String,
        after location: Int,
        wrap: Bool = true,
        options: NoteFindReplaceOptions = []
    ) -> NSRange? {
        let matches = ranges(of: query, in: text, options: options)
        guard !matches.isEmpty else { return nil }

        let pivot = min(max(0, location), (text as NSString).length)
        if let next = matches.first(where: { $0.location >= pivot }) {
            return next
        }
        return wrap ? matches.first : nil
    }

    static func findPrevious(
        in text: String,
        query: String,
        before location: Int,
        wrap: Bool = true,
        options: NoteFindReplaceOptions = []
    ) -> NSRange? {
        let matches = ranges(of: query, in: text, options: options)
        guard !matches.isEmpty else { return nil }

        let pivot = min(max(0, location), (text as NSString).length)
        if let previous = matches.last(where: { $0.location < pivot }) {
            return previous
        }
        return wrap ? matches.last : nil
    }

    static func matchOrdinal(
        for range: NSRange,
        query: String,
        in text: String,
        options: NoteFindReplaceOptions = []
    ) -> (index: Int, total: Int)? {
        let matches = ranges(of: query, in: text, options: options)
        guard !matches.isEmpty else { return nil }
        guard let index = matches.firstIndex(where: { NSEqualRanges($0, range) }) else { return nil }
        return (index + 1, matches.count)
    }

    static func selectionMatchesQuery(
        _ selectedRange: NSRange,
        in text: String,
        query: String,
        options: NoteFindReplaceOptions = []
    ) -> Bool {
        guard selectedRange.length > 0, !query.isEmpty else { return false }
        let ns = text as NSString
        guard selectedRange.location + selectedRange.length <= ns.length else { return false }
        let selected = ns.substring(with: selectedRange)
        if options.contains(.caseInsensitive) {
            return selected.compare(query, options: .caseInsensitive) == .orderedSame
        }
        return selected == query
    }

    static func replace(
        in text: String,
        range: NSRange,
        with replacement: String
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let updated = ns.replacingCharacters(in: clamped, with: replacement)
        let cursor = clamped.location + (replacement as NSString).length
        return (updated, NSRange(location: cursor, length: 0))
    }

    static func replaceCurrent(
        in text: String,
        query: String,
        replacement: String,
        selectedRange: NSRange,
        options: NoteFindReplaceOptions = []
    ) -> (text: String, selectedRange: NSRange)? {
        guard !query.isEmpty else { return nil }

        if selectionMatchesQuery(selectedRange, in: text, query: query, options: options) {
            return replace(in: text, range: selectedRange, with: replacement)
        }

        let searchStart = selectedRange.location + selectedRange.length
        guard let found = findNext(
            in: text,
            query: query,
            after: searchStart,
            wrap: true,
            options: options
        ) else { return nil }

        return replace(in: text, range: found, with: replacement)
    }

    static func replaceAll(
        in text: String,
        query: String,
        replacement: String,
        options: NoteFindReplaceOptions = []
    ) -> String {
        let matches = ranges(of: query, in: text, options: options)
        guard !matches.isEmpty else { return text }

        var mutable = text
        for range in matches.reversed() {
            mutable = (mutable as NSString).replacingCharacters(in: range, with: replacement)
        }
        return mutable
    }

    private static func clamp(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let end = min(max(range.location + range.length, location), length)
        return NSRange(location: location, length: end - location)
    }
}
