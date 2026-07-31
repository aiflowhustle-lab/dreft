import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

struct NoteCardTaskCheckboxPlacement: Identifiable, Equatable {
    let lineIndex: Int
    let rawLine: String
    let origin: CGPoint

    var id: String { "\(lineIndex)-\(rawLine.hashValue)" }
}

enum NoteCardTextLine: Identifiable, Equatable {
    case plain(String)
    case task(checked: Bool, text: String, rawLine: String)

    var id: String {
        switch self {
        case .plain(let value):
            return "plain-\(value.hashValue)"
        case .task(let checked, _, let rawLine):
            return "task-\(checked)-\(rawLine.hashValue)"
        }
    }
}

enum NoteCardTaskSupport {
    private static let taskLinePattern = #"^\s*[-*+]\s+\[([ xX])\]\s+(.*)$"#

    private struct TaskLineMatch {
        let mark: String
        let prefixEnd: Int
        let body: String
    }

    private static func parseTaskLineMatch(in line: String) -> TaskLineMatch? {
        guard let regex = try? NSRegularExpression(pattern: taskLinePattern) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
              match.numberOfRanges >= 3 else { return nil }

        let markRange = match.range(at: 1)
        let bodyRange = match.range(at: 2)
        guard markRange.location != NSNotFound, bodyRange.location != NSNotFound else { return nil }

        return TaskLineMatch(
            mark: nsLine.substring(with: markRange),
            prefixEnd: bodyRange.location,
            body: nsLine.substring(with: bodyRange)
        )
    }

    static let checkboxWidth: CGFloat = 14
    static let checkboxSpacing: CGFloat = 8

    static func scaledCheckboxWidth(fontSize: CGFloat) -> CGFloat {
        checkboxWidth * (fontSize / CanvasConstants.noteCardFontSize)
    }

    /// Matches `CanvasNoteCardBodyView` firstTextBaseline alignment for the checkbox column.
    static func checkboxBaselineAlignmentOffset(fontSize: CGFloat) -> CGFloat {
        max(2, fontSize * 0.12) + 1
    }

    /// Leading inset for task body text when the markdown prefix is hidden (checkbox column + gap).
    static func lineLeadingInset(fontSize: CGFloat = CanvasConstants.noteCardFontSize) -> CGFloat {
        let scale = fontSize / CanvasConstants.noteCardFontSize
        return (checkboxWidth + checkboxSpacing) * scale
    }

    static func parsedLines(from text: String) -> [NoteCardTextLine] {
        guard !text.isEmpty else { return [] }

        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [NoteCardTextLine] = []
        lines.reserveCapacity(parts.count)

        for (index, part) in parts.enumerated() {
            let line = String(part)
            if let task = parseTaskLine(line) {
                lines.append(task)
            } else if line.isEmpty && index < parts.count - 1 {
                lines.append(.plain(""))
            } else {
                lines.append(.plain(line))
            }
        }
        return lines
    }

    static func parseTaskLine(_ line: String) -> NoteCardTextLine? {
        guard let match = parseTaskLineMatch(in: line) else { return nil }
        return .task(
            checked: match.mark.lowercased() == "x",
            text: taskPreviewText(from: match.body),
            rawLine: line
        )
    }

