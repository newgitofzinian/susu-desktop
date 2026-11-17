import AppKit

enum PetAction: String, CaseIterable {
    case stretch, play
    var frameTime: TimeInterval { self == .stretch ? 0.48 : 0.24 }
    var duration: TimeInterval { frameTime * (self == .stretch ? 6 : 12) }
}

// Native macOS desktop companion. No web server, account, or network access.
final class SpriteFrames {
    let idle: [NSImage]
    let walk: [NSImage]
    let run: [NSImage]
    let stretch: [NSImage]
    let play: [NSImage]
    let idlePixels: [NSBitmapImageRep]
    let walkPixels: [NSBitmapImageRep]
    let runPixels: [NSBitmapImageRep]
    let stretchPixels: [NSBitmapImageRep]
    let playPixels: [NSBitmapImageRep]
    let safetyCore: NSRect

    init(resources: URL) throws {
        func load(_ state: String, count: Int) throws -> ([NSImage], [NSBitmapImageRep]) {
            let folder = resources.appendingPathComponent("frames/\(state)")
            let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard urls.count == count else { throw NSError(domain: "Susu", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(state) 素材不完整（应有 \(count) 帧，实际 \(urls.count) 帧）。"]) }
            var images: [NSImage] = [], pixels: [NSBitmapImageRep] = []
            for url in urls {
                let data = try Data(contentsOf: url)
                guard let image = NSImage(data: data), let bitmap = NSBitmapImageRep(data: data), bitmap.hasAlpha else {
                    throw NSError(domain: "Susu", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取透明素材：\(url.lastPathComponent)"])
                }
                images.append(image); pixels.append(bitmap)
            }
            return (images, pixels)
        }
        (idle, idlePixels) = try load("idle", count: 6)
        (walk, walkPixels) = try load("walking-right", count: 8)
        (run, runPixels) = try load("running-right", count: 8)
        (stretch, stretchPixels) = try load("stretch", count: 6)
        (play, playPixels) = try load("play", count: 6)
        let data = try Data(contentsOf: resources.appendingPathComponent("frames/visibility.json"))
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Double],
              let x = values["x"], let y = values["y"], let w = values["width"], let h = values["height"], w > 0, h > 0 else {
            throw NSError(domain: "Susu", code: 4, userInfo: [NSLocalizedDescriptionKey: "缺少屏幕边缘可见区域信息。"])
        }
        safetyCore = NSRect(x:x,y:y,width:w,height:h)
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// Independent reminder card: readable even when the pet is scaled down in a grid cell.
final class WaterReminderView: NSView {
    let done = NSButton(title: "喝过了 ✓", target: nil, action: nil)
    let later = NSButton(title: "5 分钟后提醒", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed:0.94,green:0.98,blue:0.98,alpha:1).cgColor
        layer?.cornerRadius = 22
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.7).cgColor
        func label(_ text: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
            let field = NSTextField(wrappingLabelWithString:text)
            field.font = .systemFont(ofSize:size,weight:weight); field.textColor = color
            field.frame = rect; addSubview(field)
        }
        let ink = NSColor(srgbRed:0.08,green:0.23,blue:0.27,alpha:1)
        label("溯溯的工作小提醒", NSRect(x:30,y:222,width:380,height:20),size:12,weight:.medium,color:ink.withAlphaComponent(0.7))
        let icon = NSImageView(frame:NSRect(x:30,y:158,width:48,height:52))
        icon.image = NSImage(systemSymbolName:"drop.fill",accessibilityDescription:"喝水提醒")
        icon.contentTintColor = .systemTeal; icon.imageScaling = .scaleProportionallyUpOrDown; addSubview(icon)
        label("该喝水啦",NSRect(x:94,y:166,width:300,height:44),size:30,weight:.bold,color:ink)
        label("先喝几口水，再陪你继续忙。\n也让眼睛和肩膀休息一下吧。",NSRect(x:32,y:87,width:376,height:60),size:16,weight:.regular,color:ink)
        for (button,x) in [(later,CGFloat(30)),(done,CGFloat(228))] {
            button.frame = NSRect(x:x,y:28,width:182,height:40)
            button.bezelStyle = .rounded; button.font = .systemFont(ofSize:15,weight:.semibold)
            addSubview(button)
        }
        done.bezelColor = .systemTeal
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class PetView: NSView {
    weak var owner: PetController?
    var frames: SpriteFrames!
    var taskBadge = ""
    var frameIndex = 0
    var walking = false
    var running = false
    var action: PetAction?
    var facesLeft = false
    var greetingDuration: TimeInterval = 2.8
    var greetingAge: TimeInterval = 100
    var speech = ""
    var dragging = false
    private var mouseStart = NSPoint.zero
    private var windowStart = NSPoint.zero
    private var moved = false
    private var previousImage: NSImage?
    private var previousMirrored = false
    var transitionAge: TimeInterval = 10

    var currentImage: NSImage {
        let sequence = action.map { $0 == .stretch ? frames.stretch : frames.play } ?? (walking ? (running ? frames.run : frames.walk) : frames.idle)
        return sequence[frameIndex % sequence.count]
    }
    var currentPixels: NSBitmapImageRep {
        let sequence = action.map { $0 == .stretch ? frames.stretchPixels : frames.playPixels } ?? (walking ? (running ? frames.runPixels : frames.walkPixels) : frames.idlePixels)
        return sequence[frameIndex % sequence.count]
    }
    func setMovement(walking nextWalking: Bool, running nextRunning: Bool, left: Bool, action nextAction: PetAction? = nil) {
        if action != nextAction || walking != nextWalking || running != nextRunning || (nextWalking && left != facesLeft) {
            previousImage = currentImage; previousMirrored = walking && facesLeft; transitionAge = 0
            walking = nextWalking; running = nextRunning; facesLeft = left; action = nextAction; frameIndex = 0
        }
    }

    var actorRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: bounds.width * 208 / 192) }
    var bounce: CGFloat {
        0 // Keep the body planted, including while a greeting bubble is visible.
    }

    override func draw(_ dirtyRect: NSRect) {
        guard frames != nil else { return }
        let mix = CGFloat(min(1, transitionAge / 0.16))
        func drawSprite(_ image: NSImage, mirrored: Bool, opacity: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        if mirrored {
            let flip = AffineTransform(translationByX: bounds.width, byY: 0)
            var transform = flip; transform.scale(x: -1, y: 1); (transform as NSAffineTransform).concat()
        }
        image.draw(in: actorRect.offsetBy(dx: 0, dy: bounce), from: .zero, operation: .sourceOver, fraction: opacity,
                   respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        }
        if let previousImage, mix < 1 { drawSprite(previousImage, mirrored: previousMirrored, opacity: 1-mix) }
        drawSprite(currentImage, mirrored: facesLeft && walking, opacity: mix)
        if !taskBadge.isEmpty {
            (taskBadge as NSString).draw(at:NSPoint(x:6,y:20),withAttributes:[.font:NSFont.systemFont(ofSize:28)])
        }
        if greetingAge < greetingDuration && !speech.isEmpty {
            let font = NSFont.systemFont(ofSize: max(11, min(14, bounds.width / 15)), weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1)]
            let textWidth = max(1, bounds.width - 32)
            let textRect = (speech as NSString).boundingRect(with: NSSize(width: textWidth, height: 34), options: [.usesLineFragmentOrigin], attributes: attrs)
            let box = NSRect(x: 4, y: actorRect.maxY + 4, width: max(1, bounds.width - 8), height: min(44, ceil(textRect.height) + 12))
            NSColor(srgbRed: 0.12, green: 0.16, blue: 0.24, alpha: 0.96).setFill()
            NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            (speech as NSString).draw(with: NSRect(x: box.minX + 12, y: box.minY + 6, width: textWidth, height: box.height - 12), options: [.usesLineFragmentOrigin], attributes: attrs)

        }
    }

    // Transparent padding passes clicks through to the user's other windows.
    func containsPet(_ point: NSPoint) -> Bool {
        let rect = actorRect.offsetBy(dx: 0, dy: bounce)
        guard rect.contains(point) else { return false }
        let bitmap = currentPixels
        var x = Int((point.x - rect.minX) / rect.width * CGFloat(bitmap.pixelsWide))
        if walking && facesLeft { x = bitmap.pixelsWide - 1 - x }
        let y = bitmap.pixelsHigh - 1 - Int((point.y - rect.minY) / rect.height * CGFloat(bitmap.pixelsHigh))
        guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { return false }
        return (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.12
    }

    override func mouseDown(with event: NSEvent) {
        guard let owner, let window else { return }
        owner.stopWalking(); dragging = true; moved = false
        mouseStart = NSEvent.mouseLocation; windowStart = window.frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let owner else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - mouseStart.x, dy = point.y - mouseStart.y
        if hypot(dx, dy) > 3 { moved = true }
        owner.move(to: NSPoint(x: windowStart.x + dx, y: windowStart.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        if !moved {
            if taskBadge.isEmpty { owner?.greet() } else { owner?.showTaskRoom() }
        }
        owner?.savePosition()
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { .copy }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard let text=sender.draggingPasteboard.string(forType:foodPasteboard),let index=Int(text),(0..<3).contains(index),containsPet(convert(sender.draggingLocation,from:nil)) else { return false }
        owner?.receiveFood(index);return true
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = owner?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class PetController: NSObject, NSApplicationDelegate {
    var panel: PetPanel!
    var pet: PetView!
    var status: NSStatusItem!
    var timer: Timer?
    var frames: SpriteFrames!
    private var startTime = ProcessInfo.processInfo.systemUptime
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var greetingStart: TimeInterval = -100
    private var target: NSPoint?
    private var logicalPosition: NSPoint?
    private var store: CompanionStore!
    private var room: CompanionRoom!
    private var waterPreview = false
    private var lastTaskPoll: TimeInterval = 0
    private var taskRunning = false
    private var taskState = ""
    private var inRoom = false
    private var runningMode = false
    private var speed: CGFloat = 0
    private var nextWalk: TimeInterval = 0
    private var walkClock: TimeInterval = 0
    private var action: PetAction?
    private var actionClock: TimeInterval = 0
    private var autoWalk = UserDefaults.standard.object(forKey: "freeRoam") == nil ? true : UserDefaults.standard.bool(forKey: "freeRoam")
    private var quiet = UserDefaults.standard.bool(forKey: "quiet")
    private var suspended = false
    private var workMode = UserDefaults.standard.bool(forKey: "workMode")
    private var territory = UserDefaults.standard.object(forKey: "workTerritory") == nil ? 15 : min(15, max(0, UserDefaults.standard.integer(forKey: "workTerritory")))
    private var workScreenID = UserDefaults.standard.integer(forKey: "workScreenID")
    private var water = WaterReminder()
    private var waterPanel: PetPanel?
    private var reminderVisible: Bool { waterPanel?.isVisible == true }
    private var gridPanels: [NSPanel] = []
    private var gridDismiss: DispatchWorkItem?
    private var scale: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "petWidth")
        return saved > 0 ? min(320, max(144, saved)) : 208
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let resources = Bundle.main.resourceURL else { throw NSError(domain: "Susu", code: 3) }
            frames = try SpriteFrames(resources: resources)
            let testDirectory = CommandLine.arguments.contains("--smoke-test") ? FileManager.default.temporaryDirectory.appendingPathComponent("susu-smoke-"+UUID().uuidString) : nil
            store = try CompanionStore(directory:testDirectory)
        } catch {
            let alert = NSAlert(); alert.messageText = "溯溯暂时无法启动"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        let minutes = UserDefaults.standard.integer(forKey: "waterMinutes")
        water.interval = Double([15,30,45,60].contains(minutes) ? minutes : 30) * 60
        let size = panelSize(displayWidth)
        panel = PetPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "溯溯"; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        pet = PetView(frame: NSRect(origin: .zero, size: size)); pet.owner = self; pet.frames = frames
        pet.registerForDraggedTypes([foodPasteboard])
        room = CompanionRoom(store:store,frames:frames)
        room.animate = { [weak self] in self?.startAction($0) }
        room.onInteraction = { [weak self] active in self?.inRoom=active;self?.stopWalking() }
        pet.setAccessibilityLabel("溯溯桌面宠物。点击回应，拖动移动，右键打开菜单。")
        pet.autoresizingMask = [.width, .height]; panel.contentView = pet
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0,y: 0,width: 1200,height: 800)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "positionX") != nil {
            move(to: NSPoint(x: defaults.double(forKey: "positionX"), y: defaults.double(forKey: "positionY")))
        } else {
            move(to: NSPoint(x: visible.maxX - size.width - 60, y: visible.minY + 10))
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "溯溯")
        status.button?.toolTip = "溯溯 · 桌面小伙伴"; status.menu = makeMenu()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking), name: NSWorkspace.screensDidWakeNotification, object: nil)
        greet(text: "你好，我是溯溯。")
        nextWalk = ProcessInfo.processInfo.systemUptime + 8
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        if CommandLine.arguments.contains("--preview-water") && !CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { [weak self] in self?.previewWater() }
        }
        if CommandLine.arguments.contains("--smoke-test") {
            // Exercise the actual drawing and alpha hit testing without staying resident.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.smokeTest() }
        }
    }

