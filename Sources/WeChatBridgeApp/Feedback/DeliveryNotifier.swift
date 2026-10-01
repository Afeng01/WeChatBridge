import AppKit
import UserNotifications
import WeChatBridgeCore

/// The success report for 「沉淀到文件夹」: a system notification, not a
/// corner capsule.
///
/// A folder delivery always happens with WeChatBridge in the background — the
/// share extension triggered it — and macOS will not render a background app's
/// own windows: the capsule's `show` ran, its frame was right,
/// `orderFrontRegardless` and a hard `NSApp.activate(true)` were tried, and
/// nothing appeared. The notification centre is a separate process and shows
/// the banner whatever owns the foreground; its action buttons give the
/// 「在访达中显示」 jump the toast used to carry.
///
/// Failures keep the toast (`ToastPresenter`): they usually arrive while the
/// user is working in WeChatBridge's own settings window, where a self-drawn
/// capsule does appear.
@MainActor
final class DeliveryNotifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let categoryIdentifier = "folderDelivery"
    nonisolated static let revealActionIdentifier = "revealInFinder"

    /// The userInfo key that carries the note paths an action replays. Plain
    /// path strings, not anything richer: userInfo crosses into the
    /// notification centre's own storage and back, and strings make that round
    /// trip lossless.
    private nonisolated static let revealPathsKey = "revealPaths"

    private var isConfigured = false

    /// `folderName` lands in the title; `notes` come back when the action is
    /// clicked. Asking for permission here — not at launch — means the prompt
    /// appears at the first delivery, when the user has a reason to answer it;
    /// `requestAuthorization` only prompts while the choice is undecided, so
    /// this is silent from the second delivery on. A refusal also returns
    /// immediately and quietly: the delivery itself succeeded, and the notice
    /// was a bonus — not something to escalate into a failure report.
    ///
    /// The authorization prompt can hold this call until the user answers it,
    /// which holds the delivery queue behind it — harmless, because the modal
    /// prompt has the user's attention anyway, and it never appears again once
    /// answered.
    func notify(savedTo folderName: String, revealing notes: [URL]) async {
        configureOnce()

        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }

        let content = UNMutableNotificationContent()
        // No sound asked for, and only `.alert` in the authorization: this is
        // an "it worked" banner, not an alarm; its visual presence is the
        // whole message.
        content.title = L10n.format("已保存到 %@", folderName)
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = Self.userInfo(forRevealing: notes)
        try? await center.add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // MARK: - Reveal round trip

    /// The encode side of the only userInfo this notifier writes.
    nonisolated static func userInfo(forRevealing notes: [URL]) -> [AnyHashable: Any] {
        [revealPathsKey: notes.map(\.path)]
    }

    /// The decode side: anything unexpected — a missing key, a foreign type —
    /// decodes to nothing rather than crashing in a notification callback.
    nonisolated static func revealPaths(from userInfo: [AnyHashable: Any]) -> [URL] {
        (userInfo[revealPathsKey] as? [String])?.map { URL(fileURLWithPath: $0) } ?? []
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// The category and the delegate both land here, once, on the way to the
    /// first notification — there is nothing to configure before the first
    /// delivery, and this object lives as long as the app does.
    private func configureOnce() {
        guard !isConfigured else { return }
        isConfigured = true
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: Self.revealActionIdentifier,
                        title: L10n.text("在访达中显示")
                    )
                ],
                intentIdentifiers: []
            )
        ])
        // The centre holds its delegate weakly; `ActionRunner` owns this
        // notifier for the app's lifetime, so the callback has somewhere to
        // land however much later the button is clicked.
        center.delegate = self
    }

    /// Both the button and a bare click on the banner mean "take me there";
    /// a dismissal does not. The callback can arrive off the main thread.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == Self.revealActionIdentifier
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else {
            completionHandler()
            return
        }
        let notes = Self.revealPaths(from: response.notification.request.content.userInfo)
        Task { @MainActor in
            if !notes.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(notes)
            }
            completionHandler()
        }
    }

    /// A foreground app gets no banner unless it opts in — and a delivery can
    /// be replayed from WeChatBridge's own 记录 window while it is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
