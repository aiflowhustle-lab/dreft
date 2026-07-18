import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum NoteEditingMenuBuilder {
    static var formatActions: [MarkdownEditAction] {
        [.bold, .italic, .strikethrough, .highlight, .inlineCode, .clearFormatting]
    }

    static var paragraphActions: [MarkdownEditAction] {
        [.bulletList, .numberedList, .taskList, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6, .body, .quote]
    }

    static var insertActions: [MarkdownEditAction] {
        [.wikilink, .externalLink, .codeBlock, .horizontalRule, .callout]
    }

    #if os(macOS)
    static func configure(menu: inout NSMenu, target: AnyObject?, action: Selector) {
        let insertIndex = 0
        let formatItem = submenuItem(title: "Format", actions: formatActions, target: target, action: action)
        let paragraphItem = submenuItem(title: "Paragraph", actions: paragraphActions, target: target, action: action)
        let insertItem = submenuItem(title: "Insert", actions: insertActions, target: target, action: action)

        menu.insertItem(formatItem, at: insertIndex)
        menu.insertItem(paragraphItem, at: insertIndex + 1)
        menu.insertItem(insertItem, at: insertIndex + 2)
        menu.insertItem(.separator(), at: insertIndex + 3)
    }

    private static func submenuItem(
        title: String,
        actions: [MarkdownEditAction],
        target: AnyObject?,
        action: Selector
    ) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        for editAction in actions {
            let item = NSMenuItem(title: editAction.menuTitle, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = editAction.rawValue
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
    #elseif os(iOS)
    static func editingMenus(handler: @escaping (MarkdownEditAction) -> Void) -> [UIMenu] {
        [
            submenu(title: "Format", actions: formatActions, handler: handler),
            submenu(title: "Paragraph", actions: paragraphActions, handler: handler),
            submenu(title: "Insert", actions: insertActions, handler: handler),
        ]
    }

    private static func submenu(
        title: String,
        actions: [MarkdownEditAction],
        handler: @escaping (MarkdownEditAction) -> Void
    ) -> UIMenu {
        UIMenu(
            title: title,
            children: actions.map { editAction in
                UIAction(title: editAction.menuTitle) { _ in handler(editAction) }
            }
        )
    }
    #endif
}
