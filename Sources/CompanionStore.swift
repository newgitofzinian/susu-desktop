import Foundation

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

    init() {}
    enum CodingKeys: String, CodingKey {
        case version, identity, foodCounts, journal, handledTasks, recordedKeys, activities, studio
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
    }
}
struct TaskEvent: Codable {
    let id: String
    let name: String
    let status: String
    let pid: Int32
    var date = Date()
    var exitCode: Int32?
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

    init(directory: URL? = nil) throws {
        self.directory = directory ?? Self.defaultDirectory
        encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:file.path) {
            let original = try Data(contentsOf:file)
            save = try decoder.decode(CompanionSave.self,from:original)
            try validate(save)
            try validateActivities(save.activities)
            try validateStudio(save.studio)
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
              Set(value.journal.map(\.id)).count == value.journal.count else {
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
        let next=try decoder.decode(CompanionSave.self,from:data);try commit(next)
    }
    func taskEvents()->[TaskEvent] {
        let folder=directory.appendingPathComponent("tasks")
        let files=(try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []
        return files.filter{$0.pathExtension=="json"}.compactMap{try? decoder.decode(TaskEvent.self,from:Data(contentsOf:$0))}
    }
    func handleTask(_ event:TaskEvent)throws {
        guard ["success","failure","cancelled"].contains(event.status), !save.handledTasks.contains(event.id) else{return}
        var next=save;next.handledTasks.append(event.id)
        if !next.recordedKeys.contains("first-task") {
            next.recordedKeys.append("first-task")
            next.journal.append(JournalEntry(text:"第一次替你等待任务：\(event.name)。"))
        }
        try commit(next)
    }
}
