import AppKit

final class ChatRoom:NSObject,NSWindowDelegate {
    private let getState:()->ChatState
    private let saveState:(ChatState)throws->Void
    private var state:ChatState
    private let client=ChatClient()
    private var task:URLSessionDataTask?
    private var requestID=UUID()
    private(set) var window:NSWindow?
    private let endpoint=NSTextField()
    private let model=NSTextField()
    private let key=NSSecureTextField()
    private let input=NSTextField()
    private let transcript=NSTextView()
    private let status=NSTextField(wrappingLabelWithString:"")
    private let messages=NSPopUpButton()
    private let memories=NSPopUpButton()
    private let memoryText=NSTextView()
    private var sendButton:NSButton!
    private var configButton:NSButton!
    private var busy=false
    var desktopAnchor:(()->NSRect)?
    private var configurationPanel:DesktopBubble?
    private var memoryPanel:DesktopBubble?

    init(getState:@escaping()->ChatState,saveState:@escaping(ChatState)throws->Void) {
        self.getState=getState;self.saveState=saveState;state=getState();super.init()
    }
    func show() {
        if window==nil{build()}
        if !busy {state=getState();endpoint.stringValue=state.endpoint;model.stringValue=state.model;reload()}
        if let window {position(window);window.orderFrontRegardless()}
    }
    private func makeBubble(_ size:NSSize)->DesktopBubble {
        let panel=DesktopBubble(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        let effect=NSVisualEffectView(frame:NSRect(origin:.zero,size:size));effect.material = .popover;effect.state = .active;effect.wantsLayer=true;effect.layer?.cornerRadius=18;effect.layer?.masksToBounds=true;panel.contentView=effect
        return panel
    }
    private func position(_ panel:NSWindow) {
        let r=desktopAnchor?() ?? NSRect(x:500,y:200,width:180,height:180)
        let area=(NSScreen.screens.first{$0.visibleFrame.intersects(r)} ?? NSScreen.main!).visibleFrame
        let y=r.maxY+8+panel.frame.height<=area.maxY ? r.maxY+8 : max(area.minY+4,r.minY-panel.frame.height-8)
        panel.setFrameOrigin(NSPoint(x:min(max(area.minX+4,r.midX-panel.frame.width/2),area.maxX-panel.frame.width-4),y:y))
    }
    private func build() {
        let w=makeBubble(NSSize(width:390,height:330));w.title="溯溯的对话气泡";w.dismiss={ [weak self] in self?.hideDesktop() }
        let root=w.contentView!
        scroll(transcript,rect:NSRect(x:12,y:130,width:366,height:188),in:root,font:14)
        input.frame=NSRect(x:12,y:86,width:256,height:32);input.placeholderString="和溯溯说句话……";root.addSubview(input);input.target=self;input.action=#selector(send)
        sendButton=button("发送",NSRect(x:280,y:86,width:98,height:32),#selector(send),in:root)
        button("新对话",NSRect(x:12,y:44,width:88,height:30),#selector(newConversation),in:root)
        button("停止",NSRect(x:104,y:44,width:70,height:30),#selector(stop),in:root)
        button("记忆",NSRect(x:182,y:44,width:88,height:30),#selector(showMemories),in:root)
        configButton=button("模型",NSRect(x:280,y:44,width:98,height:30),#selector(showConfiguration),in:root)
        status.frame=NSRect(x:12,y:3,width:366,height:36);status.font = .systemFont(ofSize:12);status.stringValue="点「模型」配置服务，再和它说句话。";root.addSubview(status)
        window=w
    }
    @objc private func showConfiguration() {
        configurationPanel?.orderOut(nil)
        let panel=makeBubble(NSSize(width:390,height:240));let root=panel.contentView!
        endpoint.frame=NSRect(x:12,y:184,width:366,height:32);endpoint.placeholderString="完整 chat/completions 接口";endpoint.stringValue=state.endpoint;root.addSubview(endpoint)
        model.frame=NSRect(x:12,y:142,width:366,height:32);model.placeholderString="模型名称";model.stringValue=state.model;root.addSubview(model)
        key.frame=NSRect(x:12,y:100,width:366,height:32);key.placeholderString="API Key，留空保留已存凭据";root.addSubview(key)
        button("保存连接",NSRect(x:12,y:53,width:170,height:32),#selector(saveConfiguration),in:root)
        button("删除已存 Key",NSRect(x:202,y:53,width:176,height:32),#selector(deleteKey),in:root)
        button("收起",NSRect(x:280,y:10,width:98,height:30),#selector(closeConfiguration),in:root)
        panel.dismiss={ [weak self] in self?.closeConfiguration() };position(panel);panel.orderFrontRegardless();configurationPanel=panel
    }
    @objc private func closeConfiguration(){configurationPanel?.orderOut(nil);configurationPanel=nil}
    @objc private func showMemories() {
        memoryPanel?.orderOut(nil)
        let panel=makeBubble(NSSize(width:390,height:300));let root=panel.contentView!
        messages.frame=NSRect(x:12,y:252,width:366,height:30);root.addSubview(messages)
        button("记住选中消息",NSRect(x:12,y:211,width:366,height:30),#selector(remember),in:root)
        memories.frame=NSRect(x:12,y:167,width:366,height:30);memories.target=self;memories.action=#selector(memorySelected);root.addSubview(memories)
        scroll(memoryText,rect:NSRect(x:12,y:67,width:366,height:90),in:root,font:13)
        button("删除选中记忆",NSRect(x:12,y:17,width:236,height:32),#selector(forget),in:root)
        button("收起",NSRect(x:270,y:17,width:108,height:32),#selector(closeMemories),in:root)
        panel.dismiss={ [weak self] in self?.closeMemories() };reload();position(panel);panel.orderFrontRegardless();memoryPanel=panel
    }
    @objc private func closeMemories(){memoryPanel?.orderOut(nil);memoryPanel=nil}
    func hideDesktop(){window?.orderOut(nil);closeConfiguration();closeMemories();stop()}
    @discardableResult private func button(_ text:String,_ rect:NSRect,_ action:Selector,in view:NSView)->NSButton {
        let b=NSButton(title:text,target:self,action:action);b.bezelStyle = .rounded;b.frame=rect;view.addSubview(b);return b
    }
    private func scroll(_ text:NSTextView,rect:NSRect,in parent:NSView,font:CGFloat) {
        let scroll=NSScrollView(frame:rect);scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        text.frame=NSRect(origin:.zero,size:rect.size);text.isEditable=false;text.isSelectable=true;text.font = .systemFont(ofSize:font);text.textContainerInset=NSSize(width:10,height:10);text.isVerticallyResizable=true;text.isHorizontallyResizable=false;text.autoresizingMask=[.width];text.textContainer?.widthTracksTextView=true
        scroll.documentView=text;parent.addSubview(scroll)
    }
    private func persist(_ next:ChatState)->Bool {
        do{try saveState(next);state=next;return true}
        catch{status.stringValue="没有保存成功："+error.localizedDescription;return false}
    }
    private func reload() {
        transcript.string=state.history.map{($0.role=="user" ? "你" : "溯溯")+"\n"+$0.content}.joined(separator:"\n\n")
        transcript.scrollToEndOfDocument(nil)
        let selected=messages.indexOfSelectedItem
        messages.removeAllItems();messages.addItem(withTitle:"选择一条消息，明确告诉它记住什么")
        messages.addItems(withTitles:state.history.map{($0.role=="user" ? "你 · " : "溯溯 · ")+String($0.content.prefix(42))})
        if selected>0 && selected<messages.numberOfItems{messages.selectItem(at:selected)}
        memories.removeAllItems();memories.addItem(withTitle:"已记住的事（\(state.memories.count)）")
        memories.addItems(withTitles:state.memories.map{String($0.prefix(60))})
        memoryText.string="只把你选择保留的记忆带入后续对话。可在上方选择后删除。"
        sendButton.isEnabled = !busy;configButton.isEnabled = !busy;endpoint.isEnabled = !busy;model.isEnabled = !busy
    }
    @objc private func saveConfiguration() {
        guard !busy else{return}
        do {
            let url=try ChatClient.validate(endpoint:endpoint.stringValue,model:model.stringValue)
            if !key.stringValue.isEmpty {try client.keychain.set(key.stringValue,origin:ChatClient.origin(url));key.stringValue=""}
            var next=getState();next.endpoint=url.absoluteString;next.model=model.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            if persist(next){status.stringValue="连接配置已保存。发送内容会交给你选择的模型服务。";reload()}
        } catch {status.stringValue=error.localizedDescription}
    }
    @objc private func deleteKey() {
        do{let url=try ChatClient.validate(endpoint:endpoint.stringValue,model:model.stringValue);try client.keychain.set("",origin:ChatClient.origin(url));key.stringValue="";status.stringValue="当前服务的 Key 已删除。"}
        catch{status.stringValue=error.localizedDescription}
    }
    @objc private func send() {
        guard !busy else{return}
        let text=input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=10000 else{status.stringValue="请输入 1 到 10000 字。";return}
        let previous=getState()
        do{_ = try ChatClient.validate(endpoint:previous.endpoint,model:previous.model)}catch{status.stringValue=error.localizedDescription;return}
        var pending=previous
        let user=ChatMessage(role:"user",content:text)
        pending.history.append(user);pending.history=Array(pending.history.suffix(98))
        guard persist(pending) else{return}
        busy=true;input.stringValue="";reload();status.stringValue="溯溯正在想……"
        let id=UUID();requestID=id
        task=client.send(state:previous,text:text){[weak self] result in
            guard let self,self.requestID==id else{return}
            self.busy=false;self.task=nil
            var latest=self.getState()
            guard latest.history.last?.id==user.id else{self.state=latest;self.reload();self.status.stringValue="对话记录已改变，本次回复未写入新对话。";return}
            switch result {
            case .success(let reply):
                latest.history.append(reply);latest.history=Array(latest.history.suffix(100))
                if self.persist(latest){self.status.stringValue=""}
            case .failure(let error):self.state=latest;self.status.stringValue=error.localizedDescription
            }
            self.reload()
        }
    }
    @objc private func stop() {
        requestID=UUID();task?.cancel();task=nil;busy=false
        state=getState();reload();status.stringValue="已停止本次回复。"
    }
    func windowWillClose(_ notification:Notification){stop()}
    @objc private func newConversation() {
        stop();var next=getState();next.history=[]
        if persist(next){reload();status.stringValue="新对话已开始，明确保存的记忆仍在。"}
    }
    @objc private func remember() {
        let index=messages.indexOfSelectedItem-1
        guard state.history.indices.contains(index) else{status.stringValue="请先在列表中选择一条消息。";return}
        let text=state.history[index].content
        guard text.count<=4000 else{status.stringValue="这条消息较长，请用一句简短的话告诉溯溯要记住什么。";return}
        var next=getState()
        guard !next.memories.contains(text) else{status.stringValue="已经记住这件事。";return}
        next.memories.append(text)
        if persist(next){reload();status.stringValue="这件事已记住，可在下方查看或删除。"}
    }
    @objc private func memorySelected() {
        let index=memories.indexOfSelectedItem-1
        memoryText.string=state.memories.indices.contains(index) ? state.memories[index] : "请选择一条记忆。"
    }
    @objc private func forget() {
        let index=memories.indexOfSelectedItem-1
        guard state.memories.indices.contains(index) else{return}
        let text=state.memories[index]
        var next=getState();next.memories.removeAll{$0==text}
        if persist(next){reload();status.stringValue="记忆已删除。新对话将不再带入这条记忆。"}
    }
    func runChecks(at directory:URL)throws {
        show();showMemories()
        precondition(window?.styleMask.contains(.titled)==false)
        // Exercise the real selection/deletion controls without contacting a model.
        var fixture=getState();fixture.history=[ChatMessage(role:"user",content:"我喜欢湖绿色围巾。")]
        guard persist(fixture) else{throw ChatError.response};reload();messages.selectItem(at:1);remember()
        precondition(getState().memories.contains("我喜欢湖绿色围巾。"))
        newConversation();precondition(getState().history.isEmpty && getState().memories.count==1)
        memories.selectItem(at:1);forget();precondition(getState().memories.isEmpty)
        window?.contentView?.layoutSubtreeIfNeeded();window?.displayIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.04))
        let root=window!.contentView!,bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds)!
        root.cacheDisplay(in:root.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("chat.png"))
    }
}
