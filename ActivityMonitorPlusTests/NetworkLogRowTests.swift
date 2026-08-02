import XCTest
@testable import ActivityMonitorPlus

final class NetworkLogRowTests: XCTestCase {
    func testEventsAreGroupedAndSortedByProcess() {
        let events = [
            event(name: "Zulu", pid: 30, seconds: 3),
            event(name: "alpha", pid: 20, seconds: 1),
            event(name: "Alpha", pid: 10, seconds: 2)
        ]

        let groups = NetworkLogRow.groupedByProcess(events)

        XCTAssertEqual(groups.map(\.process.name), ["Alpha", "alpha", "Zulu"])
        XCTAssertEqual(groups.map(\.process.pid), [10, 20, 30])
        XCTAssertTrue(groups.allSatisfy(\.isProcessGroup))
    }

    func testAProcessContainsNewestEventFirst() {
        let older = event(name: "Browser", pid: 42, seconds: 1, kind: .opened)
        let newer = event(name: "Browser", pid: 42, seconds: 5, kind: .traffic)

        let group = NetworkLogRow.groupedByProcess([older, newer])[0]

        XCTAssertEqual(group.eventCount, 2)
        XCTAssertEqual(group.lastActivity, newer.timestamp)
        XCTAssertEqual(group.children?.compactMap(\.event?.id), [newer.id, older.id])
    }

    func testSameNameWithDifferentPidsCreatesSeparateGroups() {
        let groups = NetworkLogRow.groupedByProcess([
            event(name: "Helper", pid: 100, seconds: 1),
            event(name: "Helper", pid: 200, seconds: 2)
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.process.pid), [100, 200])
    }

    private func event(name: String,
                       pid: Int32,
                       seconds: TimeInterval,
                       kind: ConnectionEvent.Kind = .traffic) -> ConnectionEvent {
        ConnectionEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: seconds),
            kind: kind,
            processName: name,
            pid: pid,
            local: "127.0.0.1.5000",
            remote: "93.184.216.34.443",
            proto: .tcp,
            bytesIn: 100,
            bytesOut: 50)
    }
}
