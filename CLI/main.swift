import Foundation
import Darwin

var childPID: Int32 = 0
var interrupted = false
func relay(_ signalNumber: Int32) {
    interrupted = true
    if childPID>0 { kill(childPID,signalNumber) }
}
var arguments=Array(CommandLine.arguments.dropFirst())
var directory=CompanionStore.defaultDirectory
if arguments.first=="--data-dir", arguments.count>2 {
    directory=URL(fileURLWithPath:arguments[1]);arguments.removeFirst(2)
}
var taskName: String?
if arguments.count >= 5, arguments[0] == "watch", arguments[1] == "--name" {
    taskName = String(arguments[2].prefix(200))
    arguments.removeSubrange(1...2)
}
guard arguments.count >= 3, arguments[0] == "watch", arguments[1] == "--" else {
    fputs("Usage: susu [--data-dir DIR] watch [--name NAME] -- command [arguments]\n", stderr)
    exit(2)
}
let folder=directory.appendingPathComponent("tasks")
do {
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let lockURL=folder.appendingPathComponent("watch.lock")
    let lockFD=open(lockURL.path,O_CREAT|O_RDWR,0o600)
    guard lockFD>=0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
    // An advisory kernel lock is automatically released even after a forced exit.
    var lock=Darwin.flock()
    lock.l_type=Int16(F_WRLCK);lock.l_whence=Int16(SEEK_SET)
    guard fcntl(lockFD,F_SETLK,&lock) != -1 else {fputs("Susu is already watching a task.\n",stderr);exit(3)}
    let identifier=UUID().uuidString
    let command=Array(arguments.dropFirst(2))
    let name = taskName ?? command.joined(separator: " ")
    let eventURL=folder.appendingPathComponent(identifier+".json")
    let watcherPID = getpid()
    let watcherStart = processStartTime(watcherPID)
    func writeEvent(_ status:String,code:Int32?=nil)throws {
        let event=TaskEvent(id:identifier,name:name,status:status,pid:watcherPID,date:Date(),exitCode:code,processStartTime: watcherStart)
        try JSONEncoder().encode(event).write(to:eventURL,options:.atomic)
    }
    signal(SIGINT,relay);signal(SIGTERM,relay)
    let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/env");process.arguments=command
    process.standardInput=FileHandle.standardInput;process.standardOutput=FileHandle.standardOutput;process.standardError=FileHandle.standardError
    try writeEvent("running")
    do { try process.run() } catch { try writeEvent("failure",code:127);throw error }
    childPID=process.processIdentifier
    if interrupted {kill(childPID,SIGTERM)}
    process.waitUntilExit();childPID=0
    let cancelled=interrupted || process.terminationReason == .uncaughtSignal
    let code=cancelled ? Int32(130) : process.terminationStatus
    try writeEvent(cancelled ? "cancelled" : code==0 ? "success" : "failure",code:code)
    close(lockFD);exit(code)
} catch {
    fputs("susu: \(error.localizedDescription)\n",stderr);exit(1)
}
