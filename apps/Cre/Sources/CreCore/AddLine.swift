import Foundation

/// A time picked in the edit card, overriding what the text says.
public struct TimeChoice: Equatable, Sendable {
    public var schedule: Schedule
    public var priority: Priority?
    /// nil keeps the todo's tags as they are.
    public var tags: [String]?

    public init(schedule: Schedule, priority: Priority?, tags: [String]? = nil) {
        self.schedule = schedule
        self.priority = priority
        self.tags = tags
    }
}

extension PlanData {
    /// One line from an input bar. Times, tags and priority come from the text unless `override` says otherwise;
    /// with no time, it lands on `viewingDay` (nil keeps it undated). Returns nil for blank input.
    @discardableResult
    public mutating func addLine(_ raw: String, override: TimeChoice?, groupID: UUID?, viewingDay: DayKey?,
                                 today: DayKey, now: Date) -> UUID? {
        let parsed = parseInput(raw, today: today)
        var schedule = override?.schedule ?? parsed.schedule
        if schedule == .none, let viewingDay { schedule = .day(viewingDay) }
        let tags = Array(Set(parsed.tags + (override?.tags ?? []))).sorted()
        guard let id = addTodo(parsed.text, schedule: schedule, groupID: groupID, tags: tags, now: now) else { return nil }
        if let p = override?.priority ?? parsed.priority { update(id) { $0.priority = p } }
        return id
    }

    /// Blank names are ignored.
    public mutating func rename(_ id: UUID, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update(id) { $0.text = t }
    }

    public mutating func setTime(_ id: UUID, _ choice: TimeChoice) {
        update(id) { t in
            t.schedule = choice.schedule
            t.priority = choice.priority
            if let tags = choice.tags { t.tags = tags }
        }
    }
}
