import AppKit

// Regression: whole-window clamps created invisible walls in 1.0. Test the
// body-based safety constraint, including offset displays and display gaps.
let screens = [NSRect(x:0,y:40,width:1440,height:860), NSRect(x:-1920,y:-120,width:1920,height:1080)]
let core = NSRect(x:0.4,y:0.25,width:0.18,height:0.16)
var checks = 0
for width: CGFloat in [160,208,272] {
    let size = NSSize(width:width,height:width*208/192)
    for x in stride(from:-3200,through:2600,by:173) {
        for y in stride(from:-800,through:1600,by:137) {
            let proposed = NSPoint(x:x,y:y)
            let p = DesktopBounds.constrain(proposed,sprite:size,core:core,screens:screens)
            let body = NSRect(x:p.x+core.minX*size.width,y:p.y+core.minY*size.height,width:core.width*size.width,height:core.height*size.height)
            let keep = min(20,min(body.width,body.height))
            precondition(screens.contains { let overlap = body.intersection($0); return overlap.width >= keep-0.0001 && overlap.height >= keep-0.0001 })
            checks += 1
        }
    }
    let left = DesktopBounds.constrain(NSPoint(x:-10000,y:100),sprite:size,core:core,screens:[screens[0]])
    let right = DesktopBounds.constrain(NSPoint(x:10000,y:100),sprite:size,core:core,screens:[screens[0]])
    precondition(left.x < screens[0].minX && right.x+width > screens[0].maxX,"Allow partial screen exit")
    let gapDisplays = [NSRect(x:0,y:0,width:1200,height:800), NSRect(x:1600,y:400,width:1200,height:800)]
    let gapPoint = DesktopBounds.constrain(NSPoint(x:1400,y:300),sprite:size,core:core,screens:gapDisplays)
    precondition(gapPoint.x != 1400,"Do not lose the fox in a display gap")
}
print("PASS: \(checks) boundary placements across three sizes, four edges, negative display coordinates and monitor gaps.")
