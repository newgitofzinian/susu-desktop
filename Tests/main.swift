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

var territoryChecks = 0
for screen in screens + [NSRect(x:0,y:0,width:800,height:520)] {
    var sum: CGFloat = 0
    for index in 0..<16 {
        let area = WorkTerritory.cell(in:screen,index:index)
        precondition(screen.contains(area))
        sum += area.width * area.height
        precondition(index % 4 != 0 || area.minX == screen.minX)
        precondition(index / 4 != 0 || area.maxY == screen.maxY)
        for preferred: CGFloat in [160,208,272] {
            let width = WorkTerritory.width(preferred:preferred,area:area)
            let size = NSSize(width:width,height:width*208/192+52)
            for point in [NSPoint(x:-99999,y:-99999),NSPoint(x:99999,y:99999),NSPoint(x:area.midX,y:area.midY)] {
                let result = WorkTerritory.constrain(point,window:size,area:area)
                precondition(area.contains(NSRect(origin:result,size:size)),"Confine the entire sprite and bubble")
                precondition(WorkTerritory.constrain(result,window:size,area:area) == result)
                territoryChecks += 1
            }
        }
    }
    precondition(abs(sum-screen.width*screen.height) < 0.01,"16 cells cover exactly one screen")
}
var water = WaterReminder()
precondition(!water.poll(at:0,active:false))
precondition(!water.poll(at:100,active:true))
precondition(!water.poll(at:1899,active:true))
precondition(water.poll(at:1900,active:true))
precondition(!water.poll(at:1900,active:true),"Do not repeat in adjacent ticks")
precondition(!water.poll(at:2000,active:false))
precondition(!water.poll(at:10000,active:true),"Resume starts a fresh interval")
precondition(water.poll(at:11800,active:true))
precondition(water.poll(at:100000,active:true),"One reminder after a delayed active tick")
precondition(!water.poll(at:100000,active:true),"Never catch up with a burst")
for minutes in [15,30,45,60] {
    water.interval = Double(minutes)*60; water.restart(at:200000)
    precondition(!water.poll(at:200000+Double(minutes)*60-1,active:true))
    precondition(water.poll(at:200000+Double(minutes)*60,active:true))
}
print("PASS: \(territoryChecks) work territory placements; 4×4 coverage and top-left numbering; reminder intervals, pause/resume and missed-interval behavior.")

water.interval = 1800
water.snooze(at:300000,seconds:300)
precondition(!water.poll(at:300299,active:true))
precondition(water.poll(at:300300,active:true),"Snooze fires after five minutes")
precondition(water.interval == 1800,"Snooze leaves the regular interval unchanged")
water.restart(at:300400)
precondition(!water.poll(at:302199,active:true))
precondition(water.poll(at:302200,active:true),"Acknowledging restarts the regular interval")
water.snooze(at:400000,seconds:300)
precondition(!water.poll(at:400010,active:false))
precondition(!water.poll(at:500000,active:true),"Inactive mode clears a pending snooze")
print("PASS: five-minute snooze, acknowledgement and cancellation while inactive.")

var horizontalChecks = 0
for screenSet in [screens,[NSRect(x:0,y:0,width:1200,height:800),NSRect(x:1600,y:200,width:1200,height:800)]] {
    for screen in screenSet {
        let origin = NSPoint(x:screen.midX,y:screen.midY)
        for width: CGFloat in [160,208,272] {
            let sprite = NSSize(width:width,height:width*208/192)
            for desired: CGFloat in [-100000,-800,0,500,1600,100000] {
                let destination = WalkingRoute.destination(desiredX:desired,from:origin,sprite:sprite,core:core,screens:screenSet)
                precondition(destination.y == origin.y,"Walking preserves its initial height")
                // Every point on the route is reachable without vertical correction.
                for step in 0...20 {
                    let point=NSPoint(x:origin.x+(destination.x-origin.x)*CGFloat(step)/20,y:origin.y)
                    let constrained=DesktopBounds.constrain(point,sprite:sprite,core:core,screens:screenSet)
                    precondition(hypot(constrained.x-point.x,constrained.y-point.y)<0.001,"Horizontal walk cannot cross an unreachable display gap")
                    horizontalChecks += 1
                }
            }
        }
    }
}
print("PASS: \(horizontalChecks) horizontal walk route samples preserve height and avoid monitor gaps.")
