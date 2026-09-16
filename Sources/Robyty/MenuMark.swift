import AppKit

enum MenuMark {
    static func image() -> NSImage {
        let point = NSSize(width: 18, height: 18)
        let scale: CGFloat = 2
        let px = Int(point.width * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px,
            pixelsHigh: px,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = point

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: point).fill()
        NSColor.black.set()

        let rect = NSRect(origin: .zero, size: point)
        let inset: CGFloat = 1.6
        let ring = rect.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = ring.width / 2
        let path = NSBezierPath()
        // Gap at ~1:30. Cocoa angles: 0 is 3 o'clock, counterclockwise.
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 48,
            endAngle: 18,
            clockwise: false
        )
        path.lineWidth = 1.8
        path.lineCapStyle = .butt
        path.stroke()

        let sunR: CGFloat = 2.05
        let sunCenter = NSPoint(
            x: center.x + radius * 0.72,
            y: center.y + radius * 0.72
        )
        let sun = NSRect(
            x: sunCenter.x - sunR,
            y: sunCenter.y - sunR,
            width: sunR * 2,
            height: sunR * 2
        )
        NSBezierPath(ovalIn: sun).fill()

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: point)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
