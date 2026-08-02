import SwiftUI

/// Color assignment for sunburst arcs. Reuses the CVD-separated categorical
/// order from `SlicePalette`; a top-level sector and its descendants share a
/// hue, fading outward so depth reads at a glance. Neutral tones for the folded
/// "smaller items" bucket and the "hidden" remainder.
enum StorageSlicePalette {
    static func color(for arc: SunburstArc) -> Color {
        switch arc.kind {
        case .hidden:
            return Color(nsColor: .quaternaryLabelColor)
        case .smallerItems:
            return Color(nsColor: .systemGray)
        case .folder, .file:
            let base = SlicePalette.processColors[arc.colorIndex % SlicePalette.processColors.count]
            let fade = max(0.4, 1.0 - Double(arc.depth - 1) * 0.16)
            return base.opacity(fade)
        }
    }
}

/// DaisyDisk-style nested ring chart drawn with `Canvas`. Ring 1 (innermost) is
/// the current root's children; each deeper ring nests inside its parent's
/// angular span. Tapping a navigable arc re-roots via `onSelect`. Purely
/// presentational — all geometry comes from the tested `SunburstGeometry`.
struct SunburstView: View {
    let root: StorageNode
    var maxRings: Int = 4
    var onSelect: (StorageNode) -> Void

    private let holeRatio = 0.30
    private let outerRatio = 0.98
    /// Slices thinner than this fraction of the turn are skipped (unreadable slivers).
    private let minSpan = 0.0009

    var body: some View {
        let arcs = SunburstGeometry.arcs(root: root, maxRings: maxRings)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Canvas { context, _ in
                let radius = side / 2
                let hole = radius * holeRatio
                let ringWidth = (radius * outerRatio - hole) / Double(maxRings)
                for arc in arcs where arc.span >= minSpan {
                    let inner = hole + ringWidth * Double(arc.depth - 1)
                    let outer = inner + ringWidth * 0.9   // hairline gap between rings
                    let path = Self.annularSector(center: center, inner: inner, outer: outer,
                                                  start: arc.start, end: arc.end)
                    context.fill(path, with: .color(StorageSlicePalette.color(for: arc)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let arc = hitTest(location: location, center: center, side: side, arcs: arcs),
                   let node = root.node(withID: arc.nodeID), node.isNavigable {
                    onSelect(node)
                }
            }
        }
        // The chart's per-arc detail is deliberately opaque to accessibility;
        // the surrounding legend list is the accessible representation.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage sunburst for \(root.name), \(Format.bytes(root.sizeBytes))")
        .accessibilityIdentifier("storage.breakdown.sunburst")
    }

    private func hitTest(location: CGPoint, center: CGPoint, side: Double,
                         arcs: [SunburstArc]) -> SunburstArc? {
        let radius = side / 2
        let hole = radius * holeRatio
        let ringWidth = (radius * outerRatio - hole) / Double(maxRings)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= hole, r <= radius * outerRatio, ringWidth > 0 else { return nil }

        let depth = Int((r - hole) / ringWidth) + 1
        guard depth >= 1, depth <= maxRings else { return nil }

        // atan2 measures from +x; convert to our "0 at top, clockwise" fraction.
        var fraction = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
        fraction = fraction.truncatingRemainder(dividingBy: 1)
        if fraction < 0 { fraction += 1 }

        return arcs.first { $0.depth == depth && fraction >= $0.start && fraction < $0.end }
    }

    /// A filled annular sector. `start`/`end` are fractions of the full turn with
    /// 0 at the top going clockwise; sampled into a polygon so orientation is
    /// unambiguous.
    static func annularSector(center: CGPoint, inner: Double, outer: Double,
                              start: Double, end: Double) -> Path {
        var path = Path()
        let steps = max(2, Int((end - start) * 260))
        func point(_ fraction: Double, _ r: Double) -> CGPoint {
            let angle = fraction * 2 * .pi - .pi / 2
            return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        }
        path.move(to: point(start, outer))
        for i in 1...steps {
            path.addLine(to: point(start + (end - start) * Double(i) / Double(steps), outer))
        }
        for i in 0...steps {
            path.addLine(to: point(end - (end - start) * Double(i) / Double(steps), inner))
        }
        path.closeSubpath()
        return path
    }
}
