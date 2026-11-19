import AppKit
import UniformTypeIdentifiers

final class StudioRoom:NSObject {
    let store:CompanionStore
    let frames:SpriteFrames
    var onChange:(()->Void)?
    var onNestPresence:((Bool)->Void)?
    var onReturnToDesktop:((NSRect)->Void)?
    var desktopMenu:(()->NSMenu)?
    var canStartHouse:(()->Bool)?
    var closeupMuted=true
    private var preferredWidth:CGFloat = {
        let saved=UserDefaults.standard.double(forKey:"houseWidth")
        return saved>0 ? CGFloat(saved) : 440
    }()
    var getNestArea:(()->NSRect)?
    private(set) var foxInNest=false
    private var selectedTab=0
    private let body=NSView(frame:NSRect(x:24,y:20,width:632,height:410))
    private let status=NSTextField(wrappingLabelWithString:"")
    private var nestPreview:NestCanvas?
    private let nest:NestWindow
    private var lastArea:NSRect?
    private var wardrobe:NSPopUpButton?
    private var looks:NSPopUpButton?
    private var lookName:NSTextField?
    private var background:NSPopUpButton?
    private var pose:NSPopUpButton?
    private var poseFrame:NSSlider?
    private var caption:NSTextField?
    private var postcard:NSImageView?
    private var closeup:CloseupView?
    private var previewSeason: PetSeason?

