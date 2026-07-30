import CoreGraphics
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum NoteCardFlowRow: Identifiable {
    case text(String)
    case inline(text: String, imagePath: String)
    case image(path: String)
    case verticalWhitespace(height: CGFloat)

    var id: String {
        switch self {
        case .text(let value):
            return "text-\(value.hashValue)"
        case .inline(let text, let path):
            return "inline-\(text.hashValue)-\(path.hashValue)"
        case .image(let path):
            return "image-\(path.hashValue)"
        case .verticalWhitespace(let height):
            return "whitespace-\(height.hashValue)"
        }
    }
}

struct NoteCardImagePlacement: Identifiable {
    let id: String
    let path: String
    let origin: CGPoint
}

enum NoteCardContentLayout {
    static let inlineSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 6

    static func flowRows(
        from segments: [NoteCardContentSegment],
        maxWidth: CGFloat,
        fontSize: CGFloat,
        imageWidthForPath: (String) -> CGFloat
    ) -> [NoteCardFlowRow] {
        var rows: [NoteCardFlowRow] = []
        var index = 0
        var previousWasImage = false

        while index < segments.count {
            guard case .text(let text) = segments[index] else {
                if case .image(let path, _) = segments[index] {
                    rows.append(.image(path: path))
                    previousWasImage = true
                }
                index += 1
                continue
            }

            if index + 1 < segments.count, case .image(let path, _) = segments[index + 1] {
                let split = splitTextBeforeEmbed(text)
                if split.endsWithLineBreak {
                    let displayText = trailingNewlineTrimmed(split.fullText)
                    if !displayText.isEmpty {
                        rows.append(.text(displayText))
                    } else {
                        let whitespaceHeight = whitespaceNewlineHeight(split.fullText, fontSize: fontSize)
                        if whitespaceHeight > 0 {
                            rows.append(.verticalWhitespace(height: whitespaceHeight))
                        }
                    }
                    rows.append(.image(path: path))
                    previousWasImage = true
                    index += 2
                    continue
                }

                let lastLine = split.lastLine
                let prefix = split.prefix
                let imageWidth = imageWidthForPath(path)
                let lastLineWidth = textWidth(lastLine, fontSize: fontSize)
                let fitsInline = !lastLine.isEmpty
                    && lastLineWidth + inlineSpacing + imageWidth <= maxWidth

                if fitsInline {
                    if !prefix.isEmpty {
                        rows.append(.text(prefix))
                    }
                    rows.append(.inline(text: lastLine, imagePath: path))
                    previousWasImage = true
                    index += 2
                    continue
                }

                rows.append(.text(text))
                rows.append(.image(path: path))
                previousWasImage = true
                index += 2
                continue
            }

            var displayText = text
            if previousWasImage {
                displayText = String(text.drop(while: { $0 == "\n" }))
            }
            if !displayText.isEmpty {
                rows.append(.text(displayText))
            }
            previousWasImage = false
            index += 1
        }

        return rows
    }

    static func imagePlacements(
        from segments: [NoteCardContentSegment],
        maxWidth: CGFloat,
        fontSize: CGFloat,
        imageSizeForPath: (String) -> CGSize
    ) -> [NoteCardImagePlacement] {
        let rows = flowRows(
            from: segments,
            maxWidth: maxWidth,
            fontSize: fontSize,
            imageWidthForPath: { path in imageSizeForPath(path).width }
        )

        var placements: [NoteCardImagePlacement] = []
        var y: CGFloat = 0

        for row in rows {
            switch row {
            case .text(let value):
                y += textBlockHeight(value, maxWidth: maxWidth, fontSize: fontSize)
                if !value.hasSuffix("\n") {
                    y += rowSpacing
                }
            case .verticalWhitespace(let height):
                y += height
            case .inline(let text, let path):
                let imageSize = imageSizeForPath(path)
                let x = textWidth(text, fontSize: fontSize) + inlineSpacing
                placements.append(
                    NoteCardImagePlacement(
                        id: "placement-\(path.hashValue)-\(placements.count)",
                        path: path,
                        origin: CGPoint(x: x, y: y)
                    )
                )
                y += max(singleLineHeight(fontSize: fontSize), imageSize.height) + rowSpacing
            case .image(let path):
                placements.append(
                    NoteCardImagePlacement(
                        id: "placement-\(path.hashValue)-\(placements.count)",
                        path: path,
                        origin: CGPoint(x: 0, y: y)
                    )
                )
                y += imageSizeForPath(path).height + rowSpacing
            }
        }

        return placements
    }

