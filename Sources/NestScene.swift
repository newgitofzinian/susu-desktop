import AppKit

struct HouseRoutine {
    enum Phase:String,CaseIterable {case free,entering,inside,bringingMat,unrolling,settling,resting,gettingUp,rolling,returning,leaving}
    private(set) var phase:Phase = .free
    private(set) var elapsed:TimeInterval=0
    private var wantsInside=false
    private(set) var isStored=false
    var progress:CGFloat {min(1,CGFloat(elapsed/duration))}
    var duration:TimeInterval {
        switch phase {
        case .entering:return 4.2
        case .bringingMat,.returning:return 4.6
        case .leaving:return 3
        case .inside:return isStored ? 0.8 : 0.45
        case .unrolling,.rolling:return 1.0
        case .settling,.gettingUp:return 0.3
        default:return .infinity
        }
    }
    mutating func takeMat() {
        guard phase == .free || phase == .inside else{return}
        phase = phase == .free ? .entering : .inside;elapsed=0;isStored=false
    }
    mutating func putMatAway() {
        switch phase {
        case .resting:phase = .gettingUp;elapsed=0
        case .entering,.bringingMat,.unrolling,.settling:wantsInside=true
        case .inside:if !isStored {wantsInside=true}
        default:break
        }
    }
    mutating func release() {phase = .free;elapsed=0;wantsInside=false;isStored=false}
    mutating func advance(_ delta:TimeInterval) {
        guard delta.isFinite,delta>=0 else{return}
        elapsed += delta
        for _ in 0..<12 {
            guard elapsed>=duration else{break}
            elapsed -= duration
            switch phase {
            case .entering:phase = .inside
            case .inside:phase = isStored ? .leaving : .bringingMat
            case .bringingMat:phase = .unrolling
            case .unrolling:phase = .settling
            case .settling:phase = wantsInside ? .gettingUp : .resting
            case .gettingUp:phase = .rolling
            case .rolling:phase = .returning
            case .returning:phase = .inside;wantsInside=false;isStored=true
            case .leaving:release();return
            default:return
            }
        }
    }
}

final class HouseArtwork {
    let house:NSImage,mat:NSImage,rolled:NSImage,rest:NSImage
    let housePixels:NSBitmapImageRep
    let matPixels:NSBitmapImageRep
    let restPixels:NSBitmapImageRep
    let carry:[NSImage],blanketAction:[NSImage]
    let carryPixels:[NSBitmapImageRep],blanketPixels:[NSBitmapImageRep]
    init(resources:URL)throws {
        func load(_ name:String)throws->NSImage {
            guard let image=NSImage(contentsOf:resources.appendingPathComponent("home/\(name).png")) else {
                throw NSError(domain:"SusuHome",code:1,userInfo:[NSLocalizedDescriptionKey:"缺少小屋素材：\(name)"])
            };return image
        }
        house=try load("house");mat=try load("mat");rolled=try load("rolled");rest=try load("rest")
        housePixels=NSBitmapImageRep(data:try Data(contentsOf:resources.appendingPathComponent("home/house.png")))!
        matPixels=NSBitmapImageRep(data:try Data(contentsOf:resources.appendingPathComponent("home/mat.png")))!
        restPixels=NSBitmapImageRep(data:try Data(contentsOf:resources.appendingPathComponent("home/rest.png")))!
        func sequence(_ folder:String,_ count:Int)throws->([NSImage],[NSBitmapImageRep]) {
            var images:[NSImage]=[],pixels:[NSBitmapImageRep]=[]
            for index in 0..<count {
                let url=resources.appendingPathComponent(String(format:"home/%@/%02d.png",folder,index))
                let data=try Data(contentsOf:url)
                guard let image=NSImage(data:data),let bitmap=NSBitmapImageRep(data:data),bitmap.hasAlpha,bitmap.pixelsWide==256,bitmap.pixelsHigh==240 else {
                    throw NSError(domain:"SusuHome",code:2,userInfo:[NSLocalizedDescriptionKey:"毯子动作素材不完整：\(url.lastPathComponent)"])
                }
                images.append(image);pixels.append(bitmap)
            }
            return (images,pixels)
        }
        (carry,carryPixels)=try sequence("carry",8)
        (blanketAction,blanketPixels)=try sequence("blanket-action",6)
    }
}

