import AppKit

final class CloseupView:NSView {
    var image:NSImage!
    var reactions:[NSImage]=[]
    var muted=true
    var feedback:((String)->Void)?
    var menuProvider:(()->NSMenu)?
    private var hitPixels: [ObjectIdentifier:NSBitmapImageRep] = [:]
    private var ear=0
    private var progress:CGFloat=0
    private var timer:Timer?
    private var lastPoint:NSPoint?
    private var scratched=false
    private var tailIndex=0
    private var happy=false
    private var sound:NSSound?
    private var actor:NSRect {NSRect(x:(bounds.width-300)/2,y:15,width:300,height:325)}
    private func rect(_ unit:NSRect)->NSRect {NSRect(x:actor.minX+unit.minX*actor.width,y:actor.minY+unit.minY*actor.height,width:unit.width*actor.width,height:unit.height*actor.height)}
    private let ears=[NSRect(x:20.0/192,y:130.0/208,width:52.0/192,height:78.0/208),NSRect(x:95.0/192,y:130.0/208,width:55.0/192,height:78.0/208)]
    private let tail=[NSPoint(x:0.7533,y:0.4375),NSPoint(x:0.8215,y:0.4170),NSPoint(x:0.8694,y:0.3702)]
    private var reactionIndex: Int { happy ? 2 : progress > 0 ? ear : -1 }
    private var selectedImage: NSImage? { reactions.indices.contains(reactionIndex) ? reactions[reactionIndex] : image }
    func setAppearance(idle: CharacterFrame, reactions: [CharacterFrame]) {
        image = idle.image
        self.reactions = reactions.map(\.image)
        hitPixels = Dictionary(uniqueKeysWithValues: ([idle] + reactions).map { (ObjectIdentifier($0.image), $0.pixels) })
        needsDisplay = true
    }
    override func draw(_ dirtyRect:NSRect) {
        guard let selected=selectedImage else{return}
        selected.draw(in:actor)
        if reactionIndex>=0{return}
        for (i,p) in tail.enumerated() {
            let point=NSPoint(x:actor.minX+p.x*actor.width,y:actor.minY+p.y*actor.height)
            (i<tailIndex ? NSColor.systemTeal : NSColor.systemOrange).setStroke()
            let ring=NSBezierPath(ovalIn:NSRect(x:point.x-11,y:point.y-11,width:22,height:22));ring.lineWidth=2;ring.stroke()
        }
    }
    func scratch(_ side:Int) {
        timer?.invalidate();ear=side;progress=0.01;happy=false
        feedback?(side==0 ? "左耳轻轻贴近你。" : "右耳轻轻贴近你。")
        timer=Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true){[weak self] timer in
            guard let self else{timer.invalidate();return}
            self.progress += 0.045
            if self.progress>=1 {self.progress=0;timer.invalidate()}
            self.needsDisplay=true
        }
    }
    func touchTail(_ index:Int) {
        guard (0..<3).contains(index) else{return}
        if index==tailIndex {tailIndex += 1} else {tailIndex=index==0 ? 1 : 0}
        if tailIndex==3 {
            timer?.invalidate();progress=0;happy=true;tailIndex=0
            timer=Timer.scheduledTimer(withTimeInterval:1.5,repeats:false){[weak self] _ in self?.happy=false;self?.needsDisplay=true}
            feedback?(muted ? "暗号收到！溯溯眯起眼睛。" : "暗号收到，溯溯轻轻叫了一声。")
            if !muted {playYip()}
        } else {happy=false;feedback?("已点亮 \(tailIndex) 颗纹样，继续从上往下触碰。")}
        needsDisplay=true
    }
    func containsVisible(_ point:NSPoint)->Bool {
        guard actor.contains(point), let selected=selectedImage else{return false}
        let key = ObjectIdentifier(selected)
        if hitPixels[key] == nil, let data=selected.tiffRepresentation {hitPixels[key]=NSBitmapImageRep(data:data)}
        guard let bitmap=hitPixels[key] else{return false}
        let x=min(bitmap.pixelsWide-1,max(0,Int((point.x-actor.minX)/actor.width*CGFloat(bitmap.pixelsWide))))
        let y=min(bitmap.pixelsHigh-1,max(0,bitmap.pixelsHigh-1-Int((point.y-actor.minY)/actor.height*CGFloat(bitmap.pixelsHigh))))
        return AlphaHitMask.hit(bitmap: bitmap, x: x, y: y)
    }
    override func rightMouseDown(with event:NSEvent) {
        if let menu=menuProvider?(){NSMenu.popUpContextMenu(menu,with:event,for:self)}
    }
    override func mouseDown(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil);lastPoint=point;scratched=false
        for (i,p) in tail.enumerated() {
            let target=NSPoint(x:actor.minX+p.x*actor.width,y:actor.minY+p.y*actor.height)
            if hypot(target.x-point.x,target.y-point.y)<16 {touchTail(i);return}
        }
    }
    override func mouseDragged(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        guard let last=lastPoint,!scratched,hypot(point.x-last.x,point.y-last.y)>5 else{return}
        if let side=ears.firstIndex(where:{rect($0).contains(point) && rect($0).contains(last)}) {scratch(side);scratched=true}
    }
    private func playYip() {
        // A short locally synthesized fox-like chirp, with no recording or network.
        let rate=22050, count=Int(Double(rate)*0.22)
        var pcm=Data()
        var phase=0.0
        for i in 0..<count {
            let t=Double(i)/Double(count)
            let frequency=1100+650*sin(t * .pi)
            phase += 2 * .pi * frequency/Double(rate)
            let wave=(sin(phase)+0.3*sin(2*phase))*sin(t * .pi)*0.16
            var sample=Int16(wave*32767).littleEndian
            withUnsafeBytes(of:&sample){pcm.append(contentsOf:$0)}
        }
        var wav=Data("RIFF".utf8)
        func append<T:FixedWidthInteger>(_ value:T) {var v=value.littleEndian;withUnsafeBytes(of:&v){wav.append(contentsOf:$0)}}
        append(UInt32(36+pcm.count));wav.append(Data("WAVEfmt ".utf8));append(UInt32(16));append(UInt16(1));append(UInt16(1));append(UInt32(rate));append(UInt32(rate*2));append(UInt16(2));append(UInt16(16));wav.append(Data("data".utf8));append(UInt32(pcm.count));wav.append(pcm)
        sound=NSSound(data:wav);sound?.play()
    }
    func stop() {timer?.invalidate();timer=nil;progress=0;happy=false;sound?.stop();needsDisplay=true}
    var secretCompleted:Bool {happy}
}
