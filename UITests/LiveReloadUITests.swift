import XCTest

final class LiveReloadUITests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkPantherUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("live.md")
        try "# First Version\n\nalpha paragraph\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    @MainActor
    func testExternalOverwriteAppearsInPreviewThenEditRoundTrips() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--open", fileURL.path]
        app.launch()

        // 既存ファイルはプレビューモードで開く
        XCTAssertTrue(app.staticTexts["First Version"].waitForExistence(timeout: 10))

        // Claude の Write と同じ atomic replace で外部から上書き → プレビューに即反映
        try "# Second Version\n\nbeta paragraph\n".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(app.staticTexts["Second Version"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["First Version"].exists)

        // ⌘E でエディタへ。同じ内容が入っている
        app.typeKey("e", modifierFlags: .command)
        let editor = app.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue((editor.value as? String ?? "").contains("# Second Version"))

        // エディタ表示中の外部上書きも反映される
        try "# Third Version\n\ngamma\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let updated = NSPredicate(format: "value CONTAINS %@", "# Third Version")
        wait(for: [expectation(for: updated, evaluatedWith: editor)], timeout: 3)

        // 末尾に入力して ⌘B → 自動保存でディスクへ
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("bold")
        app.typeKey(.leftArrow, modifierFlags: [.shift, .option])
        app.typeKey("b", modifierFlags: .command)

        let deadline = Date().addingTimeInterval(5)
        var onDisk = ""
        while Date() < deadline {
            onDisk = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            if onDisk.contains("**bold**") { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(onDisk.contains("**bold**"), "autosave did not reach disk: \(onDisk)")
        XCTAssertTrue(onDisk.contains("# Third Version"))
    }
}
