import Foundation
import Network
import Testing
@testable import CreCore

/// A Mac-side host for tests: pairing book + merge, no files.
private final class TestHost: @unchecked Sendable {
    var book = PairingBook()
    var mine = SyncPayload(plan: PlanData(), ledger: LedgerData(), schedule: ScheduleData(),
                           dayStart: DayStartSetting(hour: 0, modifiedAt: nil))
    var lastCode = ""

    func handle(_ r: SyncRequest) -> SyncResponse {
        switch r {
        case .pair(let device):
            lastCode = book.requestCode(device: device, now: Date())
            return .codeShown
        case .confirm(let code, let device):
            return book.confirm(code: code, device: device, now: Date()).map(SyncResponse.paired) ?? .badCode
        case .sync(let token, let payload):
            guard book.isValid(token: token) else { return .unpaired }
            mine = mine.merged(with: payload)
            return .synced(mine)
        }
    }
}

@Test func pairThenSync() async throws {
    let host = TestHost()
    var macPlan = PlanData()
    macPlan.addTodo("Mac 上的", schedule: .none, groupID: nil, tags: [], now: Date())
    host.mine.plan = macPlan
    let server = try SyncServer(serviceName: nil) { host.handle($0) }
    let port = try await server.start()
    defer { server.stop() }
    let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

    #expect(try await SyncClient.send(.pair(deviceName: "iPhone"), to: endpoint) == .codeShown)
    #expect(try await SyncClient.send(.confirm(code: "0000" == host.lastCode ? "1111" : "0000", deviceName: "iPhone"), to: endpoint) == .badCode)
    guard case .paired(let token) = try await SyncClient.send(.confirm(code: host.lastCode, deviceName: "iPhone"), to: endpoint) else {
        Issue.record("not paired"); return
    }
    var phonePlan = PlanData()
    phonePlan.addTodo("手机上的", schedule: .none, groupID: nil, tags: [], now: Date())
    let payload = SyncPayload(plan: phonePlan, ledger: LedgerData(), schedule: ScheduleData(),
                              dayStart: DayStartSetting(hour: 0, modifiedAt: nil))
    guard case .synced(let merged) = try await SyncClient.send(.sync(token: token, payload: payload), to: endpoint) else {
        Issue.record("not synced"); return
    }
    #expect(Set(merged.plan.todos.map(\.text)) == ["Mac 上的", "手机上的"])
}

@Test func unknownTokenIsRejected() async throws {
    let host = TestHost()
    let server = try SyncServer(serviceName: nil) { host.handle($0) }
    let port = try await server.start()
    defer { server.stop() }
    let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
    let payload = SyncPayload(plan: PlanData(), ledger: LedgerData(), schedule: ScheduleData(),
                              dayStart: DayStartSetting(hour: 0, modifiedAt: nil))
    #expect(try await SyncClient.send(.sync(token: "nope", payload: payload), to: endpoint) == .unpaired)
}

@Test func codesExpireAfterAMinute() {
    var book = PairingBook()
    let now = Date()
    let code = book.requestCode(device: "iPhone", now: now)
    #expect(code.count == 4)
    #expect(book.confirm(code: code, device: "iPhone", now: now.addingTimeInterval(61)) == nil)
}

@Test func codeLocksAfterThreeWrongTries() {
    var book = PairingBook()
    let now = Date()
    let code = book.requestCode(device: "iPhone", now: now)
    let wrong = code == "0000" ? "1111" : "0000"
    for _ in 0..<3 { #expect(book.confirm(code: wrong, device: "iPhone", now: now) == nil) }
    #expect(book.confirm(code: code, device: "iPhone", now: now) == nil)
}