    /// Strips redundant checkbox syntax when task body still contains `[ ]` / `[x]`.
    static func taskPreviewText(from body: String) -> String {
        var text = body
        if text.hasPrefix("[ ] ") {
            text = String(text.dropFirst(4))
        } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            text = String(text.dropFirst(4))
        }
        return text
    }

    static func toggleTask(matchingRawLine rawLine: String, in content: String) -> String? {
        let parts = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard let index = parts.firstIndex(where: { String($0) == rawLine }) else { return nil }
        return toggleTask(atLineIndex: index, in: content)
    }

    static func toggleTask(atLineIndex index: Int, in content: String) -> String? {
        let parts = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard index >= 0, index < parts.count else { return nil }
        guard parseTaskLine(String(parts[index])) != nil else { return nil }

        var location = 0
        for partIndex in 0..<index {
            location += (String(parts[partIndex]) as NSString).length + 1
        }

        let result = MarkdownEditingSupport.toggleTaskList(
            in: content,
            selectedRange: NSRange(location: location, length: 0)
        )
        return result.text
    }

    static func lineHeight(for line: NoteCardTextLine, fontSize: CGFloat, maxWidth: CGFloat) -> CGFloat {
        switch line {
        case .plain(let value):
            if value.isEmpty { return fontSize * 0.35 }
            return NoteCardContentLayout.textBlockHeight(value, maxWidth: maxWidth, fontSize: fontSize)
        case .task(_, let text, _):
            return max(
                NoteCardContentLayout.singleLineHeight(fontSize: fontSize),
                NoteCardContentLayout.textBlockHeight(
                    text,
                    maxWidth: max(1, maxWidth - lineLeadingInset(fontSize: fontSize)),
                    fontSize: fontSize
                )
            )
        }
    }

    static func checkboxOriginY(
        forLineIndex index: Int,
        lines: [NoteCardTextLine],
        fontSize: CGFloat,
        maxWidth: CGFloat
    ) -> CGFloat {
        guard index > 0 else { return 0 }
        var y: CGFloat = 0
        for lineIndex in 0..<index {
            y += lineHeight(for: lines[lineIndex], fontSize: fontSize, maxWidth: maxWidth)
            y += 4
        }
        return y
    }

    /// Raw markdown task body (`- [ ] **note**` → `**note**`).
    static func taskBodyMarkdown(in line: String) -> String? {
        parseTaskLineMatch(in: line)?.body
    }

    /// Character index where the visible task body begins (`- [ ] body` → start of `body`).
    static func taskBodyCharacterIndex(in line: String, lineStart: Int) -> Int? {
        guard let match = parseTaskLineMatch(in: line) else { return nil }
        return lineStart + match.prefixEnd
    }

    /// Positions checkboxes from the live text layout — required while editing formatted task lines.
    #if canImport(UIKit)
    static func checkboxPlacements(
        in content: String,
        textView: UITextView,
        contentScrollOffset: CGPoint,
        fontSize: CGFloat,
        editorBackground: Color = AppColors.canvasBackground,
        hideTaskListMarkers: Bool = false,
        usesWysiwygDisplay: Bool = false
    ) -> [NoteCardTaskCheckboxPlacement] {
        let ns = content as NSString
        guard ns.length > 0 else { return [] }

        var placements: [NoteCardTaskCheckboxPlacement] = []
        var lineStart = 0
        var lineIndex = 0
        let parts = content.split(separator: "\n", omittingEmptySubsequences: false)

        for part in parts {
            let line = String(part)
            if let task = parseTaskLine(line),
               case .task(_, _, let rawLine) = task {
                let anchorIndex: Int
                if usesWysiwygDisplay, hideTaskListMarkers {
                    let displaySource = MarkdownWysiwygEditingSupport.displaySourceString(
                        from: content,
                        hideTaskListMarkers: true
                    )
                    anchorIndex = MarkdownWysiwygEditingSupport.displayLineStartIndex(
                        forMarkdownLineStart: lineStart,
                        markdown: content,
                        displaySource: displaySource
                    )
                } else {
                    anchorIndex = taskBodyCharacterIndex(in: line, lineStart: lineStart) ?? lineStart
                }

                let origin = NoteEditingChromeSupport.checkboxOrigin(
                    forCharacterIndex: anchorIndex,
                    in: textView,
                    contentScrollOffset: contentScrollOffset,
                    fontSize: fontSize
                )
                placements.append(
                    NoteCardTaskCheckboxPlacement(
                        lineIndex: lineIndex,
                        rawLine: rawLine,
                        origin: origin
                    )
                )
            }
            lineStart += (line as NSString).length + 1
            lineIndex += 1
        }

        return placements
    }
    #endif
}
