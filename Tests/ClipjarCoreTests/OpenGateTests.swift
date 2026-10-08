import Testing
@testable import ClipjarCore

@Suite struct OpenGateTests {
    @Test func queuesLatestUntilReady() {
        var gate = OpenGate()
        #expect(!gate.isReady)
        #expect(gate.request(.cursor) == nil)
        #expect(gate.request(.statusItem) == nil)
        #expect(gate.markReady() == .statusItem)
        #expect(gate.isReady)
        #expect(gate.markReady() == nil)
        #expect(gate.request(.centred) == .centred)
    }

    @Test func readyWithNothingQueued() {
        var gate = OpenGate()
        #expect(gate.markReady() == nil)
        #expect(gate.request(.cursor) == .cursor)
    }
}
