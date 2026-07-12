import XCTest
@testable import ActivityMonitorPlus

final class RingBufferTests: XCTestCase {
    func testAppendBelowCapacityKeepsOrder() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(contentsOf: [1, 2, 3])
        XCTAssertEqual(buffer.elements, [1, 2, 3])
        XCTAssertEqual(buffer.count, 3)
    }

    func testOverflowDropsOldestAndPreservesOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])
        XCTAssertEqual(buffer.elements, [3, 4, 5])
        XCTAssertEqual(buffer.count, 3)
        buffer.append(6)
        XCTAssertEqual(buffer.elements, [4, 5, 6])
    }

    func testRemoveAllResetsBuffer() {
        var buffer = RingBuffer<Int>(capacity: 2)
        buffer.append(contentsOf: [1, 2, 3])
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        buffer.append(contentsOf: [7, 8, 9])
        XCTAssertEqual(buffer.elements, [8, 9])
    }
}

final class FormattersTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(999), "999 B")
        XCTAssertEqual(Format.bytes(12_300), "12.3 KB")
        XCTAssertEqual(Format.bytes(4_500), "4.5 KB")
        XCTAssertEqual(Format.bytes(2_000_000), "2 MB")
        XCTAssertEqual(Format.bytes(500_000_000_000), "500 GB")
    }

    func testRate() {
        XCTAssertEqual(Format.rate(1_500), "1.5 KB/s")
        XCTAssertEqual(Format.rate(-5), "0 B/s")
    }

    func testPercent() {
        XCTAssertEqual(Format.percent(0.62), "62%")
        XCTAssertEqual(Format.percent(0), "0%")
        XCTAssertEqual(Format.percent(1), "100%")
    }
}
