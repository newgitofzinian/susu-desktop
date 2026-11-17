import Foundation

struct JournalEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
    var note = ""
}
struct CompanionSave: Codable {
    var version = 1
    var identity = UUID()
    var foodCounts = [0,0,0]
    var journal: [JournalEntry] = []
    var handledTasks: [String] = []
    var recordedKeys: [String] = []
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
        try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:file.path) {
            save = try decoder.decode(CompanionSave.self,from:Data(contentsOf:file))
            try validate(save)
        } else { try commit(save) }
    }
    private func validate(_ value: CompanionSave) throws {
        guard value.version == 1, value.foodCounts.count == 3,
              value.foodCounts.allSatisfy({ $0 >= 0 && $0 <= 1_000_000 }),
              value.journal.count <= 10000, value.handledTasks.count <= 100000,
              Set(value.journal.map(\.id)).count == value.journal.count else {
            throw NSError(domain:"SusuSave",code:1,userInfo:[NSLocalizedDescriptionKey:"存档格式或数据范围无效，原存档已保留。"])
        }
    }
    private func commit(_ next: CompanionSave) throws {
        try validate(next)
        try encoder.encode(next).write(to:file,options:.atomic)
        save = next
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
