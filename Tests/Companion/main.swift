import Foundation
import Darwin
let directory=FileManager.default.temporaryDirectory.appendingPathComponent("susu-store-test-"+UUID().uuidString)
let first=try CompanionStore(directory:directory)
try first.feed(0);try first.feed(0);try first.feed(1)
let second=try CompanionStore(directory:directory)
precondition(second.save.foodCounts==[2,1,0] && second.preferred(0,1)==0)
let firstEntry=second.save.journal[0]
try second.updateNote(id:firstEntry.id,note:"一起慢慢来")
try second.record("pinecone",text:"松果")
let data=try second.exportData()
let imported=try CompanionStore(directory:directory.appendingPathComponent("imported"))
try imported.importData(data)
precondition(imported.save.identity==second.save.identity && imported.save.journal[0].note=="一起慢慢来")
let unchanged=try imported.exportData()
do {try imported.importData(Data("broken".utf8));fatalError("Invalid import accepted")} catch {}
let afterFailure=try imported.exportData()
precondition(afterFailure==unchanged)
try imported.deleteEntry(id:firstEntry.id);try imported.record("first-food",text:"duplicate")
precondition(imported.save.journal.count==1)
let event=TaskEvent(id:"task-1",name:"test",status:"success",pid:1,exitCode:0)
try imported.handleTask(event);try imported.handleTask(event)
precondition(imported.save.handledTasks==["task-1"])
try imported.clearFood();try imported.feed(1);precondition(imported.preferred(0,1)==1)
print("PASS: food preference reload, journal edits/deletion/dedup, migration identity, corrupt import preservation, completed task dedup.")

// Import and migrate an actual 2.0-shaped JSON document.
var legacy = try JSONSerialization.jsonObject(with:data) as! [String:Any]
legacy["version"] = 1
legacy.removeValue(forKey:"activities")
let legacyData = try JSONSerialization.data(withJSONObject:legacy,options:.sortedKeys)
let legacyFolder=directory.appendingPathComponent("legacy")
try FileManager.default.createDirectory(at:legacyFolder,withIntermediateDirectories:true)
try legacyData.write(to:legacyFolder.appendingPathComponent("save.json"))
let migrated=try CompanionStore(directory:legacyFolder)
precondition(migrated.save.identity==second.save.identity && migrated.save.foodCounts==[2,1,0])
precondition(migrated.save.version==3 && migrated.save.activities.cues.isEmpty)
let originalBackup=try Data(contentsOf:legacyFolder.appendingPathComponent("save-2.0-backup.json"))
precondition(originalBackup==legacyData)

try migrated.saveCue(name:"收工啦",actions:["stretch","play"])
let cueID=migrated.save.activities.cues[0].id
try migrated.saveCue(id:cueID,name:"收工啦",actions:["play","stretch"])
let reloaded=try CompanionStore(directory:legacyFolder)
precondition(reloaded.save.activities.cues[0].actions==["play","stretch"])
try reloaded.deleteCue(id:cueID)
precondition(reloaded.save.activities.cues.isEmpty)
let beforeInvalidCue=try reloaded.exportData()
do {try reloaded.saveCue(name:"错误",actions:["unknown"]);fatalError("Bad action accepted")} catch {}
let afterInvalidCue=try reloaded.exportData();precondition(beforeInvalidCue==afterInvalidCue)

let now=Date(timeIntervalSince1970:10000)
try reloaded.startExpedition(route:"river",now:now,duration:60)
let tripNotDue=try reloaded.settleActivities(now:now.addingTimeInterval(59));precondition(!tripNotDue)
let tripRestart=try CompanionStore(directory:legacyFolder)
let tripSettled=try tripRestart.settleActivities(now:now.addingTimeInterval(61));precondition(tripSettled)
let repeatSettled=try tripRestart.settleActivities(now:now.addingTimeInterval(100));precondition(!repeatSettled)
precondition(tripRestart.save.activities.collection["河岸鹅卵石"]==1)
try tripRestart.startExpedition(route:"forest",now:now,duration:1)
try tripRestart.settleActivities(now:now.addingTimeInterval(2))
precondition(tripRestart.save.activities.collection["松林松果"]==1)

for i in 0..<3 {try tripRestart.saveCard(question:"题目 \(i)",answer:"答案 \(i)")}
let cards=tripRestart.save.activities.cards
try tripRestart.reviewCard(id:cards[0].id,remembered:true)
try tripRestart.reviewCard(id:cards[2].id,remembered:true)
precondition(tripRestart.nextCard()?.id==cards[1].id)
precondition(tripRestart.nextCard(excluding:cards[1].id)?.id==cards[1].id)
try tripRestart.deleteCard(id:cards[1].id)
let cardsReload=try CompanionStore(directory:legacyFolder)
precondition(!cardsReload.save.activities.cards.contains{$0.id==cards[1].id})

