import XCTest
@testable import ActivityMonitorPlus

final class StorageTreeTests: XCTestCase {
    private let cap = StorageTree.defaultTopFilesPerDir
    private let globalCap = StorageTree.defaultGlobalFileCap

    private func node(_ path: String, _ size: UInt64,
                      kind: StorageNode.Kind = .folder) -> StorageNode {
        StorageNode(name: StorageTree.lastComponent(path), path: path, sizeBytes: size,
                    isDirectory: kind == .folder, kind: kind, children: [])
    }

    // MARK: build / rollup

    func testDirectoryTotalRollsUpOwnFilesAndChildDirectories() {
        var acc = ScanAccumulator()
        acc.addDirectory(path: "/r", parent: nil)
        acc.addDirectory(path: "/r/a", parent: "/r")
        acc.addFile(parent: "/r", name: "own.bin", bytes: 100, capPerDir: cap, globalCap: globalCap)
        acc.addFile(parent: "/r/a", name: "child.bin", bytes: 50, capPerDir: cap, globalCap: globalCap)

        let root = StorageTree.build(rootPath: "/r", rootName: "R", accumulator: acc, usedBytes: 150)

        XCTAssertEqual(root.sizeBytes, 150)
        XCTAssertFalse(root.children.contains { $0.kind == .hidden })
    }

    func testHiddenRemainderAppendedWhenUsedExceedsScanned() {
        var acc = ScanAccumulator()
        acc.addDirectory(path: "/r", parent: nil)
        acc.addFile(parent: "/r", name: "f.bin", bytes: 100, capPerDir: cap, globalCap: globalCap)

        let root = StorageTree.build(rootPath: "/r", rootName: "R", accumulator: acc, usedBytes: 300)

        XCTAssertEqual(root.sizeBytes, 300, "root anchors to the volume's used bytes")
        let hidden = root.children.first { $0.kind == .hidden }
        XCTAssertEqual(hidden?.sizeBytes, 200)
        XCTAssertEqual(hidden?.name, "System / hidden space")
    }

    func testNoHiddenRemainderWhenScanExceedsReportedUsed() {
        // Allocation quirks can make the walk total slightly exceed reported used;
        // never emit a negative/underflowed hidden node.
        var acc = ScanAccumulator()
        acc.addDirectory(path: "/r", parent: nil)
        acc.addFile(parent: "/r", name: "f.bin", bytes: 500, capPerDir: cap, globalCap: globalCap)

        let root = StorageTree.build(rootPath: "/r", rootName: "R", accumulator: acc, usedBytes: 300)

        XCTAssertFalse(root.children.contains { $0.kind == .hidden })
        XCTAssertEqual(root.sizeBytes, 500)
    }

    // MARK: prune

    func testPruneKeepsTopNAndFoldsRemainderIntoSmallerItems() {
        let dirs = [node("/r/a", 100), node("/r/b", 50), node("/r/c", 10)]
        let kept = StorageTree.prune(dirNodes: dirs, fileNodes: [], ownRemainder: 0,
                                     topN: 2, parentPath: "/r")

        XCTAssertEqual(kept.map(\.sizeBytes), [100, 50, 10])
        let smaller = kept.first { $0.kind == .smallerItems }
        XCTAssertEqual(smaller?.sizeBytes, 10)
        XCTAssertEqual(smaller?.name, "smaller items")
    }

    func testPruneFoldsOwnRemainderEvenWithNoOverflow() {
        let kept = StorageTree.prune(dirNodes: [], fileNodes: [], ownRemainder: 25,
                                     topN: 40, parentPath: "/r")
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.kind, .smallerItems)
        XCTAssertEqual(kept.first?.sizeBytes, 25)
    }

    // MARK: accumulator top-K

    func testAccumulatorKeepsLargestFilesPerDirectoryUpToCap() {
        var acc = ScanAccumulator()
        acc.addDirectory(path: "/r", parent: nil)
        for i in 0..<5 {
            acc.addFile(parent: "/r", name: "f\(i)", bytes: UInt64(i * 10),
                        capPerDir: 3, globalCap: 1000)
        }
        XCTAssertEqual(acc.ownBytes["/r"], 100)                    // 0+10+20+30+40
        XCTAssertEqual(acc.topFiles["/r"]?.map(\.bytes), [40, 30, 20])

        // The 10 bytes not covered by the kept top-3 files surface as smaller items.
        let root = StorageTree.build(rootPath: "/r", rootName: "R", accumulator: acc, usedBytes: 100)
        let smaller = root.children.first { $0.kind == .smallerItems }
        XCTAssertEqual(smaller?.sizeBytes, 10)
    }

    func testGlobalFileCapStopsMaterializingButKeepsAggregating() {
        var acc = ScanAccumulator()
        acc.addDirectory(path: "/r", parent: nil)
        acc.addFile(parent: "/r", name: "a", bytes: 10, capPerDir: 20, globalCap: 1)
        acc.addFile(parent: "/r", name: "b", bytes: 20, capPerDir: 20, globalCap: 1)

        XCTAssertTrue(acc.hitFileCap)
        XCTAssertEqual(acc.ownBytes["/r"], 30, "bytes still aggregate past the cap")
        XCTAssertEqual(acc.topFiles["/r"]?.count, 1, "only files up to the cap are materialized")
    }

    // MARK: sunburst geometry

    func testArcFractionsPartitionTheCircleAndParentSpans() {
        var acc = ScanAccumulator()
        acc.addDirectory(path: "/r", parent: nil)
        acc.addDirectory(path: "/r/a", parent: "/r")
        acc.addDirectory(path: "/r/b", parent: "/r")
        acc.addFile(parent: "/r/a", name: "fa", bytes: 60, capPerDir: cap, globalCap: globalCap)
        acc.addFile(parent: "/r/b", name: "fb", bytes: 40, capPerDir: cap, globalCap: globalCap)

        let root = StorageTree.build(rootPath: "/r", rootName: "R", accumulator: acc, usedBytes: 100)
        let arcs = SunburstGeometry.arcs(root: root, maxRings: 4)

        let depth1 = arcs.filter { $0.depth == 1 }
        XCTAssertEqual(depth1.map(\.span).reduce(0, +), 1.0, accuracy: 1e-9)

        // A parent's children exactly tile the parent's angular span.
        guard let aArc = depth1.first(where: { $0.nodeID == "/r/a" }) else {
            return XCTFail("missing arc for /r/a")
        }
        let aChildren = arcs.filter { $0.depth == 2 && $0.start >= aArc.start - 1e-9 && $0.end <= aArc.end + 1e-9 }
        XCTAssertEqual(aChildren.map(\.span).reduce(0, +), aArc.span, accuracy: 1e-9)
    }

    func testArcsStopAtMaxRings() {
        var acc = ScanAccumulator()
        acc.addDirectory(path: "/r", parent: nil)
        acc.addDirectory(path: "/r/a", parent: "/r")
        acc.addDirectory(path: "/r/a/b", parent: "/r/a")
        acc.addFile(parent: "/r/a/b", name: "deep", bytes: 100, capPerDir: cap, globalCap: globalCap)

        let root = StorageTree.build(rootPath: "/r", rootName: "R", accumulator: acc, usedBytes: 100)
        let arcs = SunburstGeometry.arcs(root: root, maxRings: 2)

        XCTAssertTrue(arcs.allSatisfy { $0.depth <= 2 })
        XCTAssertFalse(arcs.isEmpty)
    }
}
