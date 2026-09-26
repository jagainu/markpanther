import Foundation

/// Typed wrapper around `UserDefaults` for all MarkPanther app preferences.
/// Every setter posts `didChangeNotification` so observers (menus, editor, preview)
/// can react without polling.
public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences()
    public static let didChangeNotification = Notification.Name("MarkPantherCore.Preferences.didChange")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        // General
        static let showWordCount = "showWordCount"
        static let openUntitledOnLaunch = "openUntitledOnLaunch"
        // Markdown
        static let smartypants = "smartypants"
        static let superscript = "superscript"
        static let highlightMark = "highlightMark"
        static let hardLineBreaks = "hardLineBreaks"
        // Editor
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let lineSpacing = "lineSpacing"
        static let horizontalInset = "horizontalInset"
        static let verticalInset = "verticalInset"
        static let limitEditorWidth = "limitEditorWidth"
        static let editorMaxWidth = "editorMaxWidth"
        static let autoCompleteBrackets = "autoCompleteBrackets"
        static let autoIncrementOrderedList = "autoIncrementOrderedList"
        static let autoInsertLinePrefix = "autoInsertLinePrefix"
        static let insertSpacesForTab = "insertSpacesForTab"
        static let tabWidth = "tabWidth"
        static let scrollPastEnd = "scrollPastEnd"
        static let ensureTrailingNewline = "ensureTrailingNewline"
        static let listMarker = "listMarker"
        // Appearance
        static let headerSize = "headerSize"
        static let sidebarTextSize = "sidebarTextSize"
        static let sidebarWidth = "sidebarWidth"
        // Rendering
        static let styleName = "styleName"
        static let syntaxHighlighting = "syntaxHighlighting"
        static let codeLineNumbers = "codeLineNumbers"
        static let previewLineNumbers = "previewLineNumbers"
        static let changeBand = "changeBand"
        static let math = "math"
        static let frontmatter = "frontmatter"
        static let tocToken = "tocToken"
        static let taskList = "taskList"
        static let mermaid = "mermaid"
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: self)
    }

    private func bool(_ key: String, default def: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
    }

    private func setBool(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
        notifyChange()
    }

    private func double(_ key: String, default def: Double) -> Double {
        defaults.object(forKey: key) == nil ? def : defaults.double(forKey: key)
    }

    private func setDouble(_ value: Double, _ key: String) {
        defaults.set(value, forKey: key)
        notifyChange()
    }

    private func int(_ key: String, default def: Int) -> Int {
        defaults.object(forKey: key) == nil ? def : defaults.integer(forKey: key)
    }

    private func setInt(_ value: Int, _ key: String) {
        defaults.set(value, forKey: key)
        notifyChange()
    }

    private func string(_ key: String, default def: String) -> String {
        defaults.string(forKey: key) ?? def
    }

    private func setString(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
        notifyChange()
    }

    // MARK: - General

    public var showWordCount: Bool {
        get { bool(Keys.showWordCount, default: true) }
        set { setBool(newValue, Keys.showWordCount) }
    }

    public var openUntitledOnLaunch: Bool {
        get { bool(Keys.openUntitledOnLaunch, default: false) }
        set { setBool(newValue, Keys.openUntitledOnLaunch) }
    }

    // MARK: - Markdown

    public var smartypants: Bool {
        get { bool(Keys.smartypants, default: false) }
        set { setBool(newValue, Keys.smartypants) }
    }

    public var superscript: Bool {
        get { bool(Keys.superscript, default: false) }
        set { setBool(newValue, Keys.superscript) }
    }

    public var highlightMark: Bool {
        get { bool(Keys.highlightMark, default: true) }
        set { setBool(newValue, Keys.highlightMark) }
    }

    public var hardLineBreaks: Bool {
        get { bool(Keys.hardLineBreaks, default: true) }
        set { setBool(newValue, Keys.hardLineBreaks) }
    }

    // MARK: - Editor

    public var fontName: String {
        get { string(Keys.fontName, default: "") }
        set { setString(newValue, Keys.fontName) }
    }

    public var fontSize: Double {
        get { double(Keys.fontSize, default: 14.0) }
        set { setDouble(newValue, Keys.fontSize) }
    }

    public var lineSpacing: Double {
        get { double(Keys.lineSpacing, default: 4.0) }
        set { setDouble(newValue, Keys.lineSpacing) }
    }

    public var horizontalInset: Double {
        get { double(Keys.horizontalInset, default: 24.0) }
        set { setDouble(newValue, Keys.horizontalInset) }
    }

    public var verticalInset: Double {
        get { double(Keys.verticalInset, default: 20.0) }
        set { setDouble(newValue, Keys.verticalInset) }
    }

    public var limitEditorWidth: Bool {
        get { bool(Keys.limitEditorWidth, default: false) }
        set { setBool(newValue, Keys.limitEditorWidth) }
    }

    public var editorMaxWidth: Double {
        get { double(Keys.editorMaxWidth, default: 800.0) }
        set { setDouble(newValue, Keys.editorMaxWidth) }
    }

    public var autoCompleteBrackets: Bool {
        get { bool(Keys.autoCompleteBrackets, default: true) }
        set { setBool(newValue, Keys.autoCompleteBrackets) }
    }

    public var autoIncrementOrderedList: Bool {
        get { bool(Keys.autoIncrementOrderedList, default: true) }
        set { setBool(newValue, Keys.autoIncrementOrderedList) }
    }

    public var autoInsertLinePrefix: Bool {
        get { bool(Keys.autoInsertLinePrefix, default: true) }
        set { setBool(newValue, Keys.autoInsertLinePrefix) }
    }

    public var insertSpacesForTab: Bool {
        get { bool(Keys.insertSpacesForTab, default: true) }
        set { setBool(newValue, Keys.insertSpacesForTab) }
    }

    public var tabWidth: Int {
        get { int(Keys.tabWidth, default: 4) }
        set { setInt(newValue, Keys.tabWidth) }
    }

    public var scrollPastEnd: Bool {
        get { bool(Keys.scrollPastEnd, default: true) }
        set { setBool(newValue, Keys.scrollPastEnd) }
    }

    public var ensureTrailingNewline: Bool {
        get { bool(Keys.ensureTrailingNewline, default: true) }
        set { setBool(newValue, Keys.ensureTrailingNewline) }
    }

    public var listMarker: String {
        get { string(Keys.listMarker, default: "-") }
        set { setString(newValue, Keys.listMarker) }
    }

    // MARK: - Rendering

    public var styleName: String {
        get { string(Keys.styleName, default: "GitHub") }
        set { setString(newValue, Keys.styleName) }
    }

    public var syntaxHighlighting: Bool {
        get { bool(Keys.syntaxHighlighting, default: true) }
        set { setBool(newValue, Keys.syntaxHighlighting) }
    }

    public var codeLineNumbers: Bool {
        get { bool(Keys.codeLineNumbers, default: false) }
        set { setBool(newValue, Keys.codeLineNumbers) }
    }

    /// プレビューの左余白にソースの行番号を出す
    public var previewLineNumbers: Bool {
        get { bool(Keys.previewLineNumbers, default: false) }
        set { setBool(newValue, Keys.previewLineNumbers) }
    }

    /// 外部更新の変更箇所を、左余白の ●（false、既定）ではなく diff 風の帯（true）で見せる
    public var changeBand: Bool {
        get { bool(Keys.changeBand, default: false) }
        set { setBool(newValue, Keys.changeBand) }
    }

    public var math: Bool {
        get { bool(Keys.math, default: true) }
        set { setBool(newValue, Keys.math) }
    }

    public var frontmatter: Bool {
        get { bool(Keys.frontmatter, default: true) }
        set { setBool(newValue, Keys.frontmatter) }
    }

    public var tocToken: Bool {
        get { bool(Keys.tocToken, default: true) }
        set { setBool(newValue, Keys.tocToken) }
    }

    public var taskList: Bool {
        get { bool(Keys.taskList, default: true) }
        set { setBool(newValue, Keys.taskList) }
    }

    public var mermaid: Bool {
        get { bool(Keys.mermaid, default: true) }
        set { setBool(newValue, Keys.mermaid) }
    }

    // MARK: - Appearance

    /// サイドバーの幅はドラッグで決まるので、設定画面には出さずここに置くだけ。
    public static let sidebarWidthRange: ClosedRange<Double> = 180...520

    public var headerSize: InterfaceSize {
        get { size(Keys.headerSize) }
        set { setString(newValue.rawValue, Keys.headerSize) }
    }

    public var sidebarTextSize: InterfaceSize {
        get { size(Keys.sidebarTextSize) }
        set { setString(newValue.rawValue, Keys.sidebarTextSize) }
    }

    public var sidebarWidth: Double {
        get { Self.clampSidebarWidth(double(Keys.sidebarWidth, default: 230)) }
        set { setDouble(Self.clampSidebarWidth(newValue), Keys.sidebarWidth) }
    }

    public static func clampSidebarWidth(_ width: Double) -> Double {
        min(max(width, sidebarWidthRange.lowerBound), sidebarWidthRange.upperBound)
    }

    /// 未設定でも、他所で書かれた知らない文字列でも `.regular` に倒す。
    private func size(_ key: String) -> InterfaceSize {
        InterfaceSize(rawValue: string(key, default: "")) ?? .regular
    }
}
