import SwiftUI
import XCTest
@testable import ActivityMonitorPlus

final class AppAppearanceTests: XCTestCase {
    func testSystemFollowsOS() {
        XCTAssertNil(AppAppearance.system.colorScheme,
                     "system must map to nil so SwiftUI follows the OS setting")
    }

    func testLightAndDarkMap() {
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testRawValueRoundTrips() {
        for appearance in AppAppearance.allCases {
            XCTAssertEqual(AppAppearance(rawValue: appearance.rawValue), appearance)
        }
    }
}
