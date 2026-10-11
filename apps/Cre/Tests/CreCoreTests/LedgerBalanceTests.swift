import Foundation
import Testing
@testable import CreCore

private func entry(_ yuan: Int, income: Bool = false, _ day: DayKey) -> LedgerEntry {
    LedgerEntry(amount: yuan * 100, isIncome: income, category: "其他", note: "", day: day)
}

@Test func noOpeningMeansNoBalance() {
    #expect(LedgerData().balance(asOf: d(10, 4)) == nil)
}

@Test func balanceStartsFromOpening() {
    var data = LedgerData()
    data.opening = OpeningBalance(amount: 1000_00, day: d(10, 1))
    data.entries = [
        entry(50, d(9, 30)),                // before the starting day: already counted in it
        entry(30, d(10, 1)),
        entry(200, income: true, d(10, 3)),
        entry(20, d(10, 8)),                // after the asked day
    ]
    #expect(data.balance(asOf: d(10, 4)) == 1170_00)
    #expect(data.balance(asOf: d(10, 31)) == 1150_00)
    #expect(data.balance(asOf: d(9, 30)) == nil)
}

@Test func openingSurvivesSaveAndOldFilesStillLoad() throws {
    var data = LedgerData()
    data.opening = OpeningBalance(amount: 520_50, day: d(10, 4))
    let back = try JSONDecoder().decode(LedgerData.self, from: JSONEncoder().encode(data))
    #expect(back.opening == data.opening)
    let old = try JSONDecoder().decode(LedgerData.self, from: Data(#"{"version":1,"entries":[]}"#.utf8))
    #expect(old.opening == nil)
}
