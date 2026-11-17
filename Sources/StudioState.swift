import Foundation

struct FurniturePosition: Codable {
    var x: Double
    var y: Double
}
struct ScarfPack: Codable, Identifiable {
    var id = UUID()
    var name: String
    var idle: [Data]
    var walking: [Data]
}
struct SavedLook: Codable, Identifiable {
    var id = UUID()
    var name: String
    var scarf: String
}
struct StudioState: Codable {
    var furniture: [String:FurniturePosition] = [
        "cushion":FurniturePosition(x:0.57,y:0.15),
        "shelf":FurniturePosition(x:0.12,y:0.48),
        "lamp":FurniturePosition(x:0.80,y:0.49)
    ]
    var scarf = "none"
    var packs: [ScarfPack] = []
    var looks: [SavedLook] = []
    var chat = ChatState()
}

extension CompanionStore {
    func saveStudio(_ state: StudioState) throws {
        var next = save
        next.studio = state
        try commit(next)
    }
    func validateStudio(_ state: StudioState) throws {
        let furnitureValid = (state.furniture["cushion"]?.y ?? 1)<=0.35 && Set(state.furniture.keys) == Set(["cushion","shelf","lamp"]) && state.furniture.values.allSatisfy {
            $0.x.isFinite && $0.y.isFinite && (0...0.82).contains($0.x) && (0...0.72).contains($0.y)
        }
        let allFrames = state.packs.flatMap { $0.idle + $0.walking }
        let packagesValid = state.packs.count<=8 && state.packs.allSatisfy {
            !$0.name.isEmpty && $0.name.count<=80 && $0.idle.count==6 && $0.walking.count==8
        } && allFrames.reduce(0,{$0+$1.count})<=4_000_000 && allFrames.allSatisfy(Self.validOverlayHeader)
        let allowed = ["none","teal","amber","rose"] + state.packs.map{$0.id.uuidString}
        let looksValid = state.looks.count<=100 && state.looks.allSatisfy {
            !$0.name.isEmpty && $0.name.count<=80 && allowed.contains($0.scarf)
        }
        let chat = state.chat
        let chatValid = chat.endpoint.count<=2048 && chat.model.count<=200 && chat.memories.count<=100 &&
            chat.memories.allSatisfy{!$0.isEmpty && $0.count<=4000} && chat.history.count<=100 &&
            chat.history.allSatisfy{["user","assistant"].contains($0.role) && !$0.content.isEmpty && $0.content.count<=30000}
        guard furnitureValid, packagesValid, looksValid, chatValid, allowed.contains(state.scarf),
              Set(state.packs.map(\.id)).count==state.packs.count,
              Set(state.looks.map(\.id)).count==state.looks.count,
              Set(chat.history.map(\.id)).count==chat.history.count else {
            throw NSError(domain:"SusuStudio",code:1,userInfo:[NSLocalizedDescriptionKey:"小窝、换装或对话存档无效，原记录已保留。"])
        }
    }
    static func validOverlayHeader(_ data: Data) -> Bool {
        guard data.count>=24, data.count<=300000,
              Array(data.prefix(8)) == [137,80,78,71,13,10,26,10] else { return false }
        let bytes = Array(data.prefix(24))
        func number(_ start:Int)->UInt32 {
            bytes[start..<start+4].reduce(UInt32(0)){($0<<8)|UInt32($1)}
        }
        return number(16)==192 && number(20)==208
    }
}
