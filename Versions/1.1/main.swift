import AppKit

// Native macOS desktop companion. No web server, account, or network access.
final class SpriteFrames {
    let idle: [NSImage]
    let walk: [NSImage]
    let run: [NSImage]
    let idlePixels: [NSBitmapImageRep]
    let walkPixels: [NSBitmapImageRep]
    let runPixels: [NSBitmapImageRep]
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

final class PetView: NSView {
    weak var owner: PetController?
    var frames: SpriteFrames!
    var frameIndex = 0
    var walking = false
    var running = false
    var facesLeft = false
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
        let sequence = walking ? (running ? frames.run : frames.walk) : frames.idle
        return sequence[frameIndex % sequence.count]
    }
    var currentPixels: NSBitmapImageRep {
        let sequence = walking ? (running ? frames.runPixels : frames.walkPixels) : frames.idlePixels
        return sequence[frameIndex % sequence.count]
    }
    func setMovement(walking nextWalking: Bool, running nextRunning: Bool, left: Bool) {
        if walking != nextWalking || running != nextRunning || (nextWalking && left != facesLeft) {
            previousImage = currentImage; previousMirrored = walking && facesLeft; transitionAge = 0
            walking = nextWalking; running = nextRunning; facesLeft = left; frameIndex = 0
        }
    }

