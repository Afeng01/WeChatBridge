@testable import WeChatBridgeApp
import WeChatBridgeCore
import XCTest
import UserNotifications

final class DeliveryNotifierTests: XCTestCase {
    @MainActor
    func testStartupRegistersActionsBeforeAnyNewDelivery() {
        let center = TestNotificationCenter()
        let notifier = DeliveryNotifier(center: center)
        notifier.configure()
        XCTAssertTrue(center.delegate === notifier)
        XCTAssertEqual(Set(center.categories.map(\.identifier)), [DeliveryNotifier.categoryIdentifier])
        XCTAssertEqual(center.categories.first?.actions.first?.identifier, DeliveryNotifier.revealActionIdentifier)
    }

    @MainActor
    func testRestartReplacesDelegateWithoutSendingANewNotification() {
        let center = TestNotificationCenter()
        var previous: DeliveryNotifier? = DeliveryNotifier(center: center)
        previous?.configure()
        previous = nil
        XCTAssertNil(center.delegate)
        let restarted = DeliveryNotifier(center: center)
        restarted.configure()
        XCTAssertTrue(center.delegate === restarted)
        XCTAssertEqual(center.registrationCount, 2)
    }

    func testRoundTripPreservesPathsOfEveryShape() {
        let notes = [
            URL(fileURLWithPath: "/Users/甲/沉淀/微信群 聊天记录.md"),
            URL(fileURLWithPath: "/tmp/emoji-🗂- attachment (2).zip"),
            URL(fileURLWithPath: "/tmp/wxbridge/a'b\"c/hyphen-name.txt"),
        ]
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: DeliveryNotifier.userInfo(forRevealing: notes)), notes)
    }

    func testEmptyDeliveryRoundTripsToEmpty() {
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: DeliveryNotifier.userInfo(forRevealing: [])), [])
    }

    func testForeignOrMissingUserInfoDecodesToNothing() {
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: [:]), [])
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: ["unrelated": "value"]), [])
        // A wrong type under the right key — say a future change puts a single
        // path there — must not crash a notification callback.
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: ["revealPaths": "/a/single/path.md"]), [])
    }

    func testIdentifiersAreStableAndDistinct() {
        // The category and its action are matched by string on both sides of
        // the userInfo round trip; equal identifiers would make the plain
        // click indistinguishable from the button.
        XCTAssertFalse(DeliveryNotifier.categoryIdentifier.isEmpty)
        XCTAssertFalse(DeliveryNotifier.revealActionIdentifier.isEmpty)
        XCTAssertNotEqual(DeliveryNotifier.categoryIdentifier, DeliveryNotifier.revealActionIdentifier)
    }
}


private final class TestNotificationCenter: DeliveryNotificationCenter {
    weak var delegate: UNUserNotificationCenterDelegate?
    private(set) var categories = Set<UNNotificationCategory>()
    private(set) var registrationCount = 0
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func add(_ request: UNNotificationRequest) async throws {}
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
        registrationCount += 1
    }
}
