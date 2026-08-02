import Foundation

/// A node in a scanned storage hierarchy. Directories carry their recursive
/// total; leaves are individual large files, a coalesced "smaller items"
/// bucket, or the "System / hidden space" remainder. All pure and `Sendable`
/// so the scanner can build it off the main actor and hand it across.
struct StorageNode: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case folder
        case file
        /// The folded remainder of a directory's smaller children.
        case smallerItems
        /// Space the scan could not attribute (sealed system files, APFS
        /// purgeable, permission-denied areas). Anchored to the volume total.
        case hidden
    }

    var name: String
    var path: String
    var sizeBytes: UInt64
    var isDirectory: Bool
    var kind: Kind
    var children: [StorageNode]

    var id: String { path }

    /// Only folders with real sub-nodes can be drilled into.
    var isNavigable: Bool { kind == .folder && !children.isEmpty }

    /// Depth-first lookup by id (== path). Used to re-root on an arc tap.
    func node(withID id: String) -> StorageNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.node(withID: id) { return found }
        }
        return nil
    }
}

/// One file kept for display, before tree assembly.
struct FileEntry: Sendable, Equatable {
    var name: String
    var bytes: UInt64
}

/// Streaming scan state. Only *directories* are keyed here (bounded by folder
/// count, not file count); each directory keeps its own-file byte total plus a
/// capped list of its largest files so notable big files still surface without
/// holding a node per file.
struct ScanAccumulator: Sendable {
    /// Directory path → sum of that directory's own files' allocated bytes.
    var ownBytes: [String: UInt64] = [:]
    /// Directory path → its immediate child directory paths (registration order).
    var childDirs: [String: [String]] = [:]
    /// Directory path → up to `capPerDir` largest own files, kept sorted desc.
    var topFiles: [String: [FileEntry]] = [:]

    var scannedBytes: UInt64 = 0
    var fileCount: Int = 0
    var deniedCount: Int = 0
    /// Count of individually materialized file entries, to enforce `globalCap`.
    var materializedFiles: Int = 0
    /// Set once the global file cap was hit and further files are size-only.
    var hitFileCap = false

    /// Register a directory (idempotent) and link it under its parent.
    mutating func addDirectory(path: String, parent: String?) {
        if childDirs[path] == nil { childDirs[path] = [] }
        if ownBytes[path] == nil { ownBytes[path] = 0 }
        if let parent, parent != path {
            childDirs[parent, default: []].append(path)
        }
    }

    /// Add a file's bytes to its parent directory, keeping the top-K by size.
    mutating func addFile(parent: String, name: String, bytes: UInt64,
                          capPerDir: Int, globalCap: Int) {
        ownBytes[parent, default: 0] += bytes
        scannedBytes += bytes
        fileCount += 1

        // Once the global cap is reached, keep aggregating bytes but stop
        // materializing individual file nodes.
        if materializedFiles >= globalCap {
            hitFileCap = true
            return
        }
        var files = topFiles[parent] ?? []
        if files.count < capPerDir {
            files.append(FileEntry(name: name, bytes: bytes))
            files.sort { $0.bytes > $1.bytes }
            materializedFiles += 1
        } else if let smallest = files.last, bytes > smallest.bytes {
            files[files.count - 1] = FileEntry(name: name, bytes: bytes)
            files.sort { $0.bytes > $1.bytes }
        }
        topFiles[parent] = files
    }
}

enum StorageTree {
    /// Max children rendered per ring segment before folding into "smaller items".
    static let defaultTopN = 40
    /// Largest individual files kept per directory.
    static let defaultTopFilesPerDir = 20
    /// Hard ceiling on materialized file nodes across the whole scan.
    static let defaultGlobalFileCap = 300_000

    private static let smallerSentinel = "\u{2063}smaller"
    private static let hiddenSentinel = "\u{2063}hidden"

    /// Build the display tree from a completed scan. `usedBytes` is the volume's
    /// reported used space (ground truth); any of it the walk could not attribute
    /// becomes a single "System / hidden space" node so the chart always totals
    /// to the real usage.
    static func build(rootPath: String,
                      rootName: String,
                      accumulator: ScanAccumulator,
                      usedBytes: UInt64,
                      topN: Int = defaultTopN) -> StorageNode {
        var root = makeNode(path: rootPath, name: rootName,
                            accumulator: accumulator, topN: topN)

        let scanned = root.sizeBytes
        if usedBytes > scanned {
            let hidden = StorageNode(name: "System / hidden space",
                                     path: rootPath + hiddenSentinel,
                                     sizeBytes: usedBytes - scanned,
                                     isDirectory: false, kind: .hidden, children: [])
            root.children.append(hidden)
            root.children.sort { $0.sizeBytes > $1.sizeBytes }
            root.sizeBytes = usedBytes
        }
        return root
    }

