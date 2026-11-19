import AppKit

final class ChatRoom:NSObject,NSWindowDelegate {
    private let getState:()->ChatState
    private let saveState:(ChatState)throws->Void
    private var state:ChatState
    private let client: ChatClient
    private var task:URLSessionDataTask?
    private var requestID=UUID()
    private(set) var window:NSWindow?
    private let endpoint=NSTextField()
    private let model=NSTextField()
    private let key=NSSecureTextField()
    private let input=NSTextField()
    private let transcript = ChatTranscript()
    private let mode = NSTextField(labelWithString: "")
    private let emptyState = NSStackView()
    private let activity = NSProgressIndicator()
    private let configurationStatus = NSTextField(wrappingLabelWithString: "")
    private var transcriptScroll: NSScrollView?
    private let status = NSTextField(wrappingLabelWithString: "按回车发送。")
    private var statusIsError = false
    private let desktopChat = DesktopChat()
    var isVisible: Bool { desktopChat.isVisible || configurationIsDesktop || window?.isVisible == true }
    var isDesktopChatVisible: Bool { desktopChat.isVisible }
    private let messages=NSPopUpButton()
    private let historyJump = NSPopUpButton()
    private var messageRanges: [UUID: NSRange] = [:]
    private var historyDisplay = NSAttributedString()
    private var historyBubbles: [ChatTranscript.Bubble] = []
    private var contextNotice = ""
    private let memories=NSPopUpButton()
    private let memoryText=NSTextView()
    private var sendButton:NSButton!
    private var configButton:NSButton!
    private var stopButton:NSButton!
    private var busy=false
    private var streamedText=""
    private var hasPendingTranscriptUpdate = false
    private var startedAt:TimeInterval?
    private var elapsedTimer:Timer?
    private let sizeKey="SusuDesktop.ChatRoom.windowSize"
    private var suppressWindowPersistence=false
    var desktopAnchor:(()->NSRect)?
    var avatar: (() -> NSImage?)?
    private var configurationPanel: NSWindow?
    private var configurationIsDesktop = false
    private var memoryPanel:DesktopBubble?

    init(getState: @escaping () -> ChatState, saveState: @escaping (ChatState) throws -> Void, client: ChatClient = ChatClient()) {
        self.getState = getState
        self.saveState = saveState
        self.client = client
        state = getState()
        super.init()
        desktopChat.onSend = { [weak self] text in self?.send(text) == true }
        desktopChat.onStop = { [weak self] in self?.stop() }
        desktopChat.postponeDismissal = { [weak self] in self?.busy == true }
        desktopChat.onExpand = { [weak self] in self?.show() }
        desktopChat.onConfigure = { [weak self] in self?.showConfiguration() }
    }

    func showDesktop() {
        closeModelSettings(restoreDesktop: false)
        window?.close()
        if !busy { state = getState() }
        desktopChat.show(at: anchor)
        renderDesktop()
    }

    func dismissDesktopChat() {
        if configurationIsDesktop { closeModelSettings(restoreDesktop: false) }
        desktopChat.hide()
    }

    func repositionDesktop() {
        if desktopChat.isVisible { desktopChat.reposition(at: anchor) }
        if configurationIsDesktop, let configurationPanel { position(configurationPanel) }
    }

    private var anchor: NSRect {
        desktopAnchor?() ?? NSRect(x: 500, y: 200, width: 180, height: 180)
    }

