import Testing
@testable import CreCore

@Test func draftQueueAdvancesOnCancel() {
    var q = DraftQueue(["a", "b", "c"])
    #expect(q.current == "a" && q.position == "1/3")
    q.advance(); q.advance()
    #expect(q.current == "c" && q.position == "3/3")
    q.advance()
    #expect(q.current == nil && q.position == nil)
    let one = DraftQueue(["x"])
    #expect(one.current == "x" && one.position == nil)
}

@Test func draftQueueTakesMoreWhileOpen() {
    var q = DraftQueue(["a"])
    q.append(contentsOf: ["b", "c"])
    #expect(q.position == "1/3")
    q.advance()
    #expect(q.current == "b" && q.position == "2/3")
}
