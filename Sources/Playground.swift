import AppKit
import UniformTypeIdentifiers

let foodPasteboard = NSPasteboard.PasteboardType("local.susu.food")
let foodNames = ["月牙饼", "云朵糕", "琥珀糖"]
let foodIcons = ["🥐", "☁️", "🍬"]

@discardableResult
func confirmDestructiveAction(_ title: String, message: String, actionLabel: String = "删除") -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: actionLabel)
    return alert.runModal() == .alertSecondButtonReturn
}

final class FoodTile: NSView, NSDraggingSource {
    var index = 0
    override func draw(_ dirtyRect: NSRect) {
        (foodIcons[index] as NSString).draw(at:NSPoint(x:20,y:18),withAttributes:[.font:NSFont.systemFont(ofSize:40)])
    }
    override func mouseDown(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(String(index), forType:foodPasteboard)
        let drag = NSDraggingItem(pasteboardWriter:item)
        let image = NSImage(size:bounds.size)
        image.lockFocus(); draw(bounds); image.unlockFocus()
        drag.setDraggingFrame(bounds,contents:image)
        beginDraggingSession(with:[drag],event:event,source:self)
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation { .copy }
}

final class FeedingFox: NSImageView {
    var receive: ((Int)->Void)?
    override init(frame:NSRect) { super.init(frame:frame); registerForDraggedTypes([foodPasteboard]) }
    required init?(coder:NSCoder) { fatalError() }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { .copy }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard let text=sender.draggingPasteboard.string(forType:foodPasteboard),let index=Int(text),(0..<3).contains(index) else { return false }
        receive?(index); return true
    }
}

struct PineconeGame {
    enum Phase { case hide, sniff, hint, reveal }
    var phase = Phase.hide
    var hidden = 0
    var choice: Int?
    var candidates: [Int] = []
    mutating func hide(at index:Int) {
        hidden=index; choice=nil; phase = .sniff
        candidates=[index, (index+Int.random(in:1...2))%3].sorted()
    }
    mutating func reveal(_ index:Int) { choice=index; phase = .reveal }
    var found:Bool { choice == hidden }
}

final class ForestGameView:NSView {
    var game = PineconeGame()
    var pose:NSImage?
    var desktopMode=false
    var foxIndex=1
    var choose:((Int)->Void)?
    override func draw(_ dirtyRect:NSRect) {
        if !desktopMode {
            NSColor(calibratedRed:0.93,green:0.96,blue:0.91,alpha:1).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:20,yRadius:20).fill()
        }
        if !desktopMode { pose?.draw(in:NSRect(x:CGFloat(foxIndex)*160+35,y:88,width:140,height:152)) }
        for i in 0..<3 {
            let x=CGFloat(i)*160+48
            let available = game.phase != .hint || game.candidates.contains(i)
            NSColor.systemBrown.withAlphaComponent(available ? 0.65 : 0.12).setFill()
            for n in 0..<5 {
                NSBezierPath(ovalIn:NSRect(x:x+CGFloat(n)*9,y:28+CGFloat(n%2)*8,width:42,height:20)).fill()
            }
            if game.phase == .reveal && i == game.hidden {
                ("🌰" as NSString).draw(at:NSPoint(x:x+24,y:45),withAttributes:[.font:NSFont.systemFont(ofSize:30)])
            }
            if game.choice == i {
                let mark = game.found ? "找到了！" : "翻错这堆啦"
                (mark as NSString).draw(at:NSPoint(x:x,y:5),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.labelColor])
            }
        }
    }
    override func mouseDown(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        guard p.y<85 else { return }
        let index=Int((p.x-25)/160)
        guard (0..<3).contains(index) else { return }
        choose?(index)
    }
}

