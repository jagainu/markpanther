import XCTest
@testable import MarkPantherCore

final class ChangeDigestTests: XCTestCase {
    private let readme = URL(fileURLWithPath: "/tmp/README.md")
    private let notes = URL(fileURLWithPath: "/tmp/notes.md")
    private let start = Date(timeIntervalSince1970: 1_000)

    private func makeDigest(window: TimeInterval = 2) -> ChangeDigest {
        ChangeDigest(window: window)
    }

    func testHoldsBackAnEntryUntilTheWindowCloses() {
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)

        XCTAssertTrue(digest.due(at: start.addingTimeInterval(1.9)).isEmpty)
        XCTAssertEqual(digest.due(at: start.addingTimeInterval(2)).count, 1)
    }

    func testMergesWritesInsideTheWindowIntoOneEntry() {
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)
        digest.record(url: readme, changes: 2, at: start.addingTimeInterval(0.5))
        digest.record(url: readme, changes: 1, at: start.addingTimeInterval(1.5))

        let due = digest.due(at: start.addingTimeInterval(2))
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due[0].url, readme)
        XCTAssertEqual(due[0].changes, 6)
        XCTAssertEqual(due[0].updates, 3)
    }

    func testTheWindowRunsFromTheFirstWriteNotTheLast() {
        // 書き続けられても通知が無限に先送りされないこと
        let digest = makeDigest()
        digest.record(url: readme, changes: 1, at: start)
        digest.record(url: readme, changes: 1, at: start.addingTimeInterval(1.5))

        XCTAssertEqual(digest.due(at: start.addingTimeInterval(2)).count, 1)
    }

    func testAWriteAfterTheWindowStartsANewEntry() {
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)
        XCTAssertEqual(digest.due(at: start.addingTimeInterval(2))[0].changes, 3)

        digest.record(url: readme, changes: 5, at: start.addingTimeInterval(10))
        let second = digest.due(at: start.addingTimeInterval(12))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].changes, 5)
    }

    func testDueRemovesWhatItHandedOut() {
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)

        XCTAssertEqual(digest.due(at: start.addingTimeInterval(2)).count, 1)
        XCTAssertTrue(digest.due(at: start.addingTimeInterval(3)).isEmpty)
    }

    func testKeepsFilesApart() {
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)
        digest.record(url: notes, changes: 1, at: start.addingTimeInterval(0.2))

        // 窓はファイルごとに、その最初の書き込みから始まる
        let due = digest.due(at: start.addingTimeInterval(2.2)).sorted { $0.url.path < $1.url.path }
        XCTAssertEqual(due.map(\.url), [readme, notes])
        XCTAssertEqual(due.map(\.changes), [3, 1])
    }

    func testAnUnknownCountLeavesChangesNilButStillCountsTheWrite() {
        // 編集モード中はレンダリングが走らないので件数が分からない
        let digest = makeDigest()
        digest.record(url: readme, changes: nil, at: start)

        let due = digest.due(at: start.addingTimeInterval(2))
        XCTAssertEqual(due.count, 1)
        XCTAssertNil(due[0].changes)
        XCTAssertEqual(due[0].updates, 1)
    }

    func testAKnownCountWinsOverAnUnknownOneInTheSameWindow() {
        let digest = makeDigest()
        digest.record(url: readme, changes: nil, at: start)
        digest.record(url: readme, changes: 4, at: start.addingTimeInterval(0.3))

        XCTAssertEqual(digest.due(at: start.addingTimeInterval(2))[0].changes, 4)
    }

    func testUnseenTotalAccumulatesAndClears() {
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)
        digest.record(url: notes, changes: 2, at: start)
        XCTAssertEqual(digest.unseenTotal, 5)

        digest.clearUnseen()
        XCTAssertEqual(digest.unseenTotal, 0)
    }

    func testAnUnknownCountStillMovesTheBadge() {
        let digest = makeDigest()
        digest.record(url: readme, changes: nil, at: start)
        XCTAssertEqual(digest.unseenTotal, 1)
    }

    func testUnseenTotalSurvivesDelivery() {
        // バナーを出したかどうかと、まだ見ていないかどうかは別の話
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)
        _ = digest.due(at: start.addingTimeInterval(2))
        XCTAssertEqual(digest.unseenTotal, 3)
    }

    func testForgetDropsAPendingEntry() {
        let digest = makeDigest()
        digest.record(url: readme, changes: 3, at: start)
        digest.record(url: notes, changes: 1, at: start)
        digest.forget(readme)

        let due = digest.due(at: start.addingTimeInterval(2))
        XCTAssertEqual(due.map(\.url), [notes])
    }

    func testNextDueTellsWhenToWakeUp() {
        let digest = makeDigest()
        XCTAssertNil(digest.nextDue)

        digest.record(url: readme, changes: 1, at: start)
        XCTAssertEqual(digest.nextDue, start.addingTimeInterval(2))

        // 後から来た別ファイルでも、いちばん早い締め切りを返す
        digest.record(url: notes, changes: 1, at: start.addingTimeInterval(1))
        XCTAssertEqual(digest.nextDue, start.addingTimeInterval(2))
    }
}
