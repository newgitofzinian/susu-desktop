import Foundation
import Darwin

struct JournalEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
    var note = ""
}
struct CompanionSave: Codable {
    var version = 3
    var identity = UUID()
    var foodCounts = [0,0,0]
    var journal: [JournalEntry] = []
    var handledTasks: [String] = []
    var recordedKeys: [String] = []
    var activities = CompanionActivities()
    var studio = StudioState()
    var lastTask: TaskEvent?
    var plannedTasks: [PlannedTask] = []

    init() {}
    enum CodingKeys: String, CodingKey {
        case version, identity, foodCounts, journal, handledTasks, recordedKeys, activities, studio, lastTask, plannedTasks
    }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy:CodingKeys.self)
        version = try data.decode(Int.self,forKey:.version)
        identity = try data.decode(UUID.self,forKey:.identity)
        foodCounts = try data.decode([Int].self,forKey:.foodCounts)
        journal = try data.decode([JournalEntry].self,forKey:.journal)
        handledTasks = try data.decode([String].self,forKey:.handledTasks)
        recordedKeys = try data.decode([String].self,forKey:.recordedKeys)
        if version >= 2 {
            activities = try data.decode(CompanionActivities.self,forKey:.activities)
        } else {
            activities = try data.decodeIfPresent(CompanionActivities.self,forKey:.activities) ?? CompanionActivities()
        }
        studio = version>=3 ? try data.decode(StudioState.self,forKey:.studio) : StudioState()
        lastTask = try data.decodeIfPresent(TaskEvent.self,forKey:.lastTask)
        plannedTasks = try data.decodeIfPresent([PlannedTask].self, forKey: .plannedTasks) ?? []
    }
}
struct TaskEvent: Codable {
    let id: String
    let name: String
    let status: String
    let pid: Int32
    var date = Date()
    var exitCode: Int32?
    var processStartTime: TimeInterval?
}
func processStartTime(_ pid: Int32) -> TimeInterval? {
    guard pid > 0 else { return nil }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
}
final class CompanionStore {
    static var defaultDirectory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SusuDesktop")
    }
    let directory: URL
    private(set) var save = CompanionSave()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var file: URL { directory.appendingPathComponent("save.json") }
    private(set) var recoveredBackupURL: URL?

    init(directory: URL? = nil) throws {
        self.directory = directory ?? Self.defaultDirectory
        encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:file.path) {
            let original = try Data(contentsOf:file)
            do {
                save = try decoder.decode(CompanionSave.self,from:original)
                try validate(save); try validateActivities(save.activities); try validateStudio(save.studio)
            } catch {
                if let object = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
                   let version = object["version"] as? Int, version > 3 {
                    throw NSError(domain: "SusuSave", code: 5, userInfo: [NSLocalizedDescriptionKey: "这份存档来自更高版本。请用支持该存档的版本打开，原文件已保留。"])
                }
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of:":", with:"-") + "-" + UUID().uuidString
                let backup = self.directory.appendingPathComponent("save-recovered-\(stamp).json")
                try original.write(to: backup, options: .atomic); recoveredBackupURL = backup
                save = CompanionSave(); try commit(save); return
            }
            if save.version < 3 {
                let backup = self.directory.appendingPathComponent(save.version==1 ? "save-2.0-backup.json" : "save-2.1-backup.json")
                if !FileManager.default.fileExists(atPath:backup.path) { try original.write(to:backup,options:.atomic) }
                try commit(save)
            }
        } else { try commit(save) }
    }
    private func validate(_ value: CompanionSave) throws {
        guard [1,2,3].contains(value.version), value.foodCounts.count == 3,
              value.foodCounts.allSatisfy({ $0 >= 0 && $0 <= 1_000_000 }),
              value.journal.count <= 10000, value.handledTasks.count <= 100000,
              Set(value.journal.map(\.id)).count == value.journal.count,
              value.plannedTasks.count <= 1000, value.plannedTasks.allSatisfy(\.isValid),
              Set(value.plannedTasks.map(\.id)).count == value.plannedTasks.count else {
            throw NSError(domain:"SusuSave",code:1,userInfo:[NSLocalizedDescriptionKey:"存档格式或数据范围无效，原存档已保留。"])
        }
    }
    func commit(_ candidate: CompanionSave) throws {
        var next = candidate
        next.version = 3
        try validate(next)
        try validateActivities(next.activities)
        try validateStudio(next.studio)
        let encoded=try encoder.encode(next)
        guard encoded.count<=10_000_000 else{throw NSError(domain:"SusuSave",code:4,userInfo:[NSLocalizedDescriptionKey:"存档空间已满，请先导出备份并清理部分记录。"])}
        try encoded.write(to:file,options:.atomic)
        save = next
    }
    private func validateActivities(_ value: CompanionActivities) throws {
        let commandsValid = value.cues.count <= 100 && value.cues.allSatisfy {
            !$0.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.name.count <= 100 &&
            $0.actions.count == 2 && $0.actions.allSatisfy { ["stretch","play"].contains($0) }
        }
        let cardsValid = value.cards.count <= 5000 && value.cards.allSatisfy {
            !$0.question.isEmpty && !$0.answer.isEmpty && $0.question.count <= 5000 && $0.answer.count <= 10000
        }
        let lettersValid = value.letters.count <= 500 && value.letters.filter { $0.deliveredAt == nil }.count <= 1 && value.letters.allSatisfy {
            !$0.body.isEmpty && $0.body.count <= 10000 && $0.due.timeIntervalSince1970.isFinite &&
            ($0.readAt == nil || $0.deliveredAt != nil)
        }
        let collectionValid = value.collection.allSatisfy {
            ["河岸鹅卵石","松林松果"].contains($0.key) && (0...1_000_000).contains($0.value)
        }
        let tripValid = value.expedition.map {
            ["river","forest"].contains($0.route) && $0.due.timeIntervalSince1970.isFinite
        } ?? true
        guard commandsValid, cardsValid, lettersValid, collectionValid, tripValid,
              Set(value.cues.map(\.id)).count == value.cues.count,
              Set(value.cues.map(\.name)).count == value.cues.count,
              Set(value.cards.map(\.id)).count == value.cards.count,
              Set(value.letters.map(\.id)).count == value.letters.count else {
            throw NSError(domain:"SusuSave",code:3,userInfo:[NSLocalizedDescriptionKey:"新玩法存档内容无效，原存档已保留。"])
        }
    }
    func feed(_ index: Int) throws {
        guard save.foodCounts.indices.contains(index) else { return }
        var next = save
        next.foodCounts[index] += 1
        if !next.recordedKeys.contains("first-food") {
            next.recordedKeys.append("first-food")
            next.journal.append(JournalEntry(text:"第一次收到你递来的点心。"))
        }
        try commit(next)
    }
    func clearFood() throws { var next=save;next.foodCounts=[0,0,0];try commit(next) }
    func preferred(_ first:Int,_ second:Int)->Int {
        if save.foodCounts[first] == save.foodCounts[second] { return Bool.random() ? first : second }
        return save.foodCounts[first] > save.foodCounts[second] ? first : second
    }
    func record(_ key:String,text:String)throws {
        guard !save.recordedKeys.contains(key) else{return}
        var next=save;next.recordedKeys.append(key);next.journal.append(JournalEntry(text:text));try commit(next)
    }
    func updateNote(id:UUID,note:String)throws {
        var next=save
        guard let index=next.journal.firstIndex(where:{$0.id==id}) else{return}
        next.journal[index].note=note;try commit(next)
    }
    func deleteEntry(id:UUID)throws {
        var next=save;next.journal.removeAll{$0.id==id};try commit(next)
    }
    func exportData()throws->Data {try encoder.encode(save)}
    func importData(_ data:Data)throws {
        guard data.count<=10_000_000 else{throw NSError(domain:"SusuSave",code:2)}
        let next = try decoder.decode(CompanionSave.self, from: data)
        try validate(next)
        try commit(next)
    }
    func taskProcessIsAlive(_ event: TaskEvent) -> Bool {
        guard event.status == "running", let actual = processStartTime(event.pid) else { return false }
        if let expected = event.processStartTime { return abs(actual - expected) < 0.000002 }
        // A PID reused after the recorded start cannot belong to an older watcher.
        return actual <= event.date.timeIntervalSince1970
    }
    private func readTask(_ url: URL) -> (TaskEvent, Data)? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let bytes = try? file.read(upToCount: 524_289), bytes.count <= 524_288,
              let event = try? decoder.decode(TaskEvent.self, from: bytes),
              event.id == url.deletingPathExtension().lastPathComponent else { return nil }
        return (event, bytes)
    }

    /// Recheck a suspected orphan while no watcher can publish a replacement result.
    private func readStoppedTask(_ url: URL, folder: URL) -> (TaskEvent, Data)? {
        let fd = open(folder.appendingPathComponent("watch.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var lock = Darwin.flock()
        lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_SETLK, &lock) != -1, let (current, bytes) = readTask(url) else { return nil }
        if current.status != "running" { return (current, bytes) }
        guard !taskProcessIsAlive(current) else { return nil }
        let cancelled = TaskEvent(id: current.id, name: current.name, status: "cancelled", pid: current.pid,
                                  date: current.date, exitCode: nil, processStartTime: current.processStartTime)
        return (cancelled, bytes)
    }

    /// Save the full batch before removing any files. An interrupted cleanup can safely be retried.
    func pollTaskEvents() throws -> [TaskEvent] {
        let folder = directory.appendingPathComponent("tasks")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
        var active: [TaskEvent] = []
        var completed: [(TaskEvent, URL, Data)] = []
        for url in files where url.pathExtension == "json" && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            guard var (event, bytes) = readTask(url) else { continue }
            if event.status == "running" {
                if taskProcessIsAlive(event) { active.append(event); continue }
                guard let latest = readStoppedTask(url, folder: folder) else { continue }
                (event, bytes) = latest
            }
            if ["success", "failure", "cancelled"].contains(event.status) {
                completed.append((event, url, bytes))
            }
        }
        let fresh = try recordCompletedTasks(completed.map { $0.0 })
        for (_, url, bytes) in completed where readTask(url)?.1 == bytes {
            try? FileManager.default.removeItem(at: url)
        }
        return active + fresh
    }

    @discardableResult private func recordCompletedTasks(_ events: [TaskEvent]) throws -> [TaskEvent] {
        guard !events.isEmpty else { return [] }
        func earlier(_ a: TaskEvent, _ b: TaskEvent) -> Bool { a.date == b.date ? a.id < b.id : a.date < b.date }
        var known = Set(save.handledTasks)
        let ordered = events.sorted(by: earlier)
        let fresh = ordered.filter { known.insert($0.id).inserted }
        var next = save
        // A pre-2.8 save may have already handled the event but has no last result field.
        let latest = ordered.last!
        let advancesLast = next.lastTask.map({ earlier($0, latest) }) ?? true
        guard !fresh.isEmpty || advancesLast else { return [] }
        next.handledTasks.append(contentsOf: fresh.map(\.id))
        if advancesLast { next.lastTask = latest }
        if let first = fresh.first, !next.recordedKeys.contains("first-task"), next.journal.count < 10_000 {
            next.recordedKeys.append("first-task")
            next.journal.append(JournalEntry(text:"第一次替你等待任务：\(first.name)。"))
        }
        try commit(next)
        return fresh
    }
    func handleTask(_ event: TaskEvent) throws {
        guard ["success", "failure", "cancelled"].contains(event.status) else { return }
        try recordCompletedTasks([event])
    }
}
