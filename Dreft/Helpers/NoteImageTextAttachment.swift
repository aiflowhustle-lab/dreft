import CoreGraphics
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Inline canvas note image rendered by TextKit at exact bounds (no overlay guesswork).
final class NoteImageTextAttachment: NSTextAttachment {
    let vaultPath: String

    #if canImport(UIKit)
    init(vaultPath: String, cgImage: CGImage, size: CGSize) {
        self.vaultPath = vaultPath
        super.init(data: nil, ofType: nil)
        let scale = UIScreen.main.scale
        image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        var rect = bounds
        guard rect.width > 0, rect.height > 0 else { return rect }

        if rect.width > lineFrag.width, lineFrag.width > 0 {
            let scale = rect.height / rect.width
            rect.size.width = lineFrag.width
            rect.size.height = lineFrag.width * scale
        }

        let font = UIFont.systemFont(ofSize: WikilinkEditorSupport.bodyFontSize)
        rect.origin.y = font.descender - rect.height * 0.02
        return rect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    #elseif canImport(AppKit)
    init(vaultPath: String, cgImage: CGImage, size: CGSize) {
        self.vaultPath = vaultPath
        super.init(data: nil, ofType: nil)
        image = NSImage(cgImage: cgImage, size: NSSize(width: size.width, height: size.height))
        bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    #endif
}

enum NoteImageEmbedAttributedSupport {
    static func usesInlineAttachments(
        hideResolvedImageEmbeds: Bool,
        vaultURL: URL?,
        imageEmbedMaxWidth: CGFloat?
    ) -> Bool {
        hideResolvedImageEmbeds && vaultURL != nil && imageEmbedMaxWidth != nil
    }

    static func attributedString(
        from markdown: String,
        selectedRange: NSRange,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL?,
        imageEmbedMaxWidth: CGFloat,
        hideTaskListMarkers: Bool
    ) -> NSAttributedString {
        let segments = NoteCardEmbedSupport.segments(from: markdown, vaultURL: vaultURL)
        let result = NSMutableAttributedString()

        for segment in segments {
            switch segment {
            case .text(let text):
                guard !text.isEmpty else { continue }
                let styled = WikilinkEditorSupport.attributedString(
                    for: text,
                    selectedRange: NSRange(location: NSNotFound, length: 0),
                    fontSize: fontSize,
                    hiddenDelimiterOn: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: false,
                    imageEmbedMaxWidth: imageEmbedMaxWidth,
                    hideTaskListMarkers: hideTaskListMarkers
                )
                result.append(styled)
            case .image(let path):
                appendImageAttachment(
                    path: path,
                    to: result,
                    fontSize: fontSize,
                    vaultURL: vaultURL,
                    imageEmbedMaxWidth: imageEmbedMaxWidth
                )
            }
        }

        if result.length == 0 {
            return WikilinkEditorSupport.attributedString(
                for: markdown,
                selectedRange: selectedRange,
                fontSize: fontSize,
                hiddenDelimiterOn: editorBackground,
                vaultURL: vaultURL,
                hideTaskListMarkers: hideTaskListMarkers
            )
        }

        return result
    }

    static func markdown(from attributed: NSAttributedString, fallbackMarkdown: String? = nil, vaultURL: URL? = nil) -> String {
        let ns = attributed.string as NSString
        guard ns.length > 0 else { return "" }

        var markdown = ""
        markdown.reserveCapacity(ns.length)

        var fallbackEmbedIndex = 0
        let fallbackEmbeds = fallbackMarkdown.flatMap {
            NoteCardEmbedSupport.imageEmbedRanges(in: $0, vaultURL: vaultURL)
        } ?? []

        var index = 0
        while index < ns.length {
            let char = ns.substring(with: NSRange(location: index, length: 1))

            if char == "\u{FFFC}" {
                if let attachment = attributed.attribute(
                    .attachment,
                    at: index,
                    effectiveRange: nil
                ) as? NoteImageTextAttachment {
                    markdown += "![[\(attachment.vaultPath)]]"
                } else if fallbackEmbedIndex < fallbackEmbeds.count, let fallbackMarkdown {
                    let embed = fallbackEmbeds[fallbackEmbedIndex]
                    markdown += (fallbackMarkdown as NSString).substring(with: embed)
                    fallbackEmbedIndex += 1
                }
                index += 1
                continue
            }

            if let attachment = attributed.attribute(
                .attachment,
                at: index,
                effectiveRange: nil
            ) as? NoteImageTextAttachment {
                markdown += "![[\(attachment.vaultPath)]]"
                index += 1
                continue
            }

            markdown += char
            index += 1
        }

        return markdown
    }

    static func embedPaths(from attributed: NSAttributedString) -> [String] {
        var paths: [String] = []
        let ns = attributed.string as NSString
        var index = 0
        while index < ns.length {
            if let attachment = attributed.attribute(
                .attachment,
                at: index,
                effectiveRange: nil
            ) as? NoteImageTextAttachment {
                paths.append(attachment.vaultPath)
                index += 1
                continue
            }
            index += 1
        }
        return paths
    }

    static func markdownPreservingEmbeds(
        from attributed: NSAttributedString,
        previousMarkdown: String,
        vaultURL: URL?
    ) -> String {
        let extracted = markdown(
            from: attributed,
            fallbackMarkdown: previousMarkdown,
            vaultURL: vaultURL
        )
        let previousPaths = NoteCardEmbedSupport.imagePaths(from: previousMarkdown, vaultURL: vaultURL)
        let extractedPaths = NoteCardEmbedSupport.imagePaths(from: extracted, vaultURL: vaultURL)
        if !previousPaths.isEmpty, extractedPaths.isEmpty {
            return previousMarkdown
        }
        return extracted
    }

    /// Character indices occupied by inline image attachments — must not be restyled in place.
    static func inlineImageAttachmentRanges(in attributed: NSAttributedString) -> [NSRange] {
        guard attributed.length > 0 else { return [] }
        var ranges: [NSRange] = []
        let ns = attributed.string as NSString
        var index = 0
        while index < ns.length {
            if attributed.attribute(.attachment, at: index, effectiveRange: nil) is NoteImageTextAttachment {
                ranges.append(NSRange(location: index, length: 1))
                index += 1
            } else {
                index += 1
            }
        }
        return ranges
    }

    static func textRangesExcludingInlineImageAttachments(in attributed: NSAttributedString) -> [NSRange] {
        let protected = inlineImageAttachmentRanges(in: attributed)
        guard !protected.isEmpty else {
            return [NSRange(location: 0, length: attributed.length)]
        }

        var ranges: [NSRange] = []
        var cursor = 0
        for attachment in protected {
            if attachment.location > cursor {
                ranges.append(NSRange(location: cursor, length: attachment.location - cursor))
            }
            cursor = max(cursor, attachment.location + attachment.length)
        }
        if cursor < attributed.length {
            ranges.append(NSRange(location: cursor, length: attributed.length - cursor))
        }
        return ranges
    }

    static func shouldRebuildAttributedText(
        bindingMarkdown: String,
        currentAttributed: NSAttributedString,
        vaultURL: URL?
    ) -> Bool {
        let bindingPaths = NoteCardEmbedSupport.imagePaths(from: bindingMarkdown, vaultURL: vaultURL)
        let viewPaths = embedPaths(from: currentAttributed)
        if viewPaths.isEmpty, !bindingPaths.isEmpty {
            return true
        }
        if !bindingPaths.isEmpty, viewPaths.isEmpty {
            return true
        }
        return Set(bindingPaths) != Set(viewPaths)
    }

    static func attributedRange(fromMarkdownRange markdownRange: NSRange, in markdown: String, vaultURL: URL?) -> NSRange {
        guard markdownRange.location != NSNotFound else {
            return NSRange(location: NSNotFound, length: 0)
        }

        let ns = markdown as NSString
        let clamped = clamp(markdownRange, in: ns.length)
        var attributedLocation = 0
        var markdownCursor = 0
        var selectionStart = -1
        var selectionEnd = -1
        let targetStart = clamped.location
        let targetEnd = clamped.location + clamped.length

        while markdownCursor <= ns.length {
            if markdownCursor == ns.length {
                if selectionStart < 0, targetStart <= markdownCursor {
                    selectionStart = attributedLocation
                }
                if selectionEnd < 0, targetEnd <= markdownCursor {
                    selectionEnd = attributedLocation
                }
                break
            }

            if selectionStart < 0, markdownCursor >= targetStart {
                selectionStart = attributedLocation
            }

            if let embed = embedStarting(at: markdownCursor, in: markdown, vaultURL: vaultURL) {
                if markdownCursor >= targetEnd, selectionEnd < 0 {
                    selectionEnd = attributedLocation
                }

                markdownCursor = embed.location + embed.length
                attributedLocation += 1

                if markdownCursor < ns.length,
                   ns.substring(with: NSRange(location: markdownCursor, length: 1)) == "\n" {
                    if markdownCursor >= targetStart, selectionStart < 0 {
                        selectionStart = attributedLocation
                    }
                    if markdownCursor >= targetEnd, selectionEnd < 0 {
                        selectionEnd = attributedLocation + 1
                    }
                    markdownCursor += 1
                    attributedLocation += 1
                }
                continue
            }

            if markdownCursor >= targetEnd, selectionEnd < 0 {
                selectionEnd = attributedLocation
            }

            markdownCursor += 1
            attributedLocation += 1
        }

        if selectionStart < 0 { selectionStart = attributedLocation }
        if selectionEnd < 0 { selectionEnd = attributedLocation }

        return NSRange(location: selectionStart, length: max(0, selectionEnd - selectionStart))
    }

    static func markdownRange(fromAttributedRange attributedRange: NSRange, in markdown: String, vaultURL: URL?) -> NSRange {
        guard attributedRange.location != NSNotFound else {
            return NSRange(location: NSNotFound, length: 0)
        }

        let ns = markdown as NSString
        var markdownCursor = 0
        var attributedCursor = 0
        var selectionStart = -1
        var selectionEnd = -1
        let targetStart = attributedRange.location
        let targetEnd = attributedRange.location + attributedRange.length

        while markdownCursor <= ns.length {
            if markdownCursor == ns.length {
                if selectionStart < 0, targetStart <= attributedCursor {
                    selectionStart = markdownCursor
                }
                if selectionEnd < 0, targetEnd <= attributedCursor {
                    selectionEnd = markdownCursor
                }
                break
            }

            if selectionStart < 0, attributedCursor >= targetStart {
                selectionStart = markdownCursor
            }

            if let embed = embedStarting(at: markdownCursor, in: markdown, vaultURL: vaultURL) {
                if attributedCursor >= targetEnd, selectionEnd < 0 {
                    selectionEnd = markdownCursor + embed.length
                }

                markdownCursor = embed.location + embed.length
                attributedCursor += 1

                if markdownCursor < ns.length,
                   ns.substring(with: NSRange(location: markdownCursor, length: 1)) == "\n" {
                    if attributedCursor >= targetStart, selectionStart < 0 {
                        selectionStart = markdownCursor
                    }
                    if attributedCursor >= targetEnd, selectionEnd < 0 {
                        selectionEnd = markdownCursor + 1
                    }
                    markdownCursor += 1
                    attributedCursor += 1
                }
                continue
            }

            if attributedCursor >= targetEnd, selectionEnd < 0 {
                selectionEnd = markdownCursor
            }

            markdownCursor += 1
            attributedCursor += 1
        }

        if selectionStart < 0 { selectionStart = markdownCursor }
        if selectionEnd < 0 { selectionEnd = markdownCursor }

        return clamp(NSRange(location: selectionStart, length: selectionEnd - selectionStart), in: ns.length)
    }

    private static func appendImageAttachment(
        path: String,
        to result: NSMutableAttributedString,
        fontSize: CGFloat,
        vaultURL: URL?,
        imageEmbedMaxWidth: CGFloat
    ) {
        let blockSize = NoteCardInlineImageMetrics.blockAttachmentSize(
            for: path,
            vaultURL: vaultURL,
            maxWidth: imageEmbedMaxWidth
        )
        let cacheID = "note-embed|\(path)"
        let cgImage = CanvasImageCache.shared.cachedImage(forCardID: cacheID, content: path)
            ?? CanvasImageCache.shared.displayImage(forCardID: cacheID, content: path, vaultURL: vaultURL)
        if let cgImage {
            if result.length > 0,
               !result.string.hasSuffix("\n") {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes(fontSize: fontSize)))
            }
            let attachment = NoteImageTextAttachment(vaultPath: path, cgImage: cgImage, size: blockSize)
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttributes(
                blockParagraphAttributes(fontSize: fontSize),
                range: NSRange(location: 0, length: attachmentString.length)
            )
            result.append(attachmentString)
            NoteCardInlineImageMetrics.recordDisplaySize(blockSize, path: path, maxWidth: imageEmbedMaxWidth)
        } else {
            result.append(
                NSAttributedString(
                    string: "![[\(path)]]",
                    attributes: baseAttributes(fontSize: fontSize)
                )
            )
        }

        result.append(NSAttributedString(string: "\n", attributes: baseAttributes(fontSize: fontSize)))
    }

    private static func blockParagraphAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 8
        style.lineBreakMode = .byWordWrapping
        return baseAttributes(fontSize: fontSize).merging([.paragraphStyle: style]) { _, new in new }
    }

    private static func embedStarting(at location: Int, in markdown: String, vaultURL: URL?) -> NSRange? {
        NoteCardEmbedSupport.imageEmbedRanges(in: markdown, vaultURL: vaultURL)
            .first { $0.location == location }
    }

    private static func clamp(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let end = min(max(range.location + range.length, location), length)
        return NSRange(location: location, length: end - location)
    }

    private static func baseAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        #if canImport(UIKit)
        return [.font: UIFont.systemFont(ofSize: fontSize)]
        #else
        return [.font: NSFont.systemFont(ofSize: fontSize)]
        #endif
    }
}