try cardsReload.saveLetter(body:"明天继续",due:now.addingTimeInterval(60),now:now)
let letterID=cardsReload.save.activities.letters[0].id
try cardsReload.saveLetter(id:letterID,body:"从图三继续",due:now.addingTimeInterval(120),now:now)
let notDue=try cardsReload.settleActivities(now:now.addingTimeInterval(80));precondition(!notDue)
let letterReload=try CompanionStore(directory:legacyFolder)
try letterReload.settleActivities(now:now.addingTimeInterval(121))
precondition(letterReload.unreadLetters.count==1 && letterReload.unreadLetters[0].body=="从图三继续")
let delivered=letterReload.unreadLetters[0].deliveredAt
try letterReload.settleActivities(now:now.addingTimeInterval(200))
precondition(letterReload.unreadLetters[0].deliveredAt==delivered)
try letterReload.readLetter(id:letterID)
precondition(letterReload.unreadLetters.isEmpty && letterReload.save.activities.letters.count==1)
try letterReload.saveLetter(body:"可以取消",due:now.addingTimeInterval(30),now:now)
let cancelledID=letterReload.save.activities.letters.last!.id
try letterReload.deleteLetter(id:cancelledID)
try letterReload.settleActivities(now:now.addingTimeInterval(200))
precondition(!letterReload.save.activities.letters.contains{$0.id==cancelledID})
let wholeSave=try letterReload.exportData()
let moved=try CompanionStore(directory:directory.appendingPathComponent("moved-2.1"))
try moved.importData(wholeSave)
precondition(moved.save.identity==letterReload.save.identity && moved.save.activities.cards.count==2 && moved.save.activities.letters.count==1)
print("PASS: 2.0 save migration/backup; cues CRUD/restart; both expedition routes and idempotent offline settlement; cards priority/deletion; scheduled letters edit/cancel/deliver/read; full 2.1 migration.")
var missingSection=try JSONSerialization.jsonObject(with:wholeSave) as! [String:Any]
missingSection.removeValue(forKey:"activities")
let malformedV2=try JSONSerialization.data(withJSONObject:missingSection)
let beforeMissingSection=try moved.exportData()
do {try moved.importData(malformedV2);fatalError("Incomplete version-2 save accepted")} catch {}
let afterMissingSection=try moved.exportData()
precondition(beforeMissingSection==afterMissingSection)
print("PASS: incomplete version-2 saves preserve existing progress.")

var studioState=moved.save.studio
studioState.furniture["cushion"]=FurniturePosition(x:0.62,y:0.20)
studioState.scarf="teal"
studioState.looks=[SavedLook(name:"学习日",scarf:"teal")]
studioState.chat.memories=["喜欢湖绿色围巾"]
try moved.saveStudio(studioState)
let studioReload=try CompanionStore(directory:directory.appendingPathComponent("moved-2.1"))
precondition(studioReload.save.studio.furniture["cushion"]?.x==0.62 && studioReload.save.studio.scarf=="teal")
precondition(studioReload.save.studio.chat.memories==["喜欢湖绿色围巾"])
let studioExport=try studioReload.exportData()
let studioMigrated=try CompanionStore(directory:directory.appendingPathComponent("moved-2.2"))
try studioMigrated.importData(studioExport)
precondition(studioMigrated.save.identity==studioReload.save.identity && studioMigrated.save.studio.looks[0].name=="学习日")
var legacy21=try JSONSerialization.jsonObject(with:studioExport) as! [String:Any]
legacy21["version"]=2;legacy21.removeValue(forKey:"studio")
let legacy21Dir=directory.appendingPathComponent("legacy21")
try FileManager.default.createDirectory(at:legacy21Dir,withIntermediateDirectories:true)
try JSONSerialization.data(withJSONObject:legacy21).write(to:legacy21Dir.appendingPathComponent("save.json"))
let upgraded21=try CompanionStore(directory:legacy21Dir)
precondition(upgraded21.save.identity==studioReload.save.identity && upgraded21.save.activities.cards.count==2)
precondition(FileManager.default.fileExists(atPath:legacy21Dir.appendingPathComponent("save-2.1-backup.json").path))
var invalidStudio=studioMigrated.save.studio
invalidStudio.furniture["cushion"]=FurniturePosition(x:5,y:5)
let beforeInvalidStudio=try studioMigrated.exportData()
do {try studioMigrated.saveStudio(invalidStudio);fatalError("Invalid furniture accepted")}catch{}
let afterInvalidStudio=try studioMigrated.exportData();precondition(beforeInvalidStudio==afterInvalidStudio)
print("PASS: furniture/outfit/memory persistence, full 2.2 migration, automatic 2.1 backup and invalid layout preservation.")

