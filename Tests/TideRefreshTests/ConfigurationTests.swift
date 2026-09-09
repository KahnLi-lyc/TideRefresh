@testable import TideRefresh
import XCTest

final class ConfigurationTests: XCTestCase {
    func testInvalidGeometryUsesDefaults() {
        let configuration = RefreshConfiguration(headerHeight: .nan, footerHeight: -1)
        XCTAssertEqual(configuration.validHeaderHeight, 60)
        XCTAssertEqual(configuration.validFooterHeight, 44)
        XCTAssertEqual(configuration.shortContentPageLimit, 0)
    }
}
