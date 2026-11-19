import AppKit

final class TaskBoard: NSObject, NSTextFieldDelegate {
    let store: CompanionStore
    private let defaults: UserDefaults
    private static let presetKey = "SusuDesktop.authorizedProjectActions"
    private let client: ChatClient
    var onChange: (() -> Void)?
    var watcherIsRunning: (() -> Bool)?
    var attach: ((NSView, @escaping () -> Bool) -> Void)?
    var isInterpreting: Bool { interpretationID != nil }
    private var interpretationID: UUID?
    private var request: URLSessionDataTask?
    private var launched: Process?
    private var pending: TaskIntent?
    private var pendingAction: ProjectTaskPreset?
    private var presets: [ProjectTaskPreset] = []

    private let view = NSView(frame: NSRect(x: 0, y: 0, width: 476, height: 388))
    private let editor = NSView(frame: NSRect(x: 0, y: 0, width: 476, height: 336))
    private let phrase = NSTextField()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let preview = NSView(frame: NSRect(x: 0, y: 152, width: 476, height: 115))
    private let title = NSTextField()
    private let scheduled = NSButton(checkboxWithTitle: "设定截止与提醒", target: nil, action: nil)
    private let deadline = NSDatePicker()
    private let reminder = NSDatePicker()
    private let accept = NSButton()
    private let saved = NSPopUpButton()
    private let savedDetail = NSTextField(labelWithString: "")
    private let watched = NSTextField(labelWithString: "")
    private let actionList = NSPopUpButton()
    private let actionName = NSTextField()
    private let directory = NSTextField()
    private let executable = NSTextField()
    private let arguments = NSTextView()
    private let authorizationNotice = NSTextField(wrappingLabelWithString: "")
    private var editingID: UUID?

    init(store: CompanionStore, defaults: UserDefaults = .standard, client: ChatClient = ChatClient()) {
        self.store = store
        self.defaults = defaults
        self.client = client
        super.init()
        if let data = defaults.data(forKey: Self.presetKey),
           let entries = try? JSONDecoder().decode([ProjectTaskPreset].self, from: data) {
            presets = Array(entries.filter(\.isValid).prefix(40))
        }
    }

    func show(watched text: String) {
        if view.subviews.isEmpty { build() }
        refreshWatcher(text)
        refreshPlans()
        attach?(view, { [weak self] in self?.isInterpreting == true })
        view.window?.makeKey()
        view.window?.makeFirstResponder(phrase)
    }

    func refreshWatcher(_ text: String) {
        watched.stringValue = text.replacingOccurrences(of: "\n", with: " · ")
        watched.toolTip = text
    }

    func refreshPlans() {
        let previous = saved.selectedItem?.representedObject as? UUID
        saved.removeAllItems()
        saved.addItem(withTitle: "待办与提醒（\(store.save.plannedTasks.filter { $0.completedAt == nil }.count) 条待办）")
        for task in store.save.plannedTasks.reversed() {
            let prefix = task.completedAt != nil ? "✓" : task.remindedAt != nil ? "🔔" : "○"
            saved.addItem(withTitle: "\(prefix) \(task.title.prefix(52))")
            saved.lastItem?.representedObject = task.id
        }
        if let previous, let item = saved.itemArray.first(where: { $0.representedObject as? UUID == previous }) {
            saved.select(item)
        }
        selectPlan()
    }

