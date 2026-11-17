import Foundation
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
