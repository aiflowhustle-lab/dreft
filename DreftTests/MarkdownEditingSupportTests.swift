import XCTest
@testable import Dreft
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

final class MarkdownEditingSupportTests: XCTestCase {
    // MARK: - Inline wrap

    func testBoldWrapsSelection() {
        let result = MarkdownEditingSupport.apply(
            .bold,
            text: "hello world",
            selectedRange: NSRange(location: 0, length: 5)
        )
        XCTAssertEqual(result.text, "**hello** world")
        XCTAssertEqual(result.selectedRange, NSRange(location: 0, length: 9))
    }

    func testBoldUnwrapsWhenAlreadyWrapped() {
        let result = MarkdownEditingSupport.apply(
            .bold,
            text: "**hello**",
            selectedRange: NSRange(location: 0, length: 9)
        )
        XCTAssertEqual(result.text, "hello")
    }

    func testBoldThenItalicCombinesMarkers() {
        let bold = MarkdownEditingSupport.apply(
            .bold,
            text: "hello",
            selectedRange: NSRange(location: 0, length: 5)
        )
        XCTAssertEqual(bold.text, "**hello**")

        let both = MarkdownEditingSupport.apply(
            .italic,
            text: bold.text,
            selectedRange: bold.selectedRange
        )
        XCTAssertEqual(both.text, "***hello***")
    }

    func testBoldItalicDisplayShowsStyledTextWithoutMarkers() {
        let display = WikilinkEditorSupport.displayAttributedString(
            for: "***hello***",
            fontSize: WikilinkEditorSupport.bodyFontSize,
            hiddenDelimiterOn: AppColors.noteCardBackground
        )
        XCTAssertEqual(display.string, "hello")
    }

    func testBoldItalicAppliesBoldAndItalicFont() {
        let styled = WikilinkEditorSupport.attributedString(
            for: "***hello***",
            selectedRange: NSRange(location: NSNotFound, length: 0),
            fontSize: WikilinkEditorSupport.bodyFontSize,
            hiddenDelimiterOn: AppColors.noteCardBackground
        )
        var foundBoldItalic = false
        styled.enumerateAttribute(.font, in: NSRange(location: 3, length: 5)) { value, _, _ in
            #if canImport(AppKit)
            guard let font = value as? NSFont else { return }
            let traits = NSFontManager.shared.traits(of: font)
            foundBoldItalic = traits.contains(.boldFontMask) && traits.contains(.italicFontMask)
            #else
            guard let font = value as? UIFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            foundBoldItalic = traits.contains(.traitBold) && traits.contains(.traitItalic)
            #endif
        }
        XCTAssertTrue(foundBoldItalic)
    }

    func testItalicOnInnerSelectionAfterBoldCombinesMarkers() {
        let bold = MarkdownEditingSupport.apply(
            .bold,
            text: "hello",
            selectedRange: NSRange(location: 0, length: 5)
        )
        let both = MarkdownEditingSupport.apply(
            .italic,
            text: bold.text,
            selectedRange: NSRange(location: 2, length: 5)
        )
        XCTAssertEqual(both.text, "***hello***")
    }

    func testItalicWrapsSelection() {
        let result = MarkdownEditingSupport.apply(
            .italic,
            text: "word",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "*word*")
    }

    func testStrikethroughWrapsSelection() {
        let result = MarkdownEditingSupport.apply(
            .strikethrough,
            text: "gone",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "~~gone~~")
    }

    func testHighlightWrapsSelection() {
        let result = MarkdownEditingSupport.apply(
            .highlight,
            text: "mark",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "==mark==")
    }

    func testInlineCodeWrapsSelection() {
        let result = MarkdownEditingSupport.apply(
            .inlineCode,
            text: "fn()",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "`fn()`")
    }

    // MARK: - Headings and lists

    func testHeading1Prefix() {
        let result = MarkdownEditingSupport.apply(
            .heading1,
            text: "Title",
            selectedRange: NSRange(location: 0, length: 5)
        )
        XCTAssertEqual(result.text, "# Title")
    }

    func testBodyRemovesHeading() {
        let result = MarkdownEditingSupport.apply(
            .body,
            text: "## Subtitle",
            selectedRange: NSRange(location: 0, length: 11)
        )
        XCTAssertEqual(result.text, "Subtitle")
    }

    func testBulletListPrefix() {
        let result = MarkdownEditingSupport.apply(
            .bulletList,
            text: "Item",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "- Item")
    }

    func testNumberedListPrefix() {
        let result = MarkdownEditingSupport.apply(
            .numberedList,
            text: "Item",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "1. Item")
    }

    func testTaskListPrefix() {
        let result = MarkdownEditingSupport.apply(
            .taskList,
            text: "Todo",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "- [ ] Todo")
    }

    // MARK: - Links and inserts

    func testWikilinkWrapsSelection() {
        let result = MarkdownEditingSupport.apply(
            .wikilink,
            text: "Note",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "[[Note]]")
    }

    func testEmbedWrapsSelection() {
        let result = MarkdownEditingSupport.apply(
            .embed,
            text: "Image",
            selectedRange: NSRange(location: 0, length: 5)
        )
        XCTAssertEqual(result.text, "![[Image]]")
    }

    func testEmbedInsertsEmptyPlaceholder() {
        let result = MarkdownEditingSupport.apply(
            .embed,
            text: "hello",
            selectedRange: NSRange(location: 5, length: 0)
        )
        XCTAssertEqual(result.text, "hello![[]]")
        XCTAssertEqual(result.selectedRange, NSRange(location: 8, length: 0))
    }