precondition(studioReload.save.studio.season == .winter,"Legacy scarves remain winter outfits")
let beforeSeasonSelection=try studioMigrated.exportData()
for season in PetSeason.allCases {
    var state=studioMigrated.save.studio
    state.scarf=season.rawValue;state.looks=[SavedLook(name:season.title,scarf:season.rawValue)]
    try studioMigrated.saveStudio(state)
    let reload=try CompanionStore(directory:studioMigrated.directory)
    precondition(reload.save.studio.season==season && reload.save.studio.looks[0].scarf==season.rawValue)
    let transfer=try CompanionStore(directory:directory.appendingPathComponent("season-"+season.rawValue))
    try transfer.importData(reload.exportData())
    precondition(transfer.save.identity==reload.save.identity && transfer.save.studio.season==season)
}
let seasonBackup=try Data(contentsOf:studioMigrated.directory.appendingPathComponent("save-before-seasons-backup.json"))
precondition(seasonBackup==beforeSeasonSelection)
var invalidSeason=studioMigrated.save.studio;invalidSeason.scarf="unknown-season"
let beforeSeasonFailure=try studioMigrated.exportData()
do{try studioMigrated.saveStudio(invalidSeason);fatalError("Unknown season accepted")}catch{}
let afterSeasonFailure=try studioMigrated.exportData();precondition(afterSeasonFailure==beforeSeasonFailure)
print("PASS: four seasonal outfits and saved looks survive reload/export/import; legacy scarf IDs resolve to winter; invalid season preserves save.")

let recoveryDir = directory.appendingPathComponent("recovery")
try FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
let sourceSaveURL = recoveryDir.appendingPathComponent("save.json")
for unusable in [Data("{oops\n".utf8), malformedV2] {
    try unusable.write(to: sourceSaveURL, options: .atomic)
    let recovered = try CompanionStore(directory: recoveryDir)
    let backup = try Data(contentsOf: recovered.recoveredBackupURL!)
    precondition(backup == unusable && recovered.save.journal.isEmpty)
    let reopened = try CompanionStore(directory: recoveryDir)
    precondition(reopened.recoveredBackupURL == nil)
}
let future = Data("{\"version\":999,\"futureShape\":true}".utf8)
try future.write(to: sourceSaveURL, options: .atomic)
do { _ = try CompanionStore(directory: recoveryDir); fatalError("Future save should require a matching app") } catch {}
let preservedFuture = try Data(contentsOf: sourceSaveURL)
precondition(preservedFuture == future)
print("PASS: unreadable and invalid local saves are backed up byte-for-byte, future format stays intact.")

let taskStore = try CompanionStore(directory: directory.appendingPathComponent("task-cleanup"))
let spool = taskStore.directory.appendingPathComponent("tasks")
try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
func publish(_ event: TaskEvent) throws -> URL {
    let path = spool.appendingPathComponent(event.id + ".json")
    try JSONEncoder().encode(event).write(to: path, options: .atomic)
    return path
}
let latestTask = TaskEvent(id: "a", name: "latest", status: "failure", pid: 1, date: Date(timeIntervalSince1970: 300), exitCode: 1)
let olderTask = TaskEvent(id: "b", name: "earlier", status: "success", pid: 1, date: Date(timeIntervalSince1970: 200), exitCode: 0)
let latestFile = try publish(latestTask)
let olderFile = try publish(olderTask)
let reused = TaskEvent(id: "c", name: "orphan", status: "running", pid: getpid(), date: Date(timeIntervalSince1970: 100), exitCode: nil, processStartTime: 100)
let orphanFile = try publish(reused)
precondition(!taskStore.taskProcessIsAlive(reused))
if let start = processStartTime(getpid()) {
    let running = TaskEvent(id: "d", name: "running", status: "running", pid: getpid(), exitCode: nil, processStartTime: start)
    precondition(taskStore.taskProcessIsAlive(running))
}

