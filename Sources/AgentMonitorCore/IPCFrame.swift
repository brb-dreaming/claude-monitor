import Darwin
import Foundation

public enum IPCFrameError: Error, Equatable {
    case endOfStream
    case oversized(Int)
    case readFailed(Int32)
    case writeFailed(Int32)
}

public enum IPCFrame {
    public static let defaultMaximumPayload = 1_048_576

    public static func setReceiveTimeout(on fd: Int32, seconds: TimeInterval) throws {
        let boundedSeconds = max(seconds, 0.001)
        var timeout = timeval(
            tv_sec: Int(boundedSeconds),
            tv_usec: Int32((boundedSeconds.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        guard setsockopt(
            fd, SOL_SOCKET, SO_RCVTIMEO,
            &timeout, socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw IPCFrameError.readFailed(errno)
        }
    }

    public static func read(
        from fd: Int32,
        maximumPayload: Int = defaultMaximumPayload
    ) throws -> Data {
        let header = try readExactly(4, from: fd)
        let length = header.withUnsafeBytes { raw -> UInt32 in
            raw.loadUnaligned(as: UInt32.self).bigEndian
        }
        let count = Int(length)
        guard count <= maximumPayload else { throw IPCFrameError.oversized(count) }
        return try readExactly(count, from: fd)
    }

    public static func write(_ payload: Data, to fd: Int32) throws {
        guard payload.count <= Int(UInt32.max) else {
            throw IPCFrameError.oversized(payload.count)
        }
        var length = UInt32(payload.count).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        try writeAll(header, to: fd)
        try writeAll(payload, to: fd)
    }

    private static func readExactly(_ count: Int, from fd: Int32) throws -> Data {
        if count == 0 { return Data() }
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            while offset < count {
                let result = Darwin.read(fd, base.advanced(by: offset), count - offset)
                if result == 0 { throw IPCFrameError.endOfStream }
                if result < 0 {
                    if errno == EINTR { continue }
                    throw IPCFrameError.readFailed(errno)
                }
                offset += result
            }
        }
        return data
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard var base = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let result = Darwin.write(fd, base, remaining)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw IPCFrameError.writeFailed(errno)
                }
                remaining -= result
                base = base.advanced(by: result)
            }
        }
    }
}
