import XCTest

@MainActor
final class DemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuOpensTableAndProgrammaticRefresh() {
        let app = XCUIApplication()
        app.launch()
        app.tables["demo-menu"].cells["demo-table"].tap()
        waitForStatus("Refreshes: 1", in: app)
        app.buttons["refresh-button"].tap()
        waitForStatus("Refreshes: 2", in: app)
        capture("Table refreshed", app: app)
    }

    func testPullRefreshAndPullFooter() {
        let app = launch(mode: "pull")
        waitForStatus("Items: 20", in: app)
        let list = app.tables["demo-list"]
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.05, thenDragTo: end)
        waitForStatus("Refreshes: 2", in: app)
        for _ in 0 ..< 12 where !list.cells["item-19"].isHittable {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(list.cells["item-19"].exists)
        let bottom = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let upper = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        bottom.press(forDuration: 0.05, thenDragTo: upper)
        waitForStatus("Items: 40", in: app)
        capture("Pull footer loaded", app: app)
    }

    func testPrefetchFooterLoadsOnApproach() {
        let app = launch(mode: "prefetch")
        waitForStatus("Items: 20", in: app)
        let list = app.tables["demo-list"]
        for _ in 0 ..< 12 where !app.staticTexts["demo-status"].label.contains("Items: 40") {
            list.swipeUp(velocity: .slow)
        }
        waitForStatus("Items: 40", in: app)
        capture("Prefetch footer", app: app)
    }

    func testAutomaticFooterLoadsAtBottom() {
        let app = launch(mode: "table")
        waitForStatus("Items: 20", in: app)
        let list = app.tables["demo-list"]
        for _ in 0 ..< 12 where !app.staticTexts["demo-status"].label.contains("Items: 40") {
            list.swipeUp(velocity: .slow)
        }
        waitForStatus("Items: 40", in: app)
        capture("Automatic footer", app: app)
    }

    func testAccessibilityTextSizeAndDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-mode", "table", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL", "--dark-mode"]
        app.launch()
        waitForStatus("Items: 20", in: app)
        XCTAssertTrue(app.buttons["refresh-button"].isHittable)
        XCTAssertTrue(app.switches["failures-toggle"].isHittable)
        capture("Accessibility text and dark appearance", app: app)
    }

    func testFailureRetryAndReset() {
        let app = launch(mode: "table")
        waitForStatus("Items: 20", in: app)
        app.switches["failures-toggle"].tap()
        app.buttons["refresh-button"].tap()
        waitForStatus("Failed", in: app)
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Items: 20"))
        capture("Refresh failure", app: app)
        app.switches["failures-toggle"].tap()
        app.buttons["refresh-button"].tap()
        waitForStatus("Refreshes: 2", in: app)
        app.buttons["load-more-button"].tap()
        waitForStatus("Items: 40", in: app)
        app.buttons["reset-button"].tap()
        waitForStatus("Items: 20", in: app)
        waitForStatus("Refreshes: 3", in: app)
        capture("Reset pagination", app: app)
    }

    func testShortContentRemainsBoundedAndCanLoadExplicitly() {
        let app = launch(mode: "short")
        waitForStatus("Updated", in: app)
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Items: 3"))
        app.buttons["load-more-button"].tap()
        waitForStatus("Items: 6", in: app)
        app.buttons["load-more-button"].tap()
        waitForStatus("No more data", in: app)
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Items: 9"))
        capture("Short content exhausted", app: app)
    }

    func testCollectionAndFrameScreenshots() {
        let collection = launch(mode: "collection")
        waitForStatus("Items: 20", in: collection)
        XCTAssertTrue(collection.collectionViews["demo-list"].cells["item-0"].exists)
        capture("Diffable collection", app: collection)
        collection.terminate()
        let frames = launch(mode: "frames")
        waitForStatus("Items: 20", in: frames)
        capture("Frame animation", app: frames)
    }

    func testTextFreeAnimatorGallery() {
        for mode in ["spinner", "ring", "dots", "tide"] {
            let app = launch(mode: mode, extraArguments: ["--hold-refresh"])
            waitForStatus("Items: 20", in: app)
            app.buttons["refresh-button"].tap()
            waitForStatus("Refreshing", in: app)
            capture("Animator \(mode)", app: app)
            app.buttons["cancel-button"].tap()
            waitForStatus("Cancelled", in: app)
            app.terminate()
        }
    }

    func testResizePreservesData() {
        let app = launch(mode: "collection")
        waitForStatus("Items: 20", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["refresh-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Items: 20"))
        capture("Landscape resize", app: app)
        XCUIDevice.shared.orientation = .portrait
    }

    func testHorizontalPullRefreshAndPaginationLTR() {
        exerciseHorizontalPulls(forceRTL: false)
    }

    func testHorizontalPullRefreshAndPaginationRTL() {
        exerciseHorizontalPulls(forceRTL: true)
    }

    func testHorizontalResizePreservesDataAndDirection() {
        let app = launch(mode: "horizontal")
        let list = app.collectionViews["demo-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        waitForStatus("Items: 20", in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Items: 20"))
        list.swipeLeft(velocity: .slow)
        XCTAssertTrue(list.cells["item-1"].exists)
        capture("Horizontal landscape resize", app: app)
        XCUIDevice.shared.orientation = .portrait
    }

    func testCancellationPreservesVisibleItems() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-mode", "table", "--hold-refresh"]
        app.launch()
        waitForStatus("Items: 20", in: app)
        app.buttons["refresh-button"].tap()
        waitForStatus("Refreshing", in: app)
        app.buttons["cancel-button"].tap()
        waitForStatus("Cancelled", in: app)
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Refreshes: 1"))
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Items: 20"))
        capture("Cancelled refresh", app: app)
    }

    func testNetworkRefreshAndPaginationReachExhaustion() {
        let app = launchNetwork(scenario: "success")
        waitForNetworkStatus("Items: 5", in: app)
        app.buttons["load-more-button"].tap()
        waitForNetworkStatus("Items: 10", in: app)
        app.buttons["load-more-button"].tap()
        waitForNetworkStatus("No more data", in: app)
        waitForNetworkStatus("Items: 15", in: app)
        waitForNetworkStatus("Requests: 3", in: app)
        capture("Network pagination exhausted", app: app)
    }

    func testNetworkRefreshFailurePreservesItems() {
        let app = launchNetwork(scenario: "refreshFailure")
        waitForNetworkStatus("Items: 5", in: app)
        app.buttons["refresh-button"].tap()
        waitForNetworkStatus("Failed HTTP 500", in: app)
        XCTAssertTrue(app.staticTexts["network-status"].label.contains("Items: 5"))
        XCTAssertTrue(app.cells["network-item-0"].exists)
        capture("Network refresh failure", app: app)
    }

    func testNetworkLoadMoreFailureRetriesFromFooter() {
        let app = launchNetwork(scenario: "loadMoreFailure")
        waitForNetworkStatus("Items: 15", in: app)
        app.buttons["load-more-button"].tap()
        waitForNetworkStatus("Failed HTTP 503", in: app)
        let retry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Failed. Tap to retry")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        let list = app.tables["network-list"]
        for _ in 0 ..< 4 where !retry.isHittable {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        waitForNetworkStatus("Items: 30", in: app)
        waitForNetworkStatus("Requests: 3", in: app)
        capture("Network footer retry", app: app)
    }

    func testNetworkSlowPageIsPreemptedByRefresh() {
        let app = launchNetwork(scenario: "staleResponse")
        waitForNetworkStatus("Items: 5", in: app)
        app.buttons["load-more-button"].tap()
        waitForNetworkStatus("Loading more", in: app)
        app.buttons["refresh-button"].tap()
        waitForNetworkStatus("Refreshes: 2", in: app)
        waitForNetworkStatus("Requests: 3", in: app)
        waitForNetworkStatus("Completed: 3", in: app)
        XCTAssertTrue(app.staticTexts["network-status"].label.contains("Items: 5"))
        XCTAssertFalse(app.cells["network-item-5"].exists)
        capture("Network refresh preemption", app: app)
    }

    func testNetworkRequestCancellationDoesNotShowFailure() {
        let app = launchNetwork(scenario: "staleResponse", extraArguments: ["--network-auto-cancel"])
        waitForNetworkStatus("Items: 5", in: app)
        app.buttons["load-more-button"].tap()
        waitForNetworkStatus("Cancelled", in: app)
        waitForNetworkStatus("Cancels: 1", in: app)
        XCTAssertFalse(app.staticTexts["network-status"].label.contains("Failed"))
        XCTAssertFalse(app.staticTexts["network-status"].label.contains("Invalid JSON"))
        capture("Network request cancelled", app: app)
    }

    func testNetworkRequestDoesNotUpdateAfterLeavingPage() {
        let app = launchNetwork(scenario: "staleResponse")
        waitForNetworkStatus("Items: 5", in: app)
        app.buttons["load-more-button"].tap()
        waitForNetworkStatus("Loading more", in: app)
        app.navigationBars["Network Scenarios"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tables["demo-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["network-status"].exists)
        capture("Network page detached", app: app)
    }

    private func launch(mode: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-mode", mode] + extraArguments
        app.launch()
        return app
    }

    private func exerciseHorizontalPulls(forceRTL: Bool) {
        let arguments = forceRTL ? ["--force-rtl"] : []
        let app = launch(mode: "horizontal", extraArguments: arguments)
        let list = app.collectionViews["demo-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        waitForStatus("Items: 20", in: app)

        drag(list, from: 0.18, to: 0.85)
        waitForStatus("Refreshes: 2", in: app)

        let trailingItem = forceRTL ? "item-0" : "item-19"
        for _ in 0 ..< 7 where !list.cells[trailingItem].isHittable {
            list.swipeLeft(velocity: .fast)
        }
        XCTAssertTrue(list.cells[trailingItem].isHittable)
        drag(list, from: 0.95, to: 0.05)
        waitForStatus("Items: 40", in: app)
        capture(forceRTL ? "Horizontal RTL pagination" : "Horizontal LTR pagination", app: app)
    }

    private func drag(_ element: XCUIElement, from startX: CGFloat, to endX: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func launchNetwork(
        scenario: String,
        delay: String = "fast",
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo-mode", "network",
            "--network-scenario", scenario,
            "--network-delay", delay,
        ] + extraArguments
        app.launch()
        return app
    }

    private func waitForStatus(_ text: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line)
    {
        let status = app.staticTexts["demo-status"]
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        // 云端模拟器单次辅助功能查询可能超过 30 秒；这里验证最终状态，不衡量性能。
        let result = XCTWaiter.wait(for: [expectation], timeout: 60)
        if result != .completed {
            capture("Timed out waiting for \(text)", app: app)
            XCTFail("Expected \(text); actual status: \(status.label)", file: file, line: line)
        }
    }

    private func waitForNetworkStatus(_ text: String, in app: XCUIApplication,
                                      file: StaticString = #filePath, line: UInt = #line)
    {
        let status = app.staticTexts["network-status"]
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        let result = XCTWaiter.wait(for: [expectation], timeout: 60)
        if result != .completed {
            capture("Timed out waiting for network \(text)", app: app)
            XCTFail("Expected \(text); actual status: \(status.label)", file: file, line: line)
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