    private func screenID(_ screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
    private var workScreen: NSScreen? {
        NSScreen.screens.first { screenID($0) == workScreenID } ?? NSScreen.main ?? NSScreen.screens.first
    }
    private var workArea: NSRect? {
        guard workMode, let screen = workScreen else { return nil }
        return WorkTerritory.cell(in: screen.visibleFrame, index: territory)
    }
    private var displayWidth: CGFloat {
        workArea.map { WorkTerritory.width(preferred: scale, area: $0) } ?? scale
    }
    private func applyWorkArea(center: Bool = false) {
        stopWalking()
        panel.setContentSize(panelSize(displayWidth))
        let point: NSPoint
        if center, let area = workArea {
            point = NSPoint(x: area.midX-panel.frame.width/2, y: area.midY-panel.frame.height/2)
        } else { point = panel.frame.origin }
        move(to: point); savePosition(); pet.needsDisplay = true
    }

    private func panelSize(_ width: CGFloat) -> NSSize { NSSize(width: width, height: width * 208 / 192 + 52) }

    func move(to point: NSPoint) {
        guard panel != nil else { return }
        if let area = workArea {
            let constrained = WorkTerritory.constrain(point, window:panel.frame.size, area:area)
            logicalPosition = constrained
            panel.setFrameOrigin(constrained)
            return
        }
        let sprite = NSSize(width:panel.frame.width,height:panel.frame.width*208/192)
        let allowed = DesktopBounds.constrain(point, sprite:sprite, core:frames.safetyCore,
                                               screens:NSScreen.screens.map(\.visibleFrame))
        logicalPosition = allowed
        panel.setFrameOrigin(allowed)
    }
    func savePosition() {
        guard !CommandLine.arguments.contains("--smoke-test") else { return }
        UserDefaults.standard.set(panel.frame.minX, forKey: "positionX")
        UserDefaults.standard.set(panel.frame.minY, forKey: "positionY")
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now-lastTick)); lastTick = now
        if now-lastTaskPoll>1 { lastTaskPoll=now;pollTasks() }
        if !waterPreview && water.poll(at: now, active: workMode && !quiet && !suspended && panel.isVisible && !reminderVisible) {
            remindWater()
        }
        guard !suspended, panel.isVisible else { return }
        if let current = action {
            actionClock += dt
            if actionClock >= current.duration { stopWalking() }
        }
        if let destination = target, !pet.dragging {
            let logical = logicalPosition ?? panel.frame.origin
            let dx = destination.x-logical.x, dy = destination.y-logical.y
            let distance = hypot(dx,dy)
            if distance < 1.2 { stopWalking(); savePosition() }
            else {
                let nominal = (runningMode ? CGFloat(95) : CGFloat(24)) * panel.frame.width / 208
                let desired = nominal * min(1,max(0.20,distance/30))
                speed += (desired-speed)*min(1,CGFloat(dt)*5)
                let step = min(distance, speed*CGFloat(dt))
                let before = logical
                move(to:NSPoint(x:before.x+dx/distance*step,y:before.y+dy/distance*step))
                if let after=logicalPosition,step>0.05 && hypot(after.x-before.x,after.y-before.y)<0.001 { stopWalking() }
                walkClock += dt * Double(max(0.20,speed/nominal))
            }
        } else if autoWalk && !quiet && !reminderVisible && !pet.dragging && !inRoom && !taskRunning && action == nil && now > nextWalk {
            switch Int.random(in:0..<6) {
            case 0: startAction(.stretch)
            case 1: startAction(.play)
            default: startJourney(running: Int.random(in:0..<5) == 0)
            }
        }
        let walking = target != nil
        let left = target.map { $0.x < panel.frame.minX } ?? pet.facesLeft
        pet.setMovement(walking:walking,running:walking && runningMode,left:left,action:action)
        pet.transitionAge += dt
        let index: Int
        if quiet { index = 0 }
        else if let action { index = min(Int(actionClock/action.frameTime),action == .stretch ? 5 : 11) % 6 }
        else if walking { index = Int(walkClock/(runningMode ? 0.080 : 0.20)) % 8 }
        else {
            index = Int((now-startTime)/0.38) % frames.idle.count
        }
        let wasGreeting = pet.greetingAge < pet.greetingDuration
        pet.greetingAge = quiet ? 100 : now-greetingStart
        if pet.frameIndex != index || pet.transitionAge < 0.20 || wasGreeting || pet.greetingAge < pet.greetingDuration {
            pet.frameIndex = index; pet.walking = walking; pet.needsDisplay = true
        }
        let local = pet.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        panel.ignoresMouseEvents = !pet.dragging && !pet.containsPet(local)
    }

    func stopWalking() { logicalPosition = panel?.frame.origin; target = nil; action = nil; actionClock = 0; speed = 0; nextWalk = ProcessInfo.processInfo.systemUptime + Double.random(in: 8...18) }
    @objc func stretchOnce() { startAction(.stretch) }
    @objc func playOnce() { startAction(.play) }
    private func startAction(_ next: PetAction) {
        guard !quiet, !reminderVisible, !pet.dragging else { return }
        stopWalking()
        // Keep every changing pose visible; free roaming still allows partial
        // off-screen positions again after the action returns to idle.
        if workArea == nil, let screen = panel.screen ?? NSScreen.main {
            move(to:WorkTerritory.constrain(panel.frame.origin,window:panel.frame.size,area:screen.visibleFrame))
        }
        action = next; actionClock = 0
    }
    @objc func walkOnce() {
        startJourney(running:false)
    }
    @objc func runOnce() { startJourney(running:true) }
    private func startJourney(running: Bool) {
        guard !quiet, !reminderVisible, !pet.dragging, let screen = NSScreen.screens.randomElement() else { return }
        action = nil; actionClock = 0
        let area = screen.visibleFrame
        let width = panel.frame.width
        // Work mode constrains every destination as well as each movement step.
        let raw = NSPoint(x:CGFloat.random(in:(area.minX-width*0.7)...(area.maxX-width*0.3)),
                          y:CGFloat.random(in:(area.minY-width*0.6)...(area.maxY-width*0.5)))
        let sprite = NSSize(width:width,height:width*208/192)
        var destination: NSPoint
        if let cell = workArea {
            let lower = WorkTerritory.constrain(NSPoint(x:cell.minX,y:cell.minY), window:panel.frame.size, area:cell)
            let upper = WorkTerritory.constrain(NSPoint(x:cell.maxX,y:cell.maxY), window:panel.frame.size, area:cell)
            destination = NSPoint(x:CGFloat.random(in:lower.x...upper.x),y:CGFloat.random(in:lower.y...upper.y))
        } else {
            destination = DesktopBounds.constrain(raw,sprite:sprite,core:frames.safetyCore,screens:NSScreen.screens.map(\.visibleFrame))
        }
        if !running {
            if workArea != nil { destination.y = panel.frame.minY }
            else {
                destination = WalkingRoute.destination(desiredX:raw.x,from:panel.frame.origin,sprite:sprite,core:frames.safetyCore,screens:NSScreen.screens.map(\.visibleFrame))
            }
        }
        let distance = hypot(destination.x-panel.frame.minX,destination.y-panel.frame.minY)
        // Slow walks remain leisurely instead of taking a minute to cross a large monitor.
        let limit: CGFloat = running ? 680 : 260
        if distance > limit {
            destination = NSPoint(x:panel.frame.minX+(destination.x-panel.frame.minX)/distance*limit,
                                  y:panel.frame.minY+(destination.y-panel.frame.minY)/distance*limit)
        }
        guard distance > 4 else { stopWalking(); return }
        target = destination; runningMode = running; speed = 0; walkClock = 0
    }

    func greet(text: String? = nil, duration: TimeInterval = 2.8) {
        guard !quiet else { return }
        pet.greetingDuration = duration
        greetingStart = ProcessInfo.processInfo.systemUptime
        pet.speech = text ?? ["我在呢。", "找到你啦！", "陪你慢慢来。", "线索收到！"].randomElement()!
        pet.needsDisplay = true
    }
    @objc func remindWater() {
        guard workMode, !quiet, !suspended, panel.isVisible else { return }
        waterPreview = false; showWaterCard()
    }
    @objc func previewWater() { waterPreview = true; showWaterCard() }
    private func positionWaterCard() {
        guard let reminder = waterPanel, let screen = (workMode ? workScreen : panel.screen) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        reminder.setFrameOrigin(NSPoint(x:area.midX-reminder.frame.width/2,y:area.maxY-reminder.frame.height-36))
    }
    private func showWaterCard() {
        stopWalking(); dismissGrid();room?.interrupt()
        if waterPanel == nil {
            let card = PetPanel(contentRect:NSRect(x:0,y:0,width:440,height:264),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            card.title = "溯溯 · 该喝水啦"; card.isOpaque = false; card.backgroundColor = .clear
            card.hasShadow = true; card.hidesOnDeactivate = false; card.isReleasedWhenClosed = false
            card.level = .statusBar; card.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            let view = WaterReminderView(frame:NSRect(x:0,y:0,width:440,height:264))
            view.done.target = self; view.done.action = #selector(waterDone)
            view.later.target = self; view.later.action = #selector(waterLater)
            card.contentView = view; waterPanel = card
        }
        if let view=waterPanel?.contentView as? WaterReminderView {
            view.done.title = waterPreview ? "关闭预览" : "喝过了 ✓"
            view.later.isHidden = waterPreview
            (view.subviews.first as? NSTextField)?.stringValue = waterPreview ? "喝水提醒 · 预览" : "溯溯的工作小提醒"
        }
        positionWaterCard(); waterPanel?.orderFrontRegardless(); refreshMenu()
        greet(text:"喝口水，休息一下～",duration:12)
    }
    private func dismissWaterCard() { waterPanel?.orderOut(nil); waterPreview=false }
    @objc func waterDone() {
        if waterPreview { dismissWaterCard();refreshMenu();return }
        dismissWaterCard(); water.restart(at:ProcessInfo.processInfo.systemUptime)
        greet(text:"收到，继续陪你。")
        refreshMenu()
    }
    @objc func waterLater() {
        if waterPreview { dismissWaterCard();refreshMenu();return }
        dismissWaterCard(); water.snooze(at:ProcessInfo.processInfo.systemUptime,seconds:5*60)
        greet(text:"好，5 分钟后再提醒。")
        refreshMenu()
    }
    @objc func toggleWork() {
        workMode.toggle()
        dismissWaterCard()
        if workMode {
            if let screen = panel.screen ?? NSScreen.main { workScreenID = screenID(screen) }
            UserDefaults.standard.set(workScreenID, forKey: "workScreenID")
        }
        UserDefaults.standard.set(workMode, forKey: "workMode")
        water.restart(at: ProcessInfo.processInfo.systemUptime)
        applyWorkArea(center: workMode); refreshMenu()
        if workMode { showGrid() } else { dismissGrid() }
    }
    @objc func chooseTerritory(_ item: NSMenuItem) {
        territory = item.tag
        UserDefaults.standard.set(territory, forKey: "workTerritory")
        applyWorkArea(center: true); refreshMenu(); showGrid()
    }
    @objc func chooseScreen(_ item: NSMenuItem) {
        workScreenID = item.tag
        UserDefaults.standard.set(workScreenID, forKey: "workScreenID")
        applyWorkArea(center: true); refreshMenu(); showGrid()
    }
    @objc func chooseWaterInterval(_ item: NSMenuItem) {
        water.interval = Double(item.tag) * 60
        UserDefaults.standard.set(item.tag, forKey: "waterMinutes")
        water.restart(at: ProcessInfo.processInfo.systemUptime); refreshMenu()
    }
    private func dismissGrid() {
        gridDismiss?.cancel(); gridPanels.forEach { $0.orderOut(nil) }; gridPanels.removeAll()
    }
    @objc func showGrid() {
        dismissGrid()
        guard workMode, let screen = workScreen else { return }
        for index in 0..<16 {
            let area = WorkTerritory.cell(in:screen.visibleFrame,index:index).insetBy(dx:2,dy:2)
            let window = PetPanel(contentRect:area,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.ignoresMouseEvents = true; window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            let view = NSView(frame:NSRect(origin:.zero,size:area.size)); view.wantsLayer = true
            view.layer?.backgroundColor = (index == territory ? NSColor.systemTeal.withAlphaComponent(0.20) : NSColor.black.withAlphaComponent(0.035)).cgColor
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.5).cgColor
            let label = NSTextField(labelWithString:"\(index+1)\(index == territory ? " · 溯溯的地盘" : "")")
            label.textColor = .labelColor; label.frame = NSRect(x:10,y:area.height-30,width:area.width-20,height:22)
            view.addSubview(label); window.contentView = view; window.orderFrontRegardless(); gridPanels.append(window)
        }
        let task = DispatchWorkItem { [weak self] in self?.dismissGrid() }
        gridDismiss = task; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:task)
    }
    @objc func sayHello() { greet() }
    @objc func toggleAuto() { autoWalk.toggle(); UserDefaults.standard.set(autoWalk, forKey: "freeRoam"); if !autoWalk { stopWalking() }; refreshMenu() }
    @objc func toggleQuiet() {
        dismissWaterCard()
        quiet.toggle(); UserDefaults.standard.set(quiet, forKey: "quiet")
        water.restart(at:ProcessInfo.processInfo.systemUptime)
        stopWalking(); pet.frameIndex = 0; pet.greetingAge = 100; pet.needsDisplay = true; refreshMenu()
    }
    @objc func toggleVisible() {
        water.restart(at:ProcessInfo.processInfo.systemUptime); dismissGrid(); dismissWaterCard()
        if panel.isVisible { panel.orderOut(nil); stopWalking() } else { panel.orderFrontRegardless(); greet() }
        refreshMenu()
    }
    @objc func resize(_ item: NSMenuItem) {
        stopWalking()
        scale = CGFloat(item.tag)
        let origin = panel.frame.origin
        panel.setContentSize(panelSize(displayWidth)); move(to: origin)
        UserDefaults.standard.set(Double(scale), forKey: "petWidth"); pet.needsDisplay = true
        refreshMenu(); savePosition()
    }
    @objc func resetPosition() {
        stopWalking()
        if workMode {
            if let screen = NSScreen.main { workScreenID = screenID(screen); UserDefaults.standard.set(workScreenID, forKey:"workScreenID") }
            applyWorkArea(center:true)
        } else if let area = NSScreen.main?.visibleFrame { move(to: NSPoint(x: area.maxX-panel.frame.width-40, y: area.minY+10)) }
        panel.orderFrontRegardless(); savePosition(); refreshMenu()
    }
    @objc func showHelp() {
        let alert = NSAlert(); alert.messageText = "溯溯 · 桌面版 2.0"
        alert.informativeText = "点击：溯溯回应你\n拖动：在桌面自由摆放，可部分移出屏幕\n右键或菜单栏爪印：左右散步、伸个懒腰、玩耍一下、跑一圈、自由活动、大小、安静模式与退出\n\n自由活动默认开启，以左右慢走为主，偶尔伸懒腰、玩耍或跑步。始终保留一小块身体在屏幕内；选择‘回到主屏幕’可以找回。安静模式会停止摇尾巴与其他动作。\n\n工作模式：屏幕分成 4×4 共 16 格，可选择地盘与显示器；宠物会自动缩小并完整留在该格内。每 30 分钟提醒喝水，可改为 15、45、60 分钟。提醒卡片持续显示，点击‘喝过了’后重新计时，或选‘5 分钟后提醒’。菜单可立即体验。隐藏、安静与屏幕休眠时暂停提醒，恢复后重新计时。\n\n本机运行，无需联网或账号。"
        alert.addButton(withTitle: "知道啦"); alert.runModal()
    }
    @objc func screenChanged() { dismissGrid(); applyWorkArea(); positionWaterCard(); refreshMenu() }
    @objc func sleeping() {
        suspended = true; stopWalking(); dismissGrid(); dismissWaterCard(); refreshMenu()
        _ = water.poll(at:ProcessInfo.processInfo.systemUptime,active:false)
    }
    @objc func waking() {
        suspended = false; lastTick = ProcessInfo.processInfo.systemUptime
        water.restart(at:lastTick)
    }
    @objc func showRoom() { room.show() }
    @objc func showFoodRoom() { room.show(tab:1) }
    @objc func showTaskRoom() { room.show(tab:4) }
    func receiveFood(_ index:Int) { room.feed(index);greet(text:"收到点心啦！") }
    private func pollTasks() {
        let events=store.taskEvents().sorted { $0.date < $1.date }
        guard var event=events.last else { return }
        if event.status=="running", kill(event.pid,0) != 0, errno == ESRCH {
            event = TaskEvent(id:event.id,name:event.name,status:"cancelled",pid:event.pid,date:event.date,exitCode:nil)
        }
        let key=event.id+event.status
        guard key != taskState else { return }
        taskState=key;taskRunning=event.status=="running"
        if !taskRunning && store.save.handledTasks.contains(event.id) { return }
        let text:String
        switch event.status {
        case "running": text="等待中";pet.taskBadge="⌛";stopWalking()
        case "success": text="任务完成";pet.taskBadge="🍃"
        case "cancelled": text="已取消";pet.taskBadge="↩"
        default: text="任务失败";pet.taskBadge="❗"
        }
        if !taskRunning {
            do { try store.handleTask(event) } catch { taskState="" }
            greet(text:text)
        }
        room.refreshTask("\(text) · \(event.name)\n退出码 \(event.exitCode.map(String.init) ?? "—")")
        pet.needsDisplay=true
    }
    @objc func quit() { NSApp.terminate(nil) }
    private func refreshMenu() {
        status.button?.image = NSImage(systemSymbolName:reminderVisible ? "drop.fill" : "pawprint.fill",accessibilityDescription:reminderVisible ? "溯溯提醒你喝水" : "溯溯")
        status.button?.toolTip = reminderVisible ? "该喝水啦 · 点击菜单或提醒卡片处理" : "溯溯 · 桌面小伙伴"
        status.menu = makeMenu()
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self
            if let checked { entry.state = checked ? .on : .off }; menu.addItem(entry)
        }
        let name = NSMenuItem(title: "溯溯 · 陪你慢慢来", action: nil, keyEquivalent: ""); name.isEnabled = false; menu.addItem(name)
        menu.addItem(.separator())
        item("林间小屋 · 藏松果 / 手帐 / 存档", #selector(showRoom))
        item("喂点心与口味", #selector(showFoodRoom))
        item("任务报信", #selector(showTaskRoom))
        item("打个招呼", #selector(sayHello))
        item("喝水提醒（立即体验）", #selector(previewWater))
        item("左右散步", #selector(walkOnce))
        item("伸个懒腰", #selector(stretchOnce))
        item("玩耍一下", #selector(playOnce))
        item("跑一圈", #selector(runOnce))
        item("自由活动", #selector(toggleAuto), checked: autoWalk)
        item("工作模式", #selector(toggleWork), checked: workMode)
        let work = NSMenuItem(title: "工作模式设置", action:nil,keyEquivalent:"")
        let settings = NSMenu()
        let territories = NSMenuItem(title:"地盘：第 \(territory+1) 格（从左上按行编号）",action:nil,keyEquivalent:"")
        let cells = NSMenu()
        for row in 0..<4 {
            let rowItem = NSMenuItem(title:"第 \(row+1) 行",action:nil,keyEquivalent:"")
            let columns = NSMenu()
            for column in 0..<4 {
                let index = row*4+column
                let entry = NSMenuItem(title:"第 \(column+1) 列 · \(index+1) 号地盘",action:#selector(chooseTerritory(_:)),keyEquivalent:"")
                entry.target = self; entry.tag = index; entry.state = territory == index ? .on : .off
                entry.isEnabled = workMode; columns.addItem(entry)
            }
            rowItem.submenu = columns; cells.addItem(rowItem)
        }
        territories.submenu = cells; settings.addItem(territories)
        let displays = NSMenuItem(title:"工作屏幕",action:nil,keyEquivalent:"")
        let screenMenu = NSMenu()
        for screen in NSScreen.screens {
            let entry = NSMenuItem(title:screen.localizedName,action:#selector(chooseScreen(_:)),keyEquivalent:"")
            entry.target = self; entry.tag = screenID(screen); entry.state = workScreen === screen ? .on : .off
            entry.isEnabled = workMode; screenMenu.addItem(entry)
        }
        displays.submenu = screenMenu; settings.addItem(displays)
        let reminder = NSMenuItem(title:"喝水间隔",action:nil,keyEquivalent:"")
        let intervals = NSMenu()
        for minutes in [15,30,45,60] {
            let entry = NSMenuItem(title:"每 \(minutes) 分钟",action:#selector(chooseWaterInterval(_:)),keyEquivalent:"")
            entry.target = self; entry.tag = minutes; entry.state = Int(water.interval) == minutes*60 ? .on : .off
            intervals.addItem(entry)
        }
        reminder.submenu = intervals; settings.addItem(reminder)
        for (title, action) in [("显示地盘网格（3 秒）",#selector(showGrid)),("试试喝水提醒",#selector(previewWater))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target = self; entry.isEnabled = workMode
            settings.addItem(entry)
        }
        work.submenu = settings; menu.addItem(work)
        item("安静模式", #selector(toggleQuiet), checked: quiet)
        let sizes = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (label, width) in [("小",160),("中",208),("大",272)] {
            let entry = NSMenuItem(title: label, action: #selector(resize(_:)), keyEquivalent: "")
            entry.tag = width; entry.target = self; entry.state = Int(scale) == width ? .on : .off; submenu.addItem(entry)
        }
        sizes.submenu = submenu; menu.addItem(sizes)
        item(panel?.isVisible == false ? "显示溯溯" : "暂时隐藏", #selector(toggleVisible))
        item("回到主屏幕", #selector(resetPosition))
        menu.addItem(.separator())
        item("使用说明", #selector(showHelp))
        item("退出溯溯", #selector(quit))
        return menu
    }

    private func smokeTest() {
        guard let outputIndex = CommandLine.arguments.firstIndex(of: "--preview-dir"), CommandLine.arguments.count > outputIndex+1 else {
            print("Loaded \(frames.idle.count) idle, \(frames.walk.count) walk, \(frames.run.count) run frames")
            NSApp.terminate(nil); return
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[outputIndex+1])
        let savedWorkMode = workMode
        workMode = false; applyWorkArea()
        defer { workMode = savedWorkMode; applyWorkArea() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, walk, run, left, frame) in [("idle",false,false,false,0),("tail-low",false,false,false,2),("walk-right",true,false,false,2),("walk-left",true,false,true,2),("run-right",true,true,false,2),("run-left",true,true,true,2)] {
                pet.walking = walk; pet.running = run; pet.facesLeft = left; pet.frameIndex = frame; pet.greetingAge = 100; pet.transitionAge = 10
                guard let rep = pet.bitmapImageRepForCachingDisplay(in: pet.bounds) else { fatalError("Preview bitmap unavailable") }
                pet.cacheDisplay(in: pet.bounds, to: rep)
                guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
                try png.write(to: directory.appendingPathComponent("\(name).png"))
                // Find an opaque point and ensure the alpha-aware input accepts it.
                let pixel = pet.currentPixels
                var found = false
                for y in stride(from: 0, to: pixel.pixelsHigh, by: 8) {
                    for x in stride(from: 0, to: pixel.pixelsWide, by: 8) {
                        if (pixel.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.9 {
                            let xx = left && walk ? pixel.pixelsWide-1-x : x
                            let p = NSPoint(x:(CGFloat(xx)+0.5)/CGFloat(pixel.pixelsWide)*pet.actorRect.width,
                                            y:(CGFloat(pixel.pixelsHigh-y)-0.5)/CGFloat(pixel.pixelsHigh)*pet.actorRect.height)
                            precondition(pet.containsPet(p), "Opaque pet must receive mouse input")
                            found = true; break
                        }
                    }
                    if found { break }
                }
                precondition(found, "Empty sprite")
                precondition(!pet.containsPet(NSPoint(x:1,y:pet.bounds.maxY-1)), "Transparent padding must pass mouse input through")
            }
            let original = panel.frame.origin
            let screens = NSScreen.screens.map(\.visibleFrame)
            let sprite = NSSize(width:panel.frame.width,height:panel.frame.width*208/192)
            for p in [NSPoint(x:-100000,y:-100000), NSPoint(x:100000,y:-100000), NSPoint(x:-100000,y:100000), NSPoint(x:100000,y:100000)] {
                let expected = DesktopBounds.constrain(p,sprite:sprite,core:frames.safetyCore,screens:screens)
                move(to:p)
                let actual = panel.frame.origin
                guard abs(actual.x-expected.x)<=1 && abs(actual.y-expected.y)<=1 else {
                    throw NSError(domain:"SusuBoundary",code:1,userInfo:[NSLocalizedDescriptionKey:"Native window clamp: expected \(expected), actual \(actual)"])
                }
                let core = frames.safetyCore
                let body = NSRect(x:panel.frame.minX+core.minX*sprite.width,y:panel.frame.minY+core.minY*sprite.height,width:core.width*sprite.width,height:core.height*sprite.height)
                let keep = min(20,min(body.width,body.height))
                guard screens.contains(where: { let visible = $0.intersection(body); return visible.width >= keep-0.1 && visible.height >= keep-0.1 }) else {
                    throw NSError(domain:"SusuBoundary",code:2,userInfo:[NSLocalizedDescriptionKey:"Opaque body patch left the display: \(body)"])
                }
            }
            workMode = true
            for index in 0..<16 {
                territory = index; applyWorkArea(center:true)
                guard let area = workArea else { fatalError("Missing work area") }
                for point in [NSPoint(x:-100000,y:-100000),NSPoint(x:100000,y:100000)] {
                    move(to:point)
                    precondition(area.insetBy(dx:-1,dy:-1).contains(panel.frame),"Entire pet and bubble must stay inside the selected territory")
                }
                let walkY = panel.frame.minY
                startJourney(running:false)
                if let target {
                    precondition(target.y == walkY,"Work-mode walk must stay horizontal")
                    precondition(area.contains(NSRect(origin:target,size:panel.frame.size)))
                }
                startJourney(running:true)
                if let target { precondition(area.contains(NSRect(origin:target,size:panel.frame.size))) }
            }
            let savedQuiet = quiet, savedAuto = autoWalk
            quiet = false; autoWalk = false
            for mode in [false,true] {
                workMode = mode; applyWorkArea(center:mode)
                for _ in 0..<20 {
                    let y = panel.frame.minY
                    startJourney(running:false)
                    if let target { precondition(target.y == y,"Walking target must preserve height") }
                    for _ in 0..<5 { lastTick = ProcessInfo.processInfo.systemUptime-0.05; tick() }
                    precondition(abs(panel.frame.minY-y)<0.01,"Native walking window must not drift vertically")
                    stopWalking()
                }
                for next in PetAction.allCases {
                    startAction(next)
                    let origin = panel.frame.origin
                    for i in 0..<6 {
                        actionClock = Double(i)*next.frameTime
                        tick()
                        precondition(pet.action == next && pet.frameIndex == i)
                        precondition(panel.frame.origin == origin,"Actions animate in place")
                        if let rep = pet.bitmapImageRepForCachingDisplay(in:pet.bounds) {
                            pet.transitionAge = 10; pet.greetingAge = 100
                            pet.cacheDisplay(in:pet.bounds,to:rep)
                            try rep.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("\(next.rawValue)-\(mode ? "work" : "free")-\(i).png"))
                        }
                    }
                    actionClock = next.duration; tick()
                    precondition(action == nil && pet.action == nil,"One-shot action must return to idle")
                    startAction(next); stopWalking(); tick()
                    precondition(action == nil && pet.action == nil,"Dragging/quiet/reminders must interrupt action")
                }
            }
            quiet = savedQuiet; autoWalk = savedAuto
            print("PASS: native horizontal walk targets and window motion; 12 new animation poses rendered in work/free modes; one-shot completion and interruption verified.")
            previewWater()
            precondition(reminderVisible, "A manual preview must always display the reminder")
            guard let card = waterPanel?.contentView as? WaterReminderView,
                  let rep = card.bitmapImageRepForCachingDisplay(in:card.bounds) else { fatalError("Reminder card missing") }
            card.cacheDisplay(in:card.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("water-card.png"))
            let previousDeadline=water.deadline
            card.done.performClick(nil)
            precondition(water.deadline==previousDeadline,"Preview preserves real schedule")
            waterPreview=false;showWaterCard()
            let now = ProcessInfo.processInfo.systemUptime
            card.later.performClick(nil)
            precondition(!reminderVisible && abs((water.deadline ?? 0)-now-300)<2,"Snooze must dismiss and schedule five minutes later")
            waterPreview=false;showWaterCard(); card.done.performClick(nil)
            precondition(!reminderVisible && abs((water.deadline ?? 0)-ProcessInfo.processInfo.systemUptime-water.interval)<2,"Done starts a full interval")
            let oldMode = workMode
            workMode = false; previewWater()
            precondition(reminderVisible,"Immediate preview must also work outside work mode")
            dismissWaterCard(); workMode = oldMode
            print("PASS: persistent water card rendered; both button actions, five-minute snooze and preview outside work mode verified.")
            territory = min(15,max(0,UserDefaults.standard.object(forKey:"workTerritory") == nil ? 15 : UserDefaults.standard.integer(forKey:"workTerritory")))
            workMode = false; applyWorkArea(); move(to:original)
            print("PASS: 16 native work territories confine dragging, walking, running and the full pet window; water reminder rendered.")
            print("PASS: 34 frames loaded; tail poses, walk and run in both directions rendered; opaque input and click-through checked; native window moved partially off-screen at all four corners while keeping an opaque body patch visible.")
            try room.runChecks(at:directory)
            let quietBeforeMovement=quiet;quiet=false
            for size:CGFloat in [160,208,272] {
                panel.setContentSize(panelSize(size))
                for sign:CGFloat in [-1,1] {
                    stopWalking()
                    let screen=NSScreen.main!.visibleFrame
                    move(to:NSPoint(x:screen.midX,y:screen.midY))
                    let initial=panel.frame.origin;logicalPosition=initial
                    target=NSPoint(x:initial.x+sign*100,y:initial.y);runningMode=false
                    for _ in 0..<2000 {lastTick=ProcessInfo.processInfo.systemUptime-1.0/30;tick();if target==nil{break}}
                    precondition(abs(panel.frame.minX-initial.x-sign*100)<=2 && abs(panel.frame.minY-initial.y)<=1,"Both walking directions must reach target")
                }
            }
            quiet=quietBeforeMovement
            workMode=true;panel.orderOut(nil);showGrid()
            precondition(!panel.isVisible,"Grid preview must preserve hidden state")
            dismissGrid();panel.orderFrontRegardless();workMode=false
            for (command,badge) in [("/usr/bin/true","🍃"),("/usr/bin/false","❗")] {
                let process=Process()
                process.executableURL=Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/susu")
                process.arguments=["--data-dir",store.directory.path,"watch","--",command]
                try process.run();process.waitUntilExit();pollTasks()
                precondition(pet.taskBadge==badge && !store.save.handledTasks.isEmpty)
                let handled=store.save.handledTasks.count;taskState="";pollTasks()
                precondition(store.save.handledTasks.count==handled,"Completion is idempotent")
            }
            print("PASS: CLI to app task badge/journal integration, result dedup and hidden grid preview.")
            print("PASS: 2.0 six room pages, game results, preview isolation and actual left/right 100-point journeys at all three sizes.")
            print("Previews: \(directory.path)")
        } catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); savePosition() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = PetController()
app.delegate = controller
app.run()