final class NestCanvas:NSView {
    var state=StudioState()
    var frames:SpriteFrames!
    var saveLayout:(([String:FurniturePosition])throws->Void)?
    var onMenu:((NSEvent,NSView)->Void)?
    var onToggle:(()->Void)?
    var onDragged:((NSPoint)->Void)?
    var onDragFinished:(()->Void)?
    var onFinished:(()->Void)?
    private(set) var routine=HouseRoutine()
    private var time:TimeInterval=0
    private var startPoint=NSPoint.zero
    private var windowOrigin=NSPoint.zero
    private var moved=false
    private(set) var draggingWhole=false
    var isRearranging:Bool {draggingWhole}
    var foxHere:Bool {routine.phase != .free && routine.phase != .inside}
    var houseNeeded:Bool {routine.phase != .free}
    var houseRect:NSRect {NSRect(x:bounds.width*0.015,y:bounds.height*0.08,width:bounds.width*0.65,height:bounds.height*0.89)}
    var matRect:NSRect {NSRect(x:bounds.width*0.62,y:bounds.height*0.025,width:bounds.width*0.36,height:bounds.height*0.18)}
    var foxRect:NSRect {
        let p=routine.progress,t=p*p*(3-2*p)
        var x:CGFloat=0.59
        switch routine.phase {
        case .entering,.returning:x=0.59-0.43*t
        case .bringingMat,.leaving:x=0.16+0.43*t
        default:break
        }
        let scale:CGFloat
        if routine.phase == .bringingMat || routine.phase == .leaving {scale=0.72+0.28*min(1,routine.progress*5)}
        else if routine.phase == .entering || routine.phase == .returning {scale=0.68+0.32*min(1,(1-routine.progress)*5)}
        else{scale=1}
        let width=bounds.width*0.40*scale
        return NSRect(x:x*bounds.width,y:bounds.height*0.065,width:width,height:width*240/256)
    }
    func foxPosition()->NSPoint {foxRect.origin}
    func recall() {takeMat()}
    func putAway() {routine.putMatAway();needsDisplay=true}
    func dismissFox() {routine.release();needsDisplay=true}
    func advance(_ dt:TimeInterval) {
        time += dt
        let old=routine.phase
        routine.advance(dt)
        if old != routine.phase || foxHere {needsDisplay=true}
        if old != .free && routine.phase == .free {onFinished?()}
    }
    func takeMat() {routine.takeMat();needsDisplay=true}
    func simulate(_ dt:TimeInterval) {advance(dt)}
    private var blanketPosition:CGFloat {
        let p=routine.progress,t=p*p*(3-2*p)
        switch routine.phase {
        case .unrolling:return t*4
        case .settling:return 4+t
        case .resting:return 5
        case .gettingUp:return 5-t
        case .rolling:return 4*(1-t)
        default:return 0
        }
    }
    private var carrying:Bool {routine.phase == .bringingMat || routine.phase == .returning}
    private var walking:Bool {[.entering,.bringingMat,.returning,.leaving].contains(routine.phase)}
    private var left:Bool {routine.phase == .entering || routine.phase == .returning}
    private var walkRect:NSRect {
        let r=foxRect,w=r.width*0.85
        return NSRect(x:r.midX-w/2,y:r.minY+r.height*0.02,width:w,height:w*208/192)
    }

