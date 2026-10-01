// Standalone app-helper tests; no app launch or Package.swift change needed.
// After `swift build`:
// test_output="$(mktemp -d /tmp/wechatbridge-notifier-tests.XXXXXX)"
// test_sdk="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"
// mise exec -- swiftc -swift-version 5 -D DELIVERY_NOTIFIER_TEST_MAIN \
//   -I .build/debug -F "$test_sdk/Library/Frameworks" -L "$test_sdk/usr/lib" \
//   -Xlinker -rpath -Xlinker "$test_sdk/Library/Frameworks" \
//   -Xlinker -rpath -Xlinker "$test_sdk/usr/lib" \
//   .build/debug/WeChatBridgeCore.o -lz \
//   Sources/WeChatBridgeApp/Feedback/DeliveryNotifier.swift Tests/DeliveryNotifierTests.swift \
//   -o "$test_output/runner"
// "$test_output/runner"
//
// What is not here: `notify`, the authorization prompt, the category
// registration and the action callback are the notification centre's system
// behaviour — they only run inside a bundled, signed app, not a bare test
// runner. The part this file can pin down is the round trip the callback
// depends on: the paths written into userInfo must come back out unchanged,
// whatever characters the folder names carry.
import WeChatBridgeCore
import XCTest

final class DeliveryNotifierTests: XCTestCase {
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

#if DELIVERY_NOTIFIER_TEST_MAIN
@main
enum DeliveryNotifierTestRunner {
    static func main() {
        let suite = DeliveryNotifierTests.defaultTestSuite
        suite.run()
        guard let run = suite.testRun, run.executionCount > 0, run.hasSucceeded else { exit(1) }
    }
}
#endif
