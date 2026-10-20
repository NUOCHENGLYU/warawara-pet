import XCTest
@testable import WarawaraPet

final class PetStateMachineTests: XCTestCase {
    func testAllAllowedTransitions() {
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .hop))
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .float))
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .curious))
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .sleepy))
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .idle, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .hop, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .hop, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .float, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .float, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .float, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .curious, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .curious, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .curious, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .clicked, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .clicked, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .clicked, to: .settling))
        XCTAssertTrue(PetStateMachine.canTransition(from: .clicked, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .dragged, to: .settling))
        XCTAssertTrue(PetStateMachine.canTransition(from: .settling, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .settling, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .sleepy, to: .sleeping))
        XCTAssertTrue(PetStateMachine.canTransition(from: .sleepy, to: .idle))
        XCTAssertTrue(PetStateMachine.canTransition(from: .sleepy, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .sleepy, to: .dragged))
        XCTAssertTrue(PetStateMachine.canTransition(from: .sleeping, to: .clicked))
        XCTAssertTrue(PetStateMachine.canTransition(from: .sleeping, to: .dragged))
        // The formal GENTLE wake for the daily 22:17 meteor: sleeping ->
        // idle through the state machine, never a raw state overwrite.
        XCTAssertTrue(PetStateMachine.canTransition(from: .sleeping, to: .idle))
    }

    func testRejectedTransitions() {
        // Sleep never leads back to autonomy directly — except the formal
        // gentle event wake (sleeping -> idle) asserted above.
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleeping, to: .hop))
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleeping, to: .float))
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleeping, to: .sleepy))
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleeping, to: .curious))
        // Sleepy has reduced autonomy.
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleepy, to: .hop))
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleepy, to: .float))
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleepy, to: .curious))
        // Autonomous motions cannot overlap.
        XCTAssertFalse(PetStateMachine.canTransition(from: .hop, to: .float))
        XCTAssertFalse(PetStateMachine.canTransition(from: .float, to: .hop))
        XCTAssertFalse(PetStateMachine.canTransition(from: .float, to: .settling))
        XCTAssertFalse(PetStateMachine.canTransition(from: .float, to: .sleepy))
        XCTAssertFalse(PetStateMachine.canTransition(from: .curious, to: .float))
        XCTAssertFalse(PetStateMachine.canTransition(from: .curious, to: .sleepy))
        XCTAssertFalse(PetStateMachine.canTransition(from: .curious, to: .hop))
        // Others.
        XCTAssertFalse(PetStateMachine.canTransition(from: .idle, to: .settling))
        XCTAssertFalse(PetStateMachine.canTransition(from: .idle, to: .sleeping))
        XCTAssertFalse(PetStateMachine.canTransition(from: .settling, to: .hop))
        XCTAssertFalse(PetStateMachine.canTransition(from: .settling, to: .clicked))
        XCTAssertFalse(PetStateMachine.canTransition(from: .dragged, to: .idle))
        XCTAssertFalse(PetStateMachine.canTransition(from: .dragged, to: .clicked))
        XCTAssertFalse(PetStateMachine.canTransition(from: .hop, to: .clicked))
        XCTAssertFalse(PetStateMachine.canTransition(from: .hop, to: .hop))
        XCTAssertFalse(PetStateMachine.canTransition(from: .idle, to: .idle))
        XCTAssertFalse(PetStateMachine.canTransition(from: .settling, to: .settling))
        XCTAssertFalse(PetStateMachine.canTransition(from: .clicked, to: .sleepy))
        XCTAssertFalse(PetStateMachine.canTransition(from: .sleepy, to: .settling))
    }

    func testTransitionMutatesStateOnlyWhenAllowed() {
        var machine = PetStateMachine()
        XCTAssertTrue(machine.transition(to: .clicked))
        XCTAssertEqual(machine.state, .clicked)
        XCTAssertFalse(machine.transition(to: .sleepy))
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

    func testSleepAndWakeCycles() {
        var machine = PetStateMachine()
        XCTAssertTrue(machine.transition(to: .sleepy))
        XCTAssertTrue(machine.transition(to: .sleeping))
        XCTAssertFalse(machine.transition(to: .hop))
        XCTAssertTrue(machine.transition(to: .clicked))
        XCTAssertTrue(machine.transition(to: .idle))

        var machine2 = PetStateMachine()
        XCTAssertTrue(machine2.transition(to: .sleepy))
        XCTAssertTrue(machine2.transition(to: .dragged))
        XCTAssertTrue(machine2.transition(to: .settling))
        XCTAssertTrue(machine2.transition(to: .idle))
    }

    func testFloatInterruptionPaths() {
        var machine = PetStateMachine()
        XCTAssertTrue(machine.transition(to: .float))
        XCTAssertTrue(machine.transition(to: .clicked))
        XCTAssertTrue(machine.transition(to: .settling))
        XCTAssertTrue(machine.transition(to: .idle))

        // Natural float completion lands softly back in idle (no bounce
        // state in between — the settle phase lives inside the float curve).
        var machine2 = PetStateMachine()
        XCTAssertTrue(machine2.transition(to: .float))
        XCTAssertTrue(machine2.transition(to: .idle))
    }

    func testCuriosityYieldsToInteraction() {
        var machine = PetStateMachine()
        XCTAssertTrue(machine.transition(to: .curious))
        XCTAssertTrue(machine.transition(to: .clicked))
        XCTAssertTrue(machine.transition(to: .idle))

        var machine2 = PetStateMachine()
        XCTAssertTrue(machine2.transition(to: .curious))
        XCTAssertTrue(machine2.transition(to: .dragged))
        XCTAssertTrue(machine2.transition(to: .settling))
    }
}
