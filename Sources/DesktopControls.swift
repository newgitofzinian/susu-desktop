import AppKit

enum DesktopPreferences {
    static func migrate(_ defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: "freeRoam") == nil, defaults.object(forKey: "autoWalk") != nil {
            defaults.set(defaults.bool(forKey: "autoWalk"), forKey: "freeRoam")
        }
        defaults.removeObject(forKey: "autoWalk")
        defaults.removeObject(forKey: "houseShown")
        return defaults.object(forKey: "freeRoam") == nil || defaults.bool(forKey: "freeRoam")
    }
}

enum TaskTool {
    static let executable: URL? = {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "susu"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }()
    static let unavailable = "未找到随溯溯安装的任务工具。请用完整安装包覆盖安装后重试。"
    static var command: String? {
        executable.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "' watch -- /usr/bin/true" }
    }
}

struct SpeechBubbleStyle {
    enum Theme: Int, CaseIterable {
        case cream, jade, slate, custom

        var title: String {
            switch self {
            case .cream: return "暖白"
            case .jade: return "浅松绿"
            case .slate: return "深蓝"
            case .custom: return "自选颜色…"
            }
        }
    }

    static let headroom: CGFloat = 68
    static let textSizes = [12, 15, 18]
    static let greetings = ["我在呢。", "见到你啦！", "陪你慢慢来。", "今天也一起待会儿。"]
    var theme: Theme
    var sizeIndex: Int
    var customColor: NSColor?