    private var currentPose: (CharacterPose, Int) {
        if carrying { return (.carry, Int(routine.elapsed / 0.15) % 8) }
        if walking { return (.walk, Int(routine.elapsed / 0.18) % 8) }
        return (.blanket, min(5, max(0, Int(blanketPosition.rounded()))))
    }
    override func draw(_ dirtyRect:NSRect) {
        guard frames != nil,houseNeeded else{return}
        let artwork=frames.houseArtwork
        artwork.house.draw(in:houseRect)
        guard foxHere else{return}
        let phase=routine.phase,p=routine.progress,rect=foxRect
        let opacity:CGFloat
        if phase == .entering || phase == .returning {opacity=min(1,max(0,(1-p)*7))}
        else if phase == .bringingMat || phase == .leaving {opacity=min(1,p*7)}
        else{opacity=1}
        NSGraphicsContext.saveGraphicsState()
        if left {var flip=AffineTransform(translationByX:rect.midX*2,byY:0);flip.scale(x:-1,y:1);(flip as NSAffineTransform).concat()}
        let (pose, index) = currentPose
        let poseRect = pose == .walk ? walkRect : rect
        frames.character(pose, frame: index, season: state.season).image.draw(in: poseRect, from: .zero, operation: .sourceOver, fraction: opacity)
        if pose == .walk {
            ScarfRenderer.overlay(state:state,walking:true,frame:index)?.draw(in:walkRect,from:.zero,operation:.sourceOver,fraction:opacity)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func opaque(_ bitmap:NSBitmapImageRep,in rect:NSRect,at point:NSPoint,left:Bool=false)->Bool {
        guard rect.contains(point) else{return false}
        var x=min(bitmap.pixelsWide-1,max(0,Int((point.x-rect.minX)/rect.width*CGFloat(bitmap.pixelsWide))))
        if left{x=bitmap.pixelsWide-1-x}
        let y=min(bitmap.pixelsHigh-1,max(0,bitmap.pixelsHigh-1-Int((point.y-rect.minY)/rect.height*CGFloat(bitmap.pixelsHigh))))
        return AlphaHitMask.hit(bitmap: bitmap, x: x, y: y)
    }
    func containsProp(_ point:NSPoint)->Bool {
        guard frames != nil else{return false}
        guard houseNeeded else{return false}
        if foxHere {
            let (pose, index) = currentPose
            let pixels = frames.character(pose, frame: index, season: state.season).pixels
            if opaque(pixels, in: pose == .walk ? walkRect : foxRect, at: point, left: left) { return true }
        }
        return opaque(frames.houseArtwork.housePixels,in:houseRect,at:point)
    }
    override func mouseDown(with event:NSEvent) {
        draggingWhole=true;moved=false;startPoint=NSEvent.mouseLocation;windowOrigin=window?.frame.origin ?? .zero
    }
    override func mouseDragged(with event:NSEvent) {
        let mouse=NSEvent.mouseLocation,dx=mouse.x-startPoint.x,dy=mouse.y-startPoint.y
        if hypot(dx,dy)>3{moved=true}
        onDragged?(NSPoint(x:windowOrigin.x+dx,y:windowOrigin.y+dy))
    }
    override func mouseUp(with event:NSEvent) {
        draggingWhole=false
        if moved {onDragFinished?()} else {onToggle?()}
    }
    override func rightMouseDown(with event:NSEvent) {onMenu?(event,self)}
}

final class NestWindow:NSPanel,NSWindowDelegate {
    var allowedRect:NSRect?
    var closed:(()->Void)?
    var menuProvider:(()->NSMenu)?
    let canvas=NestCanvas(frame:.zero)
    private var timer:Timer?
    private var last=ProcessInfo.processInfo.systemUptime
    var paused=false
    init(frames:SpriteFrames) {
        super.init(contentRect:NSRect(x:0,y:0,width:520,height:350),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        title="溯溯的桌面小房子";isOpaque=false;backgroundColor = .clear;hasShadow=false
        isReleasedWhenClosed=false;hidesOnDeactivate=false;level = .floating;collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];delegate=self
        canvas.frames=frames;contentView=canvas
        canvas.onDragged={ [weak self] point in guard let self else{return};self.moveHouse(to:point) }
        canvas.onDragFinished={ [weak self] in self?.savePosition() }
        canvas.onMenu={ [weak self] event,view in if let menu=self?.menuProvider?(){NSMenu.popUpContextMenu(menu,with:event,for:view)} }
        startTimerIfNeeded()
    }
    override func constrainFrameRect(_ frameRect:NSRect,to screen:NSScreen?)->NSRect {frameRect}
    private func tick() {
        let now=ProcessInfo.processInfo.systemUptime,dt=min(0.1,now-last);last=now
        guard isVisible else{return}
        if !paused {canvas.advance(dt)}
        let local=canvas.convert(convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
        ignoresMouseEvents = !canvas.draggingWhole && !canvas.containsProp(local)
    }
    private func startTimerIfNeeded() {
        guard timer == nil, isVisible else { return }
        timer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        last = ProcessInfo.processInfo.systemUptime
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    override func orderOut(_ sender: Any?) { stopTimer(); super.orderOut(sender) }
    override func orderFrontRegardless() { super.orderFrontRegardless(); startTimerIfNeeded() }
    func windowDidBecomeVisible(_ notification: Notification) { startTimerIfNeeded() }
    func moveHouse(to point:NSPoint) {
        let area=allowedRect ?? NSScreen.main!.visibleFrame
        setFrameOrigin(WorkTerritory.constrain(point,window:frame.size,area:area))
    }
    func savePosition() {
        guard !CommandLine.arguments.contains("--smoke-test") else{return}
        UserDefaults.standard.set(frame.minX,forKey:"houseX");UserDefaults.standard.set(frame.minY,forKey:"houseY")
    }
    func windowWillClose(_ notification:Notification){stopTimer();closed?();canvas.dismissFox()}
    deinit{timer?.invalidate()}
}
