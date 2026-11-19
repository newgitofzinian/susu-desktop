import Foundation

struct PlannedTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var due: Date?
    var reminder: Date?
    var remindedAt: Date?
    var completedAt: Date?

    var isValid: Bool {
        let validReminder = reminder.map { time in due.map { time <= $0 } ?? false } ?? true
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 200 &&
            [due, reminder, remindedAt, completedAt].compactMap { $0 }.allSatisfy { $0.timeIntervalSince1970.isFinite } &&
            validReminder && (remindedAt == nil || reminder != nil)
    }
}

extension CompanionStore {
    func addPlannedTask(_ task: PlannedTask, now: Date = Date()) throws {
        guard task.isValid, task.due.map({ $0 > now }) ?? true,
              task.reminder.map({ $0 > now }) ?? true, task.remindedAt == nil, task.completedAt == nil else {
            throw taskPlanError("请填写任务名称，并把截止和提醒时间设在未来。")
        }
        var next = save
        next.plannedTasks.append(task)
        try commit(next)
    }

    func finishPlannedTask(_ id: UUID, now: Date = Date()) throws {
        guard let index = save.plannedTasks.firstIndex(where: { $0.id == id && $0.completedAt == nil }) else { return }
        var next = save
        next.plannedTasks[index].completedAt = now
        try commit(next)
    }

    func deletePlannedTask(_ id: UUID) throws {
        var next = save
        next.plannedTasks.removeAll { $0.id == id }
        if next.plannedTasks.count != save.plannedTasks.count { try commit(next) }
    }

    func deliverTaskReminders(now: Date = Date()) throws -> [PlannedTask] {
        var next = save
        let due = next.plannedTasks.indices.filter { index in
            let task = next.plannedTasks[index]
            return task.completedAt == nil && task.remindedAt == nil && (task.reminder.map { $0 <= now } ?? false)
        }
        guard !due.isEmpty else { return [] }
        for index in due { next.plannedTasks[index].remindedAt = now }
        try commit(next)
        return due.map { next.plannedTasks[$0] }
    }
}

struct ProjectTaskPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var directory: String
    var executable: String
    var arguments: [String]

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
        [directory, executable].allSatisfy { $0.hasPrefix("/") && $0.count <= 4096 && !$0.contains("\0") } &&
        arguments.count <= 40 && arguments.reduce(0) { $0 + $1.utf8.count } <= 8192 &&
        arguments.allSatisfy { !$0.contains("\0") }
    }

    func validateFiles() throws {
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        guard isValid, files.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw taskPlanError("请选择存在的项目目录。")
        }
        guard files.fileExists(atPath: executable, isDirectory: &isDirectory), !isDirectory.boolValue,
              files.isExecutableFile(atPath: executable) else {
            throw taskPlanError("请填写可执行文件的绝对路径。")
        }
    }
}

enum TaskIntent: Equatable {
    case plan(title: String, due: Date?, reminder: Date?)
    case run(UUID)
    case clarify(String)
}

enum TaskLanguage {
    private static let numeral = "[0-9零〇一二两三四五六七八九十]+"

    static func interpret(_ text: String, presets: [ProjectTaskPreset], now: Date = Date(),
                          calendar: Calendar = .current) -> TaskIntent {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return .clarify("想让溯溯记住或执行什么？") }
        if match("下个月|月底|周末|[0-9]{4}[-/]\\d|[0-9零一二三四五六七八九十]+(?:月|号)", in: raw) != nil {
            return .clarify("请把日期和时间说得具体些，例如「下周五下午三点」或「后天 15:00」。")
        }
        let lead = match("提前\\s*(\(numeral))\\s*(分钟|小时|天)", in: raw)
        let relative = match("(\(numeral))\\s*(分钟|小时|天)\\s*(?:之?后)", in: raw)
        let hour = match("(凌晨|早上|上午|中午|下午|傍晚|晚上)?\\s*(\(numeral))(?:点|时)(半|一刻|三刻|\(numeral)分?)?|(?<![0-9])([0-9]{1,2}):([0-9]{2})(?![0-9])", in: raw)
        let day = match("今天|明天|后天|(?:(下下|下|本|这)?(?:周|星期)([一二三四五六日天]))", in: raw)
        if recognisesExecution(raw) && relative == nil && hour == nil && day == nil {
            let matches = presets.filter { raw.localizedCaseInsensitiveContains($0.name) }
            if matches.count == 1 { return .run(matches[0].id) }
            return .clarify(matches.isEmpty ? "这句话像是要执行项目动作。请先授权一个动作，再用它的名称交办。" : "找到了多个项目动作。请写出要执行的完整动作名称。")
        }