    private func build() {
        label("任务报信", frame(8, 350, 180, 26), size: 19, weight: .semibold, in: view)
        button("项目动作…", frame(365, 348, 105, 30), #selector(showPresets), in: view)
        field(phrase, "例如：明天下午三点交报告，提前十分钟叫我", frame(8, 310, 371, 29), in: view)
        phrase.delegate = self
        phrase.target = self
        phrase.action = #selector(interpret)
        button("理解", frame(384, 307, 86, 31), #selector(interpret), in: view)
        notice.frame = frame(9, 266, 453, 37)
        notice.font = .systemFont(ofSize: 12)
        notice.textColor = .secondaryLabelColor
        view.addSubview(notice)

        view.addSubview(preview)
        field(title, "任务名称", frame(8, 83, 456, 26), in: preview)
        scheduled.frame = frame(8, 54, 151, 25)
        scheduled.target = self
        scheduled.action = #selector(toggleSchedule)
        preview.addSubview(scheduled)
        for (picker, x, hint) in [(deadline, CGFloat(161), "截止时间"), (reminder, CGFloat(315), "提醒时间")] {
            label(hint, frame(x, 59, 147, 18), size: 11, in: preview)
            picker.frame = frame(x, 30, 147, 27)
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.yearMonthDay, .hourMinute]
            picker.setAccessibilityLabel(hint)
            preview.addSubview(picker)
        }
        accept.title = "确认添加"
        accept.target = self
        accept.action = #selector(confirmIntent)
        accept.bezelStyle = .rounded
        accept.frame = frame(351, 0, 113, 29)
        preview.addSubview(accept)
        clearPreview()
        notice.stringValue = "写一句待办、提醒，或用已授权的项目动作名称交办。"

        saved.frame = frame(8, 112, 456, 29)
        saved.target = self
        saved.action = #selector(selectPlan)
        view.addSubview(saved)
        savedDetail.frame = frame(11, 82, 450, 23)
        savedDetail.font = .systemFont(ofSize: 11)
        savedDetail.lineBreakMode = .byTruncatingTail
        view.addSubview(savedDetail)
        button("标记完成", frame(8, 51, 102, 29), #selector(finishPlan), in: view)
        button("删除待办…", frame(112, 51, 107, 29), #selector(removePlan), in: view)
        button("复制终端交办命令", frame(303, 51, 161, 29), #selector(copyCommand), in: view).isEnabled = TaskTool.command != nil
        watched.frame = frame(10, 18, 452, 24)
        watched.font = .systemFont(ofSize: 12)
        watched.textColor = .secondaryLabelColor
        watched.lineBreakMode = .byTruncatingTail
        view.addSubview(watched)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === phrase else { return }
        request?.cancel()
        request = nil
        interpretationID = nil
        clearPreview()
        notice.stringValue = ""
    }

    @objc private func interpret() {
        let text = (phrase.currentEditor()?.string ?? phrase.stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else {
            notice.stringValue = "请输入 1 到 500 字的任务描述。"
            return
        }
        request?.cancel()
        request = nil
        interpretationID = nil
        clearPreview()
        let local = TaskLanguage.interpret(text, presets: presets)
        let chat = store.save.studio.chat
        guard case .clarify(let question) = local, chat.prefersLocal != true,
              (try? ChatClient.validate(endpoint: chat.endpoint, model: chat.model)) != nil else {
            display(local)
            return
        }

        let actions = presets.map { ["actionID": $0.id.uuidString, "name": $0.name] }
        let data = (try? JSONSerialization.data(withJSONObject: actions)) ?? Data("[]".utf8)
        let schema = """
        从用户输入提取待办、提醒、或立即执行的已授权动作。只回复 JSON 对象。
        待办使用 {"kind":"plan","title":"...","due":null,"reminder":null}，时间为带时区的 ISO 8601 字符串或 null。
        必须明确知道时间才能设置提醒，时间含糊时使用 {"kind":"clarify","question":"..."}。
        仅用户明确要求立即执行时，才能匹配 {"kind":"run","actionID":"已知动作的 ID"}。无法确定就追问。没有授权动作时询问授权。
        现在是 \(ISO8601DateFormatter().string(from: Date()))，本地时区 \(TimeZone.current.identifier)。
        用户已授权的动作名称和 ID：\(String(decoding: data, as: UTF8.self))
        """
        let id = UUID()
        interpretationID = id
        notice.stringValue = "正在用已配置的模型理解这句话…"
        request = client.send(state: chat, text: text, systemPrompt: schema) { [weak self] result in
            guard let self, self.interpretationID == id else { return }
            self.interpretationID = nil
            self.request = nil
            if let message = try? result.get(), let intent = TaskLanguage.modelIntent(message.content, presets: self.presets) {
                self.display(intent)
            } else { self.display(.clarify(question)) }
        }
    }

    private func clearPreview() {
        pending = nil
        pendingAction = nil
        preview.isHidden = true
    }

    private func display(_ intent: TaskIntent) {
        clearPreview()
        switch intent {
        case .clarify(let question): notice.stringValue = question
        case .plan(let name, let due, let time):
            pending = intent
            title.stringValue = name
            scheduled.state = due == nil ? .off : .on
            deadline.dateValue = due ?? Date().addingTimeInterval(3600)
            reminder.dateValue = time ?? deadline.dateValue
            accept.title = "确认添加"
            preview.isHidden = false
            title.isHidden = false
            scheduled.isHidden = false
            deadline.isHidden = false
            reminder.isHidden = false
            preview.subviews.filter { $0 is NSTextField && $0 !== title }.forEach { $0.isHidden = false }
            toggleSchedule()
            notice.stringValue = "我理解成这条待办。名称和时间可以修改。"
        case .run(let id):
            guard let action = presets.first(where: { $0.id == id }) else {
                notice.stringValue = "这个动作需要先在本机授权。"
                return
            }
            pending = intent
            pendingAction = action
            notice.stringValue = "准备运行「\(action.name)」。请核对执行内容。"
            preview.isHidden = false
            preview.subviews.forEach { $0.isHidden = $0 !== accept }
            accept.title = "核对并执行…"
        }
    }

    @objc private func toggleSchedule() {
        let enabled = scheduled.state == .on
        deadline.isEnabled = enabled
        reminder.isEnabled = enabled
    }

    @objc private func confirmIntent() {
        guard let pending else { return }
        do {
            switch pending {
            case .plan:
                let due = scheduled.state == .on ? deadline.dateValue : nil
                let when = due == nil ? nil : reminder.dateValue
                try store.addPlannedTask(PlannedTask(title: title.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     due: due, reminder: when))
                finishDraft("已添加待办。")
                refreshPlans()
                onChange?()
            case .run(let id):
                guard let action = pendingAction, action.id == id, presets.contains(action) else {
                    throw taskPlanError("授权已变更，请重新理解这句话。")
                }
                try launch(action, confirm: true)
            case .clarify: break
            }
        } catch { notice.stringValue = error.localizedDescription }
    }

    private func launch(_ action: ProjectTaskPreset, confirm: Bool) throws {
        guard launched == nil, let tool = TaskTool.executable else { throw taskPlanError("已有项目动作运行中，或交办工具不可用。") }
        guard watcherIsRunning?() != true else {
            throw taskPlanError("已有终端任务运行中，请等它完成。")
        }
        try action.validateFiles()
        if confirm {
            let alert = NSAlert()
            alert.messageText = "执行「\(action.name)」？"
            let args = action.arguments.enumerated().map { "  \($0 + 1). \($1.debugDescription)" }.joined(separator: "\n")
            let details = NSScrollView(frame: frame(0, 0, 340, 150))
            details.borderType = .bezelBorder
            details.hasVerticalScroller = true
            let text = NSTextView(frame: NSRect(origin: .zero, size: details.contentSize))
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.isVerticallyResizable = true
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.textContainer?.containerSize = NSSize(width: details.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            text.string = "项目目录\n\(action.directory)\n\n可执行文件\n\(action.executable)\n\n参数\n\(args.isEmpty ? "无" : args)"
            details.documentView = text
            alert.accessoryView = details
            let cancel = alert.addButton(withTitle: "取消")
            cancel.keyEquivalent = "\r"
            alert.addButton(withTitle: "执行").keyEquivalent = ""
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        try action.validateFiles()
        let process = Process()
        process.executableURL = tool
        process.currentDirectoryURL = URL(fileURLWithPath: action.directory, isDirectory: true)
        process.arguments = ["--data-dir", store.directory.path, "watch", "--name", action.name, "--", action.executable] + action.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launched = nil
                self.onChange?()
                if self.store.save.lastTask?.pid != proc.processIdentifier {
                    self.notice.stringValue = "任务报信没有收到这次运行的结果。请确认当前没有其他终端任务占用。"
                }
            }
        }
        try process.run()
        launched = process
        finishDraft("已交办「\(action.name)」，执行结果会在这里报信。")
    }

    private func finishDraft(_ message: String) {
        clearPreview()
        phrase.stringValue = ""
        phrase.currentEditor()?.string = ""
        notice.stringValue = message
    }

    private var selectedTask: PlannedTask? {
        guard let id = saved.selectedItem?.representedObject as? UUID else { return nil }
        return store.save.plannedTasks.first { $0.id == id }
    }

    @objc private func selectPlan() {
        guard let task = selectedTask else {
            savedDetail.stringValue = "选择上方条目查看时间与状态。"
            savedDetail.toolTip = nil
            return
        }
        let format: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
        savedDetail.stringValue = [
            task.completedAt == nil ? (task.remindedAt == nil ? "待办" : "已提醒") : "已完成",
            task.due.map { "截止 " + format($0) },
            task.reminder.map { "提醒 " + format($0) }
        ].compactMap { $0 }.joined(separator: " · ")
        savedDetail.toolTip = "\(task.title)\n\(savedDetail.stringValue)"
    }

    @objc private func finishPlan() {
        guard let task = selectedTask else { return }
        do { try store.finishPlannedTask(task.id); refreshPlans(); onChange?() }
        catch { notice.stringValue = error.localizedDescription }
    }

    @objc private func removePlan() {
        guard let task = selectedTask,
              confirmDestructiveAction("删除这条待办？", message: task.title) else { return }
        do { try store.deletePlannedTask(task.id); refreshPlans(); onChange?() }
        catch { notice.stringValue = error.localizedDescription }
    }

    @objc private func copyCommand() {
        guard let command = TaskTool.command else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        notice.stringValue = "已复制终端交办命令。"
    }

    @objc private func showPresets() {
        if editor.subviews.isEmpty { buildEditor() }
        refreshPresetList(selecting: editingID)
        attach?(editor, { false })
    }

    private func buildEditor() {
        label("授权项目动作", frame(8, 298, 220, 27), size: 18, weight: .semibold, in: editor)
        button("返回任务报信", frame(335, 296, 131, 31), #selector(returnToBoard), in: editor)
        actionList.frame = frame(8, 260, 456, 28)
        actionList.target = self
        actionList.action = #selector(selectPreset)
        editor.addSubview(actionList)
        field(actionName, "动作名称，例如 项目测试", frame(8, 222, 456, 26), in: editor)
        field(directory, "项目目录的绝对路径", frame(8, 186, 358, 26), in: editor)
        button("选择目录…", frame(370, 182, 95, 32), #selector(browseDirectory), in: editor)
        field(executable, "可执行文件绝对路径，例如 /usr/bin/make", frame(8, 151, 456, 26), in: editor)
        label("参数每行一个，按原样传给程序。", frame(8, 127, 456, 18), size: 11, in: editor)
        let scroller = NSScrollView(frame: frame(8, 61, 456, 64))
        scroller.borderType = .bezelBorder
        scroller.hasVerticalScroller = true
        arguments.frame = NSRect(origin: .zero, size: scroller.contentSize)
        arguments.isVerticallyResizable = true
        arguments.autoresizingMask = [.width]
        arguments.textContainer?.widthTracksTextView = true
        arguments.textContainer?.containerSize = NSSize(width: scroller.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        arguments.isRichText = false
        scroller.documentView = arguments
        editor.addSubview(scroller)
        authorizationNotice.frame = frame(8, 32, 456, 28)
        authorizationNotice.font = .systemFont(ofSize: 11)
        editor.addSubview(authorizationNotice)
        button("删除授权…", frame(8, 0, 108, 30), #selector(removePreset), in: editor)
        button("保存授权", frame(347, 0, 118, 30), #selector(savePreset), in: editor)
    }

    private func refreshPresetList(selecting id: UUID?) {
        actionList.removeAllItems()
        actionList.addItem(withTitle: "新建项目动作")
        for preset in presets {
            actionList.addItem(withTitle: preset.name)
            actionList.lastItem?.representedObject = preset.id
        }
        if let id, let item = actionList.itemArray.first(where: { $0.representedObject as? UUID == id }) { actionList.select(item) }
        selectPreset()
    }

    @objc private func selectPreset() {
        editingID = actionList.selectedItem?.representedObject as? UUID
        let value = presets.first { $0.id == editingID }
        actionName.stringValue = value?.name ?? ""
        directory.stringValue = value?.directory ?? ""
        executable.stringValue = value?.executable ?? ""
        arguments.string = value?.arguments.joined(separator: "\n") ?? ""
        authorizationNotice.stringValue = "保存的是本机的固定动作。每次执行前会展示目录、程序和参数。"
    }

    @objc private func browseDirectory() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        if picker.runModal() == .OK, let path = picker.url?.path { directory.stringValue = path }
    }

    @objc private func savePreset() {
        let value = ProjectTaskPreset(id: editingID ?? UUID(),
            name: actionName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            directory: directory.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            executable: executable.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            arguments: arguments.string.split(separator: "\n").map(String.init))
        do {
            try value.validateFiles()
            var next = presets.filter { $0.id != value.id }
            guard next.count < 40, !next.contains(where: { $0.name.caseInsensitiveCompare(value.name) == .orderedSame }) else {
                throw taskPlanError("请使用不同的动作名称。最多可保存 40 个动作。")
            }
            next.append(value)
            try savePresets(next)
            refreshPresetList(selecting: value.id)
            authorizationNotice.stringValue = "已授权「\(value.name)」。返回后可用动作名称交办。"
        } catch { authorizationNotice.stringValue = error.localizedDescription }
    }

    @objc private func removePreset() {
        guard let id = editingID, let value = presets.first(where: { $0.id == id }),
              confirmDestructiveAction("删除此项目动作的授权？", message: value.name) else { return }
        do { try savePresets(presets.filter { $0.id != id }); refreshPresetList(selecting: nil) }
        catch { authorizationNotice.stringValue = error.localizedDescription }
    }

    private func savePresets(_ list: [ProjectTaskPreset]) throws {
        defaults.set(try JSONEncoder().encode(list), forKey: Self.presetKey)
        presets = list
        clearPreview()
    }

    @objc private func returnToBoard() { show(watched: watched.stringValue) }

    func runChecks(at output: URL) throws {
        show(watched: "测试任务报信")
        let earlier = store.save.plannedTasks.count
        phrase.stringValue = "明天下午三点交报告，提前十分钟叫我"
        phrase.currentEditor()?.string = phrase.stringValue
        interpret()
        precondition(store.save.plannedTasks.count == earlier && !preview.isHidden)
        let calendar = Calendar.current
        precondition(calendar.component(.hour, from: deadline.dateValue) == 15)
        precondition(deadline.dateValue.timeIntervalSince(reminder.dateValue) == 600)
        if let root = view.window?.contentView,
           let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("task-board.png"))
        }
        confirmIntent()
        precondition(store.save.plannedTasks.last?.title == "交报告")

        let file = "task preset test marker"
        let marker = store.directory.appendingPathComponent(file)
        let action = ProjectTaskPreset(name: "项目测试", directory: store.directory.path,
                                       executable: "/usr/bin/touch", arguments: [file])
        try savePresets([action])
        precondition(try! JSONDecoder().decode([ProjectTaskPreset].self,
                                             from: defaults.data(forKey: Self.presetKey)!) == [action])
        phrase.stringValue = "帮我跑一下项目测试，完成后告诉我"
        phrase.currentEditor()?.string = phrase.stringValue
        interpret()
        precondition(pending == .run(action.id) && pendingAction == action)
        precondition(!FileManager.default.fileExists(atPath: marker.path))
        try launch(action, confirm: false)
        let limit = Date().addingTimeInterval(5)
        while launched != nil && Date() < limit { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        precondition(launched == nil && FileManager.default.fileExists(atPath: marker.path))
        precondition(store.save.lastTask?.name == action.name && store.save.lastTask?.status == "success")
        defaults.removeObject(forKey: Self.presetKey)
        print("PASS: desktop task preview, explicit confirmation, authorized argv and cwd, persistent preset and watcher result.")
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }

    private func label(_ text: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, in parent: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.frame = rect
        parent.addSubview(label)
    }

    private func field(_ input: NSTextField, _ placeholder: String, _ rect: NSRect, in parent: NSView) {
        input.placeholderString = placeholder
        input.setAccessibilityLabel(placeholder)
        input.frame = rect
        parent.addSubview(input)
    }

    @discardableResult
    private func button(_ title: String, _ rect: NSRect, _ action: Selector, in parent: NSView) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = rect
        parent.addSubview(button)
        return button
    }
}