    init(defaults: UserDefaults = .standard) {
        theme = Theme(rawValue: defaults.integer(forKey: "speechBubbleTheme")) ?? .cream
        let savedSize = defaults.object(forKey: "speechBubbleSize") as? Int ?? 1
        sizeIndex = min(Self.textSizes.count - 1, max(0, savedSize))
        if let rgb = defaults.array(forKey: "speechBubbleColor") as? [Double],
           rgb.count == 3, rgb.allSatisfy({ (0...1).contains($0) }) {
            customColor = NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
    }

    var background: NSColor {
        switch theme {
        case .cream: return NSColor(srgbRed: 1, green: 0.97, blue: 0.89, alpha: 1)
        case .jade: return NSColor(srgbRed: 0.87, green: 0.96, blue: 0.91, alpha: 1)
        case .slate: return NSColor(srgbRed: 0.17, green: 0.23, blue: 0.35, alpha: 1)
        case .custom: return customColor ?? NSColor(srgbRed: 1, green: 0.97, blue: 0.89, alpha: 1)
        }
    }

    var foreground: NSColor {
        let c = background.usingColorSpace(.sRGB)!
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let lightness = 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        return lightness >= 0.179 ? .black : .white
    }

    func draw(_ text: String, in region: NSRect) {
        guard region.width > 24, region.height > 16 else { return }
        let font = NSFont.systemFont(ofSize: CGFloat(Self.textSizes[sizeIndex]), weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let maxTextWidth = region.width - 22
        let maxTextHeight = region.height - 12
        let measured = (text as NSString).boundingRect(with: NSSize(width: maxTextWidth, height: maxTextHeight), options: options, attributes: attrs)
        let textWidth = min(maxTextWidth, max(8, ceil(measured.width) + 1))
        let textHeight = min(maxTextHeight, ceil(measured.height))
        let box = NSRect(x: region.midX - (textWidth + 22) / 2, y: region.minY,
                         width: textWidth + 22, height: textHeight + 12)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        background.setFill(); path.fill()
        // Two outlines keep the bubble legible on both light and dark wallpapers.
        NSColor.black.withAlphaComponent(0.68).setStroke()
        path.lineWidth = 2; path.stroke()
        let inner = NSBezierPath(roundedRect: box.insetBy(dx: 2.5, dy: 2.5), xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(0.74).setStroke(); inner.lineWidth = 1; inner.stroke()
        (text as NSString).draw(with: box.insetBy(dx: 11, dy: 6), options: options, attributes: attrs)
    }
}

/// A persistent copy of the regular menu, using the same commands and selected states.
final class PinnedControls: NSObject, NSWindowDelegate {
    private let makeMenu: () -> NSMenu
    private var panel: DesktopBubble?
    private var path: [String] = []
    private var displayed: [NSMenuItem] = []
    private var rowButtons: [NSButton] = []
    private var renderedPath: [String] = []
    private let width: CGFloat = 280
    var onClose: (() -> Void)?
    var isVisible: Bool { panel?.isVisible == true }

    init(makeMenu: @escaping () -> NSMenu) { self.makeMenu = makeMenu }

    func show(at anchor: NSRect) {
        if let panel { panel.orderFrontRegardless(); return }
        path.removeAll()
        let panel = DesktopBubble(contentRect: NSRect(x: 0, y: 0, width: width, height: 406),
                                  styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "溯溯的操作菜单"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        panel.dismiss = { [weak self] in self?.close() }
        self.panel = panel
        refresh()
        if let area = (NSScreen.screens.first { $0.visibleFrame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame {
            let right = anchor.maxX + 10
            let x = right + panel.frame.width <= area.maxX ? right : anchor.minX - panel.frame.width - 10
            panel.setFrameOrigin(NSPoint(x: min(max(x, area.minX + 4), max(area.minX + 4, area.maxX - panel.frame.width - 4)),
                                         y: min(max(anchor.midY - panel.frame.height / 2, area.minY + 4), max(area.minY + 4, area.maxY - panel.frame.height - 4))))
        }
        panel.orderFrontRegardless()
    }

    func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        displayed.removeAll()
        rowButtons.removeAll()
        onClose?()
    }

    func refresh() {
        guard let panel else { return }
        var menu = makeMenu()
        var validPath: [String] = []
        for title in path {
            guard let submenu = menu.item(withTitle: title)?.submenu else { break }
            validPath.append(title)
            menu = submenu
        }
        path = validPath
        let updated = menu.items.filter { !$0.isHidden && ($0.submenu != nil || $0.action != nil) }
        if panel.contentView != nil, rowsMatch(updated) {
            displayed = updated
            for (button, entry) in zip(rowButtons, displayed) { update(button, for: entry) }
            return
        }
        displayed = updated
        renderedPath = path
        rowButtons.removeAll(keepingCapacity: true)
        let size = panel.contentRect(forFrameRect: panel.frame).size
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let navHeight: CGFloat = path.isEmpty ? 0 : 38
        if let section = path.last {
            let back = NSButton(title: "‹ 返回", target: self, action: #selector(goBack))
            back.frame = NSRect(x: 9, y: size.height - 33, width: 69, height: 26)
            back.bezelStyle = .rounded; root.addSubview(back)
            let title = NSTextField(labelWithString: section)
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            title.frame = NSRect(x: 88, y: size.height - 29, width: size.width - 100, height: 20)
            title.lineBreakMode = .byTruncatingTail; root.addSubview(title)
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height - navHeight))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let rows = MenuRows(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: CGFloat(displayed.count) * 34 + 12))
        for (index, entry) in displayed.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(selectRow(_:)))
            button.frame = NSRect(x: 10, y: 6 + CGFloat(index) * 34, width: rows.bounds.width - 20, height: 32)
            button.alignment = .left
            button.bezelStyle = .rounded
            button.lineBreakMode = .byTruncatingTail
            button.tag = index
            update(button, for: entry)
            rowButtons.append(button)
            rows.addSubview(button)
        }
        scroll.documentView = rows
        root.addSubview(scroll)
        panel.contentView = root
    }

    private func rowsMatch(_ items: [NSMenuItem]) -> Bool {
        renderedPath == path && rowButtons.count == items.count && !rowButtons.isEmpty
            && zip(displayed, items).allSatisfy { ($0.0.title == $0.1.title && $0.0.tag == $0.1.tag && $0.0.action == $0.1.action) }
    }

    private func update(_ button: NSButton, for entry: NSMenuItem) {
        let title = (entry.state == .on ? "✓  " : "") + entry.title + (entry.submenu == nil ? "" : "  ›")
        if button.title != title { button.title = title }
        if button.isEnabled != entry.isEnabled { button.isEnabled = entry.isEnabled }
        button.toolTip = entry.title
    }

    @objc private func goBack() { _ = path.popLast(); refresh() }

    @objc private func selectRow(_ sender: NSButton) {
        guard displayed.indices.contains(sender.tag) else { return }
        let entry = displayed[sender.tag]
        guard entry.isEnabled else { return }
        if entry.submenu != nil {
            path.append(entry.title)
        } else if let action = entry.action {
            NSApp.sendAction(action, to: entry.target, from: entry)
        }
        refresh()
    }
}

private final class MenuRows: NSView { override var isFlipped: Bool { true } }
