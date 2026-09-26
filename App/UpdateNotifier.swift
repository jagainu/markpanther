import AppKit
import MarkPantherCore
import UserNotifications

/// Tells the user that a file changed underneath them while they were elsewhere.
///
/// While MarkPanther is frontmost the header's Updated pill already says this,
/// so nothing is posted. Once it isn't, a write is worth a banner — that is the
/// whole point of the app sitting beside Claude Code.
///
/// Writes are merged by [ChangeDigest] before anything is posted, because an
/// agent rewrites a file several times in a row.
@MainActor
final class UpdateNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UpdateNotifier()

    /// Set by `AppDelegate`: what to do when the user clicks a banner.
    var onOpen: ((URL) -> Void)?

    private let digest = ChangeDigest()
    private var timer: Timer?
    /// nil = まだ聞いていない。false のときはバナーを諦めて Dock バッジだけにする
    private var authorized: Bool?

    private var center: UNUserNotificationCenter? {
        // バンドル外（テストランナー等）から触ると UNUserNotificationCenter は例外を投げる
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return .current()
    }

    func start() {
        guard let center else { return }
        center.delegate = self
        Task { @MainActor in
            // まだ一度も聞いていないときだけ尋ねる。macOS はいちど決着した相手に二度目を出さない
            if await refreshAuthorization() == .notDetermined {
                await requestAuthorization()
            }
        }
    }

    /// Re-reads the permission from the system.
    ///
    /// 起動時のダイアログは数秒で引っ込むので見落としやすく、あとからシステム設定で
    /// 許可されることがある。アプリが前面に戻るたびに取り直して、再起動なしで効かせる。
    @discardableResult
    func refreshAuthorization() async -> UNAuthorizationStatus {
        guard let center else { return .denied }
        let status = await center.notificationSettings().authorizationStatus
        authorized = status == .authorized || status == .provisional
        return status
    }

    /// Asks for permission. The dialog only appears while the answer is still open.
    @discardableResult
    func requestAuthorization() async -> UNAuthorizationStatus {
        guard let center else { return .denied }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await refreshAuthorization()
    }

    /// 断られたあとはアプリ側から聞き直せない。設定の該当画面まで連れて行く。
    static func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Records one external overwrite. `changes` is nil when the count isn't known
    /// yet (edit mode renders nothing).
    func record(_ url: URL?, changes: Int?) {
        // 前面にいるなら知らせる必要がない。バッジも汚さない
        guard let url, !NSApp.isActive else { return }
        digest.record(url: url, changes: changes)
        updateBadge()
        rearm()
    }

    /// The user looked at the app, so nothing is unseen any more.
    func markSeen() {
        digest.clearUnseen()
        updateBadge()
    }

    /// This window came forward on its own; its pending banner would only repeat
    /// what the header already shows.
    func forget(_ url: URL?) {
        guard let url else { return }
        digest.forget(url)
        rearm()
    }

    // MARK: - Delivery

    private func rearm() {
        timer?.invalidate()
        guard let next = digest.nextDue else { return }
        let delay = max(0.05, next.timeIntervalSinceNow)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { UpdateNotifier.shared.deliver() }
        }
    }

    private func deliver() {
        let due = digest.due()
        rearm()
        guard !due.isEmpty else { return }
        // 窓が開いているあいだに戻ってきたなら、もう知らせる相手が見ている
        guard !NSApp.isActive else {
            markSeen()
            return
        }
        guard authorized == true, let center else { return }

        for entry in due {
            let content = UNMutableNotificationContent()
            content.title = entry.url.lastPathComponent
            content.body = Self.body(for: entry)
            content.userInfo = ["path": entry.url.path]
            // 同じファイルの知らせは通知センターで1つに畳む
            content.threadIdentifier = CanonicalPath.of(entry.url.path)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    private static func body(for entry: DigestEntry) -> String {
        guard let changes = entry.changes, changes > 0 else {
            return entry.updates > 1 ? "外部から \(entry.updates) 回更新されました" : "外部から更新されました"
        }
        let changed = changes == 1 ? "1 件の変更" : "\(changes) 件の変更"
        return entry.updates > 1 ? "\(entry.updates) 回の更新 · \(changed)" : changed
    }

    private func updateBadge() {
        let total = digest.unseenTotal
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
        NSApp.dockTile.display()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let path = response.notification.request.content.userInfo["path"] as? String
        Task { @MainActor [weak self] in
            if let path { self?.onOpen?(URL(fileURLWithPath: path)) }
            self?.markSeen()
        }
        completionHandler()
    }
}
