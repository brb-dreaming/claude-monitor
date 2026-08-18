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
    case terminationFailed(processIdentifier: Int32)
    case outputDrainFailed
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

        let readers = DispatchGroup()
        startReader(
            standardOutput.fileHandleForReading,
            capture: capture,
            toStandardError: false,
            group: readers
        )
        startReader(
            standardError.fileHandleForReading,
            capture: capture,
            toStandardError: true,
            group: readers
        )

        do {
            try process.run()
        } catch {
            closePipes(standardOutput, standardError)
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        // Process owns duplicated write descriptors after launch. Closing the
        // parent's copies lets the readers observe EOF when the child exits.
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()

        let boundedTimeout = max(timeout, 0.001)
        let timedOut = completion.wait(timeout: .now() + boundedTimeout) == .timedOut
        if timedOut {
            process.terminate()
            if completion.wait(timeout: .now() + 0.25) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                if completion.wait(timeout: .now() + 1) == .timedOut {
                    closePipes(standardOutput, standardError)
                    throw ProcessRunnerError.terminationFailed(
                        processIdentifier: process.processIdentifier
                    )
                }
            }
        }

        // Normally both readers reach EOF immediately after process exit. If a
        // descendant inherited a write descriptor, close our read ends rather
        // than waiting indefinitely for that unrelated process.
        if readers.wait(timeout: .now() + 0.25) == .timedOut {
            try? standardOutput.fileHandleForReading.close()
            try? standardError.fileHandleForReading.close()
            guard readers.wait(timeout: .now() + 1) == .success else {
                throw ProcessRunnerError.outputDrainFailed
            }
        }
        let snapshot = capture.snapshot()

        return ProcessResult(
            standardOutput: snapshot.standardOutput,
            standardError: snapshot.standardError,
            terminationStatus: process.terminationStatus,
            timedOut: timedOut,
            outputTruncated: snapshot.truncated
        )
    }

    private static func startReader(
        _ handle: FileHandle,
        capture: OutputCapture,
        toStandardError: Bool,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            while true {
                do {
                    guard let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty else {
                        return
                    }
                    capture.append(data, toStandardError: toStandardError)
                } catch {
                    return
                }
            }
        }
    }

    private static func closePipes(_ standardOutput: Pipe, _ standardError: Pipe) {
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
        try? standardOutput.fileHandleForReading.close()
        try? standardError.fileHandleForReading.close()
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
