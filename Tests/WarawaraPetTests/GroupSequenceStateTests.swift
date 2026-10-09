import XCTest
@testable import WarawaraPet

final class GroupSequenceStateTests: XCTestCase {
    func testNormalProgression() {
        var machine = GroupSequenceStateMachine()
        XCTAssertEqual(machine.state, .inactive)
        XCTAssertTrue(machine.transition(to: .appearing))
        XCTAssertTrue(machine.transition(to: .gathering))
        XCTAssertTrue(machine.transition(to: .hovering))
        XCTAssertTrue(machine.transition(to: .ascending))
        XCTAssertTrue(machine.transition(to: .finishing))
        XCTAssertTrue(machine.transition(to: .inactive))
    }

    func testCancellationFromEveryActivePhase() {
        for phase in [GroupSequenceState.appearing, .gathering, .hovering, .ascending] {
            var machine = GroupSequenceStateMachine()
            XCTAssertTrue(machine.transition(to: .appearing))
            if phase != .appearing {
                if phase == .gathering {
                    XCTAssertTrue(machine.transition(to: .gathering))
                } else if phase == .hovering {
                    XCTAssertTrue(machine.transition(to: .gathering))
                    XCTAssertTrue(machine.transition(to: .hovering))
                } else {
                    XCTAssertTrue(machine.transition(to: .gathering))
                    XCTAssertTrue(machine.transition(to: .hovering))
                    XCTAssertTrue(machine.transition(to: .ascending))
                }
            }
            XCTAssertTrue(machine.transition(to: .cancelled))
            XCTAssertTrue(machine.transition(to: .inactive))
        }
    }

    func testOnlyOneSequenceAtATime() {
        var machine = GroupSequenceStateMachine()
        XCTAssertTrue(machine.transition(to: .appearing))
        XCTAssertFalse(machine.transition(to: .appearing))  // already active
        XCTAssertFalse(machine.transition(to: .hovering))   // skipped phase
        XCTAssertTrue(machine.transition(to: .cancelled))
        XCTAssertFalse(machine.transition(to: .cancelled))  // cancel twice rejected
        XCTAssertTrue(machine.transition(to: .inactive))
    }

    func testRejectedTransitions() {
        var machine = GroupSequenceStateMachine()
        XCTAssertFalse(machine.transition(to: .gathering))
        XCTAssertFalse(machine.transition(to: .finishing))
        XCTAssertFalse(machine.transition(to: .cancelled))

        machine = GroupSequenceStateMachine()
        XCTAssertTrue(machine.transition(to: .appearing))
        XCTAssertFalse(machine.transition(to: .finishing))
        XCTAssertFalse(machine.transition(to: .inactive))

        machine = GroupSequenceStateMachine()
        XCTAssertTrue(machine.transition(to: .appearing))
        XCTAssertTrue(machine.transition(to: .finishing) == false)
        XCTAssertTrue(machine.transition(to: .gathering))
        XCTAssertFalse(machine.transition(to: .appearing))
    }
}
