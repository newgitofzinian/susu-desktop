import AppKit

/// The local and model replies share this presentation beside the desktop pet.
final class DesktopChat: NSObject {
    var onSend: ((String) -> Bool)?
    var onExpand: (() -> Void)?
    var onConfigure: (() -> Void)?
    var onStop: (() -> Void)?
    var postponeDismissal: (() -> Bool)?
    private(set) var panel: DesktopBubble?
    var isVisible: Bool { panel?.isVisible == true }
    var draft: String {
        get { input.currentEditor()?.string ?? input.stringValue }
        set {
            input.stringValue = newValue
            input.currentEditor()?.string = newValue
        }
    }
    var replyText: String { reply.string }

    private let input = NSTextField()
    private let reply = NSTextView()
    private let scroll = NSScrollView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let title = NSTextField(labelWithString: "溯溯")
    private let balloon = DesktopChatBalloon()
    private var send: NSButton!
    private var stop: NSButton!
    private var settings: NSButton!
    private var expand: NSButton!
    private var close: NSButton!
    private var anchor = NSRect.zero
    private let width: CGFloat = 352

    func show(at anchor: NSRect) {
        if panel == nil { build() }
        reposition(at: anchor)
        panel?.orderFrontRegardless()
        panel?.makeKey()
        panel?.makeFirstResponder(input)
        panel?.armIdleDismissal(postpone: postponeDismissal)
    }

    func hide() {
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
    }