    var actorRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: bounds.width * 208 / 192) }
    var bounce: CGFloat {
        greetingAge < 0.75 ? CGFloat(abs(sin(greetingAge / 0.75 * .pi * 2))) * bounds.width * 0.035 : 0
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
        if greetingAge < 2.8 && !speech.isEmpty {
            let font = NSFont.systemFont(ofSize: max(11, min(14, bounds.width / 15)), weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1)]
            let size = (speech as NSString).size(withAttributes: attrs)
            let box = NSRect(x: (bounds.width - size.width - 24) / 2, y: actorRect.maxY + 8, width: size.width + 24, height: size.height + 15)
            NSColor(srgbRed: 0.12, green: 0.16, blue: 0.24, alpha: 0.96).setFill()
            NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
            (speech as NSString).draw(at: NSPoint(x: box.minX + 12, y: box.minY + 7), withAttributes: attrs)
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
        if !moved { owner?.greet() }
        owner?.savePosition()
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
    private var runningMode = false
    private var speed: CGFloat = 0
    private var nextWalk: TimeInterval = 0
    private var walkClock: TimeInterval = 0
    private var autoWalk = UserDefaults.standard.object(forKey: "freeRoam") == nil ? true : UserDefaults.standard.bool(forKey: "freeRoam")
    private var quiet = UserDefaults.standard.bool(forKey: "quiet")
    private var suspended = false
    private var scale: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "petWidth")
        return saved > 0 ? min(320, max(144, saved)) : 208
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let resources = Bundle.main.resourceURL else { throw NSError(domain: "Susu", code: 3) }
            frames = try SpriteFrames(resources: resources)
        } catch {
            let alert = NSAlert(); alert.messageText = "溯溯没有找到完整素材"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        let size = panelSize(scale)
        panel = PetPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "溯溯"; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        pet = PetView(frame: NSRect(origin: .zero, size: size)); pet.owner = self; pet.frames = frames
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
        if CommandLine.arguments.contains("--smoke-test") {
            // Exercise the actual drawing and alpha hit testing without staying resident.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.smokeTest() }
        }
    }

    private func panelSize(_ width: CGFloat) -> NSSize { NSSize(width: width, height: width * 208 / 192 + 52) }

    func move(to point: NSPoint) {
        guard panel != nil else { return }
        let sprite = NSSize(width:panel.frame.width,height:panel.frame.width*208/192)
        let allowed = DesktopBounds.constrain(point, sprite:sprite, core:frames.safetyCore,
                                               screens:NSScreen.screens.map(\.visibleFrame))
        panel.setFrameOrigin(allowed)
    }
    func savePosition() {
        UserDefaults.standard.set(panel.frame.minX, forKey: "positionX")
        UserDefaults.standard.set(panel.frame.minY, forKey: "positionY")
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now-lastTick)); lastTick = now
        guard !suspended, panel.isVisible else { return }
        if let destination = target, !pet.dragging {
            let dx = destination.x-panel.frame.minX, dy = destination.y-panel.frame.minY
            let distance = hypot(dx,dy)
            if distance < 1.2 { stopWalking(); savePosition() }
            else {
                let nominal = (runningMode ? CGFloat(95) : CGFloat(24)) * scale / 208
                let desired = nominal * min(1,max(0.20,distance/30))
                speed += (desired-speed)*min(1,CGFloat(dt)*5)
                let step = min(distance, speed*CGFloat(dt))
                let before = panel.frame.origin
                move(to:NSPoint(x:before.x+dx/distance*step,y:before.y+dy/distance*step))
                // An unplugged display or an unreachable gap must not trap the fox in an endless walk.
                if step > 0.05 && hypot(panel.frame.minX-before.x,panel.frame.minY-before.y) < 0.01 { stopWalking() }
                walkClock += dt * Double(max(0.20,speed/nominal))
            }
        } else if autoWalk && !quiet && !pet.dragging && now > nextWalk {
            startJourney(running: Int.random(in:0..<5) == 0)
        }
        let walking = target != nil
        let left = target.map { $0.x < panel.frame.minX } ?? pet.facesLeft
        pet.setMovement(walking:walking,running:walking && runningMode,left:left)
        pet.transitionAge += dt
        let index: Int
        if quiet { index = 0 }
        else if walking { index = Int(walkClock/(runningMode ? 0.080 : 0.20)) % 8 }
        else {
            index = Int((now-startTime)/0.38) % frames.idle.count
        }
        let wasGreeting = pet.greetingAge < 2.8
        pet.greetingAge = quiet ? 100 : now-greetingStart
        if pet.frameIndex != index || pet.transitionAge < 0.20 || wasGreeting || pet.greetingAge < 2.8 {
            pet.frameIndex = index; pet.walking = walking; pet.needsDisplay = true
        }
        let local = pet.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        panel.ignoresMouseEvents = !pet.dragging && !pet.containsPet(local)
    }

    func stopWalking() { target = nil; speed = 0; nextWalk = ProcessInfo.processInfo.systemUptime + Double.random(in: 8...18) }
    @objc func walkOnce() {
        startJourney(running:false)
    }
    @objc func runOnce() { startJourney(running:true) }
    private func startJourney(running: Bool) {
        guard !quiet, !pet.dragging, let screen = NSScreen.screens.randomElement() else { return }
        let area = screen.visibleFrame
        // Independent x/y destinations across the desktop; no small roaming enclosure.
        let raw = NSPoint(x:CGFloat.random(in:(area.minX-scale*0.7)...(area.maxX-scale*0.3)),
                          y:CGFloat.random(in:(area.minY-scale*0.6)...(area.maxY-scale*0.5)))
        let sprite = NSSize(width:scale,height:scale*208/192)
        var destination = DesktopBounds.constrain(raw,sprite:sprite,core:frames.safetyCore,screens:NSScreen.screens.map(\.visibleFrame))
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

    func greet(text: String? = nil) {
        guard !quiet else { return }
        greetingStart = ProcessInfo.processInfo.systemUptime
        pet.speech = text ?? ["我在呢。", "找到你啦！", "陪你慢慢来。", "线索收到！"].randomElement()!
        pet.needsDisplay = true
    }
    @objc func sayHello() { greet() }
    @objc func toggleAuto() { autoWalk.toggle(); UserDefaults.standard.set(autoWalk, forKey: "freeRoam"); if !autoWalk { stopWalking() }; refreshMenu() }
    @objc func toggleQuiet() {
        quiet.toggle(); UserDefaults.standard.set(quiet, forKey: "quiet")
        stopWalking(); pet.frameIndex = 0; pet.greetingAge = 100; pet.needsDisplay = true; refreshMenu()
    }
    @objc func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil); stopWalking() } else { panel.orderFrontRegardless(); greet() }
        refreshMenu()
    }
    @objc func resize(_ item: NSMenuItem) {
        scale = CGFloat(item.tag)
        let origin = panel.frame.origin
        panel.setContentSize(panelSize(scale)); move(to: origin)
        UserDefaults.standard.set(Double(scale), forKey: "petWidth"); pet.needsDisplay = true
        refreshMenu(); savePosition()
    }
    @objc func resetPosition() {
        stopWalking()
        if let area = NSScreen.main?.visibleFrame { move(to: NSPoint(x: area.maxX-panel.frame.width-40, y: area.minY+10)) }
        panel.orderFrontRegardless(); savePosition(); refreshMenu()
    }
    @objc func showHelp() {
        let alert = NSAlert(); alert.messageText = "溯溯 · 桌面版 1.1"
        alert.informativeText = "点击：溯溯回应你\n拖动：在桌面自由摆放，可部分移出屏幕\n右键或菜单栏爪印：优雅散步、跑一圈、自由活动、大小、安静模式与退出\n\n自由活动默认开启，以慢走为主、偶尔跑步。始终保留一小块身体在屏幕内；选择‘回到主屏幕’可以找回。安静模式会停止摇尾巴与其他动作。\n\n本机运行，无需联网或账号。"
        alert.addButton(withTitle: "知道啦"); alert.runModal()
    }
    @objc func screenChanged() { stopWalking(); move(to: panel.frame.origin) }
    @objc func sleeping() { suspended = true; stopWalking() }
    @objc func waking() { suspended = false; lastTick = ProcessInfo.processInfo.systemUptime }
    @objc func quit() { NSApp.terminate(nil) }
    private func refreshMenu() { status.menu = makeMenu() }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self
            if let checked { entry.state = checked ? .on : .off }; menu.addItem(entry)
        }
        let name = NSMenuItem(title: "溯溯 · 陪你慢慢来", action: nil, keyEquivalent: ""); name.isEnabled = false; menu.addItem(name)
        menu.addItem(.separator())
        item("打个招呼", #selector(sayHello))
        item("散步一会儿", #selector(walkOnce))
        item("跑一圈", #selector(runOnce))
        item("自由活动", #selector(toggleAuto), checked: autoWalk)
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
                guard hypot(actual.x-expected.x,actual.y-expected.y)<1 else {
                    throw NSError(domain:"SusuBoundary",code:1,userInfo:[NSLocalizedDescriptionKey:"Native window clamp: expected \(expected), actual \(actual)"])
                }
                let core = frames.safetyCore
                let body = NSRect(x:panel.frame.minX+core.minX*sprite.width,y:panel.frame.minY+core.minY*sprite.height,width:core.width*sprite.width,height:core.height*sprite.height)
                let keep = min(20,min(body.width,body.height))
                guard screens.contains(where: { let visible = $0.intersection(body); return visible.width >= keep-0.1 && visible.height >= keep-0.1 }) else {
                    throw NSError(domain:"SusuBoundary",code:2,userInfo:[NSLocalizedDescriptionKey:"Opaque body patch left the display: \(body)"])
                }
            }
            move(to:original)
            print("PASS: 22 frames loaded; tail poses, walk and run in both directions rendered; opaque input and click-through checked; native window moved partially off-screen at all four corners while keeping an opaque body patch visible.")
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
