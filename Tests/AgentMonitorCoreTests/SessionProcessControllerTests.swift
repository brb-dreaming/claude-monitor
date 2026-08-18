import Darwin
import Foundation
import XCTest
@testable import AgentMonitorCore

final class SessionProcessControllerTests: XCTestCase {
    func testParserReturnsOnlyExactExecutableMatches() {
        let data = Data("""
          41 /opt/homebrew/bin/codex
          42 /opt/homebrew/bin/codex-helper
          43 /usr/local/bin/claude
          44 codex
        """.utf8)

        XCTAssertEqual(
            SessionProcessController.parseTargets(data, executable: "codex"),
            [
                SessionProcessTarget(pid: 41, executable: "codex", ttyName: ""),
                SessionProcessTarget(pid: 44, executable: "codex", ttyName: "")
            ]
        )
    }

    func testParserRejectsMalformedAndNonPositivePIDs() {
        let data = Data("""
          nope codex
          -1 codex
          0 codex
          52
        """.utf8)

        XCTAssertTrue(SessionProcessController.parseTargets(data, executable: "codex").isEmpty)
    }

    func testResolveRejectsUnsafeTTYWithoutLaunchingProcess() {
        XCTAssertThrowsError(
            try SessionProcessController.resolveTargets(ttyName: "ttys001;echo", agent: "codex")
        ) { error in
            XCTAssertEqual(error as? SessionProcessControllerError, .invalidTTY)
        }
    }

    func testResolveRejectsUnsupportedAgent() {
        XCTAssertThrowsError(
            try SessionProcessController.resolveTargets(ttyName: "ttys001", agent: "other")
        ) { error in
            XCTAssertEqual(error as? SessionProcessControllerError, .unsupportedAgent)
        }
    }

    func testStopWithNoTargetsIsTruthfullyNotRunning() {
        XCTAssertEqual(
            SessionProcessController.stop(targets: [], agent: "codex"),
            .notRunning
        )
    }

    func testStopSignalsOnlyRevalidatedTargetsAndVerifiesExit() {
        let targets = [
            SessionProcessTarget(pid: 91, executable: "codex", ttyName: "ttys001"),
            SessionProcessTarget(pid: 92, executable: "codex", ttyName: "ttys001")
        ]
        var inspections = 0
        var signals: [(Int32, Int32)] = []

        let result = SessionProcessController.stop(
            targets: targets,
            agent: "codex",
            force: false,
            gracePeriod: 1,
            inspector: { candidates, executable in
                XCTAssertEqual(executable, "codex")
                inspections += 1
                return inspections == 1 ? candidates : []
            },
            signaler: { pid, signal in
                signals.append((pid, signal))
                return true
            },
            now: Date.init,
            sleeper: { _ in XCTFail("Successful verification should not sleep") }
        )

        XCTAssertEqual(result, .stopped([91, 92]))
        XCTAssertEqual(signals.map(\.0), [91, 92])
        XCTAssertTrue(signals.allSatisfy { $0.1 == SIGTERM })
    }

    func testStopReportsStillRunningWithoutClaimingSuccess() {
        let target = SessionProcessTarget(pid: 93, executable: "claude", ttyName: "ttys002")
        let fixedNow = Date(timeIntervalSince1970: 100)

        let result = SessionProcessController.stop(
            targets: [target],
            agent: "claude",
            force: false,
            gracePeriod: 0,
            inspector: { candidates, _ in candidates },
            signaler: { _, _ in true },
            now: { fixedNow },
            sleeper: { _ in XCTFail("A zero grace period should not sleep") }
        )

        XCTAssertEqual(result, .stillRunning([93]))
    }

    func testForceStopUsesKillSignal() {
        let target = SessionProcessTarget(pid: 94, executable: "codex", ttyName: "ttys003")
        var inspections = 0
        var deliveredSignal: Int32?

        let result = SessionProcessController.stop(
            targets: [target],
            agent: "codex",
            force: true,
            gracePeriod: 1,
            inspector: { candidates, _ in
                inspections += 1
                return inspections == 1 ? candidates : []
            },
            signaler: { _, signal in
                deliveredSignal = signal
                return true
            },
            now: Date.init,
            sleeper: { _ in }
        )

        XCTAssertEqual(result, .stopped([94]))
        XCTAssertEqual(deliveredSignal, SIGKILL)
    }
}
