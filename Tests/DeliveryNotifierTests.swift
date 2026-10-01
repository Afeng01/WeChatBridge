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
// runner. The part this file can pin down is the round trips the callback
// depends on: whatever an action needs must come back out of userInfo
// unchanged, whatever characters the names carry.
import WeChatBridgeCore
import XCTest

final class DeliveryNotifierTests: XCTestCase {
    func testRevealRoundTripPreservesPathsOfEveryShape() {
        let notes = [
            URL(fileURLWithPath: "/Users/甲/沉淀/微信群 聊天记录.md"),
            URL(fileURLWithPath: "/tmp/emoji-🗂- attachment (2).zip"),
            URL(fileURLWithPath: "/tmp/wxbridge/a'b\"c/hyphen-name.txt"),
        ]
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: DeliveryNotifier.userInfo(forRevealing: notes)), notes)
    }

    func testEmptyRevealRoundTripsToEmpty() {
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: DeliveryNotifier.userInfo(forRevealing: [])), [])
    }

    func testObsidianRoundTripPreservesVaultAndFiles() throws {
        let userInfo = DeliveryNotifier.userInfo(
            forOpeningIn: "我的 知识库",
            files: ["微信群/张三.md", "群聊/会议 🗂 记录.md"]
        )
        let urls = DeliveryNotifier.obsidianURLs(from: userInfo)
        XCTAssertEqual(urls.count, 2)
        let components = try urls.map {
            try XCTUnwrap(URLComponents(url: $0, resolvingAgainstBaseURL: false))
        }
        XCTAssertEqual(
            components.map { $0.queryItems?.first { $0.name == "vault" }?.value },
            ["我的 知识库", "我的 知识库"]
        )
        XCTAssertEqual(
            components.map { $0.queryItems?.first { $0.name == "file" }?.value },
            ["微信群/张三.md", "群聊/会议 🗂 记录.md"]
        )
        XCTAssertTrue(urls.allSatisfy { $0.scheme == "obsidian" && $0.host == "open" })
    }

    func testObsidianURLSurvivesReservedCharacters() throws {
        // 「?」「#」「&」 break a carelessly concatenated URL; the query
        // encoding has to carry them through to Obsidian intact.
        let url = try XCTUnwrap(DeliveryNotifier.obsidianURL(vault: "vault?x", file: "a?b#c&d=e.md"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "vault" }?.value, "vault?x")
        XCTAssertEqual(components.queryItems?.first { $0.name == "file" }?.value, "a?b#c&d=e.md")
    }

    func testForeignOrMissingUserInfoDecodesToNothing() {
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: [:]), [])
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: ["unrelated": "value"]), [])
        // A wrong type under the right key — say a future change puts a single
        // path there — must not crash a notification callback.
        XCTAssertEqual(DeliveryNotifier.revealPaths(from: ["revealPaths": "/a/single/path.md"]), [])
        XCTAssertEqual(DeliveryNotifier.obsidianURLs(from: [:]), [])
        XCTAssertEqual(DeliveryNotifier.obsidianURLs(from: ["unrelated": "value"]), [])
        // Half an Obsidian target — a vault without its files — decodes to
        // nothing rather than opening something half-built.
        XCTAssertEqual(DeliveryNotifier.obsidianURLs(from: ["obsidianVault": "知识库"]), [])
        XCTAssertEqual(DeliveryNotifier.obsidianURLs(from: ["obsidianFiles": ["a.md"]]), [])
    }

    func testIdentifiersAreStableAndDistinct() {
        // Categories and actions are matched by string on both sides of the
        // userInfo round trips; equal identifiers would make one notification's
        // plain click indistinguishable from another's button.
        XCTAssertFalse(DeliveryNotifier.folderCategoryIdentifier.isEmpty)
        XCTAssertFalse(DeliveryNotifier.revealActionIdentifier.isEmpty)
        XCTAssertFalse(DeliveryNotifier.obsidianCategoryIdentifier.isEmpty)
        XCTAssertFalse(DeliveryNotifier.openNoteActionIdentifier.isEmpty)
        XCTAssertNotEqual(DeliveryNotifier.folderCategoryIdentifier, DeliveryNotifier.revealActionIdentifier)
        XCTAssertNotEqual(DeliveryNotifier.obsidianCategoryIdentifier, DeliveryNotifier.openNoteActionIdentifier)
        // The two destinations' notifications must never be confusable.
        XCTAssertNotEqual(DeliveryNotifier.folderCategoryIdentifier, DeliveryNotifier.obsidianCategoryIdentifier)
        XCTAssertNotEqual(DeliveryNotifier.revealActionIdentifier, DeliveryNotifier.openNoteActionIdentifier)
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