    private static func makeNode(path: String, name: String,
                                 accumulator: ScanAccumulator, topN: Int) -> StorageNode {
        let dirNodes = (accumulator.childDirs[path] ?? []).map { childPath in
            makeNode(path: childPath, name: lastComponent(childPath),
                     accumulator: accumulator, topN: topN)
        }
        let fileNodes = (accumulator.topFiles[path] ?? []).map { file in
            StorageNode(name: file.name, path: path + "/" + file.name,
                        sizeBytes: file.bytes, isDirectory: false,
                        kind: .file, children: [])
        }
        let shownFileBytes = fileNodes.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let ownBytes = accumulator.ownBytes[path] ?? 0
        // Own bytes not covered by the kept top files (capped or over-cap files).
        let ownRemainder = ownBytes > shownFileBytes ? ownBytes - shownFileBytes : 0

        let children = prune(dirNodes: dirNodes, fileNodes: fileNodes,
                             ownRemainder: ownRemainder, topN: topN, parentPath: path)
        let childDirTotal = dirNodes.reduce(UInt64(0)) { $0 + $1.sizeBytes }

        return StorageNode(name: name, path: path,
                           sizeBytes: ownBytes + childDirTotal,
                           isDirectory: true, kind: .folder, children: children)
    }

    /// Keep the `topN` largest children; fold everything else — plus any
    /// un-itemized own bytes — into one "smaller items" node.
    static func prune(dirNodes: [StorageNode], fileNodes: [StorageNode],
                      ownRemainder: UInt64, topN: Int, parentPath: String) -> [StorageNode] {
        var all = dirNodes + fileNodes
        all.sort { $0.sizeBytes > $1.sizeBytes }

        var kept: [StorageNode] = []
        var smallerBytes = ownRemainder
        for (index, child) in all.enumerated() {
            if index < topN {
                kept.append(child)
            } else {
                smallerBytes += child.sizeBytes
            }
        }
        if smallerBytes > 0 {
            kept.append(StorageNode(name: "smaller items",
                                    path: parentPath + smallerSentinel,
                                    sizeBytes: smallerBytes, isDirectory: false,
                                    kind: .smallerItems, children: []))
        }
        kept.sort { $0.sizeBytes > $1.sizeBytes }
        return kept
    }

    static func lastComponent(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}

/// Pure ring layout for the sunburst. Each arc's span is a fraction of the full
/// turn (0...1); a node's children exactly partition the node's own span, so a
/// ring's arcs never overflow their parent. Depth 1 is the innermost ring
/// (the current root's children); the hole in the middle shows the total.
struct SunburstArc: Identifiable, Sendable, Equatable {
    var nodeID: String
    var name: String
    var sizeBytes: UInt64
    var kind: StorageNode.Kind
    var depth: Int        // 1-based ring index outward from the center hole
    var start: Double     // fraction of the full turn, [0, 1]
    var end: Double       // fraction of the full turn, [0, 1]
    /// Index of the depth-1 ancestor, so a top-level sector and its descendants
    /// share a color family.
    var colorIndex: Int

    var id: String { "\(nodeID)@\(depth)" }
    var span: Double { end - start }
}

enum SunburstGeometry {
    /// Flatten `root`'s descendants into ring arcs, up to `maxRings` deep.
    static func arcs(root: StorageNode, maxRings: Int) -> [SunburstArc] {
        var result: [SunburstArc] = []

        func layout(_ node: StorageNode, depth: Int, start: Double, end: Double,
                    colorIndex: Int) {
            guard depth <= maxRings else { return }
            let total = node.sizeBytes
            let span = end - start
            guard total > 0, span > 0 else { return }

            var cursor = start
            for (index, child) in node.children.enumerated() {
                let fraction = Double(child.sizeBytes) / Double(total)
                let childStart = cursor
                let childEnd = min(end, cursor + span * fraction)
                cursor = childEnd
                let color = depth == 1 ? index : colorIndex
                result.append(SunburstArc(nodeID: child.id, name: child.name,
                                          sizeBytes: child.sizeBytes, kind: child.kind,
                                          depth: depth, start: childStart, end: childEnd,
                                          colorIndex: color))
                layout(child, depth: depth + 1, start: childStart, end: childEnd,
                       colorIndex: color)
            }
        }

        layout(root, depth: 1, start: 0, end: 1, colorIndex: 0)
        return result
    }
}
