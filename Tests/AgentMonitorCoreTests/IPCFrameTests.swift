import Darwin
import Foundation
import XCTest
@testable import AgentMonitorCore

final class IPCFrameTests: XCTestCase {
    func testFragmentedFrameIsReassembled() throws {
        var sockets: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }

        let payload = Data(repeating: 0x5A, count: 12_345)
        var length = UInt32(payload.count).bigEndian
        let framed = withUnsafeBytes(of: &length) { Data($0) } + payload
        let writer = DispatchQueue(label: "frame-writer")
        writer.async {
            for byte in framed {
                var value = byte
                _ = Darwin.write(sockets[1], &value, 1)
            }
        }

        XCTAssertEqual(try IPCFrame.read(from: sockets[0]), payload)
    }

    func testOversizedFrameIsRejectedBeforePayloadRead() throws {
        var sockets: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }
        var length = UInt32(2_000).bigEndian
        _ = withUnsafeBytes(of: &length) { Darwin.write(sockets[1], $0.baseAddress, 4) }
        XCTAssertThrowsError(try IPCFrame.read(from: sockets[0], maximumPayload: 1_000)) {
            XCTAssertEqual($0 as? IPCFrameError, .oversized(2_000))
        }
    }

    func testIncompleteFrameReadTimesOut() throws {
        var sockets: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }
        try IPCFrame.setReceiveTimeout(on: sockets[0], seconds: 0.1)

        var partialHeader: UInt8 = 0
        XCTAssertEqual(Darwin.write(sockets[1], &partialHeader, 1), 1)
        XCTAssertThrowsError(try IPCFrame.read(from: sockets[0])) { error in
            guard case .readFailed(let code) = error as? IPCFrameError else {
                return XCTFail("expected readFailed, got \(error)")
            }
            XCTAssertTrue(code == EAGAIN || code == EWOULDBLOCK)
        }
    }
}
