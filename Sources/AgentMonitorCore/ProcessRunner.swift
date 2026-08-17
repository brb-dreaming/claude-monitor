import Darwin
import Foundation

public struct ProcessResult: Equatable {
    public let standardOutput: Data
    public let standardError: Data
    public let terminationStatus: Int32
    public let timedOut: Bool
    public let outputTruncated: Bool

    public var succeeded: Bool { !timedOut && terminationStatus == 0 }
}

public enum ProcessRunnerError: Error, Equatable {
    case launchFailed(String)
}

public enum ProcessRunner {
    public static let defaultTimeout: TimeInterval = 5
    public static let defaultMaximumOutputBytes = 1_048_576

    public static func run(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval = defaultTimeout,
        maximumOutputBytes: Int = defaultMaximumOutputBytes
    ) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let capture = OutputCapture(maximumBytes: max(0, maximumOutputBytes))
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { _ in completion.signal() }

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            capture.append(handle.availableData, toStandardError: false)
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            capture.append(handle.availableData, toStandardError: true)
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let boundedTimeout = max(timeout, 0.001)
        var timedOut = completion.wait(timeout: .now() + boundedTimeout) == .timedOut
        if timedOut {
            process.terminate()
            if completion.wait(timeout: .now() + 0.25) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
        }

        // Give readability handlers a final scheduling turn, then detach them;
        // never wait for inherited pipe descriptors held by child processes.
        Thread.sleep(forTimeInterval: 0.005)
        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        let snapshot = capture.snapshot()

        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            timedOut = true
        }

        return ProcessResult(
            standardOutput: snapshot.standardOutput,
            standardError: snapshot.standardError,
            terminationStatus: process.terminationStatus,
            timedOut: timedOut,
            outputTruncated: snapshot.truncated
        )
    }
}

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var standardOutput = Data()
    private var standardError = Data()
    private var truncated = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ data: Data, toStandardError: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if toStandardError {
            appendBounded(data, to: &standardError)
        } else {
            appendBounded(data, to: &standardOutput)
        }
    }

    func snapshot() -> (standardOutput: Data, standardError: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, standardError, truncated)
    }

    private func appendBounded(_ data: Data, to destination: inout Data) {
        let remaining = max(0, maximumBytes - destination.count)
        if data.count > remaining { truncated = true }
        if remaining > 0 { destination.append(data.prefix(remaining)) }
    }
}
