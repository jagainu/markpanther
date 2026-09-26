import AppKit
import MarkPantherCore

/// Format メニューとツールバーで共有するコマンド定義。メニュー項目の tag は `all` の添字。
struct FormatItem {
    let title: String
    let command: FormatCommand
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let symbol: String?

    static let all: [FormatItem] = [
        .init(title: "Strong", command: .strong, key: "b", modifiers: .command, symbol: "bold"),
        .init(title: "Emphasize", command: .emphasis, key: "i", modifiers: .command, symbol: "italic"),
        .init(title: "Underline", command: .underline, key: "u", modifiers: .command, symbol: "underline"),
        .init(title: "Strikethrough", command: .strikethrough, key: "-", modifiers: [.command, .option], symbol: "strikethrough"),
        .init(title: "Highlight", command: .highlight, key: "=", modifiers: [.command, .option], symbol: "highlighter"),
        .init(title: "Inline Code", command: .inlineCode, key: "k", modifiers: .command, symbol: "chevron.left.forwardslash.chevron.right"),
        .init(title: "Link", command: .link, key: "k", modifiers: [.command, .shift], symbol: "link"),
        .init(title: "Image", command: .image, key: "i", modifiers: [.command, .shift], symbol: "photo"),
        .init(title: "Header 1", command: .heading(1), key: "1", modifiers: .command, symbol: nil),
        .init(title: "Header 2", command: .heading(2), key: "2", modifiers: .command, symbol: nil),
        .init(title: "Header 3", command: .heading(3), key: "3", modifiers: .command, symbol: nil),
        .init(title: "Header 4", command: .heading(4), key: "4", modifiers: .command, symbol: nil),
        .init(title: "Header 5", command: .heading(5), key: "5", modifiers: .command, symbol: nil),
        .init(title: "Header 6", command: .heading(6), key: "6", modifiers: .command, symbol: nil),
        .init(title: "Unordered List", command: .unorderedList, key: "u", modifiers: [.command, .shift], symbol: "list.bullet"),
        .init(title: "Ordered List", command: .orderedList, key: "o", modifiers: [.command, .shift], symbol: "list.number"),
        .init(title: "Blockquote", command: .blockquote, key: "b", modifiers: [.command, .shift], symbol: "text.quote"),
        .init(title: "Comment", command: .comment, key: "/", modifiers: .command, symbol: nil),
        .init(title: "Shift Left", command: .shiftLeft, key: "[", modifiers: .command, symbol: "decrease.indent"),
        .init(title: "Shift Right", command: .shiftRight, key: "]", modifiers: .command, symbol: "increase.indent"),
    ]

    /// メニュー内でセパレータを入れる位置（この添字の前）
    static let separatorsBefore: Set<Int> = [8, 14, 17, 18]
}

@MainActor
enum MainMenu {
    static func build(recentMenu: NSMenu) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu(recentMenu: recentMenu)))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(formatMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = "MarkPanther"
        let menu = NSMenu(title: name)
        menu.addItem(item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showPreferences(_:)), ","))
        menu.addItem(.separator())
        menu.addItem(item("Install \u{2018}markp\u{2019} Command Line Tool…",
                          #selector(AppDelegate.installCommandLineTool(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(recentMenu: NSMenu) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(AppDelegate.newDocument(_:)), "n"))
        // ⌘O は「直近から選ぶ」に充てる。従来のファイル選択ダイアログは ⌥⌘O へ
        // （⇧⌘O は Ordered List で埋まっている）
        menu.addItem(item("Open Recent…", #selector(AppDelegate.quickOpen(_:)), "o"))
        menu.addItem(item("Open File…", #selector(AppDelegate.openDocument(_:)), "o", [.command, .option]))
        menu.addItem(submenu(recentMenu))
        menu.addItem(item("Open Latest Claude Plan", #selector(AppDelegate.openLatestPlan(_:)), "l", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(DocumentWindowController.saveDocument(_:)), "s"))
        menu.addItem(item("Save As…", #selector(DocumentWindowController.saveDocumentAs(_:)), "s", [.command, .shift]))
        menu.addItem(.separator())
        let export = NSMenu(title: "Export")
        export.addItem(item("HTML…", #selector(DocumentWindowController.exportHTML(_:)), "e", [.command, .option]))
        export.addItem(item("PDF…", #selector(DocumentWindowController.exportPDF(_:)), "p", [.command, .option]))
        menu.addItem(submenu(export))
        menu.addItem(.separator())
        menu.addItem(item("Print…", #selector(DocumentWindowController.printDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        // エディタ/プレビューのどちらが前面でも効くよう、ウィンドウコントローラ経由で振り分ける
        let findAction = #selector(DocumentWindowController.performFind(_:))
        find.addItem(item("Find…", findAction, "f", tag: Int(NSTextFinder.Action.showFindInterface.rawValue)))
        find.addItem(item("Find and Replace…", findAction, "f", [.command, .option], tag: Int(NSTextFinder.Action.showReplaceInterface.rawValue)))
        find.addItem(item("Find Next", findAction, "g", tag: Int(NSTextFinder.Action.nextMatch.rawValue)))
        find.addItem(item("Find Previous", findAction, "g", [.command, .shift], tag: Int(NSTextFinder.Action.previousMatch.rawValue)))
        find.addItem(item("Use Selection for Find", findAction, tag: Int(NSTextFinder.Action.setSearchString.rawValue)))
        find.addItem(item("Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j"))
        menu.addItem(submenu(find))

        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"))
        spelling.addItem(item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"))
        spelling.addItem(.separator())
        spelling.addItem(item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))))
        spelling.addItem(item("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:))))
        spelling.addItem(item("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))))
        menu.addItem(submenu(spelling))

        let subs = NSMenu(title: "Substitutions")
        subs.addItem(item("Smart Copy/Paste", #selector(NSTextView.toggleSmartInsertDelete(_:))))
        subs.addItem(item("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))))
        subs.addItem(item("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:))))
        subs.addItem(item("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:))))
        menu.addItem(submenu(subs))

        let transform = NSMenu(title: "Transformations")
        transform.addItem(item("Make Upper Case", #selector(NSResponder.uppercaseWord(_:))))
        transform.addItem(item("Make Lower Case", #selector(NSResponder.lowercaseWord(_:))))
        transform.addItem(item("Capitalize", #selector(NSResponder.capitalizeWord(_:))))
        menu.addItem(submenu(transform))
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        for (index, format) in FormatItem.all.enumerated() {
            if FormatItem.separatorsBefore.contains(index) { menu.addItem(.separator()) }
            menu.addItem(item(format.title, #selector(DocumentWindowController.performFormat(_:)),
                              format.key, format.modifiers, tag: index))
        }
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Toggle Editor / Preview", #selector(DocumentWindowController.toggleMode(_:)), "e"))
        menu.addItem(item("Reload from Disk", #selector(DocumentWindowController.reloadFromDisk(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Show Outline", #selector(DocumentWindowController.toggleOutline(_:)), "s", [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "+"))
        menu.addItem(item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(DocumentWindowController.zoomReset(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Copy HTML", #selector(DocumentWindowController.copyHTML(_:)), "c", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option]))
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
