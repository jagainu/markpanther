import XCTest
@testable import MarkPantherCore

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "MarkPantherCoreTests.Preferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_defaultValues() {
        let prefs = Preferences(defaults: defaults)

        // General
        XCTAssertEqual(prefs.showWordCount, true)
        XCTAssertEqual(prefs.openUntitledOnLaunch, false)

        // Markdown
        XCTAssertEqual(prefs.smartypants, false)
        XCTAssertEqual(prefs.superscript, false)
        XCTAssertEqual(prefs.highlightMark, true)
        XCTAssertEqual(prefs.hardLineBreaks, true)
        // 既定はオフ（まこと指示 2026-09-21）。出したい人は Settings → Rendering で入れる
        XCTAssertEqual(prefs.previewLineNumbers, false)
        XCTAssertEqual(prefs.changeBand, false)

        // Appearance
        XCTAssertEqual(prefs.headerSize, .regular)
        XCTAssertEqual(prefs.sidebarTextSize, .regular)
        XCTAssertEqual(prefs.sidebarWidth, 230)

        // Editor
        XCTAssertEqual(prefs.fontName, "")
        XCTAssertEqual(prefs.fontSize, 14.0)
        XCTAssertEqual(prefs.lineSpacing, 4.0)
        XCTAssertEqual(prefs.horizontalInset, 24.0)
        XCTAssertEqual(prefs.verticalInset, 20.0)
        XCTAssertEqual(prefs.limitEditorWidth, false)
        XCTAssertEqual(prefs.editorMaxWidth, 800.0)
        XCTAssertEqual(prefs.autoCompleteBrackets, true)
        XCTAssertEqual(prefs.autoIncrementOrderedList, true)
        XCTAssertEqual(prefs.autoInsertLinePrefix, true)
        XCTAssertEqual(prefs.insertSpacesForTab, true)
        XCTAssertEqual(prefs.tabWidth, 4)
        XCTAssertEqual(prefs.scrollPastEnd, true)
        XCTAssertEqual(prefs.ensureTrailingNewline, true)
        XCTAssertEqual(prefs.listMarker, "-")

        // Rendering
        XCTAssertEqual(prefs.styleName, "GitHub")
        XCTAssertEqual(prefs.syntaxHighlighting, true)
        XCTAssertEqual(prefs.codeLineNumbers, false)
        XCTAssertEqual(prefs.math, true)
        XCTAssertEqual(prefs.frontmatter, true)
        XCTAssertEqual(prefs.tocToken, true)
        XCTAssertEqual(prefs.taskList, true)
        XCTAssertEqual(prefs.mermaid, true)
    }

    func test_roundTrip_persistsAcrossInstances() {
        let prefs = Preferences(defaults: defaults)
        prefs.showWordCount = false
        prefs.openUntitledOnLaunch = true
        prefs.smartypants = true
        prefs.superscript = true
        prefs.highlightMark = false
        prefs.hardLineBreaks = false
        prefs.fontName = "Menlo"
        prefs.fontSize = 16.5
        prefs.lineSpacing = 6.0
        prefs.horizontalInset = 32.0
        prefs.verticalInset = 12.0
        prefs.limitEditorWidth = true
        prefs.editorMaxWidth = 600.0
        prefs.autoCompleteBrackets = false
        prefs.autoIncrementOrderedList = false
        prefs.autoInsertLinePrefix = false
        prefs.insertSpacesForTab = false
        prefs.tabWidth = 2
        prefs.scrollPastEnd = false
        prefs.ensureTrailingNewline = false
        prefs.listMarker = "*"
        prefs.styleName = "Solarized"
        prefs.syntaxHighlighting = false
        prefs.codeLineNumbers = true
        prefs.math = false
        prefs.frontmatter = false
        prefs.tocToken = false
        prefs.taskList = false
        prefs.mermaid = false

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.showWordCount, false)
        XCTAssertEqual(reloaded.openUntitledOnLaunch, true)
        XCTAssertEqual(reloaded.smartypants, true)
        XCTAssertEqual(reloaded.superscript, true)
        XCTAssertEqual(reloaded.highlightMark, false)
        XCTAssertEqual(reloaded.hardLineBreaks, false)
        XCTAssertEqual(reloaded.fontName, "Menlo")
        XCTAssertEqual(reloaded.fontSize, 16.5)
        XCTAssertEqual(reloaded.lineSpacing, 6.0)
        XCTAssertEqual(reloaded.horizontalInset, 32.0)
        XCTAssertEqual(reloaded.verticalInset, 12.0)
        XCTAssertEqual(reloaded.limitEditorWidth, true)
        XCTAssertEqual(reloaded.editorMaxWidth, 600.0)
        XCTAssertEqual(reloaded.autoCompleteBrackets, false)
        XCTAssertEqual(reloaded.autoIncrementOrderedList, false)
        XCTAssertEqual(reloaded.autoInsertLinePrefix, false)
        XCTAssertEqual(reloaded.insertSpacesForTab, false)
        XCTAssertEqual(reloaded.tabWidth, 2)
        XCTAssertEqual(reloaded.scrollPastEnd, false)
        XCTAssertEqual(reloaded.ensureTrailingNewline, false)
        XCTAssertEqual(reloaded.listMarker, "*")
        XCTAssertEqual(reloaded.styleName, "Solarized")
        XCTAssertEqual(reloaded.syntaxHighlighting, false)
        XCTAssertEqual(reloaded.codeLineNumbers, true)
        XCTAssertEqual(reloaded.math, false)
        XCTAssertEqual(reloaded.frontmatter, false)
        XCTAssertEqual(reloaded.tocToken, false)
        XCTAssertEqual(reloaded.taskList, false)
        XCTAssertEqual(reloaded.mermaid, false)
    }

    func test_didChangeNotification_postedOnSet() {
        let prefs = Preferences(defaults: defaults)
        let exp = expectation(forNotification: Preferences.didChangeNotification, object: prefs, handler: nil)
        prefs.showWordCount = true
        wait(for: [exp], timeout: 1.0)
    }

    func test_didChangeNotification_postedForStringAndNumericSetters() {
        let prefs = Preferences(defaults: defaults)
        let exp = expectation(forNotification: Preferences.didChangeNotification, object: prefs, handler: nil)
        exp.expectedFulfillmentCount = 2
        prefs.fontName = "Courier"
        prefs.tabWidth = 8
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Appearance

    func test_interfaceSize_roundTrips() {
        let prefs = Preferences(defaults: defaults)
        for size in InterfaceSize.allCases {
            prefs.headerSize = size
            prefs.sidebarTextSize = size
            XCTAssertEqual(prefs.headerSize, size)
            XCTAssertEqual(prefs.sidebarTextSize, size)
        }
    }

    func test_interfaceSize_unknownValueFallsBackToRegular() {
        defaults.set("enormous", forKey: "headerSize")
        XCTAssertEqual(Preferences(defaults: defaults).headerSize, .regular)
    }

    func test_sidebarWidth_isClampedOnWriteAndRead() {
        let prefs = Preferences(defaults: defaults)
        prefs.sidebarWidth = 10_000
        XCTAssertEqual(prefs.sidebarWidth, Preferences.sidebarWidthRange.upperBound)
        prefs.sidebarWidth = 1
        XCTAssertEqual(prefs.sidebarWidth, Preferences.sidebarWidthRange.lowerBound)

        // 他所が範囲外を書き込んでいても、読み出し側で丸める
        defaults.set(5.0, forKey: "sidebarWidth")
        XCTAssertEqual(prefs.sidebarWidth, Preferences.sidebarWidthRange.lowerBound)
    }

    func test_sidebarWidth_keepsAValueInRange() {
        let prefs = Preferences(defaults: defaults)
        prefs.sidebarWidth = 312
        XCTAssertEqual(prefs.sidebarWidth, 312)
    }

    func test_interfaceSize_pickSelectsByStep() {
        XCTAssertEqual(InterfaceSize.compact.pick(1, 2, 3), 1)
        XCTAssertEqual(InterfaceSize.regular.pick(1, 2, 3), 2)
        XCTAssertEqual(InterfaceSize.large.pick(1, 2, 3), 3)
    }

}