    func reposition(at anchor: NSRect) {
        self.anchor = anchor
        guard let panel,
              let area = (NSScreen.screens.first { $0.visibleFrame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
                ?? NSScreen.screens.first { $0.visibleFrame.intersects(anchor) }
                ?? NSScreen.main)?.visibleFrame.insetBy(dx: 5, dy: 5) else { return }

        let size = panel.frame.size
        let x = min(max(anchor.midX - size.width / 2, area.minX), area.maxX - size.width)
        let y = min(max(anchor.midY - size.height / 2, area.minY), area.maxY - size.height)
        let positions: [(NSPoint, DesktopChatBalloon.Edge)] = [
            (NSPoint(x: x, y: anchor.maxY + 3), .bottom),
            (NSPoint(x: x, y: anchor.minY - size.height - 3), .top),
            (NSPoint(x: anchor.maxX + 3, y: y), .left),
            (NSPoint(x: anchor.minX - size.width - 3, y: y), .right)
        ]
        let placement = positions.first { area.contains(NSRect(origin: $0.0, size: size)) }
        let origin = placement?.0 ?? NSPoint(x: x, y: min(max(anchor.maxY + 3, area.minY), area.maxY - size.height))
        balloon.point(to: placement?.1, at: NSPoint(x: anchor.midX - origin.x, y: anchor.midY - origin.y))
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    func update(reply text: String, replyLabel: String, mode: String, status notice: String, busy: Bool, isError: Bool) {
        guard let panel else { return }
        let caption = replyLabel.isEmpty ? mode : replyLabel
        title.stringValue = caption.isEmpty ? "溯溯" : "溯溯  ·  \(caption)"
        status.stringValue = notice
        status.textColor = isError ? .systemRed : ChatPalette.muted
        status.toolTip = notice.isEmpty ? nil : notice
        send.isHidden = busy
        send.isEnabled = !busy
        stop.isHidden = !busy
        settings.isEnabled = !busy

        let oldOrigin = scroll.contentView.bounds.origin
        let follow = text.hasPrefix(reply.string) && busy &&
            scroll.documentVisibleRect.maxY >= reply.bounds.maxY - 24
        let changed = reply.string != text
        if changed { reply.string = text }

        let hasReply = !text.isEmpty
        let noticeHeight: CGFloat = notice.isEmpty ? 0 : (isError ? 32 : 16)
        let layout = reply.layoutManager!
        let container = reply.textContainer!
        layout.ensureLayout(for: container)
        let replyHeight = hasReply ? min(106, max(32, ceil(layout.usedRect(for: container).height) + 10)) : 0
        let replyGap: CGFloat = hasReply && noticeHeight > 0 ? 8 : 0
        let height = 82 + replyHeight + noticeHeight + replyGap
        let size = NSSize(width: width, height: height)
        if panel.frame.size != size { panel.setContentSize(size) }

        title.frame.origin.y = height - 33
        settings.frame.origin.y = height - 34
        expand.frame.origin.y = height - 34
        close.frame.origin.y = height - 34
        status.isHidden = noticeHeight == 0
        status.frame = NSRect(x: 20, y: 49, width: width - 40, height: noticeHeight)
        scroll.isHidden = !hasReply
        scroll.frame = NSRect(x: 17, y: 45 + noticeHeight + replyGap, width: width - 34, height: replyHeight)
        if hasReply {
            reply.sizeToFit()
            if changed {
                let y = follow ? max(0, reply.bounds.maxY - scroll.contentView.bounds.height) : (busy ? oldOrigin.y : 0)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        reposition(at: anchor)
    }

    private func build() {
        let rect = NSRect(x: 0, y: 0, width: width, height: 82)
        let panel = DesktopBubble(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.dismiss = { [weak self] in self?.hide() }
        balloon.frame = rect
        panel.contentView = balloon

        title.frame = NSRect(x: 19, y: 49, width: width - 172, height: 19)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = ChatPalette.muted
        balloon.addSubview(title)
        settings = button("", symbol: "gearshape", label: "模型设置", x: width - 141, action: #selector(configure))
        expand = button("完整聊天", symbol: nil, label: "打开完整聊天", x: width - 111, action: #selector(expandChat))
        expand.frame.size.width = 70
        close = button("", symbol: "xmark", label: "收起聊天气泡", x: width - 37, action: #selector(closeChat))

        scroll.frame = NSRect(x: 17, y: 45, width: width - 34, height: 52)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        reply.frame = NSRect(origin: .zero, size: scroll.contentSize)
        reply.isEditable = false
        reply.isSelectable = true
        reply.drawsBackground = false
        reply.font = .systemFont(ofSize: 15)
        reply.textColor = ChatPalette.ink
        reply.textContainerInset = NSSize(width: 2, height: 4)
        reply.isVerticallyResizable = true
        reply.isHorizontallyResizable = false
        reply.autoresizingMask = [.width]
        reply.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        reply.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        reply.textContainer?.widthTracksTextView = true
        reply.setAccessibilityLabel("溯溯的回复")
        scroll.documentView = reply
        balloon.addSubview(scroll)

        status.font = .systemFont(ofSize: 11)
        balloon.addSubview(status)
        input.frame = NSRect(x: 17, y: 15, width: width - 98, height: 26)
        input.bezelStyle = .roundedBezel
        input.font = .systemFont(ofSize: 14)
        input.placeholderString = "和溯溯说句话…"
        input.setAccessibilityLabel("给溯溯的消息")
        input.target = self
        input.action = #selector(sendDraft)
        balloon.addSubview(input)
        send = button("发送", symbol: nil, label: "发送消息", x: width - 75, action: #selector(sendDraft))
        stop = button("停止", symbol: nil, label: "停止回复", x: width - 75, action: #selector(stopReply))
        send.frame = NSRect(x: width - 75, y: 14, width: 57, height: 28)
        stop.frame = send.frame
        stop.isHidden = true
        panel.initialFirstResponder = input
        self.panel = panel
    }

    private func button(_ text: String, symbol: String?, label: String, x: CGFloat, action: Selector) -> NSButton {
        let button = NSButton(title: text, target: self, action: action)
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imageScaling = .scaleProportionallyDown
        }
        button.frame = NSRect(x: x, y: 48, width: 24, height: 24)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = label
        button.setAccessibilityLabel(label)
        balloon.addSubview(button)
        return button
    }

    @objc func sendDraft() {
        if onSend?(draft) == true { draft = "" }
    }

    @objc private func stopReply() { onStop?() }
    @objc private func configure() { onConfigure?() }
    @objc private func expandChat() { onExpand?() }
    @objc private func closeChat() { hide() }
}

private final class DesktopChatBalloon: NSView {
    enum Edge { case bottom, top, left, right }
    private var edge: Edge?
    private var pointer = NSPoint.zero

    func point(to edge: Edge?, at point: NSPoint) {
        guard self.edge != edge || pointer != point else { return }
        self.edge = edge
        pointer = point
        needsDisplay = true
        window?.invalidateShadow()
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = bounds.insetBy(dx: 8, dy: 8)
        ChatPalette.surface.setFill()
        NSBezierPath(roundedRect: body, xRadius: 15, yRadius: 15).fill()

        guard let edge else { return }
        let x = min(max(pointer.x, body.minX + 22), body.maxX - 22)
        let y = min(max(pointer.y, body.minY + 22), body.maxY - 22)
        let points: [NSPoint]
        switch edge {
        case .bottom:
            points = [NSPoint(x: x - 8, y: body.minY + 1), NSPoint(x: x, y: bounds.minY + 1),
                      NSPoint(x: x + 8, y: body.minY + 1)]
        case .top:
            points = [NSPoint(x: x - 8, y: body.maxY - 1), NSPoint(x: x, y: bounds.maxY - 1),
                      NSPoint(x: x + 8, y: body.maxY - 1)]
        case .left:
            points = [NSPoint(x: body.minX + 1, y: y - 8), NSPoint(x: bounds.minX + 1, y: y),
                      NSPoint(x: body.minX + 1, y: y + 8)]
        case .right:
            points = [NSPoint(x: body.maxX - 1, y: y - 8), NSPoint(x: bounds.maxX - 1, y: y),
                      NSPoint(x: body.maxX - 1, y: y + 8)]
        }
        let tip = NSBezierPath()
        tip.move(to: points[0])
        tip.line(to: points[1])
        tip.line(to: points[2])
        tip.close()
        tip.fill()
    }
}
