import Darwin
import Foundation

public struct SessionProcessTarget: Equatable, Identifiable {
    public let pid: Int32
    public let executable: String
    public let ttyName: String

    public var id: Int32 { pid }

    public init(pid: Int32, executable: String, ttyName: String) {
        self.pid = pid
        self.executable = executable
        self.ttyName = ttyName
    }
}

public enum SessionStopResult: Equatable {
    case stopped([Int32])
    case notRunning
    case stillRunning([Int32])
    case failed(String)
}

public enum SessionProcessControllerError: Error, Equatable, LocalizedError {
    case invalidTTY
    case unsupportedAgent
    case inspectionTimedOut
    case inspectionOutputTruncated
    case inspectionFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidTTY:
            return "The terminal identifier is invalid."
        case .unsupportedAgent:
            return "The session's agent type is unsupported."
        case .inspectionTimedOut:
            return "Process inspection timed out."
        case .inspectionOutputTruncated:
            return "Process inspection returned too much data."
        case .inspectionFailed(let status):
            return "Process inspection failed with status \(status)."
        }
    }
}

/// Resolves and signals only exact agent executables on a specific TTY.
///
/// The UI performs resolution before asking for confirmation so it can show the
/// concrete PIDs. `stop` revalidates those PIDs immediately before signaling to
/// avoid acting on a stale or reused process identifier.
public enum SessionProcessController {
    public static func resolveTargets(ttyName: String, agent: String) throws -> [SessionProcessTarget] {
        guard isValidTTYName(ttyName) else {
            throw SessionProcessControllerError.invalidTTY
        }
        let executable = try executableName(for: agent)
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-t", ttyName, "-o", "pid=,comm="],
            timeout: 2,
            maximumOutputBytes: 64 * 1024
        )
        guard !result.timedOut else {
            throw SessionProcessControllerError.inspectionTimedOut
        }
        guard !result.outputTruncated else {
            throw SessionProcessControllerError.inspectionOutputTruncated
        }
        // BSD ps returns 1 when the selection contains no processes.
        guard result.terminationStatus == 0 || result.terminationStatus == 1 else {
            throw SessionProcessControllerError.inspectionFailed(result.terminationStatus)
        }
        return parseTargets(result.standardOutput, executable: executable)
            .map { SessionProcessTarget(pid: $0.pid, executable: $0.executable, ttyName: ttyName) }
    }

    public static func stop(
        targets: [SessionProcessTarget],
        agent: String,
        force: Bool = false,
        gracePeriod: TimeInterval = 2
    ) -> SessionStopResult {
        stop(
            targets: targets,
            agent: agent,
            force: force,
            gracePeriod: gracePeriod,
            inspector: inspect,
            signaler: { pid, signal in
                Darwin.kill(pid, signal) == 0 || errno == ESRCH
            },
            now: Date.init,
            sleeper: Thread.sleep(forTimeInterval:)
        )
    }

    static func stop(
        targets: [SessionProcessTarget],
        agent: String,
        force: Bool,
        gracePeriod: TimeInterval,
        inspector: ([SessionProcessTarget], String) throws -> [SessionProcessTarget],
        signaler: (Int32, Int32) -> Bool,
        now: () -> Date,
        sleeper: (TimeInterval) -> Void
    ) -> SessionStopResult {
        guard !targets.isEmpty else { return .notRunning }

        let executable: String
        do {
            executable = try executableName(for: agent)
        } catch {
            return .failed(error.localizedDescription)
        }

        let liveTargets: [SessionProcessTarget]
        do {
            liveTargets = try inspector(targets, executable)
        } catch {
            return .failed(error.localizedDescription)
        }
        guard !liveTargets.isEmpty else { return .notRunning }

        let signal = force ? SIGKILL : SIGTERM
        var failedPIDs: [Int32] = []
        for target in liveTargets {
            if !signaler(target.pid, signal) {
                failedPIDs.append(target.pid)
            }
        }
        if !failedPIDs.isEmpty {
            let list = failedPIDs.sorted().map(String.init).joined(separator: ", ")
            return .failed("Could not signal PID\(failedPIDs.count == 1 ? "" : "s") \(list).")
        }

        let deadline = now().addingTimeInterval(max(0, gracePeriod))
        while true {
            let remaining: [SessionProcessTarget]
            do {
                remaining = try inspector(liveTargets, executable)
            } catch {
                return .failed(error.localizedDescription)
            }
            if remaining.isEmpty {
                return .stopped(liveTargets.map(\.pid).sorted())
            }
            if now() >= deadline {
                return .stillRunning(remaining.map(\.pid).sorted())
            }
            sleeper(0.1)
        }
    }

    static func parseTargets(_ data: Data, executable: String) -> [SessionProcessTarget] {
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2,
                  let pid = Int32(fields[0]),
                  pid > 0 else { return nil }
            let command = URL(fileURLWithPath: String(fields[1])).lastPathComponent
            guard command == executable else { return nil }
            return SessionProcessTarget(pid: pid, executable: command, ttyName: "")
        }.sorted { $0.pid < $1.pid }
    }

    private static func inspect(
        targets: [SessionProcessTarget],
        executable: String
    ) throws -> [SessionProcessTarget] {
        let pids = Set(targets.map(\.pid))
        guard !pids.isEmpty else { return [] }
        let pidList = pids.sorted().map(String.init).joined(separator: ",")
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-p", pidList, "-o", "pid=,tty=,comm="],
            timeout: 2,
            maximumOutputBytes: 64 * 1024
        )
        guard !result.timedOut else {
            throw SessionProcessControllerError.inspectionTimedOut
        }
        guard !result.outputTruncated else {
            throw SessionProcessControllerError.inspectionOutputTruncated
        }
        guard result.terminationStatus == 0 || result.terminationStatus == 1 else {
            throw SessionProcessControllerError.inspectionFailed(result.terminationStatus)
        }
        let expectedTTYByPID = Dictionary(uniqueKeysWithValues: targets.map { ($0.pid, $0.ttyName) })
        let output = String(data: result.standardOutput, encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  let pid = Int32(fields[0]),
                  let expectedTTY = expectedTTYByPID[pid],
                  String(fields[1]) == expectedTTY else { return nil }
            let command = URL(fileURLWithPath: String(fields[2])).lastPathComponent
            guard command == executable else { return nil }
            return SessionProcessTarget(pid: pid, executable: command, ttyName: expectedTTY)
        }.sorted { $0.pid < $1.pid }
    }

    private static func executableName(for agent: String) throws -> String {
        switch agent.lowercased() {
        case "codex": return "codex"
        case "claude": return "claude"
        default: throw SessionProcessControllerError.unsupportedAgent
        }
    }

    private static func isValidTTYName(_ ttyName: String) -> Bool {
        !ttyName.isEmpty && ttyName.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
