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
    let closeup: [NSImage]
    let houseArtwork: HouseArtwork
    let seasons: SeasonArtwork
    let idlePixels: [NSBitmapImageRep]
    let walkPixels: [NSBitmapImageRep]
    let runPixels: [NSBitmapImageRep]
    let stretchPixels: [NSBitmapImageRep]
    let playPixels: [NSBitmapImageRep]
    let closeupPixels: [NSBitmapImageRep]
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
        (closeup, closeupPixels) = try load("closeup", count: 3)
        houseArtwork=try HouseArtwork(resources:resources)
        seasons=try SeasonArtwork(resources:resources)
        let data = try Data(contentsOf: resources.appendingPathComponent("frames/visibility.json"))
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Double],
              let x = values["x"], let y = values["y"], let w = values["width"], let h = values["height"], w > 0, h > 0 else {
            throw NSError(domain: "Susu", code: 4, userInfo: [NSLocalizedDescriptionKey: "缺少屏幕边缘可见区域信息。"])
        }
        safetyCore = NSRect(x:x,y:y,width:w,height:h)
    }

    func character(_ pose: CharacterPose, frame: Int, season: PetSeason?) -> CharacterFrame {
        let index = frame % pose.frameCount
        if let season, pose == .idle || pose == .walk {
            let walking = pose == .walk
            let dressed = seasons[season]
            return CharacterFrame(image: dressed.image(walking: walking, frame: index),
                                  pixels: dressed.pixels(walking: walking, frame: index))
        }
        let sequence: ([NSImage], [NSBitmapImageRep])
        switch pose {
        case .idle: sequence = (idle, idlePixels)
        case .walk: sequence = (walk, walkPixels)
        case .run: sequence = (run, runPixels)
        case .stretch: sequence = (stretch, stretchPixels)
        case .play: sequence = (play, playPixels)
        case .closeup: sequence = (closeup, closeupPixels)
        case .carry: sequence = (houseArtwork.carry, houseArtwork.carryPixels)
        case .blanket: sequence = (houseArtwork.blanketAction, houseArtwork.blanketPixels)
        }
        let base = CharacterFrame(image: sequence.0[index], pixels: sequence.1[index])
        guard let season else { return base }
        return seasons.dressing.frame(for: season, pose: pose, index: index, base: base)
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
    var letterWaiting = false
    var away = false
    var home = false
    var scarfState = StudioState()
    var zoomHidden=false
    var frameIndex = 0
    var walking = false
    var running = false
    var action: PetAction?
    var facesLeft = false
    var greetingDuration: TimeInterval = 2.8
    var greetingAge: TimeInterval = 100
    var speech = ""
    var speechStyle = SpeechBubbleStyle()
    var dragging = false
    private var mouseStart = NSPoint.zero
    private var windowStart = NSPoint.zero
    private var moved = false
    private var previousImage: NSImage?
    private var previousMirrored = false
    var transitionAge: TimeInterval = 10

    var currentPose: CharacterPose {
        if let action { return action == .stretch ? .stretch : .play }
        return walking ? (running ? .run : .walk) : .idle
    }
    private var currentFrame: CharacterFrame { frames.character(currentPose, frame: frameIndex, season: scarfState.season) }
    var currentImage: NSImage { currentFrame.image }
    var currentPixels: NSBitmapImageRep { currentFrame.pixels }
    private var mirrored: Bool { (walking || action != nil) && facesLeft }
    var currentSafetyCore:NSRect {
        if action == nil,!running,let season=scarfState.season {return frames.seasons[season].safetyCore}
        return frames.safetyCore
    }
    func setMovement(walking nextWalking: Bool, running nextRunning: Bool, left: Bool, action nextAction: PetAction? = nil) {
        if action != nextAction || walking != nextWalking || running != nextRunning || (nextWalking && left != facesLeft) {
            previousImage = currentImage; previousMirrored = mirrored; transitionAge = 0
            walking = nextWalking; running = nextRunning; facesLeft = left; action = nextAction; frameIndex = 0
        }
    }

    var actorRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: bounds.width * 208 / 192) }
    var bounce: CGFloat {
        0 // Keep the body planted, including while a greeting bubble is visible.
    }

    override func draw(_ dirtyRect: NSRect) {
        guard frames != nil,!zoomHidden else { return }
        if away && home {
            if letterWaiting { ("✉️" as NSString).draw(at:NSPoint(x:8,y:70),withAttributes:[.font:NSFont.systemFont(ofSize:28)]) }
            return
        }
        if away {
            ((home ? "🏡 小窝中" : "🌲 探险中") as NSString).draw(at:NSPoint(x:8,y:35),withAttributes:[.font:NSFont.systemFont(ofSize:min(18,max(10,bounds.width/7))),.foregroundColor:NSColor.systemBrown])
            if letterWaiting { ("✉️" as NSString).draw(at:NSPoint(x:8,y:70),withAttributes:[.font:NSFont.systemFont(ofSize:28)]) }
            return
        }
        // Complete dressed poses switch together so a turn doesn't show two overlapping outfits.
        let mix = scarfState.season == nil ? CGFloat(min(1, transitionAge / 0.16)) : 1
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
        drawSprite(currentImage, mirrored: mirrored, opacity: mix)
        if action == nil && !running, let scarf=ScarfRenderer.overlay(state:scarfState,walking:walking,frame:frameIndex) {
            drawSprite(scarf,mirrored:facesLeft && walking,opacity:mix)
        }
        if letterWaiting {
            ("✉️" as NSString).draw(at:NSPoint(x:bounds.width-42,y:20),withAttributes:[.font:NSFont.systemFont(ofSize:28)])
        }
        if !taskBadge.isEmpty {
            (taskBadge as NSString).draw(at:NSPoint(x:6,y:20),withAttributes:[.font:NSFont.systemFont(ofSize:28)])
        }
        if greetingAge < greetingDuration && !speech.isEmpty {
            speechStyle.draw(speech, in: NSRect(x: 4, y: actorRect.maxY + 4, width: bounds.width - 8,
                                                height: SpeechBubbleStyle.headroom - 6))
        }
    }

    private var letterBadgeRect: NSRect {
        away ? NSRect(x: 4, y: 60, width: 42, height: 48) : NSRect(x: bounds.width - 42, y: 20, width: 36, height: 36)
    }
    private let taskBadgeRect = NSRect(x: 6, y: 20, width: 36, height: 36)

    // Transparent padding passes clicks through to the user's other windows.
    func containsPet(_ point: NSPoint) -> Bool {
        if zoomHidden{return false}
        if away && home {return letterWaiting && letterBadgeRect.contains(point)}
        if away { return NSRect(x:4,y:25,width:min(140,bounds.width-8),height:letterWaiting ? 85 : 45).contains(point) }
        if letterWaiting && letterBadgeRect.contains(point) { return true }
        if !taskBadge.isEmpty && taskBadgeRect.contains(point) { return true }
        let rect = actorRect.offsetBy(dx: 0, dy: bounce)
        guard rect.contains(point) else { return false }
        let bitmap = currentPixels
        var x = Int((point.x - rect.minX) / rect.width * CGFloat(bitmap.pixelsWide))
        if mirrored { x = bitmap.pixelsWide - 1 - x }
        let y = bitmap.pixelsHigh - 1 - Int((point.y - rect.minY) / rect.height * CGFloat(bitmap.pixelsHigh))
        guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { return false }
        return AlphaHitMask.hit(bitmap: bitmap, x: x, y: y, threshold: 0.12)
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
            let point = convert(event.locationInWindow, from: nil)
            if letterWaiting && letterBadgeRect.contains(point) { owner?.showLetters() }
            else if away { if home {owner?.showStudio()} else {owner?.showExpedition()} }
            else if !taskBadge.isEmpty && taskBadgeRect.contains(point) { owner?.showTaskRoom() }
            else if event.clickCount == 2 { owner?.showChat() }
            else { owner?.greet() }
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

final class PetController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: PetPanel!
    var pet: PetView!
    var status: NSStatusItem!
    private var animationTimer: Timer?
    private var activityTimer: Timer?
    private let statusMenu = NSMenu()
    private var statusMenuDirty = true
    private var trackingStatusMenu = false
    var frames: SpriteFrames!
    private var startTime = ProcessInfo.processInfo.systemUptime
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var greetingStart: TimeInterval = -100
    private var target: NSPoint?
    private var logicalPosition: NSPoint?
    private var store: CompanionStore!
    private var room: CompanionRoom!
    private var activities: ActivitiesRoom!
    private var studio: StudioRoom!
    private var chat: ChatRoom!
    private var desktop:DesktopActions!
    private var taskBoard: TaskBoard!
    private var pinnedControls: PinnedControls?
    private var cueActions: [PetAction] = []
    private var waterPreview = false
    private var waterSpeech = UserDefaults.standard.bool(forKey: "waterSpeech")
    private let waterSpeechText = "喝口水，休息一下～"
    private var taskRunning = false
    private var taskState = ""
    private var watchedTaskBadge = ""
    private var inRoom: Bool { chat?.isVisible == true || desktop?.isVisible == true }
    private var runningMode = false
    private var speed: CGFloat = 0
    private var nextWalk: TimeInterval = 0
    private var walkClock: TimeInterval = 0
    private var action: PetAction?
    private var actionClock: TimeInterval = 0
    private var autoWalk = true
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
        if CommandLine.arguments.contains("--outfit-preview") {
            do {
                let args = CommandLine.arguments
                guard let index = args.firstIndex(of: "--preview-dir"), args.indices.contains(index + 1),
                      let resources = Bundle.main.resourceURL else {
                    throw NSError(domain: "SusuPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "请提供 --preview-dir <目录>"])
                }
                let artwork = try SpriteFrames(resources: resources)
                try Self.exportOutfitPreviews(artwork, to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            } catch {
                fputs("Outfit preview failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            NSApp.terminate(nil)
            return
        }
        do {
            guard let resources = Bundle.main.resourceURL else { throw NSError(domain: "Susu", code: 3) }
            frames = try SpriteFrames(resources: resources)
            let testDirectory = CommandLine.arguments.contains("--smoke-test") ? FileManager.default.temporaryDirectory.appendingPathComponent("susu-smoke-"+UUID().uuidString) : nil
            store = try CompanionStore(directory:testDirectory)
        } catch {
            let alert = NSAlert(); alert.messageText = "溯溯暂时无法启动"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        if !CommandLine.arguments.contains("--smoke-test") {
            autoWalk = DesktopPreferences.migrate(.standard)
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
        activities = ActivitiesRoom(store:store,frames:frames)
        activities.playCue = { [weak self] in self?.performCue($0) ?? false }
        activities.onChange = { [weak self] in self?.syncActivities() }
        studio = StudioRoom(store:store,frames:frames)
        studio.onChange = { [weak self] in self?.syncActivities() }
        studio.onNestPresence = { [weak self] _ in self?.stopWalking();self?.syncActivities() }
        studio.getNestArea = { [weak self] in
            self?.workArea ?? self?.panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        }
        chat = ChatRoom(getState:{ [weak self] in self?.store.save.studio.chat ?? ChatState() },saveState:{ [weak self] state in
            guard let self else{return}
            var studioState=self.store.save.studio
            studioState.chat=state
            try self.store.saveStudio(studioState)
        })
        desktop=DesktopActions(store:store,frames:frames,room:room,activities:activities,anchor:{[weak self] in self?.studio.desktopAnchor ?? self?.panel.frame ?? .zero})
        let taskDefaults = CommandLine.arguments.contains("--smoke-test") ?
            UserDefaults(suiteName: "Susu.Smoke.Tasks." + UUID().uuidString)! : UserDefaults.standard
        taskBoard = TaskBoard(store: store, defaults: taskDefaults)
        taskBoard.watcherIsRunning = { [weak self] in self?.taskRunning == true }
        taskBoard.attach = { [weak self] view, busy in self?.desktop.present(view, postponeDismissal: busy) }
        taskBoard.onChange = { [weak self] in self?.pollTasks(); self?.pollTaskReminders() }
        desktop.animate={ [weak self] action in self?.studio.releaseFox();self?.startAction(action) }
        desktop.invokeCue={ [weak self] actions in self?.studio.releaseFox();return self?.performCue(actions) ?? false }
        desktop.onChange={ [weak self] in self?.syncActivities() }
        desktop.onPresent={ [weak self] in self?.stopWalking(); self?.chat.dismissDesktopChat() }
        desktop.onDismiss={ [weak self] in self?.pet.zoomHidden=false;self?.pet.needsDisplay=true;self?.studio.stopCloseup() }
        studio.onReturnToDesktop={ [weak self] rect in
            guard let self else{return}
            self.move(to:NSPoint(x:rect.midX-self.panel.frame.width/2,y:rect.minY))
        }
        studio.desktopMenu={ [weak self] in self?.makeMenu() ?? NSMenu() }
        studio.canStartHouse={ [weak self] in self?.quiet == false && self?.suspended == false }
        chat.desktopAnchor = { [weak self] in
            guard let self else { return .zero }
            if self.studio.foxInNest, let nestAnchor = self.studio.desktopAnchor { return nestAnchor }
            return self.panel.convertToScreen(self.pet.convert(self.pet.actorRect, to: nil))
        }
        chat.avatar = { [weak self] in
            guard let self else { return nil }
            return self.frames.character(.idle, frame: 0, season: self.store.save.studio.season).image
        }
        syncActivities()
        pet.setAccessibilityLabel("溯溯桌面宠物。点击回应，双击聊天，拖动移动，右键打开菜单。")
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
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        status.menu = statusMenu
        refreshMenu()
        menuNeedsUpdate(statusMenu)
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking), name: NSWorkspace.screensDidWakeNotification, object: nil)
        greet(text: "你好，我是溯溯。")
        if CommandLine.arguments.contains("--show-home") && !CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline:.now()+1){[weak self] in self?.studio.restOutside()}
        }
        nextWalk = ProcessInfo.processInfo.systemUptime + 8
        updateAnimationTimer()
        startActivityTimer()
        if let backup = store.recoveredBackupURL {
            DispatchQueue.main.async { [weak self] in self?.showSaveRecovery(backup) }
        }
        if CommandLine.arguments.contains("--preview-water") && !CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { [weak self] in self?.previewWater() }
        }
        if CommandLine.arguments.contains("--smoke-test") {
            // Exercise the actual drawing and alpha hit testing without staying resident.
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.smokeTest() }
        }
    }

    private func showSaveRecovery(_ backup: URL) {
        let alert = NSAlert()
        alert.messageText = "旧存档暂时无法读取"
        alert.informativeText = "溯溯已用空白存档启动，并保留了原文件。你可以打开备份所在位置，检查或修复后再导入。"
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "显示原文件")
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
    }

    private func updateAnimationTimer() {
        guard panel?.isVisible == true, !suspended else {
            animationTimer?.invalidate()
            animationTimer = nil
            return
        }
        guard animationTimer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startActivityTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.pollTasks()
            self?.pollTaskReminders()
            self?.syncActivities()
        }
        timer.tolerance = 0.2
        activityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        workArea.map { WorkTerritory.width(preferred: scale, area: $0, bubbleHeight: SpeechBubbleStyle.headroom) } ?? scale
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

    private func panelSize(_ width: CGFloat) -> NSSize { NSSize(width: width, height: width * 208 / 192 + SpeechBubbleStyle.headroom) }

    func move(to point: NSPoint) {
        guard panel != nil else { return }
        if let area = workArea {
            let constrained = WorkTerritory.constrain(point, window:panel.frame.size, area:area)
            logicalPosition = constrained
            panel.setFrameOrigin(constrained)
            chat?.repositionDesktop()
            return
        }
        let sprite = NSSize(width:panel.frame.width,height:panel.frame.width*208/192)
        let allowed = DesktopBounds.constrain(point, sprite:sprite, core:pet.currentSafetyCore,
                                               screens:NSScreen.screens.map(\.visibleFrame))
        logicalPosition = allowed
        panel.setFrameOrigin(allowed)
        chat?.repositionDesktop()
    }
    func savePosition() {
        guard let panel, !CommandLine.arguments.contains("--smoke-test") else { return }
        UserDefaults.standard.set(panel.frame.minX, forKey: "positionX")
        UserDefaults.standard.set(panel.frame.minY, forKey: "positionY")
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now-lastTick)); lastTick = now
        if !waterPreview && water.poll(at: now, active: workMode && !quiet && !suspended && panel.isVisible && !reminderVisible) {
            remindWater()
        }
        guard !suspended, panel.isVisible else { return }
        if let current = action {
            actionClock += dt
            if actionClock >= current.duration {
                let queued = cueActions
                stopWalking()
                if let first = queued.first {
                    startAction(first)
                    cueActions = Array(queued.dropFirst())
                }
            }
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
        } else if autoWalk && !quiet && !reminderVisible && !pet.dragging && !pet.away && !inRoom && !taskRunning && action == nil && now > nextWalk {
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
        let passThrough = !pet.dragging && !pet.containsPet(local)
        if panel.ignoresMouseEvents != passThrough { panel.ignoresMouseEvents = passThrough }
    }

    func stopWalking() { cueActions = []; logicalPosition = panel?.frame.origin; target = nil; action = nil; actionClock = 0; speed = 0; nextWalk = ProcessInfo.processInfo.systemUptime + Double.random(in: 8...18) }
    @objc func stretchOnce() { startAction(.stretch) }
    @objc func playOnce() { startAction(.play) }
    private func startAction(_ next: PetAction) {
        guard !quiet, !reminderVisible, !pet.away, !pet.dragging else { return }
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
        guard !quiet, !reminderVisible, !pet.away, !pet.dragging, let screen = NSScreen.screens.randomElement() else { return }
        cueActions = [];action = nil; actionClock = 0
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
            destination = DesktopBounds.constrain(raw,sprite:sprite,core:pet.currentSafetyCore,screens:NSScreen.screens.map(\.visibleFrame))
        }
        if !running {
            if workArea != nil { destination.y = panel.frame.minY }
            else {
                destination = WalkingRoute.destination(desiredX:raw.x,from:panel.frame.origin,sprite:sprite,core:pet.currentSafetyCore,screens:NSScreen.screens.map(\.visibleFrame))
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
        pet.speech = text ?? (SpeechBubbleStyle.greetings.randomElement() ?? "我在呢。")
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
        stopWalking(); dismissGrid();desktop?.interrupt();room?.interrupt()
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
        if waterSpeech { greet(text: waterSpeechText) }
    }
    private func dismissWaterCard() {
        waterPanel?.orderOut(nil)
        waterPreview = false
        clearWaterSpeech()
    }
    private func clearWaterSpeech() {
        guard pet?.speech == waterSpeechText else { return }
        greetingStart = -100
        pet.greetingAge = 100
        pet.needsDisplay = true
    }
    @objc private func toggleWaterSpeech() {
        waterSpeech.toggle()
        UserDefaults.standard.set(waterSpeech, forKey: "waterSpeech")
        if !waterSpeech { clearWaterSpeech() }
        refreshMenu()
    }
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
    @objc private func togglePinnedControls() {
        if let pinnedControls, pinnedControls.isVisible {
            pinnedControls.close()
            return
        }
        let controls = PinnedControls { [weak self] in self?.makeMenu(includePin: false) ?? NSMenu() }
        controls.onClose = { [weak self] in
            self?.pinnedControls = nil
            self?.refreshMenu()
        }
        pinnedControls = controls
        controls.show(at: studio.desktopAnchor ?? panel.frame)
        refreshMenu()
    }

    @objc private func chooseBubbleTheme(_ item: NSMenuItem) {
        guard let theme = SpeechBubbleStyle.Theme(rawValue: item.tag) else { return }
        if theme == .custom {
            let picker = NSColorPanel.shared
            picker.showsAlpha = false
            picker.setTarget(nil)
            picker.color = pet.speechStyle.customColor ?? pet.speechStyle.background
            picker.setTarget(self)
            picker.setAction(#selector(changeBubbleColor(_:)))
            picker.makeKeyAndOrderFront(nil)
        } else {
            pet.speechStyle.theme = theme
            UserDefaults.standard.set(theme.rawValue, forKey: "speechBubbleTheme")
            refreshBubble()
        }
    }

    @objc private func changeBubbleColor(_ picker: NSColorPanel) {
        guard let color = picker.color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([color.redComponent, color.greenComponent, color.blueComponent], forKey: "speechBubbleColor")
        UserDefaults.standard.set(SpeechBubbleStyle.Theme.custom.rawValue, forKey: "speechBubbleTheme")
        pet.speechStyle = SpeechBubbleStyle()
        refreshBubble()
    }

    @objc private func chooseBubbleSize(_ item: NSMenuItem) {
        guard SpeechBubbleStyle.textSizes.indices.contains(item.tag) else { return }
        pet.speechStyle.sizeIndex = item.tag
        UserDefaults.standard.set(item.tag, forKey: "speechBubbleSize")
        refreshBubble()
    }

    private func refreshBubble() {
        greet(text: "我在呢。")
        pet.needsDisplay = true
        refreshMenu()
    }
    @objc func toggleAuto() { autoWalk.toggle(); UserDefaults.standard.set(autoWalk, forKey: "freeRoam"); if !autoWalk { stopWalking() }; refreshMenu() }
    @objc func toggleQuiet() {
        dismissWaterCard()
        quiet.toggle()
        UserDefaults.standard.set(quiet, forKey: "quiet")
        if quiet {
            desktop?.interrupt()
            chat?.hideDesktop()
        }
        studio?.pauseHouse(quiet || suspended)
        water.restart(at:ProcessInfo.processInfo.systemUptime)
        stopWalking()
        pet.frameIndex = 0
        pet.greetingAge = 100
        pet.needsDisplay = true
        refreshMenu()
    }
    @objc func toggleVisible() {
        water.restart(at:ProcessInfo.processInfo.systemUptime); dismissGrid(); dismissWaterCard();desktop?.interrupt();chat?.hideDesktop()
        studio.suspendHouse(panel.isVisible)
        if panel.isVisible { panel.orderOut(nil); stopWalking() } else { panel.orderFrontRegardless(); greet() }
        updateAnimationTimer()
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
        panel.orderFrontRegardless(); updateAnimationTimer(); savePosition(); refreshMenu()
    }
    @objc func showHelp() {
        let alert = NSAlert(); alert.messageText = "溯溯 · 桌面版 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        alert.informativeText = "点击：溯溯回应你\n双击：在溯溯身边聊天\n拖动：在桌面自由摆放，可部分移出屏幕\n右键或菜单栏爪印：按陪伴互动、吃喝与小窝、玩耍与行动、学习与信件、造型与合影、工作与提醒、设置与存档分类。进入对应子菜单即可操作\n\n自由活动默认开启，以左右慢走为主，偶尔伸懒腰、玩耍或跑步。始终保留一小块身体在屏幕内；选择‘回到主屏幕’可以找回。安静模式会停止摇尾巴与其他动作。\n\n工作模式：屏幕分成 4×4 共 16 格，可选择地盘与显示器；宠物会自动缩小并完整留在该格内。每 30 分钟提醒喝水，可改为 15、45、60 分钟。提醒卡片持续显示，点击‘喝过了’后重新计时，或选‘5 分钟后提醒’。菜单可立即体验。隐藏、安静与屏幕休眠时暂停提醒，恢复后重新计时。\n\n本地简答无需联网。可在聊天气泡中设置大模型。"
        alert.addButton(withTitle: "知道啦"); alert.runModal()
    }
    @objc func screenChanged() { dismissGrid(); applyWorkArea(); positionWaterCard(); refreshMenu() }
    @objc func sleeping() {
        suspended = true; stopWalking(); dismissGrid(); dismissWaterCard(); refreshMenu()
        updateAnimationTimer()
        studio?.pauseHouse(true)
        _ = water.poll(at:ProcessInfo.processInfo.systemUptime,active:false)
    }
    @objc func waking() {
        suspended = false; lastTick = ProcessInfo.processInfo.systemUptime
        updateAnimationTimer()
        water.restart(at:lastTick);studio?.pauseHouse(quiet)
    }
    private func performCue(_ names: [String]) -> Bool {
        let sequence = names.compactMap(PetAction.init(rawValue:))
        guard sequence.count == 2, !quiet, !suspended, panel.isVisible,
              !reminderVisible, !pet.dragging, !pet.away else { return false }
        stopWalking()
        startAction(sequence[0])
        cueActions = Array(sequence.dropFirst())
        return true
    }
    private func syncActivities() {
        guard store != nil, pet != nil else { return }
        do {
            let changed = try store.settleActivities()
            if store.save.activities.expedition != nil && studio?.foxInNest == true {studio.leaveNest()}
            let away = store.save.activities.expedition != nil || studio?.foxInNest == true
            if away != pet.away { stopWalking() }
            pet.away = away
            pet.home = studio?.foxInNest == true
            pet.scarfState = store.save.studio
            studio?.refreshState()
            studio?.pauseHouse(quiet || suspended)
            studio?.updateNestArea()
            chat?.repositionDesktop()
            pet.letterWaiting = !store.unreadLetters.isEmpty
            pet.needsDisplay = true
            if changed { activities?.refreshDelivery() }
        } catch {
            status?.button?.toolTip = "新玩法保存未完成，稍后重试。"
        }
    }
    @objc func showStudio() {stopWalking();studio.showHouse()}
    @objc func showChat() {
        if !panel.isVisible { toggleVisible() }
        stopWalking()
        desktop.interrupt()
        pet.greetingAge = pet.greetingDuration
        greetingStart = -Double.infinity
        pet.needsDisplay = true
        chat.showDesktop()
    }
    @objc func showActivities() {studio.releaseFox();desktop.cues()}
    @objc func showExpedition() {desktop.expedition()}
    @objc func showLetters() {desktop.letters()}
    @objc func showRoom() {studio.releaseFox();desktop.game()}
    @objc func showFoodRoom() {studio.releaseFox();desktop.food()}
    @objc func showTaskRoom() {
        if !panel.isVisible { toggleVisible() }
        taskBoard.show(watched: room.taskDetail)
    }

    @objc private func chooseAutoDismissal(_ item: NSMenuItem) {
        guard DesktopDismissal.choices.contains(item.tag) else { return }
        UserDefaults.standard.set(item.tag, forKey: DesktopDismissal.key)
        refreshMenu()
    }

    private func pollTaskReminders() {
        defer { refreshTaskBadge() }
        guard panel?.isVisible == true, !quiet, !suspended else { return }
        do {
            let reminders = try store.deliverTaskReminders()
            if let first = reminders.first {
                let suffix = reminders.count > 1 ? "等 \(reminders.count) 条待办" : ""
                greet(text: "待办提醒 · \(first.title)\(suffix)", duration: 8)
                taskBoard.refreshPlans()
            }
        } catch {
            taskBoard.refreshWatcher("待办提醒暂未保存，溯溯会重试。")
        }
    }

    private func refreshTaskBadge() {
        let hasReminder = store.save.plannedTasks.contains { $0.remindedAt != nil && $0.completedAt == nil }
        let icon = taskRunning || !hasReminder ? watchedTaskBadge : "🔔"
        if pet.taskBadge != icon { pet.taskBadge = icon; pet.needsDisplay = true }
    }
    @objc func showCards(){desktop.cards()}
    @objc func showJournal(){desktop.journal()}
    @objc func showArchive(){desktop.archive()}
    @objc func compareFood(){desktop.compareFood()}
    @objc func restAtHouse(){studio.restOutside()}
    @objc func storeMat(){studio.putMatInside()}
    @objc func leaveHouse(){studio.releaseFox()}
    @objc func hideHouse(){studio.leaveNest()}
    @objc func houseSize(_ item:NSMenuItem){studio.resizeHouse(CGFloat(item.tag))}
    @objc func showCloseup(){studio.releaseFox();stopWalking();desktop.present(studio.desktopCloseup(feedback:{[weak self] in self?.greet(text:$0)}),glass:false);pet.zoomHidden=true;pet.needsDisplay=true}
    @objc func showPhoto(){desktop.present(studio.desktopPhotoView())}
    @objc func changeSeason(_ item:NSMenuItem) {
        guard (0...4).contains(item.tag) else{return}
        studio.selectScarf(item.tag==4 ? "none" : PetSeason.allCases[item.tag].rawValue)
        move(to:panel.frame.origin);refreshMenu()
    }
    @objc func changeScarf(_ item:NSMenuItem){let ids=["none","teal","amber","rose"]+store.save.studio.packs.map{$0.id.uuidString};guard ids.indices.contains(item.tag) else{return};studio.selectScarf(ids[item.tag]);refreshMenu()}
    @objc func changeLook(_ item:NSMenuItem){studio.useLook(item.tag);refreshMenu()}
    @objc func deleteLook(_ item:NSMenuItem){studio.deleteDesktopLook(item.tag);refreshMenu()}
    @objc func deleteScarf(_ item:NSMenuItem){studio.deleteDesktopPack(item.tag);refreshMenu()}
    @objc func toggleCloseupSound(){studio.toggleCloseupSound();refreshMenu()}
    @objc func dismissDesktopProps(){desktop.interrupt();chat.hideDesktop()}
    @objc func saveLook(){desktop.askName("给今天的造型起个名字"){[weak self] in self?.studio.saveDesktopLook(name:$0);self?.refreshMenu()}}
    @objc func importScarf(){studio.importDesktopScarf();refreshMenu()}
    @objc func exportScarf(){studio.exportDesktopTemplate()}
    func receiveFood(_ index:Int) {room.feed(index);greet(text:"收到点心啦！")}
    private func pollTasks() {
        let events: [TaskEvent]
        do { events = try store.pollTaskEvents() }
        catch {
            room.refreshTask("任务结果暂未保存。\(error.localizedDescription)")
            return
        }
        let running = events.filter { $0.status == "running" }.max { $0.date < $1.date }
        taskRunning = running != nil
        guard let event = running ?? store.save.lastTask else {
            if !taskState.isEmpty {
                taskState = ""
                watchedTaskBadge = ""
                refreshTaskBadge()
                room.refreshTask("还没有交办任务。")
                taskBoard.refreshWatcher(room.taskDetail)
            }
            return
        }
        let key = "\(event.id):\(event.status)"
        guard key != taskState else { return }
        taskState = key
        let text: String
        switch event.status {
        case "running": text="等待中";watchedTaskBadge="⌛";stopWalking()
        case "success": text="任务完成";watchedTaskBadge="🍃"
        case "cancelled": text="已取消";watchedTaskBadge="↩"
        default: text="任务失败";watchedTaskBadge="❗"
        }
        if !taskRunning, panel.isVisible, events.contains(where: { $0.id == event.id && $0.status == event.status }) {
            greet(text: text)
        }
        room.refreshTask("\(text) · \(event.name)\n退出码 \(event.exitCode.map(String.init) ?? "—")")
        taskBoard.refreshWatcher(room.taskDetail)
        refreshTaskBadge()
    }
    @objc func quit() { NSApp.terminate(nil) }
    private func refreshMenu() {
        status.button?.image = NSImage(systemSymbolName:reminderVisible ? "drop.fill" : "pawprint.fill",accessibilityDescription:reminderVisible ? "溯溯提醒你喝水" : "溯溯")
        status.button?.toolTip = reminderVisible ? "该喝水啦 · 点击菜单或提醒卡片处理" : "溯溯 · 桌面小伙伴"
        statusMenuDirty = true
        pinnedControls?.refresh()
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu, statusMenuDirty, !trackingStatusMenu else { return }
        let updated = makeMenu()
        menu.removeAllItems()
        for item in updated.items {
            updated.removeItem(item)
            menu.addItem(item)
        }
        statusMenuDirty = false
    }
    func menuWillOpen(_ menu: NSMenu) { if menu === statusMenu { trackingStatusMenu = true } }
    func menuDidClose(_ menu: NSMenu) { if menu === statusMenu { trackingStatusMenu = false } }
    func makeMenu(includePin: Bool = true) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        @discardableResult
        func item(_ parent:NSMenu,_ title:String,_ action:Selector,checked:Bool?=nil,tag:Int=0,enabled:Bool=true)->NSMenuItem {
            let entry=NSMenuItem(title:title,action:action,keyEquivalent:"")
            entry.target=self;entry.tag=tag;entry.isEnabled=enabled
            if let checked {entry.state=checked ? .on : .off}
            parent.addItem(entry);return entry
        }
        func group(_ parent:NSMenu,_ title:String)->NSMenu {
            let entry=NSMenuItem(title:title,action:nil,keyEquivalent:"")
            let submenu=NSMenu(title:title);submenu.autoenablesItems=false
            entry.submenu=submenu;parent.addItem(entry);return submenu
        }
        let name=NSMenuItem(title:"点空白关闭 · 右键或爪印重开",action:nil,keyEquivalent:"")
        name.isEnabled=false;menu.addItem(name);menu.addItem(.separator())
        if includePin {
            let visible = pinnedControls?.isVisible == true
            let pin = item(menu, visible ? "关闭固定菜单" : "固定菜单到桌面…", #selector(togglePinnedControls))
            pin.image = NSImage(systemSymbolName: visible ? "pin.slash" : "pin", accessibilityDescription: nil)
            pin.toolTip = "固定后，点击桌面其他地方也会保留。"
            menu.addItem(.separator())
        }

        let companion=group(menu,"陪伴互动")
        item(companion,"打个招呼",#selector(sayHello))
        item(companion,"和溯溯聊天",#selector(showChat))
        item(companion,"近看互动",#selector(showCloseup))
        companion.addItem(.separator())
        item(companion,"近看互动静音",#selector(toggleCloseupSound),checked:studio.closeupMuted)

        let home=group(menu,"吃喝与小窝")
        item(home,"喂点心",#selector(showFoodRoom))
        item(home,"两盘选口味",#selector(compareFood))
        home.addItem(.separator())
        item(home,"回窝拿毯子休息",#selector(restAtHouse))
        item(home,"收毯子回屋",#selector(storeMat))
        item(home,"结束休息，出来走走",#selector(leaveHouse))
        let houseSizes=group(home,"小窝大小")
        for (label,width) in [("小",320),("中",440),("大",560)] {
            item(houseSizes,label,#selector(houseSize(_:)),tag:width)
        }

        let play=group(menu,"玩耍与行动")
        item(play,"藏松果",#selector(showRoom))
        item(play,"去探险",#selector(showExpedition))
        play.addItem(.separator())
        item(play,"左右散步",#selector(walkOnce))
        item(play,"跑一圈",#selector(runOnce))
        item(play,"伸个懒腰",#selector(stretchOnce))
        item(play,"玩耍一下",#selector(playOnce))
        play.addItem(.separator())
        item(play,"自由活动",#selector(toggleAuto),checked:autoWalk)

        let learning=group(menu,"学习与信件")
        item(learning,"听暗号 / 教暗号",#selector(showActivities))
        item(learning,"抽认卡",#selector(showCards))
        item(learning,"信箱 / 留一封信",#selector(showLetters))
        item(learning,"手帐",#selector(showJournal))

        let appearance=group(menu,"造型与合影")
        let seasons=group(appearance,"季节外观")
        for (index,season) in PetSeason.allCases.enumerated() {
            item(seasons,season.title,#selector(changeSeason(_:)),checked:store.save.studio.season==season,tag:index)
        }
        seasons.addItem(.separator())
        item(seasons,"原始外观",#selector(changeSeason(_:)),checked:store.save.studio.scarf=="none",tag:4)
        if !store.save.studio.packs.isEmpty {
            let packs=group(appearance,"导入的配饰")
            for (index,pack) in store.save.studio.packs.enumerated() {
                item(packs,pack.name,#selector(changeScarf(_:)),checked:store.save.studio.scarf==pack.id.uuidString,tag:index+4)
            }
        }
        let looks=group(appearance,"保存与管理造型")
        item(looks,"保存当前造型",#selector(saveLook))
        if !store.save.studio.looks.isEmpty {
            let saved=group(looks,"穿戴已保存造型")
            let remove=group(looks,"删除造型")
            for (index,look) in store.save.studio.looks.enumerated() {
                item(saved,look.name,#selector(changeLook(_:)),tag:index)
                item(remove,look.name,#selector(deleteLook(_:)),tag:index)
            }
        }
        looks.addItem(.separator())
        item(looks,"导入配饰…",#selector(importScarf))
        item(looks,"导出配饰模板…",#selector(exportScarf))
        if !store.save.studio.packs.isEmpty {
            let remove=group(looks,"删除导入的配饰")
            for (index,pack) in store.save.studio.packs.enumerated() {
                item(remove,pack.name,#selector(deleteScarf(_:)),tag:index)
            }
        }
        item(appearance,"合影明信片",#selector(showPhoto))
        let sizes=group(appearance,"溯溯大小")
        for (label,width) in [("小",160),("中",208),("大",272)] {
            item(sizes,label,#selector(resize(_:)),checked:Int(scale)==width,tag:width)
        }

        let work=group(menu,"工作与提醒")
        item(work,"工作模式",#selector(toggleWork),checked:workMode)
        item(work,"任务报信",#selector(showTaskRoom))
        work.addItem(.separator())
        let cells=group(work,"选择地盘")
        for row in 0..<4 {
            if row > 0 { cells.addItem(.separator()) }
            for column in 0..<4 {
                let index=row*4+column
                item(cells,"\(index+1) 号 · 第 \(row+1) 行第 \(column+1) 列",#selector(chooseTerritory(_:)),checked:territory==index,tag:index,enabled:workMode)
            }
        }
        let displays=group(work,"工作屏幕")
        for screen in NSScreen.screens {
            item(displays,screen.localizedName,#selector(chooseScreen(_:)),checked:workScreen===screen,tag:screenID(screen),enabled:workMode)
        }
        item(work,"显示地盘网格（3 秒）",#selector(showGrid),enabled:workMode)
        work.addItem(.separator())
        let intervals=group(work,"喝水间隔")
        for minutes in [15,30,45,60] {
            item(intervals,"每 \(minutes) 分钟",#selector(chooseWaterInterval(_:)),checked:Int(water.interval)==minutes*60,tag:minutes)
        }
        item(work,"喝水提醒（立即体验）",#selector(previewWater))
        item(work,"喝水提醒附带回应气泡",#selector(toggleWaterSpeech),checked:waterSpeech)
        if reminderVisible {
            item(work,"喝过了 ✓",#selector(waterDone))
            item(work,"5 分钟后提醒",#selector(waterLater))
        }

        let settings=group(menu,"设置与存档")
        item(settings,"安静模式",#selector(toggleQuiet),checked:quiet)
        item(settings,"回到主屏幕",#selector(resetPosition))
        let dismissal = group(settings, "道具 / 气泡自动收起")
        for seconds in DesktopDismissal.choices {
            item(dismissal, seconds == 0 ? "手动收起" : "\(seconds) 秒", #selector(chooseAutoDismissal(_:)),
                 checked: DesktopDismissal.seconds == seconds, tag: seconds)
        }
        let bubble = group(settings, "回应气泡")
        let palette = group(bubble, "背景颜色")
        for theme in SpeechBubbleStyle.Theme.allCases {
            item(palette, theme.title, #selector(chooseBubbleTheme(_:)), checked: pet.speechStyle.theme == theme, tag: theme.rawValue)
        }
        let textSizes = group(bubble, "文字大小")
        for (index, points) in SpeechBubbleStyle.textSizes.enumerated() {
            item(textSizes, "\(["小", "中", "大"][index]) · \(points) pt", #selector(chooseBubbleSize(_:)), checked: pet.speechStyle.sizeIndex == index, tag: index)
        }
        settings.addItem(.separator())
        item(settings,"存档备份 / 迁移",#selector(showArchive))
        item(settings,"使用说明",#selector(showHelp))

        menu.addItem(.separator())
        item(menu,"收起道具 / 气泡",#selector(dismissDesktopProps))
        item(menu,panel?.isVisible==false ? "显示溯溯" : "暂时隐藏",#selector(toggleVisible))
        item(menu,"退出溯溯",#selector(quit))
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
            let retiredTitles = ["林间小屋", "新的共同经历", "生活工坊"]
            precondition(!NSApp.windows.contains { window in retiredTitles.contains(where: { window.title.contains($0) }) })
            precondition(chat.window == nil)
            let suiteName = "Susu.smoke." + UUID().uuidString
            let prefs = UserDefaults(suiteName: suiteName)!
            prefs.set(false, forKey: "autoWalk")
            prefs.set(true, forKey: "houseShown")
            precondition(!DesktopPreferences.migrate(prefs) && prefs.object(forKey: "autoWalk") == nil && prefs.object(forKey: "houseShown") == nil)
            prefs.set(true, forKey: "freeRoam")
            prefs.set(false, forKey: "autoWalk")
            precondition(DesktopPreferences.migrate(prefs))
            prefs.removePersistentDomain(forName: suiteName)
            toggleVisible()
            precondition(!panel.isVisible && animationTimer == nil && activityTimer?.isValid == true)
            toggleVisible()
            precondition(panel.isVisible && animationTimer?.isValid == true)
            let bitmap = frames.walkPixels[0]
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 5) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 5) {
                    let reference = (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.12
                    precondition(AlphaHitMask.hit(bitmap: bitmap, x: x, y: y, threshold: 0.12) == reference,
                                 "Alpha mask must preserve logical orientation and transparency")
                }
            }
            print("PASS: legacy preference migration, hidden-window animation pause and alpha-mask equivalence.")
            togglePinnedControls()
            let pinPanel = NSApp.windows.first { $0.title == "溯溯的操作菜单" && $0.isVisible } as? NSPanel
            precondition(pinPanel?.hidesOnDeactivate == false && pinnedControls?.isVisible == true)
            precondition(makeMenu().item(withTitle: "关闭固定菜单") != nil)
            togglePinnedControls()
            precondition(pinnedControls == nil && makeMenu().item(withTitle: "固定菜单到桌面…") != nil)
            print("PASS: no retired startup windows; menu pins to a persistent panel and closes from the regular menu.")
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
                let expected = DesktopBounds.constrain(p,sprite:sprite,core:pet.currentSafetyCore,screens:screens)
                move(to:p)
                let actual = panel.frame.origin
                guard abs(actual.x-expected.x)<=1 && abs(actual.y-expected.y)<=1 else {
                    throw NSError(domain:"SusuBoundary",code:1,userInfo:[NSLocalizedDescriptionKey:"Native window clamp: expected \(expected), actual \(actual)"])
                }
                let core = pet.currentSafetyCore
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
            print("PASS: 37 frames loaded; tail poses, walk and run in both directions rendered; opaque input and click-through checked; native window moved partially off-screen at all four corners while keeping an opaque body patch visible.")
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
                guard let taskExecutable = TaskTool.executable else { fatalError(TaskTool.unavailable) }
                process.executableURL = taskExecutable
                process.arguments=["--data-dir",store.directory.path,"watch","--",command]
                try process.run();process.waitUntilExit();pollTasks()
                precondition(pet.taskBadge==badge && !store.save.handledTasks.isEmpty)
                let handled=store.save.handledTasks.count;taskState="";pollTasks()
                precondition(store.save.handledTasks.count==handled,"Completion is idempotent")
            }
            print("PASS: CLI to app task badge/journal integration, result dedup and hidden grid preview.")
            print("PASS: 2.0 six room pages, game results, preview isolation and actual left/right 100-point journeys at all three sizes.")
            try activities.runChecks(at:directory)
            let previousQuiet=quiet;quiet=false;stopWalking()
            precondition(performCue(["stretch","play"]))
            precondition(action == .stretch && cueActions == [.play])
            actionClock=PetAction.stretch.duration;tick()
            precondition(action == .play && cueActions.isEmpty)
            actionClock=PetAction.play.duration;tick()
            precondition(action == nil)
            precondition(performCue(["play","stretch"]))
            stopWalking();precondition(cueActions.isEmpty && action == nil)
            quiet=true;precondition(!performCue(["stretch","play"]))
            quiet=previousQuiet
            pet.letterWaiting=true
            precondition(pet.containsPet(NSPoint(x:pet.bounds.width-25,y:35)),"The envelope badge must be clickable")
            pet.letterWaiting=false
            print("PASS: 2.1 four activity pages; ordered cue playback, completion, interrupt and quiet-state guard.")
            quiet=false
            try studio.runChecks(at:directory)
            showChat()
            precondition(chat.isDesktopChatVisible && chat.window == nil)
            try chat.runChecks(at:directory)
            try taskBoard.runChecks(at: directory)
            desktop.interrupt()
            try desktop.runChecks(at:directory)
            try checkSeasonArt(at:directory)
            print("PASS: 2.2 studio pages, scarf template import/validation, postcard export and closeup sequence.")
            print("PASS: Borderless desktop house, transparent input, scarf template import and desktop prop regression.")
            print("PASS: 2.4 on-demand house stays hidden before rest and after packing/exit; integrated carrying and paw/blanket poses; seven interrupted packing paths and full lifecycle.")
            print("PASS: four seasonal whole-character outfits; all 56 frames loaded; native idle/right/left drawing and alpha hit testing; season-specific visible body patch.")
            print("Previews: \(directory.path)")
        } catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
        NSApp.terminate(nil)
    }

    private func checkSeasonArt(at directory:URL)throws {
        let preview=PetView(frame:NSRect(x:0,y:0,width:192,height:260));preview.frames=frames
        for season in PetSeason.allCases {
            preview.scarfState.scarf=season.rawValue
            for walking in [false,true] {
                preview.walking=walking;preview.running=false;preview.action=nil
                for left in walking ? [false,true] : [false] {
                    preview.facesLeft=left
                    for index in 0..<(walking ? 8 : 6) {
                        preview.frameIndex=index
                        let core=preview.currentSafetyCore
                        let point=NSPoint(x:core.midX*preview.actorRect.width,y:core.midY*preview.actorRect.height)
                        precondition(preview.containsPet(point),"Seasonal visible body patch must accept input, including mirrored walks")
                        precondition(!preview.containsPet(NSPoint(x:1,y:259)))
                        if index == (walking ? 2 : 0) {
                            let rep=preview.bitmapImageRepForCachingDisplay(in:preview.bounds)!
                            preview.cacheDisplay(in:preview.bounds,to:rep)
                            let name="season-\(season.rawValue)-\(walking ? (left ? "left" : "right") : "idle").png"
                            try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
                        }
                    }
                }
            }
        }
    }

    private static func exportOutfitPreviews(_ artwork: SpriteFrames, to directory: URL) throws {
        for season in PetSeason.allCases {
            for pose in CharacterPose.allCases {
                let folder = directory.appendingPathComponent("\(season.rawValue)/\(pose.rawValue)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for index in 0..<pose.frameCount {
                    let frame = artwork.character(pose, frame: index, season: season).pixels
                    let filename = "\(season.rawValue)/\(pose.rawValue)/\(index)"
                    guard let data = frame.representation(using: .png, properties: [:]),
                          data != artwork.character(pose, frame: index, season: nil).pixels.representation(using: .png, properties: [:]),
                          (frame.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0 else {
                        throw NSError(domain: "SusuPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "预览帧无效：\(filename)"])
                    }
                    try data.write(to: folder.appendingPathComponent(String(format: "%02d.png", index)))
                }
            }
        }
        print("Rendered all \(PetSeason.allCases.count * CharacterPose.allCases.map(\.frameCount).reduce(0, +)) seasonal frames in \(directory.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.invalidate()
        activityTimer?.invalidate()
        savePosition()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = PetController()
app.delegate = controller
app.run()