    /// Total height of rendered note body (text + inline images) at `maxWidth`.
    static func requiredBodyHeight(
        content: String,
        vaultURL: URL?,
        maxWidth: CGFloat,
        fontSize: CGFloat = CanvasConstants.noteCardFontSize,
        imageSizeForPath: (String) -> CGSize
    ) -> CGFloat {
        let segments = NoteCardEmbedSupport.segments(from: content, vaultURL: vaultURL)
        let rows = flowRows(
            from: segments,
            maxWidth: maxWidth,
            fontSize: fontSize,
            imageWidthForPath: { imageSizeForPath($0).width }
        )
        guard !rows.isEmpty else {
            return singleLineHeight(fontSize: fontSize)
        }

        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            switch row {
            case .text(let value):
                height += textBlockHeight(value, maxWidth: maxWidth, fontSize: fontSize)
            case .verticalWhitespace(let whitespaceHeight):
                height += whitespaceHeight
            case .inline(_, let path):
                height += max(singleLineHeight(fontSize: fontSize), imageSizeForPath(path).height)
            case .image(let path):
                height += imageSizeForPath(path).height
            }
            if index < rows.count - 1 {
                height += rowSpacing
            }
        }
        return height
    }

    static let contentHorizontalPadding: CGFloat = 16
    static let contentVerticalPadding: CGFloat = 16

    static func requiredCardHeight(
        content: String,
        vaultURL: URL?,
        cardWidth: CGFloat,
        fontSize: CGFloat = CanvasConstants.noteCardFontSize,
        imageSizeForPath: (String) -> CGSize,
        minimumHeight: CGFloat = CanvasConstants.compactNoteHeight
    ) -> CGFloat {
        let innerWidth = max(1, cardWidth - contentHorizontalPadding)
        let bodyHeight = requiredBodyHeight(
            content: content,
            vaultURL: vaultURL,
            maxWidth: innerWidth,
            fontSize: fontSize,
            imageSizeForPath: imageSizeForPath
        )
        return max(minimumHeight, ceil(bodyHeight + contentVerticalPadding))
    }

    static func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
        #endif
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func singleLineHeight(fontSize: CGFloat) -> CGFloat {
        ceil(fontSize * 1.35)
    }

    static func textBlockHeight(_ text: String, maxWidth: CGFloat, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
        #endif
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return max(singleLineHeight(fontSize: fontSize), ceil(rect.height))
    }

    private struct TextBeforeEmbedSplit {
        var prefix: String
        var lastLine: String
        var fullText: String
        var endsWithLineBreak: Bool
    }

    private static func splitTextBeforeEmbed(_ text: String) -> TextBeforeEmbedSplit {
        if text.hasSuffix("\n") {
            return TextBeforeEmbedSplit(
                prefix: text,
                lastLine: "",
                fullText: text,
                endsWithLineBreak: true
            )
        }

        guard let newlineIndex = text.lastIndex(of: "\n") else {
            return TextBeforeEmbedSplit(
                prefix: "",
                lastLine: text,
                fullText: text,
                endsWithLineBreak: false
            )
        }

        let afterNewline = text[text.index(after: newlineIndex)...]
        return TextBeforeEmbedSplit(
            prefix: String(text[..<text.index(after: newlineIndex)]),
            lastLine: String(afterNewline),
            fullText: text,
            endsWithLineBreak: false
        )
    }

    /// Trailing newline before an image lives in markdown only — not as visible empty text line.
    private static func trailingNewlineTrimmed(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// Height of newline-only text the editor still lays out before an image embed.
    private static func whitespaceNewlineHeight(_ text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty, text.allSatisfy(\.isWhitespace) else { return 0 }
        let newlineCount = text.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        return CGFloat(newlineCount) * singleLineHeight(fontSize: fontSize)
    }
}
