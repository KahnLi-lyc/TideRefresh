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
            list.swipeUp()
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
            list.swipeUp()
        }
        waitForStatus("Items: 40", in: app)
        capture("Prefetch footer", app: app)
    }

    func testAutomaticFooterLoadsAtBottom() {
        let app = launch(mode: "table")
        waitForStatus("Items: 20", in: app)
        let list = app.tables["demo-list"]
        for _ in 0 ..< 12 where !app.staticTexts["demo-status"].label.contains("Items: 40") {
            list.swipeUp()
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

    func testResizePreservesData() {
        let app = launch(mode: "collection")
        waitForStatus("Items: 20", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["refresh-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo-status"].label.contains("Items: 20"))
        capture("Landscape resize", app: app)
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

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-mode", mode]
        app.launch()
        return app
    }

    private func waitForStatus(_ text: String, in app: XCUIApplication) {
        let status = app.staticTexts["demo-status"]
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