    // The full history window opens only when the desktop composer is expanded.
    private func show() {
        let firstOpen = window == nil
        if firstOpen {
            if configurationIsDesktop { closeModelSettings(restoreDesktop: false) }
            build()
            input.stringValue = desktopChat.draft
            desktopChat.hide()
        }
        if !busy { state = getState() }
        reload()
        if let window {
            if firstOpen { position(window) }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            if firstOpen { refreshTranscript(follow: true) }
            if busy { activity.startAnimation(nil); updateProgress() }
        }
    }
    private func makeBubble(_ size:NSSize)->DesktopBubble {
        let panel=DesktopBubble(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        let effect=NSVisualEffectView(frame:NSRect(origin:.zero,size:size));effect.material = .popover;effect.state = .active;effect.wantsLayer=true;effect.layer?.cornerRadius=18;effect.layer?.masksToBounds=true;panel.contentView=effect
        return panel
    }
    private func position(_ panel:NSWindow) {
        let r = anchor
        guard let area = (NSScreen.screens.first { $0.visibleFrame.intersects(r) } ?? NSScreen.main)?.visibleFrame else { return }
        let y=r.maxY+8+panel.frame.height<=area.maxY ? r.maxY+8 : max(area.minY+4,r.minY-panel.frame.height-8)
        panel.setFrameOrigin(NSPoint(x:max(area.minX+4,min(r.midX-panel.frame.width/2,area.maxX-panel.frame.width-4)),y:y))
    }
    private func build() {
        let saved = UserDefaults.standard.string(forKey: sizeKey).map(NSSizeFromString) ?? .zero
        let anchor = desktopAnchor?() ?? .zero
        let visible = (NSScreen.screens.first { $0.visibleFrame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame
        let minimum = NSSize(width: 430, height: 360)
        let maximum = NSSize(width: max(minimum.width, (visible?.width ?? 1400) - 12),
                             height: max(minimum.height, (visible?.height ?? 920) - 46))
        let size = NSSize(width: min(maximum.width, saved.width >= minimum.width ? saved.width : 580),
                          height: min(maximum.height, saved.height >= minimum.height ? saved.height : 530))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "溯溯"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentMinSize = minimum
        window.contentMaxSize = maximum

        let root = ChatSurface(frame: NSRect(origin: .zero, size: size), color: ChatPalette.canvas)
        window.contentView = root
        let header = ChatSurface(frame: NSRect(x: 0, y: size.height - 77, width: size.width, height: 77),
                                 color: ChatPalette.surface)
        header.autoresizingMask = [.width, .minYMargin]
        root.addSubview(header)
        let portrait = ChatSurface(frame: NSRect(x: 18, y: 13, width: 50, height: 50),
                                   color: ChatPalette.foxBubble, radius: 17)
        let fox = NSImageView(frame: portrait.bounds.insetBy(dx: 4, dy: 4))
        fox.image = avatar?() ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "溯溯")
        fox.imageScaling = .scaleProportionallyUpOrDown
        portrait.addSubview(fox)
        header.addSubview(portrait)
        label("和溯溯聊天", NSRect(x: 81, y: 38, width: 185, height: 25),
              size: 21, weight: .semibold, color: ChatPalette.ink, in: header)
        mode.frame = NSRect(x: 82, y: 14, width: size.width - 220, height: 18)
        mode.autoresizingMask = [.width]
        mode.font = .systemFont(ofSize: 12, weight: .medium)
        mode.lineBreakMode = .byTruncatingTail
        header.addSubview(mode)
        configButton = button("连接模型…", NSRect(x: size.width - 122, y: 22, width: 104, height: 32),
                              #selector(showConfiguration), in: header)
        configButton.autoresizingMask = [.minXMargin]

        let scrollRect = NSRect(x: 0, y: 113, width: size.width, height: size.height - 190)
        scroll(transcript, rect: scrollRect, in: root, font: 15)
        transcriptScroll = transcript.enclosingScrollView
        transcriptScroll?.borderType = .noBorder
        transcriptScroll?.drawsBackground = false
        transcript.drawsBackground = false
        transcript.textContainerInset = NSSize(width: 14, height: 18)
        transcript.setAccessibilityLabel("聊天记录")
        buildEmptyState(in: root)

        let footer = ChatSurface(frame: NSRect(x: 0, y: 0, width: size.width, height: 113),
                                 color: ChatPalette.surface)
        footer.autoresizingMask = [.width]
        root.addSubview(footer)
        historyJump.frame = NSRect(x: 16, y: 84, width: 134, height: 24)
        historyJump.bezelStyle = .rounded
        historyJump.font = .systemFont(ofSize: 11)
        historyJump.target = self
        historyJump.action = #selector(jumpToMessage(_:))
        historyJump.setAccessibilityLabel("跳到历史消息")
        footer.addSubview(historyJump)
        button("记忆", NSRect(x: 155, y: 83, width: 58, height: 26), #selector(showMemories), in: footer)
        button("新对话", NSRect(x: 215, y: 83, width: 71, height: 26), #selector(newConversation), in: footer)
        stopButton = button("停止回复", NSRect(x: size.width - 111, y: 83, width: 95, height: 26),
                            #selector(stop), in: footer)
        stopButton.autoresizingMask = [.minXMargin]

        input.frame = NSRect(x: 18, y: 45, width: size.width - 126, height: 31)
        input.placeholderString = "和溯溯说句话…"
        input.setAccessibilityLabel("消息")
        input.font = .systemFont(ofSize: 15)
        input.autoresizingMask = [.width]
        input.bezelStyle = .roundedBezel
        input.target = self
        input.action = #selector(sendWindowDraft)
        footer.addSubview(input)
        sendButton = button("发送", NSRect(x: size.width - 101, y: 42, width: 83, height: 36),
                            #selector(sendWindowDraft), in: footer)
        sendButton.bezelColor = ChatPalette.accent
        sendButton.keyEquivalent = "\r"
        sendButton.autoresizingMask = [.minXMargin]

        activity.frame = NSRect(x: 20, y: 20, width: 13, height: 13)
        activity.style = .spinning
        activity.controlSize = .small
        activity.isDisplayedWhenStopped = false
        footer.addSubview(activity)
        status.frame = NSRect(x: 19, y: 4, width: size.width - 38, height: 34)
        status.autoresizingMask = [.width]
        status.font = .systemFont(ofSize: 11)
        status.textColor = ChatPalette.muted
        footer.addSubview(status)
        self.window = window
        window.initialFirstResponder = input
    }

    private func buildEmptyState(in root: NSView) {
        emptyState.subviews.forEach { $0.removeFromSuperview() }
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 12
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "今天想聊点什么？")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.textColor = ChatPalette.ink
        emptyState.addArrangedSubview(title)
        let prompts = NSStackView()
        prompts.spacing = 7
        for prompt in ["你好，溯溯", "陪我休息一下", "今天有点累"] {
            let button = NSButton(title: prompt, target: self, action: #selector(sendPrompt(_:)))
            button.bezelStyle = .rounded
            prompts.addArrangedSubview(button)
        }
        emptyState.addArrangedSubview(prompts)
        root.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -18)
        ])
    }

    @objc private func sendPrompt(_ sender: NSButton) {
        input.stringValue = sender.title
        input.currentEditor()?.string = sender.title
        sendWindowDraft()
        window?.makeFirstResponder(input)
    }

    @discardableResult private func label(_ text: String, _ frame: NSRect, size: CGFloat = 13,
                                           weight: NSFont.Weight = .regular, color: NSColor = .labelColor,
                                           in parent: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.frame = frame
        parent.addSubview(label)
        return label
    }

    @objc private func showConfiguration() {
        guard !busy, configurationPanel == nil else { return }
        let size = NSSize(width: 442, height: 319)
        let panel: NSWindow
        if window == nil {
            let bubble = makeBubble(size)
            bubble.dismiss = { [weak self] in self?.closeConfiguration() }
            panel = bubble
        } else {
            panel = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                             backing: .buffered, defer: false)
        }
        panel.title = "聊天模型"
        panel.isReleasedWhenClosed = false
        let root = ChatSurface(frame: NSRect(x: 0, y: 0, width: 442, height: 319), color: ChatPalette.surface)
        panel.contentView = root
        label("接入 OpenAI 兼容模型", NSRect(x: 20, y: 280, width: 402, height: 25),
              size: 18, weight: .semibold, in: root)
        label("模型模式会将消息、近期对话和已保存的记忆发给你配置的服务。",
              NSRect(x: 20, y: 256, width: 402, height: 18), size: 11, color: .secondaryLabelColor, in: root)
        label("服务地址", NSRect(x: 20, y: 225, width: 80, height: 20), in: root)
        endpoint.frame = NSRect(x: 111, y: 222, width: 311, height: 25)
        endpoint.placeholderString = "https://服务地址/v1"
        endpoint.stringValue = state.endpoint
        endpoint.setAccessibilityLabel("服务地址")
        root.addSubview(endpoint)
        label("模型名称", NSRect(x: 20, y: 185, width: 80, height: 20), in: root)
        model.frame = NSRect(x: 111, y: 182, width: 311, height: 25)
        model.placeholderString = "填写服务提供的模型 ID"
        model.stringValue = state.model
        model.setAccessibilityLabel("模型名称")
        root.addSubview(model)
        label("API Key", NSRect(x: 20, y: 145, width: 80, height: 20), in: root)
        key.frame = NSRect(x: 111, y: 142, width: 311, height: 25)
        key.placeholderString = "留空继续使用此服务已有的 Key"
        key.stringValue = ""
        key.setAccessibilityLabel("API Key")
        root.addSubview(key)
        configurationStatus.frame = NSRect(x: 20, y: 54, width: 402, height: 48)
        configurationStatus.font = .systemFont(ofSize: 12)
        configurationStatus.textColor = .secondaryLabelColor
        configurationStatus.stringValue = "API Key 保存在本机钥匙串。保存后，下一条消息会使用该服务。"
        root.addSubview(configurationStatus)
        button("删除已存 Key…", NSRect(x: 16, y: 103, width: 121, height: 28), #selector(deleteKey), in: root)
        button("使用本地简答", NSRect(x: 16, y: 15, width: 116, height: 32), #selector(useLocal), in: root)
        button("取消", NSRect(x: 245, y: 15, width: 72, height: 32), #selector(closeConfiguration), in: root)
        let save = button("保存并启用", NSRect(x: 319, y: 15, width: 108, height: 32), #selector(saveConfiguration), in: root)
        save.keyEquivalent = "\r"
        configurationPanel = panel
        panel.initialFirstResponder = endpoint
        if let window {
            window.beginSheet(panel)
        } else {
            configurationIsDesktop = true
            desktopChat.hide()
            position(panel)
            panel.orderFrontRegardless()
            panel.makeKey()
            panel.makeFirstResponder(endpoint)
        }
    }

    @objc private func closeConfiguration() { closeModelSettings() }

    private func closeModelSettings(restoreDesktop: Bool = true) {
        guard let panel = configurationPanel else { return }
        let wasDesktop = configurationIsDesktop
        configurationIsDesktop = false
        configurationPanel = nil
        key.stringValue = ""
        if let window { window.endSheet(panel) }
        panel.orderOut(nil)
        if restoreDesktop && wasDesktop {
            desktopChat.show(at: anchor)
            renderDesktop()
        }
    }
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
        panel.armIdleDismissal()
    }
    @objc private func closeMemories(){memoryPanel?.orderOut(nil);memoryPanel=nil}
    func hideDesktop() {
        dismissDesktopChat()
        window?.close()
        closeModelSettings(restoreDesktop: false)
        closeMemories()
        stop()
    }
    @discardableResult private func button(_ text:String,_ rect:NSRect,_ action:Selector,in view:NSView)->NSButton {
        let b=NSButton(title:text,target:self,action:action);b.bezelStyle = .rounded;b.frame=rect;view.addSubview(b);return b
    }
    private func scroll(_ text:NSTextView,rect:NSRect,in parent:NSView,font:CGFloat) {
        let scroll=NSScrollView(frame:rect);scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        scroll.autoresizingMask=[.width,.height]
        text.frame=NSRect(origin:.zero,size:rect.size);text.isEditable=false;text.isSelectable=true;text.font = .systemFont(ofSize:font);text.textContainerInset=NSSize(width:10,height:10);text.isVerticallyResizable=true;text.isHorizontallyResizable=false;text.autoresizingMask=[.width];text.textContainer?.widthTracksTextView=true
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = NSSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView=text;parent.addSubview(scroll)
    }
    private func persist(_ next: ChatState) -> Bool {
        do {
            try saveState(next)
            state = next
            return true
        } catch {
            let message = "保存失败。\(error.localizedDescription)"
            showStatus(message, error: true)
            if configurationPanel != nil { showConfigurationStatus(message, error: true) }
            return false
        }
    }

    private func modelEnabled(_ state: ChatState) -> Bool {
        state.prefersLocal != true && (try? ChatClient.validate(endpoint: state.endpoint, model: state.model)) != nil
    }

    private func showStatus(_ message: String, error: Bool = false) {
        status.stringValue = message
        status.textColor = error ? .systemRed : ChatPalette.muted
        statusIsError = error
        renderDesktop()
    }

    private func showConfigurationStatus(_ message: String, error: Bool = false) {
        configurationStatus.stringValue = message
        configurationStatus.textColor = error ? .systemRed : .secondaryLabelColor
    }

    private func renderDesktop() {
        guard desktopChat.isVisible else { return }
        let usesModel = modelEnabled(state)
        let latestReply = state.history.last.flatMap { $0.role == "assistant" ? $0 : nil }
        let text = busy ? (streamedText.isEmpty ? "我正在想…" : streamedText) : latestReply?.content ?? ""
        let replyLabel: String
        switch busy ? ChatMessage.Source.model : latestReply?.source {
        case .local: replyLabel = "本地简答"
        case .model: replyLabel = "模型回复"
        case nil: replyLabel = ""
        }
        let modeText = usesModel ? "模型模式" : "本地简答"
        let notice = busy || statusIsError || status.stringValue.hasPrefix("已停止") ? status.stringValue : ""
        desktopChat.update(reply: text, replyLabel: replyLabel, mode: modeText, status: notice,
                           busy: busy, isError: statusIsError)
    }

    private func reload() {
        guard window != nil else { renderDesktop(); return }
        let selectedMessage = messages.selectedItem?.representedObject as? UUID
        let display = NSMutableAttributedString()
        messageRanges.removeAll(keepingCapacity: true)
        historyBubbles.removeAll(keepingCapacity: true)
        for message in state.history {
            let bubble = ChatTranscript.append(message, to: display)
            messageRanges[message.id] = bubble.range
            historyBubbles.append(bubble)
        }
        historyDisplay = display
        refreshTranscript()
        populateMessages(messages, placeholder: "选择要记住的消息")
        populateMessages(historyJump, placeholder: "历史消息…")
        historyJump.isEnabled = !state.history.isEmpty
        if let selectedMessage, let index = state.history.firstIndex(where: { $0.id == selectedMessage }) {
            messages.selectItem(at: index + 1)
        }
        let selectedMemory = memories.indexOfSelectedItem
        memories.removeAllItems()
        memories.addItem(withTitle: "已记住的事（\(state.memories.count)）")
        memories.addItems(withTitles: state.memories.map { String($0.prefix(60)) })
        if selectedMemory > 0 && selectedMemory < memories.numberOfItems {
            memories.selectItem(at: selectedMemory)
            memorySelected()
        } else {
            memoryText.string = "明确保存的记忆会随模型对话发送。可在上方选择后查看或删除。"
        }
        let usesModel = modelEnabled(state)
        mode.stringValue = usesModel ? "模型模式 · \(state.model)" : "本地简答 · 无需联网"
        mode.textColor = usesModel ? ChatPalette.accent : ChatPalette.muted
        configButton.title = usesModel ? "模型设置…" : "连接模型…"
        sendButton.isEnabled = !busy
        stopButton.isHidden = !busy
        stopButton.isEnabled = busy
        configButton.isEnabled = !busy
    }

    private func populateMessages(_ picker: NSPopUpButton, placeholder: String) {
        picker.removeAllItems()
        picker.addItem(withTitle: placeholder)
        for (index, message) in state.history.enumerated() {
            let speaker = message.role == "user" ? "你" : "溯溯"
            let excerpt = message.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            picker.addItem(withTitle: "\(index+1) · \(speaker) · \(excerpt.prefix(40))")
            picker.lastItem?.representedObject = message.id
        }
    }

    @objc private func jumpToMessage(_ picker: NSPopUpButton) {
        guard let id = picker.selectedItem?.representedObject as? UUID, let range = messageRanges[id] else { return }
        transcript.setSelectedRange(range)
        transcript.scrollRangeToVisible(NSRange(location: range.location, length: min(1, range.length)))
        picker.selectItem(at: 0)
    }

    private func refreshTranscript(follow: Bool = false) {
        renderDesktop()
        guard let scroll = transcriptScroll else { return }
        let clip = scroll.contentView
        let visible = scroll.documentVisibleRect
        let nearBottom = visible.maxY >= transcript.bounds.maxY - 32
        let display = NSMutableAttributedString(attributedString: historyDisplay)
        var bubbles = historyBubbles
        if busy || !streamedText.isEmpty {
            let pending = ChatMessage(role: "assistant",
                                      content: streamedText.isEmpty ? "正在等模型回复…" : streamedText, source: .model)
            bubbles.append(ChatTranscript.append(pending, to: display))
        }
        emptyState.isHidden = !bubbles.isEmpty
        if transcript.textStorage?.isEqual(to: display) == false {
            let origin = clip.bounds.origin
            let selection = transcript.selectedRange()
            transcript.bubbles = bubbles
            transcript.textStorage?.setAttributedString(display)
            transcript.needsDisplay = true
            if selection.location != NSNotFound, NSMaxRange(selection) <= display.length {
                transcript.setSelectedRange(selection)
            }
            if let container = transcript.textContainer { transcript.layoutManager?.ensureLayout(for: container) }
            transcript.sizeToFit()
            if follow || nearBottom { scrollToLatest() }
            else { clip.scroll(to: origin); scroll.reflectScrolledClipView(clip) }
        } else if follow { scrollToLatest() }
    }

    private func scrollToLatest() {
        guard let scroll = transcriptScroll else { return }
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(0, transcript.bounds.maxY - clip.bounds.height)))
        scroll.reflectScrolledClipView(clip)
    }

    @objc private func saveConfiguration() {
        guard !busy else { return }
        do {
            let cleanedModel = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = try ChatClient.validate(endpoint: ChatClient.normalizedEndpoint(endpoint.stringValue), model: cleanedModel)
            let apiKey = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty { try client.keychain.set(apiKey, origin: ChatClient.origin(url)) }
            var next = getState()
            next.endpoint = url.absoluteString
            next.model = cleanedModel
            next.prefersLocal = false
            if persist(next) {
                closeConfiguration()
                reload()
                showStatus("模型设置已保存。发送一条消息即可试用。")
            }
        } catch { showConfigurationStatus(error.localizedDescription, error: true) }
    }

    @objc private func useLocal() {
        guard !busy else { return }
        var next = getState()
        next.prefersLocal = true
        if persist(next) {
            closeConfiguration()
            reload()
            showStatus("已切换到本地简答。")
        }
    }

    @objc private func deleteKey() {
        guard confirmDestructiveAction("删除当前服务的凭据？", message: "下次需要凭据时，可以在模型设置重新填写。") else { return }
        do {
            let url = try ChatClient.validate(endpoint: ChatClient.normalizedEndpoint(endpoint.stringValue),
                                              model: model.stringValue)
            try client.keychain.set("", origin: ChatClient.origin(url))
            key.stringValue = ""
            showConfigurationStatus("当前服务的 Key 已删除。")
        } catch { showConfigurationStatus(error.localizedDescription, error: true) }
    }

    @objc private func sendWindowDraft() {
        if send(input.currentEditor()?.string ?? input.stringValue) {
            input.stringValue = ""
            input.currentEditor()?.string = ""
        }
    }

    @discardableResult
    private func send(_ raw: String) -> Bool {
        guard !busy else { return false }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 10_000 else {
            showStatus("请输入 1 到 10000 字。", error: true)
            return false
        }
        let previous = getState()
        var pending = previous
        let user = ChatMessage(role: "user", content: text)
        pending.history.append(user)
        if !modelEnabled(previous) {
            pending.history.append(LocalChat.reply(to: text))
            pending.history = Array(pending.history.suffix(100))
            guard persist(pending) else { return false }
            reload()
            refreshTranscript(follow: true)
            showStatus("按回车发送。")
            return true
        }
        pending.history = Array(pending.history.suffix(99))
        guard persist(pending) else { return false }
        busy = true
        streamedText = ""
        startedAt = ProcessInfo.processInfo.systemUptime
        let omitted = max(0, previous.history.count - ChatClient.contextHistoryLimit)
        contextNotice = omitted == 0 ? "" : "较早的 \(omitted) 条历史未带入。"
        activity.startAnimation(nil)
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.updateProgress() }
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        reload()
        refreshTranscript(follow: true)
        updateProgress()

        let id = UUID()
        requestID = id
        task = client.send(state: previous, text: text, onDelta: { [weak self] delta in
            guard let self, self.requestID == id else { return }
            self.streamedText = delta
            self.hasPendingTranscriptUpdate = true
        }) { [weak self] result in
            guard let self, self.requestID == id else { return }
            self.busy = false
            self.task = nil
            self.stopProgress()
            self.streamedText = ""
            var latest = self.getState()
            guard latest.history.last?.id == user.id else {
                self.state = latest
                self.reload()
                self.showStatus("对话记录已改变，本次回复未写入新对话。")
                return
            }
            switch result {
            case .success(let reply):
                latest.history.append(ChatMessage(id: reply.id, role: reply.role, content: reply.content, source: .model))
                if self.persist(latest) {
                    self.showStatus(self.contextNotice.isEmpty ? "回复完成。" : "回复完成。"+self.contextNotice)
                }
            case .failure(let error):
                latest.history.append(LocalChat.reply(to: text))
                if self.persist(latest) {
                    self.showStatus("已改用本地简答。\(error.localizedDescription)", error: true)
                }
            }
            self.reload()
        }
        return true
    }
    @objc private func stop() {
        guard busy else { return }
        requestID=UUID();task?.cancel();task=nil;busy=false;streamedText="";stopProgress()
        state=getState();reload();showStatus("已停止本次回复。")
    }
    func windowWillClose(_ notification: Notification) {
        desktopChat.draft = input.currentEditor()?.string ?? input.stringValue
        closeModelSettings(restoreDesktop: false)
        closeMemories()
        transcriptScroll = nil
        window = nil
    }
    func windowDidResize(_ notification:Notification) { guard !suppressWindowPersistence,let window else{return};let contentSize=window.contentRect(forFrameRect:window.frame).size;UserDefaults.standard.set(NSStringFromSize(contentSize),forKey:sizeKey) }
    private func stopProgress() {
        elapsedTimer?.invalidate(); elapsedTimer = nil; startedAt = nil; hasPendingTranscriptUpdate = false
        activity.stopAnimation(nil)
        status.frame.origin.x = 19
        if let footer = status.superview { status.frame.size.width = footer.bounds.width - 38 }
    }
    private func updateProgress() {
        guard let startedAt else { return }
        let elapsed = Int(ProcessInfo.processInfo.systemUptime - startedAt)
        let phase = streamedText.isEmpty ? "等待模型开始回复" : "正在接收回复"
        let message = "\(phase) · \(elapsed) 秒\(contextNotice.isEmpty ? "" : "  " + contextNotice)"
        status.frame.origin.x = 40
        if let footer = status.superview { status.frame.size.width = footer.bounds.width - 59 }
        if status.stringValue != message { showStatus(message) }
        if hasPendingTranscriptUpdate {
            hasPendingTranscriptUpdate = false
            refreshTranscript()
        }
    }
    @objc private func newConversation() {
        guard confirmDestructiveAction("开始新对话？", message: "当前对话记录将被清除，已保存的记忆不会删除。", actionLabel: "清除对话") else { return }
        stop();var next=getState();next.history=[]
        if persist(next){reload();showStatus("新对话已开始，明确保存的记忆仍在。")}
    }
    @objc private func remember() {
        let index=messages.indexOfSelectedItem-1
        guard state.history.indices.contains(index) else{showStatus("请先在列表中选择一条消息。");return}
        let text=state.history[index].content
        guard text.count<=4000 else{showStatus("这条消息较长，请用一句简短的话告诉溯溯要记住什么。");return}
        var next=getState()
        guard !next.memories.contains(text) else{showStatus("已经记住这件事。");return}
        next.memories.append(text)
        if persist(next){reload();showStatus("这件事已记住，可在记忆里查看或删除。")}
    }
    @objc private func memorySelected() {
        let index=memories.indexOfSelectedItem-1
        memoryText.string=state.memories.indices.contains(index) ? state.memories[index] : "请选择一条记忆。"
    }
    @objc private func forget() {
        let index=memories.indexOfSelectedItem-1
        guard state.memories.indices.contains(index) else{return}
        let text=state.memories[index]
        guard confirmDestructiveAction("删除这条记忆？", message: "删除后，后续对话将不再带入这条记忆。") else { return }
        var next=getState();next.memories.removeAll{$0==text}
        if persist(next){reload();showStatus("记忆已删除。")}
    }
    func runChecks(at directory:URL)throws {
        suppressWindowPersistence = true
        defer { suppressWindowPersistence = false }
        try checkDesktopChat(at: directory)
        show();showMemories()
        precondition(window?.styleMask.contains(.titled)==true)
        precondition(window?.styleMask.contains(.resizable)==true)
        let window = window!
        let originalSize = window.contentRect(forFrameRect: window.frame).size
        window.setContentSize(window.contentMinSize)
        let before = transcriptScroll!.bounds.size
        window.setContentSize(NSSize(width: min(600, window.contentMaxSize.width), height: min(520, window.contentMaxSize.height)))
        window.displayIfNeeded()
        let after = transcriptScroll!.bounds.size
        if window.contentMaxSize.width > window.contentMinSize.width { precondition(after.width > before.width) }
        if window.contentMaxSize.height > window.contentMinSize.height { precondition(after.height > before.height) }
        window.setContentSize(originalSize)
        // Exercise the real selection/deletion controls without contacting a model.
        var fixture=getState();fixture.history=[ChatMessage(role:"user",content:"我喜欢湖绿色围巾。")]
        guard persist(fixture) else{throw ChatError.response};reload();messages.selectItem(at:1);remember()
        precondition(getState().memories.contains("我喜欢湖绿色围巾。"))
        fixture=getState();fixture.history=[];fixture.memories=[]
        guard persist(fixture) else{throw ChatError.response};reload()
        precondition(getState().history.isEmpty && getState().memories.isEmpty)
        // An incoming delta must leave a reader at the same spot in a long transcript.
        let originalState = state
        let intro = ChatMessage(role: "assistant", content: "你好 🦊 e\u{0301}")
        let longMessage = ChatMessage(role: "user", content: (1...85).map { "第 \($0) 行对话" }.joined(separator: "\n"))
        state.history = [intro, longMessage]
        reload()
        precondition(!stopButton.isEnabled)
        historyJump.selectItem(at: 2)
        jumpToMessage(historyJump)
        let selected = (transcript.string as NSString).substring(with: transcript.selectedRange())
        precondition(selected == "你\n" + longMessage.content, "History jump must use UTF-16 ranges")
        let scroll = transcriptScroll!
        precondition(transcript.bounds.height > scroll.documentVisibleRect.height)
        scroll.contentView.scroll(to: .zero)
        streamedText = "这段文字正在接收。"
        refreshTranscript()
        precondition(scroll.documentVisibleRect.minY < 32 && transcript.string.hasSuffix(streamedText))
        refreshTranscript(follow: true)
        precondition(scroll.documentVisibleRect.maxY >= transcript.bounds.maxY - 32)
        streamedText = ""
        var unconfigured = originalState
        unconfigured.endpoint = ""
        unconfigured.model = ""
        precondition(persist(unconfigured))
        reload()
        precondition(mode.stringValue.contains("本地简答") && !emptyState.isHidden)
        closeMemories()
        showStatus("按回车发送。")
        try capture(window, to: directory.appendingPathComponent("chat-empty.png"))
        input.stringValue = "你好，溯溯"
        sendButton.performClick(nil)
        input.stringValue = "今天有点累"
        sendWindowDraft()
        let offlineHistory = getState().history
        precondition(offlineHistory.count == 4 && offlineHistory[1].source == .local && offlineHistory[3].source == .local)
        precondition(transcript.string.contains(offlineHistory[3].content) && transcript.bubbles.count == 4 && emptyState.isHidden)
        precondition(scroll.documentVisibleRect.maxY >= transcript.bounds.maxY - 32)
        try capture(window, to: directory.appendingPathComponent("chat.png"))
        window.appearance = NSAppearance(named: .darkAqua)
        try capture(window, to: directory.appendingPathComponent("chat-dark.png"))
        window.appearance = nil

        showConfiguration()
        endpoint.stringValue = "https://mock.example/v1"
        model.stringValue = "susu-test"
        if let panel = configurationPanel { try capture(panel, to: directory.appendingPathComponent("chat-model.png")) }
        saveConfiguration()
        precondition(configurationPanel == nil && mode.stringValue.contains("susu-test"))
        precondition(getState().endpoint == "https://mock.example/v1/chat/completions")
        showConfiguration()
        useLocal()
        precondition(getState().prefersLocal == true && mode.stringValue.contains("本地简答"))
        precondition(persist(originalState))
        reload()
        checkMockModel()
        print("PASS: default desktop chat, anchor placement, draft and history handoff, local replies, model streaming, cancellation and fallback.")
    }

    private func checkDesktopChat(at directory: URL) throws {
        let original = getState()
        let originalAnchor = desktopAnchor
        defer {
            desktopAnchor = originalAnchor
            precondition(persist(original))
            hideDesktop()
        }
        precondition(persist(ChatState()))
        showDesktop()
        guard let panel = desktopChat.panel else { throw ChatError.response }
        precondition(window == nil && panel.isVisible && !panel.styleMask.contains(.titled))
        precondition(panel.frame.height < 100)
        try capture(panel, to: directory.appendingPathComponent("desktop-chat-empty.png"))

        desktopChat.draft = "今天有点累"
        desktopChat.sendDraft()
        let messages = getState().history
        precondition(messages.count == 2 && messages.first?.content == "今天有点累" && messages.last?.source == .local)
        precondition(desktopChat.replyText == messages.last?.content && desktopChat.draft.isEmpty)
        precondition(panel.frame.height > 100 && panel.frame.height < 210 && window == nil)
        try capture(panel, to: directory.appendingPathComponent("desktop-chat.png"))

        let shortConversation = getState()
        var longConversation = shortConversation
        let longReply = (1...48).map { "第 \($0) 行回复" }.joined(separator: "\n")
        longConversation.history.append(ChatMessage(role: "assistant", content: longReply, source: .model))
        precondition(persist(longConversation))
        renderDesktop()
        guard let replyScroll = panel.contentView?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView else {
            throw ChatError.response
        }
        precondition(desktopChat.replyText == longReply && panel.frame.height < 210)
        precondition((replyScroll.documentView?.bounds.height ?? 0) > replyScroll.documentVisibleRect.height)
        precondition(persist(shortConversation))
        renderDesktop()

        if let area = NSScreen.main?.visibleFrame {
            desktopAnchor = { NSRect(x: area.maxX - 55, y: area.maxY - 53, width: 110, height: 95) }
            repositionDesktop()
            precondition(area.contains(panel.frame) && !panel.frame.intersects(anchor))
            desktopAnchor = { NSRect(x: area.minX - 55, y: area.minY - 47, width: 110, height: 95) }
            repositionDesktop()
            precondition(area.contains(panel.frame) && !panel.frame.intersects(anchor))
        }

        desktopChat.draft = "还没发出去的草稿"
        let idleStart = ProcessInfo.processInfo.systemUptime
        panel.checkIdle(at: idleStart + 29, limit: 30)
        precondition(desktopChat.isVisible)
        panel.checkIdle(at: idleStart + 31, limit: 30)
        precondition(!desktopChat.isVisible)
        showDesktop()
        precondition(desktopChat.draft == "还没发出去的草稿")
        desktopChat.onConfigure?()
        precondition(configurationIsDesktop && configurationPanel?.isVisible == true &&
                     !desktopChat.isVisible && window == nil)
        closeConfiguration()
        precondition(desktopChat.isVisible && desktopChat.draft == "还没发出去的草稿")

        desktopChat.onExpand?()
        precondition(window?.isVisible == true && !desktopChat.isVisible)
        precondition(input.stringValue == "还没发出去的草稿" && transcript.string.contains(desktopChat.replyText))
        input.stringValue = "写在窗口里的草稿"
        input.currentEditor()?.string = input.stringValue
        showDesktop()
        precondition(window == nil && desktopChat.isVisible && desktopChat.draft == "写在窗口里的草稿")
        desktopChat.draft = ""
    }

    private func capture(_ window: NSWindow, to url: URL) throws {
        let root = window.contentView!
        root.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    private func checkMockModel() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatSmokeProvider.self]
        let modelClient = ChatClient(configuration: config, credential: { _ in nil })
        var fixture = ChatState(endpoint: "https://mock.example/v1/chat/completions", model: "smoke")
        let room = ChatRoom(getState: { fixture }, saveState: { fixture = $0 }, client: modelClient)
        room.suppressWindowPersistence = true
        room.showDesktop()
        defer { room.hideDesktop() }

        func waitForReply() {
            let deadline = Date().addingTimeInterval(3)
            while room.busy && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(!room.busy, "Mock model reply did not finish")
        }
        room.desktopChat.draft = "你在吗？"
        room.desktopChat.sendDraft()
        precondition(room.busy && room.window == nil && room.desktopChat.replyText == "我正在想…")
        room.desktopChat.panel?.checkIdle(at: ProcessInfo.processInfo.systemUptime + 31, limit: 30)
        precondition(room.desktopChat.isVisible)
        waitForReply()
        precondition(fixture.history.count == 2 && fixture.history.last?.source == .model)
        precondition(room.desktopChat.replyText == "我就在桌边。")

        fixture.endpoint = "https://mock.example/unavailable"
        room.desktopChat.draft = "你好"
        room.desktopChat.sendDraft()
        waitForReply()
        precondition(fixture.history.count == 4 && fixture.history.last?.source == .local)
        precondition(room.desktopChat.replyText.contains("你好") && room.status.stringValue.contains("503"))

        fixture.endpoint = "https://mock.example/v1/chat/completions"
        room.desktopChat.draft = "切换界面测试"
        room.desktopChat.sendDraft()
        room.desktopChat.onExpand?()
        precondition(room.busy && room.window?.isVisible == true && !room.desktopChat.isVisible)
        precondition(room.transcript.string.hasSuffix("正在等模型回复…"))
        waitForReply()
        precondition(fixture.history.count == 6 && room.transcript.string.hasSuffix("我就在桌边。"))

        fixture.endpoint = "https://mock.example/v1/chat/completions"
        room.input.stringValue = "停止测试"
        room.sendWindowDraft()
        room.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(fixture.history.count == 7 && fixture.history.last?.role == "user")
        precondition(!room.busy && !room.transcript.string.contains("正在等模型回复…"))
    }
}

enum ChatPalette {
    static let canvas = adaptive(0xf6f3ee, 0x201e1c)
    static let surface = adaptive(0xfffdf9, 0x2b2826)
    static let ink = adaptive(0x332621, 0xf6ece3)
    static let muted = adaptive(0x6f5d53, 0xccb9aa)
    static let accent = adaptive(0xa64626, 0xf5aa86)
    static let foxBubble = adaptive(0xfffdf9, 0x332d29)
    static let foxBorder = adaptive(0xe9dfd6, 0x4d413a)
    static let userBubble = adaptive(0xf7dfd0, 0x583727)
    static let userBorder = adaptive(0xeccdbb, 0x80523d)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
                           green: CGFloat((rgb >> 8) & 0xff) / 255,
                           blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
        }
    }
}

