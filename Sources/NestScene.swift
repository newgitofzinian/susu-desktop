import AppKit

struct HouseRoutine {
    enum Phase:String,CaseIterable {case free,entering,inside,bringingMat,unrolling,settling,resting,gettingUp,rolling,returning}
    private(set) var phase:Phase = .free
    private(set) var elapsed:TimeInterval=0
    private var wantsInside=false
    private(set) var isStored=false
    var progress:CGFloat {min(1,CGFloat(elapsed/duration))}
    var duration:TimeInterval {
        switch phase {
        case .entering,.bringingMat,.returning:return 6
        case .inside:return 0.5
        case .unrolling,.rolling:return 0.8
        case .settling,.gettingUp:return 0.65
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
        guard delta.isFinite,delta>=0,!(phase == .inside && isStored) else{return}
        elapsed += delta
        for _ in 0..<12 {
            guard elapsed>=duration else{break}
            elapsed -= duration
            switch phase {
            case .entering:phase = .inside
            case .inside:phase = .bringingMat
            case .bringingMat:phase = .unrolling
            case .unrolling:phase = .settling
            case .settling:phase = wantsInside ? .gettingUp : .resting
            case .gettingUp:phase = .rolling
            case .rolling:phase = .returning
            case .returning:phase = .inside;elapsed=0;wantsInside=false;isStored=true;return
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
    private(set) var routine=HouseRoutine()
    private var time:TimeInterval=0
    private var startPoint=NSPoint.zero
    private var windowOrigin=NSPoint.zero
    private var moved=false
    private(set) var draggingWhole=false
    var isRearranging:Bool {draggingWhole}
    var foxHere:Bool {routine.phase != .free && routine.phase != .inside}
    var houseRect:NSRect {NSRect(x:bounds.width*0.015,y:bounds.height*0.08,width:bounds.width*0.65,height:bounds.height*0.89)}
    var matRect:NSRect {NSRect(x:bounds.width*0.62,y:bounds.height*0.025,width:bounds.width*0.36,height:bounds.height*0.18)}
    var foxRect:NSRect {
        var x:CGFloat=0.64
        switch routine.phase {
        case .entering:x=0.92-0.76*routine.progress
        case .bringingMat:x=0.16+0.48*routine.progress
        case .returning:x=0.64-0.48*routine.progress
        default:break
        }
        let scale:CGFloat
        if routine.phase == .bringingMat {scale=0.68+0.32*min(1,routine.progress*5)}
        else if routine.phase == .entering || routine.phase == .returning {scale=0.68+0.32*min(1,(1-routine.progress)*5)}
        else{scale=1}
        let width=bounds.width*0.34*scale
        return NSRect(x:x*bounds.width,y:bounds.height*0.065,width:width,height:width*208/192)
    }
    func foxPosition()->NSPoint {foxRect.origin}
    func recall() {takeMat()}
    func putAway() {routine.putMatAway();needsDisplay=true}
    func dismissFox() {routine.release();needsDisplay=true}
    func advance(_ dt:TimeInterval) {
        time += dt
        if routine.phase == .inside && routine.isStored {return}
        let old=routine.phase
        routine.advance(dt)
        if old != routine.phase || foxHere {needsDisplay=true}
    }
    func takeMat() {routine.takeMat();needsDisplay=true}
    func simulate(_ dt:TimeInterval) {advance(dt)}
    override func draw(_ dirtyRect:NSRect) {
        guard frames != nil else{return}
        let artwork=frames.houseArtwork
        artwork.house.draw(in:houseRect)
        let phase=routine.phase,p=routine.progress
        let openMat:Bool=[.unrolling,.settling,.resting,.gettingUp,.rolling].contains(phase)
        if openMat {
            let opacity=phase == .unrolling ? p : phase == .rolling ? 1-p : 1
            artwork.mat.draw(in:matRect,from:.zero,operation:.sourceOver,fraction:opacity)
        }
        guard foxHere else{return}
        let walk=[.entering,.bringingMat,.returning].contains(phase)
        let left=phase == .entering || phase == .returning
        let rect=foxRect
        let enteringFade:CGFloat
        if phase == .entering {enteringFade=min(1,max(0,(1-p)*5))}
        else if phase == .returning {enteringFade=min(1,max(0,(1-p)*5))}
        else if phase == .bringingMat {enteringFade=min(1,p*5)}
        else{enteringFade=1}
        NSGraphicsContext.saveGraphicsState()
        if left {var flip=AffineTransform(translationByX:rect.midX*2,byY:0);flip.scale(x:-1,y:1);(flip as NSAffineTransform).concat()}
        let index=Int(time/0.18)%8
        let restMix:CGFloat=phase == .resting ? 1 : phase == .settling ? p : phase == .gettingUp ? 1-p : 0
        if restMix<1 {
            (walk ? frames.walk[index] : frames.idle[0]).draw(in:rect,from:.zero,operation:.sourceOver,fraction:enteringFade*(1-restMix))
            ScarfRenderer.overlay(state:state,walking:walk,frame:walk ? index : 0)?.draw(in:rect,from:.zero,operation:.sourceOver,fraction:enteringFade*(1-restMix))
        }
        if restMix>0 {artwork.rest.draw(in:rect,from:.zero,operation:.sourceOver,fraction:restMix)}
        NSGraphicsContext.restoreGraphicsState()
        if phase == .bringingMat || phase == .returning {
            let width=rect.width*0.30
            let carry=NSRect(x:left ? rect.minX-width*0.6 : rect.maxX-width*0.20,y:rect.minY+rect.height*0.46,width:width,height:width*0.60)
            artwork.rolled.draw(in:carry,from:.zero,operation:.sourceOver,fraction:enteringFade)
        } else if phase == .rolling || phase == .unrolling {
            let opacity=phase == .rolling ? p : 1-p
            let r=NSRect(x:matRect.midX-matRect.width*0.20,y:matRect.minY,width:matRect.width*0.4,height:matRect.height)
            artwork.rolled.draw(in:r,from:.zero,operation:.sourceOver,fraction:opacity)
        }
    }
    private func opaque(_ bitmap:NSBitmapImageRep,in rect:NSRect,at point:NSPoint,left:Bool=false)->Bool {
        guard rect.contains(point) else{return false}
        var x=min(bitmap.pixelsWide-1,max(0,Int((point.x-rect.minX)/rect.width*CGFloat(bitmap.pixelsWide))))
        if left{x=bitmap.pixelsWide-1-x}
        let y=min(bitmap.pixelsHigh-1,max(0,bitmap.pixelsHigh-1-Int((point.y-rect.minY)/rect.height*CGFloat(bitmap.pixelsHigh))))
        return (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.1
    }
    func containsProp(_ point:NSPoint)->Bool {
        guard frames != nil else{return false}
        let phase=routine.phase
        if foxHere {
            let bitmap:NSBitmapImageRep
            if phase == .resting {bitmap=frames.houseArtwork.restPixels}
            else if [.entering,.bringingMat,.returning].contains(phase) {bitmap=frames.walkPixels[Int(time/0.18)%8]}
            else{bitmap=frames.idlePixels[0]}
            if opaque(bitmap,in:foxRect,at:point,left:phase == .entering || phase == .returning){return true}
        }
        if [.unrolling,.settling,.resting,.gettingUp,.rolling].contains(phase),opaque(frames.houseArtwork.matPixels,in:matRect,at:point){return true}
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
        timer=Timer(timeInterval:1.0/30,repeats:true){[weak self] _ in self?.tick()}
        RunLoop.main.add(timer!,forMode:.common)
    }
    override func constrainFrameRect(_ frameRect:NSRect,to screen:NSScreen?)->NSRect {frameRect}
    private func tick() {
        let now=ProcessInfo.processInfo.systemUptime,dt=min(0.1,now-last);last=now
        guard isVisible else{return}
        if !paused {canvas.advance(dt)}
        let local=canvas.convert(convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
        ignoresMouseEvents = !canvas.draggingWhole && !canvas.containsProp(local)
    }
    func moveHouse(to point:NSPoint) {
        let area=allowedRect ?? NSScreen.main!.visibleFrame
        setFrameOrigin(WorkTerritory.constrain(point,window:frame.size,area:area))
    }
    func savePosition() {
        guard !CommandLine.arguments.contains("--smoke-test") else{return}
        UserDefaults.standard.set(frame.minX,forKey:"houseX");UserDefaults.standard.set(frame.minY,forKey:"houseY")
    }
    func windowWillClose(_ notification:Notification){closed?();canvas.dismissFox()}
    deinit{timer?.invalidate()}
}
