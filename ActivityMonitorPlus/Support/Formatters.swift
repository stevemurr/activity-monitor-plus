import Foundation

/// Deterministic, locale-independent formatting (UI tests assert on these strings).
enum Format {
    static func bytes(_ value: UInt64) -> String {
        scaled(Double(value), suffix: "")
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        scaled(max(0, bytesPerSecond), suffix: "/s")
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    private static func scaled(_ value: Double, suffix: String) -> String {
        var scaled = value
        var unit = 0
        while scaled >= 1000, unit < units.count - 1 {
            scaled /= 1000
            unit += 1
        }
        let number: String
        if unit == 0 {
            number = String(Int(scaled))
        } else if scaled >= 100 {
            number = String(format: "%.0f", scaled)
        } else {
            let oneDecimal = String(format: "%.1f", scaled)
            number = oneDecimal.hasSuffix(".0") ? String(oneDecimal.dropLast(2)) : oneDecimal
        }
        return "\(number) \(units[unit])\(suffix)"
    }
}
