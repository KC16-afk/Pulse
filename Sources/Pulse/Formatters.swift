import Foundation

enum Formatters {
    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "GB", "TB"]
        var amount = Double(value)
        var index = 0
        while amount >= 1024 && index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        if index == 0 {
            return String(format: "%.0f %@", amount, units[index])
        }
        return String(format: amount >= 100 ? "%.0f %@" : "%.1f %@", amount, units[index])
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let clamped = UInt64(max(bytesPerSecond, 0))
        return bytes(clamped) + "/s"
    }

    static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}
