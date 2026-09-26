import AppIntents

/// What Siri, Spotlight and the Shortcuts app offer without the user building
/// anything first.
///
/// App Shortcuts have to live in the main app target — put them in a package or
/// an extension and they never appear in Shortcuts. Every phrase must contain
/// `\(.applicationName)`.
struct MarkPantherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenMarkdownIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Open a document in \(.applicationName)",
                "\(.applicationName)で開く",
            ],
            shortTitle: "Open Document",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: ShowChangesIntent(),
            phrases: [
                "Show changes in \(.applicationName)",
                "What changed in \(.applicationName)",
                "\(.applicationName)の変更を見せて",
            ],
            shortTitle: "Show Changes",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
