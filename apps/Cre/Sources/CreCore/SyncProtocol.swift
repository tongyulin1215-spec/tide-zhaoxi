import Foundation

// MARK: - What the phone and the Mac say to each other

/// Everything that syncs: plan data, ledger, schedule, and when a new day starts.
public struct SyncPayload: Codable, Equatable, Sendable {
    public var plan: PlanData
    public var ledger: LedgerData
    public var schedule: ScheduleData
    public var dayStart: DayStartSetting

    public init(plan: PlanData, ledger: LedgerData, schedule: ScheduleData, dayStart: DayStartSetting) {
        self.plan = plan
        self.ledger = ledger
        self.schedule = schedule
        self.dayStart = dayStart
    }

    public func merged(with other: SyncPayload) -> SyncPayload {
        SyncPayload(plan: plan.merged(with: other.plan), ledger: ledger.merged(with: other.ledger),
                    schedule: schedule.merged(with: other.schedule), dayStart: dayStart.merged(with: other.dayStart))
    }

    /// Drops deletion marks both sides have had a month to see.
    public mutating func pruneOldMarks(now: Date) {
        pruneDeletions(&plan.deletions, olderThan: 30, now: now)
        pruneDeletions(&ledger.deletions, olderThan: 30, now: now)
        pruneDeletions(&schedule.deletions, olderThan: 30, now: now)
    }
}

public enum SyncRequest: Codable, Equatable, Sendable {
    /// 连接 Mac: the Mac shows a 4-digit code.
    case pair(deviceName: String)
    /// The code typed on the phone.
    case confirm(code: String, deviceName: String)
    case sync(token: String, payload: SyncPayload)
}

public enum SyncResponse: Codable, Equatable, Sendable {
    case codeShown
    case paired(token: String)
    case badCode
    /// Token unknown (unpaired on the Mac): pair again.
    case unpaired
    case synced(SyncPayload)
    /// The Mac couldn't back up before a first sync; nothing was changed.
    case refused
}

/// The Mac's list of paired phones and the code currently on screen.
public struct PairingBook: Codable, Equatable, Sendable {
    public struct Device: Codable, Equatable, Sendable {
        public var name: String
        public var token: String
        public var lastSync: Date?
    }

    public var devices: [Device] = []
    private var pending: (code: String, device: String, until: Date)? {
        get { pendingCode.map { ($0, pendingDevice ?? "", pendingUntil ?? .distantPast) } }
        set { pendingCode = newValue?.code; pendingDevice = newValue?.device; pendingUntil = newValue?.until }
    }
    private var pendingCode: String?
    private var pendingDevice: String?
    private var pendingUntil: Date?
    /// Wrong tries on the code on screen; three and it's void.
    private var misses = 0

    public init() {}

    /// A fresh 4-digit code, valid for one minute.
    public mutating func requestCode(device: String, now: Date) -> String {
        let code = String(format: "%04d", Int.random(in: 0...9999))
        pending = (code, device, now.addingTimeInterval(60))
        misses = 0
        return code
    }

    public var shownCode: String? { pendingCode }

    /// The right code within the minute pairs the device and returns its token.
    public mutating func confirm(code: String, device: String, now: Date) -> String? {
        guard let p = pending, now <= p.until else { return nil }
        guard p.code == code else {
            misses += 1
            if misses >= 3 { pending = nil }
            return nil
        }
        pending = nil
        let token = UUID().uuidString + UUID().uuidString
        devices.removeAll { $0.name == device }
        devices.append(Device(name: device, token: token, lastSync: nil))
        return token
    }

    public func isValid(token: String) -> Bool { devices.contains { $0.token == token } }

    public func device(token: String) -> Device? { devices.first { $0.token == token } }

    public mutating func synced(token: String, now: Date) {
        if let i = devices.firstIndex(where: { $0.token == token }) { devices[i].lastSync = now }
    }

    public mutating func unpair(_ name: String) { devices.removeAll { $0.name == name } }
}
