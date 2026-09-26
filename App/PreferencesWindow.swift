import AppKit
import SwiftUI
import MarkPantherCore
import UserNotifications

@MainActor
final class PreferencesWindowController: NSWindowController {
    init() {
        // 中身に合わせて窓を立てる。寸法を先に決め打ちすると、いちばん長いラベルを持つ
        // タブで左右が切れる（実際に Editor タブで切れていた）。
        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Settings"
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Preferences（UserDefaults ラッパ）を SwiftUI にバインドするための薄い橋渡し。
@MainActor
private final class PreferencesModel: ObservableObject {
    let prefs = Preferences.shared

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { self.prefs[keyPath: keyPath] },
                set: { self.objectWillChange.send(); self.prefs[keyPath: keyPath] = $0 })
    }
}

private struct PreferencesView: View {
    @StateObject private var model = PreferencesModel()

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            markdown.tabItem { Label("Markdown", systemImage: "text.badge.checkmark") }
            editor.tabItem { Label("Editor", systemImage: "pencil") }
            rendering.tabItem { Label("Rendering", systemImage: "eye") }
        }
        .padding(20)
        .frame(minWidth: 640)
    }

    private var general: some View {
        Form {
            Toggle("Create an untitled document on launch", isOn: model.binding(\.openUntitledOnLaunch))
            Toggle("Show document statistics (approx. tokens, words)", isOn: model.binding(\.showWordCount))
            NotificationPermissionRow()
        }
    }

    private var markdown: some View {
        Form {
            Toggle("Smartypants (smart quotes and dashes)", isOn: model.binding(\.smartypants))
            Toggle("Superscript (^text^)", isOn: model.binding(\.superscript))
            Toggle("Highlight (==text==)", isOn: model.binding(\.highlightMark))
            Toggle("Render newlines literally (single line breaks become line breaks)", isOn: model.binding(\.hardLineBreaks))
            Text("Tables, fenced code, autolinks, strikethrough and footnotes are always on.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var editor: some View {
        Form {
            TextField("Font name (empty = system monospaced)", text: model.binding(\.fontName))
            Stepper(value: model.binding(\.fontSize), in: 9...36, step: 1) {
                Text("Font size: \(Int(model.prefs.fontSize)) pt")
            }
            Stepper(value: model.binding(\.lineSpacing), in: 0...20, step: 1) {
                Text("Line spacing: \(Int(model.prefs.lineSpacing)) pt")
            }
            Stepper(value: model.binding(\.horizontalInset), in: 0...200, step: 4) {
                Text("Horizontal inset: \(Int(model.prefs.horizontalInset)) pt")
            }
            Stepper(value: model.binding(\.verticalInset), in: 0...200, step: 4) {
                Text("Vertical inset: \(Int(model.prefs.verticalInset)) pt")
            }
            Toggle("Limit editor width", isOn: model.binding(\.limitEditorWidth))
            Stepper(value: model.binding(\.editorMaxWidth), in: 400...2000, step: 50) {
                Text("Maximum width: \(Int(model.prefs.editorMaxWidth)) pt")
            }
            .disabled(!model.prefs.limitEditorWidth)
            Divider()
            Toggle("Auto-complete matching characters", isOn: model.binding(\.autoCompleteBrackets))
            Toggle("Automatically insert line prefix for the current block", isOn: model.binding(\.autoInsertLinePrefix))
            Toggle("Auto-increment numbering in ordered lists", isOn: model.binding(\.autoIncrementOrderedList))
            Toggle("Insert spaces instead of tabs", isOn: model.binding(\.insertSpacesForTab))
            Stepper(value: model.binding(\.tabWidth), in: 2...8) {
                Text("Tab width: \(model.prefs.tabWidth)")
            }
            Toggle("Scroll past end", isOn: model.binding(\.scrollPastEnd))
            Toggle("Ensure newline at end of file on save", isOn: model.binding(\.ensureTrailingNewline))
            Picker("List marker", selection: model.binding(\.listMarker)) {
                Text("- (Minus sign)").tag("-")
                Text("* (Asterisk)").tag("*")
                Text("+ (Plus sign)").tag("+")
            }
        }
    }

    private var rendering: some View {
        Form {
            Picker("Style", selection: model.binding(\.styleName)) {
                ForEach(availableStyles, id: \.self) { Text($0).tag($0) }
            }
            Button("Reveal Custom Styles Folder") { NSWorkspace.shared.open(AppDelegate.stylesDirectory) }
            Divider()
            Toggle("Show source line numbers in the preview", isOn: model.binding(\.previewLineNumbers))
            Picker("Changed lines", selection: model.binding(\.changeBand)) {
                Text("Marker (● beside the line number)").tag(false)
                Text("Diff band (full-width highlight)").tag(true)
            }
            Toggle("Syntax highlighted code blocks", isOn: model.binding(\.syntaxHighlighting))
            Toggle("Show line numbers in code blocks", isOn: model.binding(\.codeLineNumbers))
            Toggle("TeX-like math syntax (KaTeX)", isOn: model.binding(\.math))
            Toggle("Mermaid diagrams", isOn: model.binding(\.mermaid))
            Toggle("Detect YAML front matter", isOn: model.binding(\.frontmatter))
            Toggle("Detect table of contents token ([TOC])", isOn: model.binding(\.tocToken))
            Toggle("Task list syntax", isOn: model.binding(\.taskList))
        }
    }

    private var availableStyles: [String] {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("preview/styles")
        let names = [bundled, AppDelegate.stylesDirectory].compactMap { $0 }.flatMap { directory in
            ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "css" }
                .map { $0.deletingPathExtension().lastPathComponent }
        }
        return Array(Set(names)).sorted()
    }
}

/// Lets the user grant update notifications from Settings.
///
/// 起動時の許可ダイアログは数秒で引っ込み、見逃すと macOS は二度と出してくれない。
/// 「まだ聞いていないなら聞く」「断られているなら設定まで連れて行く」の両方をここから辿れるようにする。
private struct NotificationPermissionRow: View {
    @State private var status: UNAuthorizationStatus?
    @State private var isWorking = false

    var body: some View {
        LabeledContent("Update notifications") {
            HStack(spacing: 10) {
                Text(summary).foregroundStyle(.secondary)
                action
            }
        }
        .task { status = await UpdateNotifier.shared.refreshAuthorization() }
    }

    @ViewBuilder
    private var action: some View {
        switch status {
        case .notDetermined:
            Button("Allow…") {
                isWorking = true
                Task {
                    status = await UpdateNotifier.shared.requestAuthorization()
                    isWorking = false
                }
            }
            .disabled(isWorking)
        case .denied:
            Button("Open System Settings…") { UpdateNotifier.openSystemNotificationSettings() }
        default:
            EmptyView()
        }
    }

    private var summary: String {
        switch status {
        case .authorized, .provisional: "Allowed"
        case .denied: "Turned off"
        case .notDetermined: "Not asked yet"
        default: "—"
        }
    }
}
