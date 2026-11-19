import AppKit

final class ActivitiesRoom: NSObject {
    let store: CompanionStore
    let frames: SpriteFrames
    var playCue: (([String]) -> Bool)?
    var onChange: (() -> Void)?
    private var selectedTab=0
    private let body = NSView(frame:NSRect(x:24,y:22,width:592,height:380))
    private let status = NSTextField(wrappingLabelWithString:"")
    private var picker: NSPopUpButton?
    private var firstAction: NSPopUpButton?
    private var secondAction: NSPopUpButton?
    private var titleInput: NSTextField?
    private var answerInput: NSTextField?
    private var letterDate: NSDatePicker?
    private var selectedCard: UUID?
    private var flipped = false
    private var practicing = false
    private var activeCueID: UUID?
    private var activeLetterID: UUID?

    init(store: CompanionStore, frames: SpriteFrames) {
        self.store = store
        self.frames = frames
        super.init()
    }
    func desktopView(tab:Int)->NSView {
        selectedTab=tab
        if tab==2,!store.save.activities.cards.isEmpty {selectedCard=store.nextCard()?.id;practicing=true;flipped=false}
        if tab==3,let unread=store.save.activities.letters.first(where:{$0.deliveredAt != nil && $0.readAt == nil}) {activeLetterID=unread.id}
        render()
        let wrapper=NSView(frame:NSRect(x:0,y:0,width:592,height:425))
        body.removeFromSuperview();body.frame.origin=NSPoint(x:0,y:0);wrapper.addSubview(body)
        status.removeFromSuperview();status.frame=NSRect(x:10,y:390,width:572,height:30);wrapper.addSubview(status)
        return wrapper
    }
    @discardableResult private func label(_ text: String, rect: NSRect, size: CGFloat = 14, parent: NSView? = nil) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString:text)
        field.font = .systemFont(ofSize:size,weight:size>20 ? .semibold : .regular)
        field.frame = rect
        (parent ?? body).addSubview(field)
        return field
    }
    @discardableResult private func button(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 170, action: Selector, tag: Int = 0) -> NSButton {
        let b = NSButton(title:text,target:self,action:action)
        b.bezelStyle = .rounded
        b.frame = NSRect(x:x,y:y,width:width,height:32)
        b.tag = tag
        body.addSubview(b)
        return b
    }
    private func input(_ text: String, placeholder: String, rect: NSRect) -> NSTextField {
        let field = NSTextField(string:text)
        field.placeholderString = placeholder
        field.frame = rect
        body.addSubview(field)
        return field
    }
    private func dropdown(_ names: [String], rect: NSRect, action: Selector? = nil) -> NSPopUpButton {
        let menu = NSPopUpButton(frame:rect)
        menu.addItems(withTitles:names)
        menu.target = self
        menu.action = action
        body.addSubview(menu)
        return menu
    }
    @discardableResult private func attempt(_ work: () throws -> Void) -> Bool {
        do { try work(); onChange?(); return true }
        catch {
            let alert = NSAlert()
            alert.messageText = "这一步没有完成"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }
    private func render() {
        body.subviews.forEach { $0.removeFromSuperview() }
        switch selectedTab {
        case 0: renderCues()
        case 1: renderExpedition()
        case 2: renderCards()
        default: renderLetters()
        }
    }
    private func renderCues() {
        status.stringValue = "教它一句文字暗号，按顺序做两个动作。"
        let cues = store.save.activities.cues
        picker = dropdown(["新暗号"] + cues.map(\.name),rect:NSRect(x:0,y:330,width:592,height:30),action:#selector(cueSelected))
        if let id = activeCueID, let index = cues.firstIndex(where: { $0.id == id }) { picker?.selectItem(at:index+1) }
        else { activeCueID = nil }
        let cue = cues.first { $0.id == activeCueID }
        titleInput = input(cue?.name ?? "",placeholder:"例如：收工啦",rect:NSRect(x:0,y:270,width:592,height:34))
        label("第一个动作",rect:NSRect(x:0,y:230,width:230,height:24))
        label("第二个动作",rect:NSRect(x:312,y:230,width:230,height:24))
        firstAction = dropdown(["伸个懒腰","玩耍一下"],rect:NSRect(x:0,y:190,width:280,height:32))
        secondAction = dropdown(["伸个懒腰","玩耍一下"],rect:NSRect(x:312,y:190,width:280,height:32))
        firstAction?.selectItem(at:cue?.actions.first == "play" ? 1 : 0)
        secondAction?.selectItem(at:cue?.actions.last == "stretch" ? 0 : 1)
        button("教会 / 更新暗号",x:0,y:120,action:#selector(saveCue))
        button("删除暗号",x:215,y:120,action:#selector(deleteCue)).isEnabled = cue != nil
        label("输入一句已经教过的暗号，再叫溯溯做给你看。",rect:NSRect(x:0,y:72,width:592,height:30))
        button("说出上面这句暗号",x:0,y:20,width:250,action:#selector(invokeCue))
    }
    @objc private func cueSelected() {
        let index = (picker?.indexOfSelectedItem ?? 0)-1
        activeCueID = store.save.activities.cues.indices.contains(index) ? store.save.activities.cues[index].id : nil
        render()
    }
    @objc private func saveCue() {
        let actions = [firstAction,secondAction].map { $0?.indexOfSelectedItem == 0 ? "stretch" : "play" }
        let name = titleInput?.stringValue ?? ""
        if attempt({ try store.saveCue(id:activeCueID,name:name,actions:actions) }) {
            activeCueID = store.save.activities.cues.first { $0.name == name.trimmingCharacters(in:.whitespacesAndNewlines) }?.id
            render()
            status.stringValue = "学会啦！下次见面也记得。"
        }
    }
    @objc private func deleteCue() {
        guard let id = activeCueID else { return }
        guard confirmDestructiveAction("删除这个暗号？",message:"删除后需要重新教它。") else{return}
        if attempt({ try store.deleteCue(id:id) }) { activeCueID=nil;render() }
    }
    @objc private func invokeCue() {
        let text = titleInput?.stringValue.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        guard let cue = store.save.activities.cues.first(where: { $0.name == text }) else {
            status.stringValue = "还没学过这句，请先教会它。"; return
        }
        status.stringValue = playCue?(cue.actions) == true ? "收到暗号，开始啦。" : "先显示并唤醒溯溯，再试一次；探险或提醒期间它会稍后回应。"
    }
    private func renderExpedition() {
        status.stringValue = "去河岸捡石头，或去松林找松果。"
        let fox = NSImageView(frame:NSRect(x:220,y:205,width:150,height:162))
        fox.image = store.save.activities.expedition == nil ? frames.character(.idle, frame: 0, season: store.save.studio.season).image : frames.character(.walk, frame: 2, season: store.save.studio.season).image
        fox.imageScaling = .scaleProportionallyUpOrDown
        body.addSubview(fox)
        if let trip = store.save.activities.expedition {
            let route = trip.route == "river" ? "河岸" : "松林"
            label("正去\(route)探险，约在 \(trip.due.formatted(date:.omitted,time:.shortened)) 回来。\n关闭应用后也会记得这次旅程。",rect:NSRect(x:0,y:133,width:592,height:64))
        } else {
            label("每次约一分钟。回来会把发现物收进收藏册。",rect:NSRect(x:0,y:150,width:592,height:36))
            button("出发去河岸",x:0,y:108,width:270,action:#selector(startTrip(_:)),tag:0)
            button("出发去松林",x:322,y:108,width:270,action:#selector(startTrip(_:)),tag:1)
        }
        let items = store.save.activities.collection
        label("收藏册\n🪨 河岸鹅卵石  \(items["河岸鹅卵石",default:0])\n🌰 松林松果  \(items["松林松果",default:0])",rect:NSRect(x:0,y:10,width:592,height:85),size:16)
    }
    @objc private func startTrip(_ sender: NSButton) {
        if attempt({ try store.startExpedition(route:sender.tag == 0 ? "river" : "forest") }) { render() }
    }
    private func renderCards() {
        status.stringValue = "给溯溯几道题，下次休息时一起复习。"
        let cards = store.save.activities.cards
        if practicing, let card = cards.first(where:{$0.id==selectedCard}) {
            renderPractice(card)
            return
        }
        practicing=false
        picker = dropdown(["新卡片"] + cards.map(\.question),rect:NSRect(x:0,y:340,width:592,height:30),action:#selector(cardSelected))
        if let id=selectedCard,let index=cards.firstIndex(where:{$0.id==id}) { picker?.selectItem(at:index+1) }
        else { selectedCard=nil }
        let card=cards.first{$0.id==selectedCard}
        titleInput=input(card?.question ?? "",placeholder:"题面",rect:NSRect(x:0,y:286,width:592,height:42))
        answerInput=input(card?.answer ?? "",placeholder:"答案",rect:NSRect(x:0,y:225,width:592,height:50))
        button("保存卡片",x:0,y:180,action:#selector(saveCard))
        button("删除卡片",x:205,y:180,action:#selector(deleteCard)).isEnabled = card != nil
        button("开始复习",x:410,y:180,action:#selector(drawCard)).isEnabled = !cards.isEmpty
        label("保存后点「开始复习」，溯溯会先出题，再让你翻面核对。",rect:NSRect(x:0,y:75,width:592,height:80))
    }
    private func readOnlyText(_ text:String,rect:NSRect) {
        let scroll=NSScrollView(frame:rect)
        scroll.hasVerticalScroller=true
        scroll.borderType = .bezelBorder
        let textView=NSTextView(frame:NSRect(origin:.zero,size:rect.size))
        textView.isEditable=false
        textView.font = .systemFont(ofSize:18)
        textView.string=text
        textView.textContainerInset=NSSize(width:12,height:12)
        textView.isVerticallyResizable=true
        textView.isHorizontallyResizable=false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView=true
        scroll.documentView=textView
        body.addSubview(scroll)
    }
    private func renderPractice(_ card:StudyCard) {
        status.stringValue=flipped ? "核对答案，再决定是否需要复习。" : "先想一想答案，再翻面。"
        label(flipped ? "答案" : "溯溯叼来一张题卡",rect:NSRect(x:0,y:325,width:592,height:35),size:21)
        readOnlyText(flipped ? card.answer : card.question,rect:NSRect(x:0,y:115,width:592,height:198))
        button("编辑卡片",x:0,y:62,action:#selector(editCard))
        button("抽下一张",x:410,y:62,action:#selector(drawCard))
        if flipped {
            button("记住了",x:0,y:10,action:#selector(review(_:)),tag:1)
            button("再练",x:215,y:10,action:#selector(review(_:)),tag:0)
        } else { button("翻面看答案",x:0,y:10,action:#selector(flipCard)) }
    }
    @objc private func editCard() { practicing=false;render() }
    @objc private func cardSelected() {
        let index=(picker?.indexOfSelectedItem ?? 0)-1
        selectedCard=store.save.activities.cards.indices.contains(index) ? store.save.activities.cards[index].id : nil
        practicing=false;flipped=false;render()
    }
    @objc private func saveCard() {
        let question=titleInput?.stringValue ?? "", answer=answerInput?.stringValue ?? ""
        if attempt({try store.saveCard(id:selectedCard,question:question,answer:answer)}) {
            if selectedCard == nil { selectedCard=store.save.activities.cards.last?.id }
            flipped=false;render()
        }
    }
    @objc private func deleteCard() {
        guard let id=selectedCard else{return}
        guard confirmDestructiveAction("删除这张卡片？",message:"删除后无法恢复。") else{return}
        if attempt({try store.deleteCard(id:id)}) { selectedCard=nil;flipped=false;render() }
    }
    @objc private func drawCard() { selectedCard=store.nextCard(excluding:selectedCard)?.id;practicing=true;flipped=false;render() }
    @objc private func flipCard() { flipped=true;render() }
    @objc private func review(_ sender:NSButton) {
        guard let id=selectedCard else{return}
        if attempt({try store.reviewCard(id:id,remembered:sender.tag==1)}) { drawCard() }
    }
    private func renderLetters() {
        status.stringValue = "给未来的自己留一句话，让溯溯替你保管。"
        let letters=store.save.activities.letters
        picker=dropdown(["写一封信"]+letters.map {
            ($0.deliveredAt == nil ? "待投递 " : $0.readAt == nil ? "未读 " : "已读 ")+$0.due.formatted(date:.abbreviated,time:.shortened)
        },rect:NSRect(x:0,y:338,width:592,height:30),action:#selector(letterSelected))
        if let id=activeLetterID,let index=letters.firstIndex(where:{$0.id==id}) {picker?.selectItem(at:index+1)}
        else {activeLetterID=nil}
        let letter=letters.first{$0.id==activeLetterID}
        if let letter,letter.deliveredAt != nil {
            if letter.readAt == nil {
                label("✉️ 一封信在等你拆开",rect:NSRect(x:0,y:212,width:592,height:70),size:24)
                button("拆开这封信",x:0,y:130,action:#selector(openLetter))
            } else {
                readOnlyText(letter.body,rect:NSRect(x:0,y:115,width:592,height:195))
                button("删除这封信",x:0,y:30,action:#selector(deleteLetter))
            }
        } else {
            titleInput=input(letter?.body ?? "",placeholder:"明天继续从这里开始……",rect:NSRect(x:0,y:185,width:592,height:130))
            letterDate=NSDatePicker(frame:NSRect(x:0,y:128,width:350,height:32))
            letterDate?.datePickerStyle = .textFieldAndStepper
            letterDate?.datePickerElements = [.yearMonthDay,.hourMinute]
            letterDate?.dateValue=letter?.due ?? Date().addingTimeInterval(60)
            body.addSubview(letterDate!)
            button(letter == nil ? "交给溯溯" : "保存内容与改期",x:0,y:65,action:#selector(sendLetter))
            button("取消这封信",x:215,y:65,action:#selector(deleteLetter)).isEnabled = letter != nil
            label("到期时若应用已关闭，下次启动会投递一次。",rect:NSRect(x:0,y:5,width:592,height:40))
        }
    }
    @objc private func letterSelected() {
        let index=(picker?.indexOfSelectedItem ?? 0)-1
        activeLetterID=store.save.activities.letters.indices.contains(index) ? store.save.activities.letters[index].id : nil
        render()
    }
    @objc private func sendLetter() {
        let body=titleInput?.stringValue ?? "",due=letterDate?.dateValue ?? Date()
        if attempt({try store.saveLetter(id:activeLetterID,body:body,due:due)}) {
            if activeLetterID == nil {activeLetterID=store.save.activities.letters.last?.id}
            render();status.stringValue="收到啦，我会替你把信留到那时候。"
        }
    }
    @objc private func openLetter() {
        guard let id=activeLetterID else{return}
        if attempt({try store.readLetter(id:id)}) {render()}
    }
    @objc private func deleteLetter() {
        guard let id=activeLetterID else{return}
        guard confirmDestructiveAction("删除这封信？",message:"删除后无法恢复。") else{return}
        if attempt({try store.deleteLetter(id:id)}) {activeLetterID=nil;render()}
    }
    func refreshDelivery() {
        // Do not rebuild an editor while the user is typing.
        if selectedTab == 1 { render() }
        if selectedTab == 3 && !store.unreadLetters.isEmpty { status.stringValue="✉️ 新信到了，点击桌面信封或重新打开信箱查看。" }
    }
    func runChecks(at directory:URL)throws {
        selectedTab=0;render()
        titleInput?.stringValue="收工啦"
        saveCue()
        precondition(store.save.activities.cues.contains{$0.name=="收工啦"})
        selectedTab=2;render()
        titleInput?.stringValue="TCP 为什么需要序列号？"
        answerInput?.stringValue="按序重组数据，并识别重复内容。"
        saveCard();drawCard();flipCard()
        precondition(practicing && flipped && selectedCard != nil)
        selectedTab=3;render()
        titleInput?.stringValue="明天从图三继续。"
        letterDate?.dateValue=Date().addingTimeInterval(60)
        sendLetter()
        precondition(activeLetterID != nil)
        try store.settleActivities(now:Date().addingTimeInterval(61))
        render();openLetter()
        precondition(store.save.activities.letters.last?.readAt != nil)
        let startButton=NSButton();startButton.tag=0
        selectedTab=1;startTrip(startButton)
        precondition(store.save.activities.expedition != nil)
        try store.settleActivities(now:Date().addingTimeInterval(61));onChange?()
        precondition(store.save.activities.collection["河岸鹅卵石"]==1)
        for tab in 0..<4 {
            selectedTab=tab;render()
            body.layoutSubtreeIfNeeded();body.displayIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            let root=body
            guard let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) else{fatalError("Missing activity preview")}
            root.cacheDisplay(in:root.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("activities-\(tab).png"))
        }
    }
}