    init(store:CompanionStore,frames:SpriteFrames) {
        self.store=store;self.frames=frames
        nest=NestWindow(frames:frames)
        super.init()
        nest.closed={ [weak self] in self?.releaseFox() }
        nest.menuProvider={ [weak self] in self?.desktopMenu?() ?? NSMenu() }
        nest.canvas.onToggle={ [weak self] in self?.toggleMat() }
        nest.canvas.onFinished={ [weak self] in self?.releaseFox() }
        nest.canvas.saveLayout={ [weak self] layout in try self?.persistFurniture(layout) }
    }
    @discardableResult private func label(_ text:String,rect:NSRect,size:CGFloat=14,parent:NSView?=nil)->NSTextField {
        let field=NSTextField(wrappingLabelWithString:text);field.frame=rect;field.font = .systemFont(ofSize:size,weight:size>20 ? .semibold : .regular);(parent ?? body).addSubview(field);return field
    }
    @discardableResult private func button(_ title:String,x:CGFloat,y:CGFloat,width:CGFloat=190,action:Selector,tag:Int=0)->NSButton {
        let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;b.frame=NSRect(x:x,y:y,width:width,height:32);b.tag=tag;body.addSubview(b);return b
    }
    private func field(_ text:String,placeholder:String,rect:NSRect)->NSTextField {
        let edit=NSTextField(string:text);edit.placeholderString=placeholder;edit.frame=rect;body.addSubview(edit);return edit
    }
    private func picker(_ items:[String],rect:NSRect,action:Selector)->NSPopUpButton {
        let menu=NSPopUpButton(frame:rect);menu.addItems(withTitles:items);menu.target=self;menu.action=action;body.addSubview(menu);return menu
    }
    @discardableResult private func attempt(_ work:()throws->Void)->Bool {
        do {try work();refreshState();onChange?();return true} catch {
            let a=NSAlert();a.messageText="这一步没有完成";a.informativeText=error.localizedDescription;a.runModal();return false
        }
    }
    private func persistFurniture(_ layout:[String:FurniturePosition])throws {
        var state=store.save.studio;state.furniture=layout;try store.saveStudio(state)
        nest.canvas.state=state;nest.canvas.needsDisplay=true
        nestPreview?.state=state;nestPreview?.needsDisplay=true
        onChange?()
    }
    func refreshState() {
        if !nest.canvas.isRearranging {nest.canvas.state=store.save.studio;nest.canvas.needsDisplay=true}
        if let nestPreview,!nestPreview.isRearranging {nestPreview.state=store.save.studio;nestPreview.needsDisplay=true}
        let season = store.save.studio.season
        if previewSeason != season {
            previewSeason = season
            if let closeup { dressCloseup(closeup) }
            if postcard?.window?.isVisible == true { updatePostcard() }
        }
    }
    var desktopAnchor:NSRect? {
        guard nest.isVisible else{return nil}
        let local=foxInNest && nest.canvas.foxHere ? nest.canvas.foxRect : nest.canvas.houseRect
        return nest.convertToScreen(local)
    }
    var houseIsVisible:Bool {nest.isVisible}
    var housePhase:HouseRoutine.Phase {nest.canvas.routine.phase}
    func updateNestArea() {
        guard nest.isVisible,let area=getNestArea?(),area != lastArea else{return}
        lastArea=area;nest.allowedRect=area
        let width=min(preferredWidth,area.width-8),height=min(preferredWidth*0.68,area.height-8)
        var origin=nest.frame.origin
        if !positionedHouse {
            if !CommandLine.arguments.contains("--smoke-test"),UserDefaults.standard.object(forKey:"houseX") != nil {
                origin=NSPoint(x:UserDefaults.standard.double(forKey:"houseX"),y:UserDefaults.standard.double(forKey:"houseY"))
            } else {origin=NSPoint(x:area.maxX-width-12,y:area.minY+4)}
            positionedHouse=true
        }
        nest.setFrame(NSRect(origin:WorkTerritory.constrain(origin,window:NSSize(width:width,height:height),area:area),size:NSSize(width:width,height:height)),display:true)
    }
    private var positionedHouse=false
    func pauseHouse(_ paused:Bool){nest.paused=paused}
    func showHouse() {recall()}
    func restOutside() {recall()}
    func putMatInside() {nest.canvas.putAway()}
    func toggleMat() {
        if nest.canvas.routine.phase == .free || nest.canvas.routine.phase == .inside {recall()}
        else {putMatInside()}
    }
    func resizeHouse(_ width:CGFloat) {
        preferredWidth=width
        if !CommandLine.arguments.contains("--smoke-test"){UserDefaults.standard.set(Double(width),forKey:"houseWidth")}
        lastArea=nil;if nest.isVisible {updateNestArea()}
    }
    func releaseFox() {
        guard foxInNest else{nest.orderOut(nil);return}
        let rect=nest.convertToScreen(nest.canvas.foxRect)
        foxInNest=false;nest.canvas.dismissFox();nest.orderOut(nil);onReturnToDesktop?(rect);onNestPresence?(false)
    }
    func leaveNest() {
        releaseFox();nest.orderOut(nil)
    }
    func suspendHouse(_ hidden:Bool) {
        if hidden {pausedVisible=nest.isVisible;nest.orderOut(nil)}
        else if pausedVisible && foxInNest {nest.orderFrontRegardless();pausedVisible=false}
    }
    private var pausedVisible=false
    private func render() {
        closeup?.stop();closeup=nil;nestPreview=nil
        body.subviews.forEach{$0.removeFromSuperview()}
        switch selectedTab {
        case 0:
            status.stringValue="拖动睡垫、收藏架和灯，摆好后叫溯溯回来。"
            let scene=NestCanvas(frame:NSRect(x:0,y:70,width:632,height:330));scene.state=store.save.studio;scene.frames=frames
            scene.saveLayout={ [weak self] layout in try self?.persistFurniture(layout) };body.addSubview(scene);nestPreview=scene
            button("打开桌面小窝",x:0,y:15,action:#selector(openNest))
            button("叫溯溯进窝",x:220,y:15,action:#selector(recall))
            button("收起小窝",x:440,y:15,action:#selector(closeNest))
        case 1:renderWardrobe()
        case 2:renderPostcard()
        default:renderCloseup()
        }
    }
    @objc private func openNest() {
        nest.canvas.state=store.save.studio;nest.orderFrontRegardless();lastArea=nil;updateNestArea()
    }
    @objc private func recall() {
        guard canStartHouse?() ?? true else{return}
        guard store.save.activities.expedition == nil else{status.stringValue="溯溯还在探险，回来后再叫它进窝吧。";return}
        openNest();foxInNest=true;nest.canvas.recall();onNestPresence?(true)
        status.stringValue="溯溯正在进屋拿毯子；休息结束后房子会自动收起。"
    }
    @objc private func closeNest() {leaveNest()}
    func desktopCloseup(feedback:@escaping(String)->Void)->NSView {
        closeup?.stop()
        let view=CloseupView(frame:NSRect(x:0,y:0,width:360,height:350))
        dressCloseup(view)
        view.feedback=feedback;view.menuProvider=desktopMenu;view.muted=closeupMuted
        closeup=view;return view
    }
    private func dressCloseup(_ view: CloseupView) {
        let season = store.save.studio.season
        view.setAppearance(idle: frames.character(.idle, frame: 0, season: season),
                           reactions: (0..<CharacterPose.closeup.frameCount).map { frames.character(.closeup, frame: $0, season: season) })
    }
    func stopCloseup(){closeup?.stop()}
    func toggleCloseupSound(){closeupMuted.toggle();closeup?.muted=closeupMuted}
    func desktopPhotoView()->NSView {
        selectedTab=2;render()
        body.removeFromSuperview();body.frame.origin = .zero
        return body
    }
    func selectScarf(_ id:String) {
        var state=store.save.studio;state.scarf=id
        _=attempt{try store.saveStudio(state)}
    }
    func importDesktopScarf(){importScarf()}
    func exportDesktopTemplate(){exportTemplate()}
    func useLook(_ index:Int) {
        guard store.save.studio.looks.indices.contains(index) else{return}
        selectScarf(store.save.studio.looks[index].scarf)
    }
    func deleteDesktopLook(_ index:Int) {
        guard store.save.studio.looks.indices.contains(index) else{return}
        let look = store.save.studio.looks[index]
        guard confirmDestructiveAction("删除造型「\(look.name)」？", message: "删除后无法恢复。") else { return }
        var state = store.save.studio
        state.looks.removeAll { $0.id == look.id }
        _=attempt{try store.saveStudio(state)}
    }
    func deleteDesktopPack(_ index:Int) {
        guard store.save.studio.packs.indices.contains(index) else { return }
        let pack = store.save.studio.packs[index]
        let id = pack.id.uuidString
        let dependent = store.save.studio.looks.filter { $0.scarf == id }.count
        let impact = dependent > 0 ? "同时会删除 \(dependent) 个使用此配饰的造型。删除后无法恢复。" : "从溯溯存档中移除后无法恢复。"
        guard confirmDestructiveAction("删除配饰包「\(pack.name)」？", message: impact) else { return }
        var state = store.save.studio
        state.packs.removeAll { $0.id == pack.id }
        state.looks.removeAll{$0.scarf==id}
        if state.scarf==id {state.scarf="none"}
        _=attempt{try store.saveStudio(state)}
    }
    func saveDesktopLook(name:String) {
        var state=store.save.studio
        if let i=state.looks.firstIndex(where:{$0.name==name}) {state.looks[i].scarf=state.scarf}
        else {state.looks.append(SavedLook(name:name,scarf:state.scarf))}
        _=attempt{try store.saveStudio(state)}
    }
    private var scarfIDs:[String] {["none","teal","amber","rose"]+store.save.studio.packs.map{$0.id.uuidString}}
    private func renderWardrobe() {
        status.stringValue="选围巾，也可以导入自己画的逐帧配饰。"
        wardrobe=picker(["不戴围巾","湖绿围巾","琥珀围巾","莓红围巾"]+store.save.studio.packs.map(\.name),rect:NSRect(x:0,y:365,width:632,height:30),action:#selector(scarfChanged))
        wardrobe?.selectItem(at:scarfIDs.firstIndex(of:store.save.studio.scarf) ?? 0)
        for (i,mode) in [(false,false),(true,false),(true,true)].enumerated() {
            let image=NSImageView(frame:NSRect(x:CGFloat(i)*210+20,y:170,width:175,height:190));image.image=wearingPreview(walking:mode.0,left:mode.1);body.addSubview(image)
        }
        lookName=field("",placeholder:"给造型起名，例如 学习日",rect:NSRect(x:0,y:125,width:420,height:30))
        button("保存造型",x:442,y:125,width:190,action:#selector(saveLook))
        looks=picker(["选择已保存造型"]+store.save.studio.looks.map(\.name),rect:NSRect(x:0,y:82,width:420,height:30),action:#selector(applyLook))
        button("删除所选造型",x:442,y:82,action:#selector(deleteLook))
        button("导入配饰文件夹…",x:0,y:26,action:#selector(importScarf))
        button("导出制作模板…",x:220,y:26,action:#selector(exportTemplate))
        button("删除当前导入包",x:440,y:26,action:#selector(removePack)).isEnabled=store.save.studio.packs.contains{$0.id.uuidString==store.save.studio.scarf}
    }
    private func wearingPreview(walking:Bool,left:Bool)->NSImage {
        let state=store.save.studio
        return NSImage(size:NSSize(width:192,height:208),flipped:false){[frames] _ in
            NSGraphicsContext.saveGraphicsState()
            if left && walking {var t=AffineTransform(translationByX:192,byY:0);t.scale(x:-1,y:1);(t as NSAffineTransform).concat()}
            let r=NSRect(x:0,y:0,width:192,height:208)
            frames.character(walking ? .walk : .idle, frame: walking ? 2 : 0, season: state.season).image.draw(in:r)
            ScarfRenderer.overlay(state:state,walking:walking,frame:walking ? 2 : 0)?.draw(in:r)
            NSGraphicsContext.restoreGraphicsState();return true
        }
    }
    @objc private func scarfChanged() {
        let index=wardrobe?.indexOfSelectedItem ?? 0
        guard scarfIDs.indices.contains(index) else{return}
        var state=store.save.studio;state.scarf=scarfIDs[index]
        if attempt({try store.saveStudio(state)}) {render()}
    }
    @objc private func saveLook() {
        let name=lookName?.stringValue.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else{status.stringValue="先给造型起个名字吧。";return}
        var state=store.save.studio
        if let index=state.looks.firstIndex(where:{$0.name==name}) {state.looks[index].scarf=state.scarf}
        else{state.looks.append(SavedLook(name:name,scarf:state.scarf))}
        if attempt({try store.saveStudio(state)}){render();status.stringValue="造型已保存。"}
    }
    @objc private func applyLook() {
        let index=(looks?.indexOfSelectedItem ?? 0)-1
        guard store.save.studio.looks.indices.contains(index) else{return}
        var state=store.save.studio;state.scarf=state.looks[index].scarf
        if attempt({try store.saveStudio(state)}){render()}
    }
    @objc private func deleteLook() {
        let index=(looks?.indexOfSelectedItem ?? 0)-1
        deleteDesktopLook(index)
        render()
    }
    @objc private func importScarf() {
        let dialog=NSOpenPanel();dialog.canChooseFiles=false;dialog.canChooseDirectories=true
        guard dialog.runModal() == .OK,let folder=dialog.url else{return}
        if attempt({let pack=try ScarfRenderer.importPack(at:folder);var state=store.save.studio;state.packs.append(pack);state.scarf=pack.id.uuidString;try store.saveStudio(state)}){render()}
    }
    @objc private func exportTemplate() {
        let dialog=NSOpenPanel();dialog.canChooseFiles=false;dialog.canChooseDirectories=true;dialog.canCreateDirectories=true
        guard dialog.runModal() == .OK,let folder=dialog.url else{return}
        let target=folder.appendingPathComponent("溯溯围巾模板-"+String(UUID().uuidString.prefix(6)))
        if attempt({try ScarfRenderer.exportTemplate(to:target)}){status.stringValue="已创建模板文件夹：\(target.lastPathComponent)"}
    }
    @objc private func removePack() {
        let state = store.save.studio
        guard let index = state.packs.firstIndex(where: { $0.id.uuidString == state.scarf }) else { return }
        deleteDesktopPack(index)
        render()
    }
    private func renderPostcard() {
        status.stringValue="选背景、定格姿势，写一张属于你的狐狸明信片。"
        background=picker(["森林绿","湖水蓝","暖色纸笺"],rect:NSRect(x:0,y:365,width:200,height:30),action:#selector(updatePostcard))
        pose=picker(["待机","伸懒腰","玩耍"],rect:NSRect(x:218,y:365,width:190,height:30),action:#selector(updatePostcard))
        poseFrame=NSSlider(value:0,minValue:0,maxValue:5,target:self,action:#selector(updatePostcard));poseFrame?.numberOfTickMarks=6;poseFrame?.allowsTickMarkValuesOnly=true;poseFrame?.frame=NSRect(x:428,y:365,width:204,height:30);body.addSubview(poseFrame!)
        postcard=NSImageView(frame:NSRect(x:50,y:105,width:532,height:250));postcard?.imageScaling = .scaleProportionallyUpOrDown;body.addSubview(postcard!)
        caption=field("",placeholder:"写一句题字……",rect:NSRect(x:0,y:64,width:632,height:30));caption?.target=self;caption?.action=#selector(updatePostcard)
        button("刷新题字 / 预览",x:0,y:15,action:#selector(updatePostcard))
        button("导出 PNG…",x:442,y:15,action:#selector(exportPostcard));updatePostcard()
    }
    func postcardImage(caption text:String,background index:Int,pose kind:Int,frame:Int)->NSBitmapImageRep {
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:720,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        let colors:[NSColor]=[NSColor(srgbRed:0.87,green:0.93,blue:0.82,alpha:1),NSColor(srgbRed:0.81,green:0.91,blue:0.94,alpha:1),NSColor(srgbRed:0.98,green:0.92,blue:0.81,alpha:1)]
        colors[min(2,max(0,index))].setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:1200,height:720)).fill()
        let pose: CharacterPose = kind == 1 ? .stretch : kind == 2 ? .play : .idle
        let r=NSRect(x:408,y:160,width:384,height:416)
        frames.character(pose, frame: frame, season: store.save.studio.season).image.draw(in:r)
        if kind==0 {ScarfRenderer.overlay(state:store.save.studio,walking:false,frame:frame%6)?.draw(in:r)}
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        (text as NSString).draw(with:NSRect(x:70,y:55,width:1060,height:90),options:.usesLineFragmentOrigin,attributes:[.font:NSFont.systemFont(ofSize:30),.foregroundColor:NSColor.darkGray,.paragraphStyle:paragraph])
        (Date().formatted(date:.abbreviated,time:.omitted) as NSString).draw(at:NSPoint(x:70,y:650),withAttributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState();return bitmap
    }
    @objc private func updatePostcard() {
        let bitmap=postcardImage(caption:caption?.stringValue ?? "",background:background?.indexOfSelectedItem ?? 0,pose:pose?.indexOfSelectedItem ?? 0,frame:poseFrame?.integerValue ?? 0)
        let image=NSImage(size:NSSize(width:1200,height:720));image.addRepresentation(bitmap);postcard?.image=image
    }
    @objc private func exportPostcard() {
        let dialog=NSSavePanel();dialog.allowedContentTypes=[.png];dialog.nameFieldStringValue="溯溯明信片.png"
        guard dialog.runModal() == .OK,let url=dialog.url else{return}
        attempt{try postcardImage(caption:caption?.stringValue ?? "",background:background?.indexOfSelectedItem ?? 0,pose:pose?.indexOfSelectedItem ?? 0,frame:poseFrame?.integerValue ?? 0).representation(using:.png,properties:[:])!.write(to:url,options:.atomic)}
    }
    private func renderCloseup() {
        status.stringValue="轻划耳尖，或按从上到下的顺序点三颗琥珀尾纹。"
        let view=CloseupView(frame:NSRect(x:100,y:50,width:432,height:360));dressCloseup(view)
        view.feedback={ [weak self] in self?.status.stringValue=$0 };body.addSubview(view);closeup=view
        button("挠左耳",x:0,y:7,width:130,action:#selector(scratch(_:)),tag:0)
        button("挠右耳",x:145,y:7,width:130,action:#selector(scratch(_:)),tag:1)
        let mute=NSButton(checkboxWithTitle:"静音",target:self,action:#selector(muteChanged(_:)));mute.frame=NSRect(x:450,y:7,width:160,height:30);mute.state = .on;body.addSubview(mute)
    }
    @objc private func scratch(_ sender:NSButton){closeup?.scratch(sender.tag)}
    @objc private func muteChanged(_ sender:NSButton){closeup?.muted=sender.state == .on}
    func runChecks(at directory:URL)throws {
        for delay in [0.0,3.0,4.4,6.0,9.3,10.7,30.0] {
            var routine=HouseRoutine();routine.takeMat();routine.advance(delay);routine.putMatAway();routine.advance(60)
            precondition(routine.phase == .free,"Packing up must return to free desktop activity")
            routine.advance(600);precondition(routine.phase == .free)
            routine.takeMat();routine.advance(20);precondition(routine.phase == .resting)
            routine.release();precondition(routine.phase == .free)
        }
        var initial=store.save.studio;initial.scarf="teal";try store.saveStudio(initial)
        for index in 0..<4 {
            selectedTab=index;render();body.layoutSubtreeIfNeeded();body.displayIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.04))
            let root=body,bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds)!
            root.cacheDisplay(in:root.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("studio-\(index).png"))
        }
        closeup?.scratch(0)
        RunLoop.current.run(until:Date().addingTimeInterval(0.25))
        if let closeup,let rep=closeup.bitmapImageRepForCachingDisplay(in:closeup.bounds) {
            closeup.cacheDisplay(in:closeup.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("ear-reaction.png"))
        }
        closeup?.stop()
        closeup?.touchTail(0);closeup?.touchTail(2);precondition(closeup?.secretCompleted==false)
        for i in 0..<3{closeup?.touchTail(i)};precondition(closeup?.secretCompleted==true)
        if let closeup,let rep=closeup.bitmapImageRepForCachingDisplay(in:closeup.bounds) {
            closeup.cacheDisplay(in:closeup.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("tail-secret.png"))
        }
        closeup?.stop()
        let png=postcardImage(caption:"一起慢慢来",background:0,pose:2,frame:2)
        precondition(png.pixelsWide==1200 && png.pixelsHigh==720)
        try png.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("postcard.png"))
        let folder=directory.appendingPathComponent("scarf-template")
        try ScarfRenderer.exportTemplate(to:folder);let pack=try ScarfRenderer.importPack(at:folder)
        precondition(pack.idle.count==6 && pack.walking.count==8)
        var state=store.save.studio;state.packs.append(pack);state.scarf=pack.id.uuidString
        try store.saveStudio(state)
        let persisted=try CompanionStore(directory:store.directory)
        precondition(persisted.save.studio.packs.first?.idle.count==6)
        let originalScarf=store.save.studio.scarf
        try FileManager.default.removeItem(at:folder.appendingPathComponent("walking/07.png"))
        do{_ = try ScarfRenderer.importPack(at:folder);fatalError("Incomplete accessory accepted")}catch{}
        precondition(store.save.studio.scarf==originalScarf)
        try pack.walking[7].write(to:folder.appendingPathComponent("walking/07.png"))
        var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("scarf.json"))) as! [String:Any]
        manifest["idle"]=["../escape.png"]+Array((manifest["idle"] as! [String]).dropFirst())
        try JSONSerialization.data(withJSONObject:manifest).write(to:folder.appendingPathComponent("scarf.json"))
        do{_ = try ScarfRenderer.importPack(at:folder);fatalError("Escaped accessory path accepted")}catch{}
        precondition(store.save.studio.scarf==originalScarf)
        precondition(!nest.isVisible && !nest.canvas.houseNeeded,"House must not occupy the desktop before rest")
        resizeHouse(440);precondition(!nest.isVisible,"Changing size must not summon the house")
        recall()
        precondition(!nest.styleMask.contains(.titled) && !nest.isOpaque)
        precondition(nest.canvas.routine.phase == .entering)
        func snapshot(_ name:String)throws {
            let view=nest.canvas,rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
        }
        func nextPhase() {nest.canvas.simulate(nest.canvas.routine.duration-nest.canvas.routine.elapsed+0.001)}
        try snapshot("desktop-house-entering")
        nextPhase();precondition(housePhase == .inside)
        nextPhase();precondition(housePhase == .bringingMat)
        nest.canvas.simulate(2.2);try snapshot("desktop-house-carry")
        nextPhase();precondition(housePhase == .unrolling)
        nest.canvas.simulate(0.85);try snapshot("desktop-house-lay-blanket")
        nextPhase();precondition(housePhase == .settling)
        nextPhase();precondition(housePhase == .resting)
        precondition(nest.isVisible && foxInNest)
        try snapshot("desktop-house-rest")
        putMatInside();nextPhase();precondition(housePhase == .rolling)
        nest.canvas.simulate(0.8);try snapshot("desktop-house-pack-blanket")
        nextPhase();precondition(housePhase == .returning)
        nest.canvas.simulate(2);try snapshot("desktop-house-return")
        nextPhase();precondition(housePhase == .inside)
        try snapshot("desktop-house-inside")
        nextPhase();precondition(housePhase == .leaving)
        nextPhase();precondition(housePhase == .free && !nest.isVisible && !foxInNest,"House and blanket disappear after the fox comes back out")
        precondition(!nest.canvas.containsProp(NSPoint(x:nest.canvas.houseRect.midX,y:nest.canvas.houseRect.midY)))
        restOutside();precondition(nest.isVisible && foxInNest)
        precondition(!nest.canvas.containsProp(NSPoint(x:nest.canvas.bounds.maxX-1,y:nest.canvas.bounds.maxY-1)))
        closeNest();precondition(!foxInNest && !nest.isVisible)
    }
}