final class CompanionRoom:NSObject {
    let store:CompanionStore
    let frames:SpriteFrames
    private var selectedTab = 0
    private var content:NSView!
    private lazy var message:NSTextField = NSTextField(wrappingLabelWithString:"")
    private var forest:ForestGameView?
    private var gameTimer:Timer?
    private var journalPicker:NSPopUpButton?
    private var note:NSTextField?
    private var journalPage = 0
    private var selectedJournalUUID: UUID?
    private var generation=0
    private var desktopMode=false
    var animate:((PetAction)->Void)?
    var taskDetail="还没有交办任务。"
    init(store:CompanionStore,frames:SpriteFrames) {
        self.store=store;self.frames=frames
        super.init()
        content=NSView(frame:NSRect(x:24,y:20,width:512,height:300))
    }
    @discardableResult private func label(_ text:String,x:CGFloat,y:CGFloat,width:CGFloat,size:CGFloat=14,in parent:NSView)->NSTextField {
        let field=NSTextField(wrappingLabelWithString:text)
        field.font = .systemFont(ofSize:size,weight:size>20 ? .semibold : .regular)
        field.frame=NSRect(x:x,y:y,width:width,height:size>20 ? 38 : 56)
        parent.addSubview(field);return field
    }
    @discardableResult private func button(_ title:String,x:CGFloat,y:CGFloat,width:CGFloat=150,action:Selector,tag:Int=0)->NSButton {
        let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded
        b.frame=NSRect(x:x,y:y,width:width,height:32);b.tag=tag;content.addSubview(b);return b
    }
    @discardableResult private func attempt(_ work:()throws->Void)->Bool {
        do { try work();return true } catch {
            let alert=NSAlert();alert.messageText="这一步没有保存成功";alert.informativeText=error.localizedDescription;alert.runModal();return false
        }
    }
    func desktopView(tab:Int)->NSView {
        desktopMode=true;selectedTab=tab;render()
        let wrapper=NSView(frame:NSRect(x:0,y:0,width:512,height:tab==0 ? 180 : 350))
        content.removeFromSuperview();content.frame.origin=NSPoint(x:0,y:0);wrapper.addSubview(content)
        message.removeFromSuperview();message.frame=NSRect(x:10,y:tab==0 ? 144 : 310,width:492,height:32);wrapper.addSubview(message)
        return wrapper
    }
    func exportDesktopSave(){exportSave()}
    func importDesktopSave(){importSave()}
    private func cancelGame() { gameTimer?.invalidate();gameTimer=nil;generation += 1 }
    func interrupt() { cancelGame();forest?.game = PineconeGame();if selectedTab==0, content.window != nil { render() } }
    private func render() {
        cancelGame();content.subviews.forEach{$0.removeFromSuperview()};forest=nil
        switch selectedTab {
        case 0:
            message.stringValue="溯溯闭上眼啦。点击一堆落叶，把松果藏进去。"
            let view=ForestGameView(frame:NSRect(x:0,y:30,width:512,height:desktopMode ? 100 : 250))
            view.pose=frames.character(.stretch, frame: 3, season: store.save.studio.season).image;view.desktopMode=desktopMode;view.choose={ [weak self] in self?.choosePile($0) }
            content.addSubview(view);forest=view
            button("再玩一局",x:0,y:0,action:#selector(newGame))
            button("让它自己选",x:180,y:0,action:#selector(noHint))
        case 1:
            message.stringValue="把一份点心拖给狐狸，也可以拖到桌面上的溯溯。"
            let fox=FeedingFox(frame:NSRect(x:165,y:92,width:170,height:184));fox.image=frames.character(.idle, frame: 0, season: store.save.studio.season).image
            fox.imageScaling = .scaleProportionallyUpOrDown
            fox.receive={ [weak self] in self?.feed($0) };content.addSubview(fox)
            for i in 0..<3 {
                let tile=FoodTile(frame:NSRect(x:CGFloat(i)*170+20,y:28,width:100,height:78));tile.index=i;content.addSubview(tile)
                label("\(foodNames[i]) · \(store.save.foodCounts[i]) 次",x:CGFloat(i)*170+10,y:0,width:160,in:content).frame.size.height=22
            }
            button("清除口味记录",x:340,y:260,action:#selector(clearFood))
        case 2:
            let total=store.save.foodCounts.reduce(0,+)
            message.stringValue=total<3 ? "再投喂 \(3-total) 次，就能摆出双盘让它选啦。" : "选两种点心，看溯溯先闻哪一盘。"
            label("口味会随相处改变，也会在重启后保留。",x:20,y:210,width:460,in:content)
            for (i,pair) in [(0,[0,1]),(1,[0,2]),(2,[1,2])] {
                button("\(foodNames[pair[0]]) / \(foodNames[pair[1]])",x:75,y:CGFloat(150-i*50),width:350,action:#selector(compareFood(_:)),tag:i).isEnabled=total>=3
            }
        case 3: renderJournal()
        case 4:
            message.stringValue="请溯溯盯住一次由你交办的命令。"
            label(taskDetail,x:12,y:205,width:480,size:16,in:content)
            label("在终端输入下方命令。用你的命令替换 /usr/bin/true。",x:12,y:140,width:480,in:content)
            let command=NSTextField(string:TaskTool.command ?? TaskTool.unavailable);command.isEditable=false;command.isSelectable=true
            command.frame=NSRect(x:12,y:100,width:488,height:44);content.addSubview(command)
            button("复制命令",x:12,y:45,action:#selector(copyTask))
        default:
            message.stringValue="把同一只溯溯和它的经历带去下一台 Mac。"
            label("角色编号\n\(store.save.identity.uuidString)\n\n存档包含口味、手帐和已处理任务。导入会替换这些内容。",x:16,y:120,width:480,in:content)
            button("导出存档…",x:35,y:65,action:#selector(exportSave))
            button("导入存档…",x:265,y:65,action:#selector(importSave))
        }
    }
    func feed(_ index:Int) {
        guard attempt({ try store.feed(index) }) else { return }
        animate?(.play)
        render()
        if let fox=content.subviews.compactMap({$0 as? FeedingFox}).first {
            var frame=0
            gameTimer=Timer.scheduledTimer(withTimeInterval:0.16,repeats:true){[weak self,weak fox] timer in
                guard let self,let fox else{timer.invalidate();return}
                fox.image=self.frames.character(.play, frame: frame%6, season: self.store.save.studio.season).image;frame += 1
                if frame==12 {timer.invalidate();fox.image=self.frames.character(.idle, frame: 0, season: self.store.save.studio.season).image}
            }
        }
        message.stringValue="溯溯接住了\(foodNames[index])，开心地尝了一口。"
    }
    @objc private func clearFood() {
        guard confirmDestructiveAction("清除口味记录？",message:"三种点心的次数会归零，无法恢复。", actionLabel: "清除") else{return}
        attempt { try store.clearFood() };render()
    }
    @objc private func compareFood(_ sender:NSButton) {
        let pairs=[[0,1],[0,2],[1,2]], pair=pairs[sender.tag]
        render()
        let selected=store.preferred(pair[0],pair[1]);message.stringValue="溯溯先闻了闻\(foodNames[selected])，把盘子往自己身边拨了拨。"
        for (position,index) in pair.enumerated() {
            label(foodIcons[index]+" "+foodNames[index],x:CGFloat(position)*260+30,y:185,width:230,in:content)
        }
        let image=NSImageView(frame:NSRect(x:selected==pair[0] ? 100 : 350,y:215,width:90,height:85));image.image=frames.character(.stretch, frame: 2, season: store.save.studio.season).image;content.addSubview(image)
        animate?(.stretch)
    }
    private func choosePile(_ index:Int) {
        guard let forest else{return}
        switch forest.game.phase {
        case .hide:
            forest.game.hide(at:index);forest.pose=frames.character(.stretch, frame: 2, season: store.save.studio.season).image
            message.stringValue="它正沿着落叶闻一闻……"
            var step=0
            gameTimer=Timer.scheduledTimer(withTimeInterval:0.55,repeats:true){[weak self] timer in
                guard let self,let view=self.forest else{timer.invalidate();return}
                view.foxIndex=step;view.needsDisplay=true;step += 1
                if step==3 {timer.invalidate();view.game.phase = .hint;self.message.stringValue="它犹豫在两堆之间。点一堆提示它，或让它自己选。";view.needsDisplay=true}
            }
        case .hint:
            guard forest.game.candidates.contains(index) else{return}
            forest.game.reveal(index);forest.foxIndex=index;forest.pose=frames.character(.play, frame: 2, season: store.save.studio.season).image
            message.stringValue=forest.game.found ? "找到啦！松果就是你藏的位置。" : "翻错啦，松果原来在另一堆。再试一次？"
            if forest.game.found {attempt {try store.record("first-pinecone",text:"第一次找到你藏的松果。")}}
            animate?(.play)
        default: break
        }
        forest.needsDisplay=true
    }
    @objc private func noHint() {
        guard let forest,forest.game.phase == .hint,let index=forest.game.candidates.randomElement() else{return};choosePile(index)
    }
    @objc private func newGame() {render()}
    private func renderJournal() {
        let picker=NSPopUpButton(frame:NSRect(x:10,y:248,width:490,height:30));journalPicker=picker
        let pages=max(1,(store.save.journal.count+99)/100); journalPage=min(max(0,journalPage),pages-1)
        message.stringValue = "手帐 · 第 \(journalPage + 1) / \(pages) 页"
        let start=max(0,store.save.journal.count-(journalPage+1)*100), end=store.save.journal.count-journalPage*100
        let entries=Array(store.save.journal[start..<end])
        for (index, entry) in entries.enumerated() {
            let date = entry.date.formatted(date: .abbreviated, time: .omitted)
            let excerpt = entry.text.split(whereSeparator: \.isNewline).first?.prefix(60) ?? ""
            picker.addItem(withTitle: "\(start + index + 1) · \(date) · \(excerpt)")
            picker.lastItem?.representedObject = entry.id.uuidString
        }
        if let id=selectedJournalUUID,let i=entries.firstIndex(where:{$0.id==id}){picker.selectItem(at:i)}else if let first=entries.first{selectedJournalUUID=first.id;picker.selectItem(at:0)}
        picker.target=self;picker.action=#selector(journalChanged);content.addSubview(picker)
        let edit=NSTextField(string:entries.first(where:{$0.id==selectedJournalUUID})?.note ?? "");edit.placeholderString="给这一天留句话……"
        edit.frame=NSRect(x:10,y:110,width:490,height:110);content.addSubview(edit);note=edit
        button("保存批注",x:10,y:50,action:#selector(saveNote)).isEnabled = !store.save.journal.isEmpty
        button("删除这条",x:270,y:50,action:#selector(deleteNote)).isEnabled = !store.save.journal.isEmpty
        button("更早",x:10,y:15,width:100,action:#selector(previousJournalPage)).isEnabled=journalPage < pages-1
        button("更新",x:120,y:15,width:100,action:#selector(nextJournalPage)).isEnabled=journalPage > 0
    }
    private func selectedJournalID() -> UUID? { guard let raw=journalPicker?.selectedItem?.representedObject as? String else{return selectedJournalUUID}; return UUID(uuidString:raw) }
    @objc private func journalChanged() { guard let id=selectedJournalID(), let entry=store.save.journal.first(where:{$0.id==id}) else{return}; selectedJournalUUID=id; note?.stringValue=entry.note }
    @objc private func previousJournalPage(){journalPage += 1;render()}
    @objc private func nextJournalPage(){journalPage=max(0,journalPage-1);render()}
    @objc private func saveNote() {
        guard let id = selectedJournalID() else { return }
        if attempt({ try store.updateNote(id: id, note: note?.stringValue ?? "") }) { message.stringValue = "批注已保存。" }
    }
    @objc private func deleteNote() {
        guard let id = selectedJournalID(), confirmDestructiveAction("删除这条手帐？", message: "删除后无法恢复。") else { return }
        if attempt({ try store.deleteEntry(id: id) }) { selectedJournalUUID = nil; render() }
    }
    @objc private func copyTask() {
        guard let command = TaskTool.command else { message.stringValue = TaskTool.unavailable; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        message.stringValue = "命令已复制。"
    }
    @objc private func exportSave() {
        let dialog=NSSavePanel();dialog.nameFieldStringValue="溯溯存档.json";dialog.allowedContentTypes=[.json]
        guard dialog.runModal() == .OK,let url=dialog.url else{return}
        attempt{try store.exportData().write(to:url,options:.atomic)}
    }
    @objc private func importSave() {
        let dialog=NSOpenPanel();dialog.allowedContentTypes=[.json]
        guard dialog.runModal() == .OK,let url=dialog.url else{return}
        guard confirmDestructiveAction("用这份存档替换当前记录？", message: "导入会覆盖当前记录。需要保留的话请先导出。", actionLabel: "导入") else { return }
        attempt{try store.importData(Data(contentsOf:url))};render()
    }
    func refreshTask(_ text:String){taskDetail=text;if selectedTab==4{render()}}
    func runChecks(at directory:URL)throws {
        for hidden in 0..<3 {
            var game=PineconeGame();game.hide(at:hidden);game.phase = .hint;game.reveal(hidden);precondition(game.found)
            game.reveal((hidden+1)%3);precondition(!game.found && game.hidden==hidden)
        }
        selectedTab=0;render()
        choosePile(1)
        precondition(forest?.game.phase == .sniff)
        gameTimer?.invalidate();forest?.game.phase = .hint
        choosePile(1)
        precondition(forest?.game.found == true)
        let countBefore=store.save.foodCounts.reduce(0,+)
        for food in 0..<3 { selectedTab=1;feed(food) }
        precondition(store.save.foodCounts.reduce(0,+)==countBefore+3)
        for tab in 0..<6 {
            let preview=desktopView(tab:tab)
            preview.layoutSubtreeIfNeeded()
            preview.displayIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            let root=preview
            guard let rep=root.bitmapImageRepForCachingDisplay(in:root.bounds) else{fatalError()}
            root.cacheDisplay(in:root.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("room-\(tab).png"))
        }
    }
}
