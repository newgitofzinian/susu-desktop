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
