import AppKit

enum MenuBarRenderer {
    /// Renders a crisp, colored CPU sparkline suitable for an NSStatusItem button.
    static func image(for values: [Double], cpu: Double) -> NSImage {
        let logicalSize = NSSize(width: 92, height: 24)
        let scale: CGFloat = 2
        let pixelSize = NSSize(width: logicalSize.width * scale, height: logicalSize.height * scale)

        let image = NSImage(size: pixelSize)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: pixelSize)
        let tint = color(for: cpu)

        // Very subtle backdrop so the graph reads on both light and dark menu bars.
        NSColor.controlBackgroundColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 1), xRadius: 3, yRadius: 3).fill()

        let samples = values.count >= 2 ? Array(values.suffix(48)) : [0, cpu]
        let inset: CGFloat = 2.5 * scale
        let height = pixelSize.height - inset * 2
        let step = pixelSize.width / CGFloat(samples.count - 1)

        func point(at index: Int) -> NSPoint {
            let v = min(max(samples[index], 0), 1)
            return NSPoint(
                x: CGFloat(index) * step,
                y: inset + CGFloat(v) * height * 0.94
            )
        }

        // Soft gradient fill under the curve.
        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: 0, y: inset))
        for i in 0..<samples.count { fill.line(to: point(at: i)) }
        fill.line(to: NSPoint(x: pixelSize.width, y: inset))
        fill.close()
        NSGradient(starting: tint.withAlphaComponent(0.42), ending: tint.withAlphaComponent(0.0))?
            .draw(in: fill, angle: 90)

        // Baseline.
        NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setStroke()
        let baseline = NSBezierPath()
        baseline.lineWidth = scale
        baseline.move(to: NSPoint(x: 0, y: inset))
        baseline.line(to: NSPoint(x: pixelSize.width, y: inset))
        baseline.stroke()

        // Main line.
        let line = NSBezierPath()
        for i in 0..<samples.count {
            let p = point(at: i)
            if i == 0 { line.move(to: p) } else { line.line(to: p) }
        }
        line.lineWidth = 1.7 * scale
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        tint.setStroke()
        line.stroke()

        // Leading dot.
        if let last = samples.indices.last {
            let p = point(at: last)
            let radius: CGFloat = 2.3 * scale
            tint.setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: p.x - radius, y: p.y - radius,
                    width: radius * 2, height: radius * 2
                )
            ).fill()
        }

        image.unlockFocus()
        image.size = logicalSize       // draw at 2x, display at 1x for retina crispness
        image.isTemplate = false
        return image
    }

    static func color(for cpu: Double) -> NSColor {
        if cpu < 0.40 {
            return NSColor(srgbRed: 0.18, green: 0.82, blue: 0.45, alpha: 1)  // green
        } else if cpu < 0.75 {
            return NSColor(srgbRed: 1.00, green: 0.72, blue: 0.10, alpha: 1)  // amber
        } else {
            return NSColor(srgbRed: 1.00, green: 0.36, blue: 0.34, alpha: 1)  // red
        }
    }
}
