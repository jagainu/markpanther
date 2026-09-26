import XCTest

/// アウトライン・プレビュー内検索・ズーム。実行中はキーボードとマウスを占有する。
final class NavigationUITests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkPantherUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("long.md")
        var lines = ["# Long doc", ""]
        for i in 1...40 {
            lines += ["## Section \(i)", "", "Paragraph \(i). Lorem ipsum dolor sit amet.", "", "needle-\(i % 4)", ""]
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    @MainActor
    func testOutlineJumpFindAndZoom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--open", fileURL.path, "-outlineVisible", "YES", "-viewZoom", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Long doc"].firstMatch.waitForExistence(timeout: 10))

        // アウトライン: 行をクリック → その見出しへ飛ぶ
        let row = app.tables["outline"].staticTexts["Section 37"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let heading = app.webViews.staticTexts["Section 37"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        XCTAssertTrue(heading.isHittable, "outline jump did not scroll the heading into view")

        // プレビュー内検索: needle-1 は 10 件。Return で次へ進む
        app.typeKey("f", modifierFlags: .command)
        let find = app.searchFields["previewFind"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.typeText("NEEDLE-1")
        let count = app.staticTexts["previewFindCount"]
        let total = NSPredicate(format: "value ENDSWITH %@", "/10")
        wait(for: [expectation(for: total, evaluatedWith: count)], timeout: 3)
        let first = count.value as? String
        find.typeText("\r")
        let advanced = NSPredicate(format: "value ENDSWITH %@ AND value != %@", "/10", first ?? "")
        wait(for: [expectation(for: advanced, evaluatedWith: count)], timeout: 3)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(find.exists)

        // ズーム: ⌘+ で 110%、⌘0 で 100%
        let zoom = app.buttons["statusZoom"]
        XCTAssertEqual(zoom.title, "100%")
        app.typeKey("+", modifierFlags: .command)
        XCTAssertEqual(zoom.title, "110%")
        app.typeKey("0", modifierFlags: .command)
        XCTAssertEqual(zoom.title, "100%")
    }
}
