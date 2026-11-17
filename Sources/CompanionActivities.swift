import Foundation

struct LearnedCue: Codable, Identifiable {
    var id = UUID()
    var name: String
    var actions: [String]
}
struct StudyCard: Codable, Identifiable {
    var id = UUID()
    var question: String
    var answer: String
    var needsReview = true
    var reviewedAt: Date?
}
struct FutureLetter: Codable, Identifiable {
    var id = UUID()
    var body: String
    var due: Date
    var deliveredAt: Date?
    var readAt: Date?
}
struct Expedition: Codable {
    var id = UUID()
    var route: String
    var due: Date
}
struct CompanionActivities: Codable {
    var cues: [LearnedCue] = []
    var cards: [StudyCard] = []
    var letters: [FutureLetter] = []
    var expedition: Expedition?
    var collection: [String:Int] = [:]
}

extension CompanionStore {
    var unreadLetters: [FutureLetter] {
        save.activities.letters.filter { $0.deliveredAt != nil && $0.readAt == nil }
    }
    func saveCue(id: UUID? = nil, name: String, actions: [String]) throws {
        let cleanName = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !cleanName.isEmpty, actions.count == 2,
              actions.allSatisfy({ ["stretch","play"].contains($0) }) else { throw activityError("请填写暗号，并选择两个动作。") }
        var next = save
        guard !next.activities.cues.contains(where: { $0.name == cleanName && $0.id != id }) else { throw activityError("这个暗号已经存在，请换个名字或编辑原暗号。") }
        if let id, let index = next.activities.cues.firstIndex(where: { $0.id == id }) {
            next.activities.cues[index] = LearnedCue(id:id,name:cleanName,actions:actions)
        } else { next.activities.cues.append(LearnedCue(name:cleanName,actions:actions)) }
        try commit(next)
    }
    func deleteCue(id: UUID) throws {
        var next = save
        next.activities.cues.removeAll { $0.id == id }
        try commit(next)
    }
    func startExpedition(route: String, now: Date = Date(), duration: TimeInterval = 60) throws {
        guard ["river","forest"].contains(route), duration >= 1, duration <= 86400 else { throw activityError("探险路线或时长无效。") }
        guard save.activities.expedition == nil else { throw activityError("溯溯还在路上，等它回来再出发吧。") }
        var next = save
        next.activities.expedition = Expedition(route:route,due:now.addingTimeInterval(duration))
        try commit(next)
    }
    /// Atomically settles a trip and delivers due letters once, including after restart.
    @discardableResult func settleActivities(now: Date = Date()) throws -> Bool {
        var next = save
        var changed = false
        if let trip = next.activities.expedition, trip.due <= now {
            let item = trip.route == "river" ? "河岸鹅卵石" : "松林松果"
            next.activities.collection[item, default:0] += 1
            next.journal.append(JournalEntry(text:"溯溯探险归来，带回了\(item)。"))
            next.activities.expedition = nil
            changed = true
        }
        for index in next.activities.letters.indices {
            if next.activities.letters[index].deliveredAt == nil && next.activities.letters[index].due <= now {
                next.activities.letters[index].deliveredAt = now
                changed = true
            }
        }
        if changed { try commit(next) }
        return changed
    }
    func saveCard(id: UUID? = nil, question: String, answer: String) throws {
        let q = question.trimmingCharacters(in:.whitespacesAndNewlines)
        let a = answer.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !q.isEmpty, !a.isEmpty else { throw activityError("题面和答案都要填写。") }
        var next = save
        if let id, let index = next.activities.cards.firstIndex(where: { $0.id == id }) {
            next.activities.cards[index].question = q
            next.activities.cards[index].answer = a
        } else { next.activities.cards.append(StudyCard(question:q,answer:a)) }
        try commit(next)
    }
    func deleteCard(id: UUID) throws {
        var next = save
        next.activities.cards.removeAll { $0.id == id }
        try commit(next)
    }
    func nextCard(excluding: UUID? = nil) -> StudyCard? {
        let cards = save.activities.cards
        let pending = cards.filter(\.needsReview)
        let priority = pending.isEmpty ? cards : pending
        let remaining = priority.filter { $0.id != excluding }
        let pool = remaining.isEmpty ? priority : remaining
        return pool.sorted {
            ($0.reviewedAt ?? .distantPast) < ($1.reviewedAt ?? .distantPast)
        }.first
    }
    func reviewCard(id: UUID, remembered: Bool, now: Date = Date()) throws {
        var next = save
        guard let index = next.activities.cards.firstIndex(where: { $0.id == id }) else { return }
        next.activities.cards[index].needsReview = !remembered
        next.activities.cards[index].reviewedAt = now
        try commit(next)
    }
    func saveLetter(id: UUID? = nil, body: String, due: Date, now: Date = Date()) throws {
        let text = body.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, due > now else { throw activityError("请填写信件，并选择未来的投递时间。") }
        var next = save
        if let id, let index = next.activities.letters.firstIndex(where: { $0.id == id }) {
            guard next.activities.letters[index].deliveredAt == nil else { throw activityError("已投递的信不能改期。") }
            next.activities.letters[index].body = text
            next.activities.letters[index].due = due
        } else {
            guard !next.activities.letters.contains(where: { $0.deliveredAt == nil }) else { throw activityError("已有一封待投递的信，可先改期或取消。") }
            next.activities.letters.append(FutureLetter(body:text,due:due))
        }
        try commit(next)
    }
    func deleteLetter(id: UUID) throws {
        var next = save
        next.activities.letters.removeAll { $0.id == id }
        try commit(next)
    }
    func readLetter(id: UUID, now: Date = Date()) throws {
        var next = save
        guard let index = next.activities.letters.firstIndex(where: { $0.id == id }),
              next.activities.letters[index].deliveredAt != nil else { return }
        if next.activities.letters[index].readAt == nil {
            next.activities.letters[index].readAt = now
            try commit(next)
        }
    }
    private func activityError(_ text: String) -> NSError {
        NSError(domain:"SusuActivities",code:1,userInfo:[NSLocalizedDescriptionKey:text])
    }
}