    func testQuotePrefix() {
        let result = MarkdownEditingSupport.apply(
            .quote,
            text: "Quoted",
            selectedRange: NSRange(location: 0, length: 6)
        )
        XCTAssertEqual(result.text, "> Quoted")
    }

    func testBulletListToggleOff() {
        let result = MarkdownEditingSupport.apply(
            .bulletList,
            text: "- Item",
            selectedRange: NSRange(location: 0, length: 6)
        )
        XCTAssertEqual(result.text, "Item")
    }

    func testTaskListToggleOff() {
        let result = MarkdownEditingSupport.apply(
            .taskList,
            text: "- [ ] Todo",
            selectedRange: NSRange(location: 0, length: 10)
        )
        XCTAssertEqual(result.text, "Todo")
    }

    func testIndentAddsSpaces() {
        let result = MarkdownEditingSupport.apply(
            .indent,
            text: "line",
            selectedRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(result.text, "  line")
    }

    func testOutdentRemovesSpaces() {
        let result = MarkdownEditingSupport.apply(
            .outdent,
            text: "  line",
            selectedRange: NSRange(location: 0, length: 6)
        )
        XCTAssertEqual(result.text, "line")
    }

    func testTagInsertsHash() {
        let result = MarkdownEditingSupport.apply(
            .tag,
            text: "hello",
            selectedRange: NSRange(location: 5, length: 0)
        )
        XCTAssertEqual(result.text, "hello#")
    }

    func testClearFormattingRemovesBoldMarkers() {
        let result = MarkdownEditingSupport.apply(
            .clearFormatting,
            text: "**bold**",
            selectedRange: NSRange(location: 0, length: 8)
        )
        XCTAssertEqual(result.text, "bold")
    }

    func testHorizontalRuleInsertsSeparators() {
        let result = MarkdownEditingSupport.apply(
            .horizontalRule,
            text: "hello",
            selectedRange: NSRange(location: 5, length: 0)
        )
        XCTAssertEqual(result.text, "hello\n\n---\n\n")
    }

    func testCalloutInsertsNoteBlock() {
        let result = MarkdownEditingSupport.apply(
            .callout,
            text: "",
            selectedRange: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(result.text, "\n> [!note]\n> \n")
    }

    func testExternalLinkInsertsURLPlaceholder() {
        let result = MarkdownEditingSupport.apply(
            .externalLink,
            text: "label",
            selectedRange: NSRange(location: 0, length: 5)
        )
        XCTAssertEqual(result.text, "[label](https://)")
        XCTAssertEqual(result.selectedRange, NSRange(location: 7, length: 8))
    }

    func testCodeBlockInsertsFence() {
        let result = MarkdownEditingSupport.apply(
            .codeBlock,
            text: "",
            selectedRange: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(result.text, "\n```\n\n```\n")
    }

    // MARK: - Hidden delimiter layout

    func testDisplayAttributedStringStripsBoldMarkers() {
        let display = WikilinkEditorSupport.displayAttributedString(
            for: "**hello**",
            fontSize: WikilinkEditorSupport.bodyFontSize,
            hiddenDelimiterOn: AppColors.noteCardBackground
        )
        XCTAssertEqual(display.string, "hello")
    }

    func testHiddenBoldDelimitersDoNotShiftVisibleText() {
        let fontSize = WikilinkEditorSupport.bodyFontSize
        let hiddenOn = AppColors.noteCardBackground
        let noSelection = NSRange(location: NSNotFound, length: 0)

        let styledBold = WikilinkEditorSupport.attributedString(
            for: "**hello**",
            selectedRange: noSelection,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenOn
        )

        #if canImport(AppKit)
        let reference = NSMutableAttributedString(string: "hello")
        reference.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: NSRange(location: 0, length: 5))
        #else
        let reference = NSMutableAttributedString(string: "hello")
        reference.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: fontSize), range: NSRange(location: 0, length: 5))
        #endif

        let styledWidth = Self.attributedStringWidth(styledBold)
        let referenceWidth = Self.attributedStringWidth(reference)
        XCTAssertEqual(styledWidth, referenceWidth, accuracy: 2.0)
    }

    func testHiddenWikilinkBracketsDoNotShiftVisibleText() {
        let fontSize = WikilinkEditorSupport.bodyFontSize
        let hiddenOn = AppColors.noteCardBackground
        let noSelection = NSRange(location: NSNotFound, length: 0)

        let styledLink = WikilinkEditorSupport.attributedString(
            for: "[[Note]]",
            selectedRange: noSelection,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenOn
        )

        let reference = NSMutableAttributedString(string: "Note")
        #if canImport(AppKit)
        reference.addAttribute(.foregroundColor, value: NSColor(AppColors.noteLink), range: NSRange(location: 0, length: 4))
        reference.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 4))
        #else
        reference.addAttribute(.foregroundColor, value: UIColor(AppColors.noteLink), range: NSRange(location: 0, length: 4))
        reference.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 4))
        #endif

        let styledWidth = Self.attributedStringWidth(styledLink)
        let referenceWidth = Self.attributedStringWidth(reference)
        XCTAssertEqual(styledWidth, referenceWidth, accuracy: 2.0)
    }

    private static func attributedStringWidth(_ string: NSAttributedString) -> CGFloat {
        string.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width
    }
}