        var due: Date?
        if let relative, let count = number(relative.groups[1]), count > 0 {
            let unit: Calendar.Component = relative.groups[2] == "天" ? .day : relative.groups[2] == "小时" ? .hour : .minute
            due = calendar.date(byAdding: unit, value: count, to: now)
        } else if let hour, let hours = number(hour.groups[2] ?? hour.groups[4]) {
            let period = hour.groups[1]
            let minuteText = hour.groups[3]
            let minute = minuteText == "半" ? 30 : minuteText == "一刻" ? 15 : minuteText == "三刻" ? 45 :
                number(minuteText?.replacingOccurrences(of: "分", with: "") ?? hour.groups[5]) ?? 0
            var clock = hours
            if ["中午", "下午", "傍晚", "晚上"].contains(period ?? ""), (1...11).contains(clock) { clock += 12 }
            if period == "凌晨" && clock == 12 { clock = 0 }
            if let date = dayDate(day?.groups, now: now, calendar: calendar),
               (0...23).contains(clock), (0...59).contains(minute) {
                due = calendar.date(bySettingHour: clock, minute: minute, second: 0, of: date,
                                    matchingPolicy: .strict)
                if let value = due, !calendar.isDate(value, inSameDayAs: date) { due = nil }
            }
        }
        if (relative != nil || hour != nil || day != nil || lead != nil || raw.contains("提醒") ||
            match("晚点|稍后|今晚|早上|上午|中午|下午|晚上|下班后|下个月|[0-9]月|[0-9]号", in: raw) != nil),
           due == nil {
            return .clarify("具体什么时候？例如「明天下午三点提醒我交报告」或「20 分钟后提醒我休息」。")
        }
        var reminder = due
        if let lead, let count = number(lead.groups[1]), let deadline = due {
            let unit: Calendar.Component = lead.groups[2] == "天" ? .day : lead.groups[2] == "小时" ? .hour : .minute
            reminder = calendar.date(byAdding: unit, value: -count, to: deadline)
        }
        if due.map({ $0 <= now }) == true || reminder.map({ $0 <= now }) == true {
            return .clarify("识别出的时间已经过去了，请指定一个未来的时间。")
        }

        var title = raw
        for part in [lead?.text, relative?.text, hour?.text, day?.text].compactMap({ $0 }) {
            title = title.replacingOccurrences(of: part, with: " ")
        }
        title = title.replacingOccurrences(of: "(?:记一下|记录一下|记个待办|添加待办|提醒我|叫我|叫一声|提醒一下|提前通知)[：:，,、]?", with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard matchesTitle(title) else { return .clarify("具体要做什么？请写明任务名称。") }
        return .plan(title: title, due: due, reminder: reminder)
    }

    static func modelIntent(_ text: String, presets: [ProjectTaskPreset], now: Date = Date()) -> TaskIntent? {
        struct Result: Decodable {
            let kind: String
            let title: String?
            let due: String?
            let reminder: String?
            let actionID: UUID?
            let question: String?
        }
        guard text.count <= 4000, let result = try? JSONDecoder().decode(Result.self, from: Data(text.utf8)) else { return nil }
        switch result.kind {
        case "plan":
            guard let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines), matchesTitle(title) else { return nil }
            let formatter = ISO8601DateFormatter()
            let due = result.due.flatMap { formatter.date(from: $0) }
            let explicitReminder = result.reminder.flatMap { formatter.date(from: $0) }
            let reminder = explicitReminder ?? due
            guard result.due == nil || due != nil, result.reminder == nil || explicitReminder != nil,
                  due.map({ $0 > now }) ?? true, reminder.map({ $0 > now }) ?? true,
                  PlannedTask(title: title, due: due, reminder: reminder).isValid else { return nil }
            return .plan(title: title, due: due, reminder: reminder)
        case "run":
            guard let id = result.actionID, presets.contains(where: { $0.id == id }) else { return nil }
            return .run(id)
        case "clarify":
            guard let question = result.question, !question.isEmpty, question.count <= 180 else { return nil }
            return .clarify(question)
        default: return nil
        }
    }

    private static func recognisesExecution(_ raw: String) -> Bool {
        match("^(?:(?:请|帮我|替我|可以|现在)\\s*)*(?:跑(?:一下|一遍)?|运行|执行|启动|构建|编译|打包|测试)", in: raw) != nil
    }

    private static func matchesTitle(_ title: String) -> Bool {
        !title.isEmpty && title.count <= 200 && title.contains(where: { $0.isLetter || $0.isNumber })
    }

    private static func match(_ pattern: String, in text: String) -> (groups: [String?], text: String)? {
        let input = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: input.length)) else { return nil }
        let groups = (0..<result.numberOfRanges).map { index -> String? in
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : input.substring(with: range)
        }
        return (groups, input.substring(with: result.range))
    }

    private static func number(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        if let value = Int(raw) { return (0...100_000).contains(value) ? value : nil }
        let digits: [Character: Int] = ["零":0, "〇":0, "一":1, "二":2, "两":2, "三":3, "四":4, "五":5, "六":6, "七":7, "八":8, "九":9]
        if raw == "十" { return 10 }
        if let ten = raw.firstIndex(of: "十") {
            let before = raw[..<ten]
            let after = raw[raw.index(after: ten)...]
            guard before.count <= 1, after.count <= 1 else { return nil }
            let tens = before.isEmpty ? 1 : before.first.flatMap { digits[$0] }
            let ones = after.isEmpty ? 0 : after.first.flatMap { digits[$0] }
            if let tens, let ones { return tens * 10 + ones }
        }
        return raw.count == 1 ? raw.first.flatMap { digits[$0] } : nil
    }

    private static func dayDate(_ groups: [String?]?, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let groups else { return today }
        switch groups[0] {
        case "今天": return today
        case "明天": return calendar.date(byAdding: .day, value: 1, to: today)
        case "后天": return calendar.date(byAdding: .day, value: 2, to: today)
        default:
            guard let name = groups[2], let index = ["一","二","三","四","五","六","日","天"].firstIndex(of: name) else { return nil }
            let weekday = (calendar.component(.weekday, from: today) + 5) % 7
            var offset = min(index, 6) - weekday
            if groups[1] == "下" { offset += 7 }
            else if groups[1] == "下下" { offset += 14 }
            else if groups[1] == nil && offset < 0 { offset += 7 }
            return calendar.date(byAdding: .day, value: offset, to: today)
        }
    }
}

func taskPlanError(_ message: String) -> NSError {
    NSError(domain: "SusuTaskPlan", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