let taskSave = taskStore.directory.appendingPathComponent("save.json")
let heldSave = taskStore.directory.appendingPathComponent("hold.json")
try FileManager.default.moveItem(at: taskSave, to: heldSave)
try FileManager.default.createDirectory(at: taskSave, withIntermediateDirectories: false)
do { _ = try taskStore.pollTaskEvents(); fatalError("Task commit should fail") } catch {}
precondition(FileManager.default.fileExists(atPath: latestFile.path) && taskStore.save.handledTasks.isEmpty)
try FileManager.default.removeItem(at: taskSave)
try FileManager.default.moveItem(at: heldSave, to: taskSave)
let processed = try taskStore.pollTaskEvents()
precondition(processed.map(\.id) == ["c", "b", "a"] && processed.first?.status == "cancelled")
precondition([latestFile, olderFile, orphanFile].allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
let afterRelaunch = try CompanionStore(directory: taskStore.directory)
precondition(afterRelaunch.save.lastTask?.id == latestTask.id)
_ = try publish(olderTask)
let duplicate = try afterRelaunch.pollTaskEvents()
precondition(duplicate.isEmpty && afterRelaunch.save.handledTasks.count == 3 && !FileManager.default.fileExists(atPath: olderFile.path))
var oldTaskSave = afterRelaunch.save
oldTaskSave.lastTask = nil
try afterRelaunch.commit(oldTaskSave)
_ = try publish(latestTask)
let migratedResult = try afterRelaunch.pollTaskEvents()
precondition(migratedResult.isEmpty && afterRelaunch.save.lastTask?.id == latestTask.id)
print("PASS: batch task cleanup follows successful commit, orphaned PID is cancelled, latest result and dedup survive restart.")

do {
    var planCalendar = Calendar(identifier: .gregorian)
    planCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let planNow = planCalendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
    let taskIntent = TaskLanguage.interpret("明天下午三点交报告，提前十分钟叫我", presets: [], now: planNow, calendar: planCalendar)
    guard case .plan(let taskTitle, let deadline?, let reminder?) = taskIntent else { fatalError("Expected a scheduled task") }
    precondition(taskTitle == "交报告" && planCalendar.component(.day, from: deadline) == 20 &&
                 planCalendar.component(.hour, from: deadline) == 15 && deadline.timeIntervalSince(reminder) == 600)
    let relativeTask = TaskLanguage.interpret("二十分钟后提醒我休息", presets: [], now: planNow, calendar: planCalendar)
    precondition(relativeTask == .plan(title: "休息", due: planNow.addingTimeInterval(1200), reminder: planNow.addingTimeInterval(1200)))
    precondition(TaskLanguage.interpret("记一下，把实验图整理好", presets: [], now: planNow) ==
                 .plan(title: "把实验图整理好", due: nil, reminder: nil))
    guard case .clarify = TaskLanguage.interpret("晚点提醒我交报告", presets: [], now: planNow),
          case .clarify = TaskLanguage.interpret("11月20日上午9点交报告", presets: [], now: planNow) else {
        fatalError("Ambiguous times need clarification")
    }
    let action = ProjectTaskPreset(name: "项目测试", directory: "/tmp", executable: "/usr/bin/true", arguments: [])
    precondition(TaskLanguage.interpret("跑一下项目测试，完成后提醒我", presets: [action], now: planNow) == .run(action.id))
    precondition(TaskLanguage.modelIntent(#"{"kind":"run","actionID":"00000000-0000-0000-0000-000000000000"}"#,
                                         presets: [action], now: planNow) == nil)
    precondition(TaskLanguage.modelIntent(#"{"kind":"run","actionID":"\#(action.id.uuidString)","executable":"/other"}"#,
                                         presets: [action], now: planNow) == .run(action.id))

    let planDirectory = directory.appendingPathComponent("planned-tasks")
    let plans = try CompanionStore(directory: planDirectory)
    let plan = PlannedTask(title: taskTitle, due: deadline, reminder: reminder)
    try plans.addPlannedTask(plan, now: planNow)
    let cancelledPlan = PlannedTask(title: "提前完成", due: deadline, reminder: reminder)
    try plans.addPlannedTask(cancelledPlan, now: planNow)
    try plans.finishPlannedTask(cancelledPlan.id, now: planNow)
    let notDue = try plans.deliverTaskReminders(now: reminder.addingTimeInterval(-1))
    precondition(notDue.isEmpty)
    let restartedPlans = try CompanionStore(directory: planDirectory)
    let duePlans = try restartedPlans.deliverTaskReminders(now: reminder.addingTimeInterval(90))
    precondition(duePlans.map(\.id) == [plan.id])
    let deliveredPlans = try CompanionStore(directory: planDirectory)
    let repeated = try deliveredPlans.deliverTaskReminders(now: deadline)
    precondition(repeated.isEmpty && deliveredPlans.save.plannedTasks.first?.remindedAt != nil)
    try deliveredPlans.deletePlannedTask(plan.id)
    precondition(deliveredPlans.save.plannedTasks.map(\.id) == [cancelledPlan.id])
    print("PASS: Chinese task interpretation, date ambiguity, authorized action lookup, reminder persistence, cancellation and deduplication.")
}
