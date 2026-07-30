import XCTest
@testable import Dreft
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

final class NoteImageEmbedRoundTripTests: XCTestCase {
    private let assetPath = ".dreft/assets/photo.jpg"

    func testSegmentsPreserveAlias() {
        let markdown = "![[photo.jpg|My caption]]"
        let segments = NoteCardEmbedSupport.segments(from: markdown, vaultURL: nil)
        XCTAssertEqual(segments.count, 1)
        guard case .image(let path, let alias) = segments[0] else {
            return XCTFail("Expected image segment")
        }
        XCTAssertEqual(path, assetPath)
        XCTAssertEqual(alias, "My caption")
    }

    func testEmbedMarkdownIncludesAlias() {
        let markdown = NoteCardEmbedSupport.embedMarkdown(path: assetPath, alias: "Caption")
        XCTAssertEqual(markdown, "![[\(assetPath)|Caption]]")
    }

    func testMarkdownPreservingEmbedsAllowsEmptyAfterDelete() {
        let previous = "![[\(assetPath)|Caption]]\nHello"
        let empty = NSAttributedString(string: "")
        let result = NoteImageEmbedAttributedSupport.markdownPreservingEmbeds(
            from: empty,
            previousMarkdown: previous,
            vaultURL: nil
        )
        XCTAssertEqual(result, "")
    }

    func testMarkdownPreservingEmbedsSerializesRemainingAttachments() {
        let previous = "![[\(assetPath)]]"
        let attachment = NoteImageTextAttachment(
            vaultPath: assetPath,
            alias: nil,
            cgImage: Self.singlePixelImage(),
            size: CGSize(width: 10, height: 10)
        )
        let attributed = NSMutableAttributedString(attachment: attachment)
        let result = NoteImageEmbedAttributedSupport.markdownPreservingEmbeds(
            from: attributed,
            previousMarkdown: previous,
            vaultURL: nil
        )
        XCTAssertEqual(result, "![[\(assetPath)]]")
    }

    func testMarkdownPreservingEmbedsFallsBackWhenSerializationFails() {
        let previous = "![[\(assetPath)|Caption]]"
        let attributed = NSAttributedString(string: "\u{FFFC}")
        let result = NoteImageEmbedAttributedSupport.markdownPreservingEmbeds(
            from: attributed,
            previousMarkdown: previous,
            vaultURL: nil
        )
        XCTAssertEqual(result, previous)
    }

    func testShouldRebuildDetectsDuplicateEmbeds() {
        let markdown = "![[\(assetPath)]]\n![[\(assetPath)]]"
        let singleAttachment = NSMutableAttributedString(
            attachment: NoteImageTextAttachment(
                vaultPath: assetPath,
                alias: nil,
                cgImage: Self.singlePixelImage(),
                size: CGSize(width: 10, height: 10)
            )
        )
        XCTAssertTrue(
            NoteImageEmbedAttributedSupport.shouldRebuildAttributedText(
                bindingMarkdown: markdown,
                currentAttributed: singleAttachment,
                vaultURL: nil
            )
        )
    }

    func testShouldRebuildDetectsAliasChange() {
        let markdown = "![[\(assetPath)|One]]"
        let attachment = NSMutableAttributedString(
            attachment: NoteImageTextAttachment(
                vaultPath: assetPath,
                alias: "Two",
                cgImage: Self.singlePixelImage(),
                size: CGSize(width: 10, height: 10)
            )
        )
        XCTAssertTrue(
            NoteImageEmbedAttributedSupport.shouldRebuildAttributedText(
                bindingMarkdown: markdown,
                currentAttributed: attachment,
                vaultURL: nil
            )
        )
    }

    func testMarkdownFromAttachmentPreservesAlias() {
        let attachment = NoteImageTextAttachment(
            vaultPath: assetPath,
            alias: "My caption",
            cgImage: Self.singlePixelImage(),
            size: CGSize(width: 10, height: 10)
        )
        let attributed = NSMutableAttributedString(attachment: attachment)
        let markdown = NoteImageEmbedAttributedSupport.markdown(from: attributed)
        XCTAssertEqual(markdown, "![[\(assetPath)|My caption]]")
    }

    func testTextEmbedRoundTripPreservesInlineSpacing() {
        let source = "Text![[\(assetPath)]]More"
        let segments = NoteCardEmbedSupport.segments(from: source, vaultURL: nil)
        XCTAssertEqual(segments.count, 3)
        guard case .text(let leading) = segments[0],
              case .image(let path, _) = segments[1],
              case .text(let trailing) = segments[2] else {
            return XCTFail("Unexpected segment layout")
        }
        XCTAssertEqual(leading, "Text")
        XCTAssertEqual(path, assetPath)
        XCTAssertEqual(trailing, "More")
    }

    func testSanitizeEmbedSpacingIsIdempotent() {
        let source = "Hello\n\n![[\(assetPath)]]\n\nWorld"
        let first = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(in: source, vaultURL: nil)
        let second = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(in: first, vaultURL: nil)
        XCTAssertEqual(first, second)
    }

    func testSanitizeEmbedSpacingPreservesCaretWithEmoji() {
        let source = "Hello 👋\n![[\(assetPath)]]\n"
        let cursor = (source as NSString).length
        let sanitized = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
            in: source,
            vaultURL: nil,
            selectedRange: NSRange(location: cursor, length: 0)
        )
        XCTAssertNotNil(sanitized.selectedRange)
        XCTAssertLessThanOrEqual(
            (sanitized.selectedRange?.location ?? 0) + (sanitized.selectedRange?.length ?? 0),
            (sanitized.text as NSString).length
        )
    }

    private static func singlePixelImage() -> CGImage {
        var pixel: UInt32 = 0xFF_FF_FF_FF
        let provider = CGDataProvider(data: Data(bytes: &pixel, count: 4) as CFData)!
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
