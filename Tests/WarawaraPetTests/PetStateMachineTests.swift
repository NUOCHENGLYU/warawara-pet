import XCTest
@testable import WarawaraPet

final class PetStateMachineTests: XCTestCase {
    func testAllAllowedTransitions() {
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .hop))
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .hop, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .hop, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .clicked, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .clicked, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .clicked, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .dragged, to: .settling))
        XCTAssertTrue(PetStateMachine.canTransition(from: .settling, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .settling, to: .dragged))
    }

    func testRejectedTransitions() {
        XCTAssertFalse(PetStateMachine.canTransition(from: .idle, to: .settling))
        XCTAssertFalse(PetStateMachine.canTransition(from: .settling, to: .hop))
        XCTAssertFalse(PetStateMachine.canTransition(from: .dragged, to: .idle))
        XCTAssertFalse(PetStateMachine.canTransition(from: .dragged, to: .clicked))
        XCTAssertFalse(PetStateMachine.canTransition(from: .hop, to: .clicked))
        XCTAssertFalse(PetStateMachine.canTransition(from: .hop, to: .hop))
        XCTAssertFalse(PetStateMachine.canTransition(from: .idle, to: .idle))
        XCTAssertFalse(PetStateMachine.canTransition(from: .settling, to: .settling))
    }

    func testTransitionMutatesStateOnlyWhenAllowed() {
        var machine = PetStateMachine()
        XCTAssertTrue(machine.transition(to: .clicked))
        XCTAssertEqual(machine.state, .clicked)
        XCTAssertFalse(machine.transition(to: .settling))
        XCTAssertEqual(machine.state, .clicked)
        XCTAssertTrue(machine.transition(to: .dragged))
        XCTAssertTrue(machine.transition(to: .settling))
        XCTAssertTrue(machine.transition(to: .idle))
    }

    func testFullHopCycle() {
        var machine = PetStateMachine()
        XCTAssertTrue(machine.transition(to: .hop))
        XCTAssertTrue(machine.transition(to: .idle))
    }
}
