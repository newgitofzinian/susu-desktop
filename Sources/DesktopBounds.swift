import AppKit

// `core` is a normalized rectangle opaque in every animation frame, including
// mirrored moving poses. Keeping a small piece of it visible prevents losing
// the fox even at a screen corner, independently of transparent window padding.
enum DesktopBounds {
    static func constrain(_ origin: NSPoint, sprite: NSSize, core: NSRect, screens: [NSRect]) -> NSPoint {
        guard !screens.isEmpty else { return origin }
        let bx: CGFloat = core.origin.x * sprite.width
        let by: CGFloat = core.origin.y * sprite.height
        let bw: CGFloat = core.size.width * sprite.width
        let bh: CGFloat = core.size.height * sprite.height
        let body = NSRect(x:bx,y:by,width:bw,height:bh)
        let keep: CGFloat = min(CGFloat(20), min(bw,bh))
        // AppKit rounds window origins to backing pixels. Reserve two points so
        // that rounding cannot consume the final visible part at a corner.
        let protected: CGFloat = keep + 2
        var result = origin
        var bestDistance = Double.greatestFiniteMagnitude
        for screen in screens {
            let lowerX: CGFloat = screen.minX - body.maxX + protected
            let upperX: CGFloat = screen.maxX - body.minX - protected
            let lowerY: CGFloat = screen.minY - body.maxY + protected
            let upperY: CGFloat = screen.maxY - body.minY - protected
            let x: CGFloat = min(max(origin.x,lowerX),upperX)
            let y: CGFloat = min(max(origin.y,lowerY),upperY)
            let dx = Double(x-origin.x), dy = Double(y-origin.y)
            let distance = dx*dx+dy*dy
            if distance < bestDistance { bestDistance = distance; result = NSPoint(x:x,y:y) }
        }
        return result
    }
}

// Row-major numbering, starting at the top left of a display's usable area.
enum WorkTerritory {
    static func cell(in screen: NSRect, index: Int) -> NSRect {
        let index = min(15, max(0, index))
        let w = screen.width / 4, h = screen.height / 4
        return NSRect(x: screen.minX + CGFloat(index % 4) * w,
                      y: screen.maxY - CGFloat(index / 4 + 1) * h, width: w, height: h)
    }

    static func width(preferred: CGFloat, area: NSRect, bubbleHeight: CGFloat = 52) -> CGFloat {
        // Reserve room for the speech bubble and rounding at the cell edges.
        max(1, min(preferred, area.width - 8, (area.height - bubbleHeight - 8) * 192 / 208))
    }

    static func constrain(_ point: NSPoint, window: NSSize, area: NSRect) -> NSPoint {
        NSPoint(x: min(max(point.x, area.minX + 2), max(area.minX + 2, area.maxX - window.width - 2)),
                y: min(max(point.y, area.minY + 2), max(area.minY + 2, area.maxY - window.height - 2)))
    }
}

struct WaterReminder {
    var interval: TimeInterval = 30 * 60
    private(set) var deadline: TimeInterval?

    mutating func restart(at now: TimeInterval) { deadline = now + interval }
    mutating func snooze(at now: TimeInterval, seconds: TimeInterval) { deadline = now + max(1,seconds) }
    mutating func poll(at now: TimeInterval, active: Bool) -> Bool {
        guard active else { deadline = nil; return false }
        guard let deadline else { restart(at: now); return false }
        guard now >= deadline else { return false }
        restart(at: now) // Never accumulate reminders after sleep or a long pause.
        return true
    }
}

// A walking route stays on its starting horizontal line and cannot cross a
// monitor gap. Running retains its existing two-dimensional destinations.
enum WalkingRoute {
    static func destination(desiredX: CGFloat, from origin: NSPoint, sprite: NSSize, core: NSRect, screens: [NSRect]) -> NSPoint {
        var intervals: [(CGFloat,CGFloat)] = []
        for screen in screens {
            let check = DesktopBounds.constrain(origin,sprite:sprite,core:core,screens:[screen])
            guard abs(check.y-origin.y) < 0.001 else { continue }
            let left = DesktopBounds.constrain(NSPoint(x:-1e8,y:origin.y),sprite:sprite,core:core,screens:[screen]).x
            let right = DesktopBounds.constrain(NSPoint(x:1e8,y:origin.y),sprite:sprite,core:core,screens:[screen]).x
            intervals.append((left,right))
        }
        intervals.sort { $0.0 < $1.0 }
        var merged: [(CGFloat,CGFloat)] = []
        for interval in intervals {
            if let last = merged.last, interval.0 <= last.1 {
                merged[merged.count-1] = (last.0,max(last.1,interval.1))
            } else { merged.append(interval) }
        }
        guard let span = merged.first(where: { origin.x >= $0.0-0.001 && origin.x <= $0.1+0.001 }) else { return origin }
        return NSPoint(x:min(max(desiredX,span.0),span.1),y:origin.y)
    }
}
