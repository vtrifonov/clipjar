import Testing
@testable import ClipjarCore

@Suite struct PasteGateTests {
    @Test func secondActivationWhilePastingIsRefused() {
        var gate = PasteGate()
        let first = gate.begin()
        let second = gate.begin()
        #expect(first)
        #expect(!second)
        #expect(gate.isBusy)
    }

    @Test func reopensWhenThePasteFinishes() {
        var gate = PasteGate()
        _ = gate.begin()
        gate.end()
        #expect(!gate.isBusy)
        let next = gate.begin()
        #expect(next)
    }
}
