import AppKit

final class DesktopBubble:NSPanel {
    var dismiss:(()->Void)?
    override var canBecomeKey:Bool {true}
    override func cancelOperation(_ sender:Any?) {orderOut(nil);dismiss?()}
}

/// One temporary speech/prop surface, positioned beside the actual desktop pet.
final class DesktopActions:NSObject {
    let store:CompanionStore
    let frames:SpriteFrames
    let room:CompanionRoom
    let activities:ActivitiesRoom
    let anchor:()->NSRect
    var animate:((PetAction)->Void)?
    var invokeCue:(([String])->Bool)?
    var onChange:(()->Void)?
    var onPresent:(()->Void)?
    var onDismiss:(()->Void)?
    private var hitTimer:Timer?
    var isVisible:Bool {panel?.isVisible==true}
    private var panel:DesktopBubble?
    private var targets:[ActionTarget]=[]
    init(store:CompanionStore,frames:SpriteFrames,room:CompanionRoom,activities:ActivitiesRoom,anchor:@escaping()->NSRect) {
        self.store=store;self.frames=frames;self.room=room;self.activities=activities;self.anchor=anchor
    }
    func present(_ view:NSView,glass:Bool=true) {
        interrupt();onPresent?()
        let bubble=DesktopBubble(contentRect:view.bounds.insetBy(dx:-12,dy:-12),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        bubble.isOpaque=false;bubble.backgroundColor = .clear;bubble.hasShadow=glass;bubble.level = .floating
        bubble.isReleasedWhenClosed=false;bubble.hidesOnDeactivate=false
        bubble.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        bubble.dismiss={ [weak self] in self?.interrupt() }
        let root:NSView
        if glass {
            let effect=NSVisualEffectView(frame:NSRect(origin:.zero,size:bubble.frame.size));effect.material = .popover;effect.state = .active;effect.wantsLayer=true;effect.layer?.cornerRadius=18;effect.layer?.masksToBounds=true;root=effect
        } else {root=NSView(frame:NSRect(origin:.zero,size:bubble.frame.size))}
        view.frame.origin=NSPoint(x:12,y:12);root.addSubview(view);bubble.contentView=root
        let r=anchor()
        let screen=NSScreen.screens.first{$0.visibleFrame.intersects(r)} ?? NSScreen.main!
        let area=screen.visibleFrame
        let y=r.maxY+10+bubble.frame.height<=area.maxY ? r.maxY+10 : max(area.minY+4,r.minY-bubble.frame.height-10)
        bubble.setFrameOrigin(NSPoint(x:min(max(r.midX-bubble.frame.width/2,area.minX+4),area.maxX-bubble.frame.width-4),y:y))
        bubble.orderFrontRegardless();panel=bubble
        if !glass {
            hitTimer=Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true){[weak self,weak bubble] _ in
                guard let self,let bubble else{return}
                let point=bubble.convertPoint(fromScreen:NSEvent.mouseLocation)
                bubble.ignoresMouseEvents = !self.propHit(point,in:bubble.contentView!)
            }
        }
    }
    private func propHit(_ point:NSPoint,in view:NSView)->Bool {
        guard !view.isHidden else{return false}
        if let closeup=view as? CloseupView {return closeup.containsVisible(point)}
        if let game=view as? ForestGameView,game.desktopMode {
            return (0..<3).contains{NSRect(x:CGFloat($0)*160+40,y:18,width:100,height:60).contains(point)}
        }
        if (view is NSControl || view is FoodTile) && view.bounds.contains(point){return true}
        return view.subviews.contains{self.propHit(view.convert(point,to:$0),in:$0)}
    }
    func interrupt(){hitTimer?.invalidate();hitTimer=nil;panel?.dismiss=nil;panel?.close();panel=nil;targets=[];room.interrupt();onDismiss?()}
    private func button(_ title:String,frame:NSRect,in view:NSView,action:@escaping()->Void) {
        let target=ActionTarget(action);targets.append(target)
        let button=NSButton(title:title,target:target,action:#selector(ActionTarget.invoke));button.bezelStyle = .rounded;button.frame=frame;view.addSubview(button)
    }
    func say(_ text:String) {
        let label=NSTextField(wrappingLabelWithString:text);label.font = .systemFont(ofSize:14);label.frame=NSRect(x:6,y:6,width:348,height:90)
        let view=NSView(frame:NSRect(x:0,y:0,width:360,height:105));view.addSubview(label);present(view)
    }
    func askName(_ prompt:String,completion:@escaping(String)->Void) {
        let view=NSView(frame:NSRect(x:0,y:0,width:360,height:120))
        let label=NSTextField(labelWithString:prompt);label.frame=NSRect(x:6,y:90,width:348,height:24);view.addSubview(label)
        let input=NSTextField();input.frame=NSRect(x:6,y:46,width:348,height:32);view.addSubview(input)
        present(view)
        button("记住这个名字",frame:NSRect(x:6,y:4,width:348,height:30),in:view){[weak self] in
            let text=input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !text.isEmpty,text.count<=80 else{return}
            completion(text);self?.interrupt()
        }
    }
    func game(){present(room.desktopView(tab:0),glass:false);animate?(.stretch)}
    func food(){
        let view=NSView(frame:NSRect(x:0,y:0,width:330,height:110))
        for index in 0..<3 {
            let tile=FoodTile(frame:NSRect(x:CGFloat(index)*110,y:25,width:100,height:78));tile.index=index;tile.toolTip="拖给溯溯 · \(foodNames[index]) · \(store.save.foodCounts[index]) 次";view.addSubview(tile)
            let label=NSTextField(labelWithString:foodNames[index]);label.frame=NSRect(x:CGFloat(index)*110+10,y:3,width:100,height:22);view.addSubview(label)
        }
        present(view,glass:false)
    }
    func compareFood(){
        guard store.save.foodCounts.reduce(0,+)>=3 else{say("再投喂几次点心，溯溯就能告诉你偏好啦。");return}
        let view=NSView(frame:NSRect(x:0,y:0,width:370,height:155))
        let title=NSTextField(labelWithString:"摆出两盘点心，让它闻一闻。" );title.frame=NSRect(x:8,y:120,width:350,height:26);view.addSubview(title)
        // Targets are attached after presenting so they survive replacement of the old surface.
        present(view)
        for (index,pair) in [[0,1],[0,2],[1,2]].enumerated() {
            button("\(foodNames[pair[0]]) / \(foodNames[pair[1]])",frame:NSRect(x:8,y:CGFloat(75-index*34),width:350,height:30),in:view){[weak self] in
                guard let self else{return};let chosen=self.store.preferred(pair[0],pair[1]);self.animate?(.stretch);self.say("溯溯先闻了闻\(foodNames[chosen])，轻轻把盘子拨近。")
            }
        }
    }
    func task(_ text:String){
        let view=NSView(frame:NSRect(x:0,y:0,width:400,height:170))
        let label=NSTextField(wrappingLabelWithString:text);label.frame=NSRect(x:6,y:85,width:388,height:80);view.addSubview(label)
        let command=NSTextField(string:room.desktopTaskCommand);command.isEditable=false;command.isSelectable=true;command.frame=NSRect(x:6,y:40,width:388,height:34);view.addSubview(command)
        present(view)
        button("复制交办命令",frame:NSRect(x:6,y:0,width:180,height:30),in:view){[weak self] in guard let self else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(self.room.desktopTaskCommand,forType:.string)}
    }
    func letters(){present(activities.desktopView(tab:3))}
    func cues(){present(activities.desktopView(tab:0))}
    func cards(){present(activities.desktopView(tab:2))}
    func expedition(){
        let trip=store.save.activities.expedition
        if let trip {say("溯溯正在\(trip.route=="river" ? "河岸" : "松林")探险，约 \(trip.due.formatted(date:.omitted,time:.shortened)) 回来。");return}
        let view=NSView(frame:NSRect(x:0,y:0,width:370,height:130))
        let label=NSTextField(wrappingLabelWithString:"去哪儿转一转？\n收藏 · 河岸石 \(store.save.activities.collection["河岸鹅卵石",default:0]) / 松果 \(store.save.activities.collection["松林松果",default:0])");label.frame=NSRect(x:8,y:52,width:350,height:70);view.addSubview(label)
        present(view)
        for (index,route) in ["river","forest"].enumerated() {
            button(route=="river" ? "去河岸" : "去松林",frame:NSRect(x:CGFloat(index)*185+5,y:6,width:175,height:32),in:view){[weak self] in
                guard let self else{return};do{try self.store.startExpedition(route:route);self.onChange?();self.interrupt()}catch{self.say(error.localizedDescription)}
            }
        }
    }
    func journal(){present(room.desktopView(tab:3))}
    func archive(){
        let view=NSView(frame:NSRect(x:0,y:0,width:370,height:100))
        let text=NSTextField(labelWithString:"把同一只溯溯和经历带去新电脑。" );text.frame=NSRect(x:6,y:62,width:360,height:24);view.addSubview(text);present(view)
        button("导出存档…",frame:NSRect(x:6,y:10,width:170,height:32),in:view){[weak self] in self?.room.exportDesktopSave()}
        button("导入存档…",frame:NSRect(x:190,y:10,width:170,height:32),in:view){[weak self] in self?.room.importDesktopSave();self?.onChange?()}
    }
    func runChecks(at url:URL)throws {
        game();precondition(panel?.styleMask.contains(.titled)==false)
        food();precondition(panel?.contentView?.subviews.first?.subviews.compactMap{$0 as? FoodTile}.count==3)
        interrupt()
    }
}
private final class ActionTarget:NSObject {
    let action:()->Void
    init(_ action:@escaping()->Void){self.action=action}
    @objc func invoke(){action()}
}
