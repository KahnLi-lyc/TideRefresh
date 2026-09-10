@testable import TideRefresh
import XCTest

final class ConfigurationTests: XCTestCase {
    func testRefreshAxisAndEdgesExposeHorizontalSemantics() {
        XCTAssertEqual(RefreshAxis.vertical, .vertical)
        XCTAssertEqual(RefreshAxis.horizontal, .horizontal)
        XCTAssertEqual(RefreshEdge.leading, .leading)
        XCTAssertEqual(RefreshEdge.trailing, .trailing)
    }

    func testInvalidGeometryUsesDefaults() {
        let configuration = RefreshConfiguration(headerHeight: .nan, footerHeight: -1)
        XCTAssertEqual(configuration.validHeaderHeight, 60)
        XCTAssertEqual(configuration.validFooterHeight, 44)
        XCTAssertEqual(configuration.shortContentPageLimit, 0)
    }
}
