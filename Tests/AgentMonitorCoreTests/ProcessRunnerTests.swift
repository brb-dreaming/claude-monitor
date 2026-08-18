import Foundation
import XCTest
@testable import AgentMonitorCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndExitStatus() throws {
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf hello; printf problem >&2; exit 7"]
        )

        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "hello")
        XCTAssertEqual(String(data: result.standardError, encoding: .utf8), "problem")
        XCTAssertEqual(result.terminationStatus, 7)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.succeeded)
    }

    func testTimeoutTerminatesProcess() throws {
        let started = Date()
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: 0.05
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testTimeoutEscalatesWhenProcessIgnoresTerm() throws {
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do sleep 1; done"],
            timeout: 0.05
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.terminationStatus, SIGKILL)
    }

    func testCapturesLargeOutputFromBothStreamsExactly() throws {
        let output = String(repeating: "o", count: 256 * 1024)
        let error = String(repeating: "e", count: 256 * 1024)
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [
                "-c",
                "import sys; sys.stdout.write('o' * 262144); sys.stderr.write('e' * 262144)"
            ]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), output)
        XCTAssertEqual(String(data: result.standardError, encoding: .utf8), error)
        XCTAssertFalse(result.outputTruncated)
    }

    func testDoesNotWaitForDescendantHoldingPipeDescriptors() throws {
        let started = Date()
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 5 & printf done"],
            timeout: 1
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "done")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testOutputIsCappedWhilePipeContinuesDraining() throws {
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "i=0; while [ $i -lt 5000 ]; do printf x; i=$((i+1)); done"],
            maximumOutputBytes: 128
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput.count, 128)
        XCTAssertTrue(result.outputTruncated)
    }
}