private final class ChatSurface: NSView {
    private let color: NSColor
    private let radius: CGFloat

    init(frame: NSRect, color: NSColor, radius: CGFloat = 0) {
        self.color = color
        self.radius = radius
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}

private final class ChatTranscript: NSTextView {
    struct Bubble {
        let range: NSRange
        let isUser: Bool
    }

    var bubbles: [Bubble] = []

    static func append(_ message: ChatMessage, to display: NSMutableAttributedString) -> Bubble {
        let isUser = message.role == "user"
        let heading: String
        switch message.source {
        case .local: heading = "溯溯  ·  本地简答"
        case .model: heading = "溯溯  ·  模型回复"
        case nil: heading = isUser ? "你" : "溯溯"
        }
        if display.length > 0 {
            display.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 16)]))
        }
        let start = display.length
        let title = NSMutableParagraphStyle()
        title.firstLineHeadIndent = isUser ? 100 : 12
        title.headIndent = title.firstLineHeadIndent
        title.tailIndent = isUser ? -14 : -102
        title.alignment = isUser ? .right : .left
        title.paragraphSpacing = 3
        let paragraph = title.mutableCopy() as! NSMutableParagraphStyle
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 0
        display.append(NSAttributedString(string: heading + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: isUser ? ChatPalette.accent : ChatPalette.muted,
            .paragraphStyle: title
        ]))
        display.append(NSAttributedString(string: message.content, attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: ChatPalette.ink,
            .paragraphStyle: paragraph
        ]))
        return Bubble(range: NSRange(location: start, length: display.length - start), isUser: isUser)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer, let storage = textStorage else { return }
        let origin = textContainerOrigin
        let visible = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y),
                                              in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        for bubble in bubbles where NSMaxRange(bubble.range) <= storage.length {
            guard NSIntersectionRange(visibleCharacters, bubble.range).length > 0 else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: bubble.range, actualCharacterRange: nil)
            let first = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let last = layoutManager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            var edges = first
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
                edges = edges.union(used)
            }
            let left = max(6, edges.minX - 11)
            let right = min(textContainer.size.width - 6, edges.maxX + 11)
            let area = NSRect(x: origin.x + left, y: origin.y + first.minY - 7,
                              width: right - left, height: last.maxY - first.minY + 14)
            guard area.intersects(rect), area.width > 0 else { continue }
            let path = NSBezierPath(roundedRect: area, xRadius: 13, yRadius: 13)
            (bubble.isUser ? ChatPalette.userBubble : ChatPalette.foxBubble).setFill()
            path.fill()
            (bubble.isUser ? ChatPalette.userBorder : ChatPalette.foxBorder).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}


private final class ChatSmokeProvider: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let available = url.path != "/unavailable"
        let response = HTTPURLResponse(url: url, statusCode: available ? 200 : 503, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if available {
            let reply = #"data: {"choices":[{"delta":{"content":"我就在桌边。"}}]}"# + "\n\ndata: [DONE]\n\n"
            client?.urlProtocol(self, didLoad: Data(reply.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
