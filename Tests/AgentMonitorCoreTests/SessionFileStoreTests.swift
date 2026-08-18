import Foundation
import XCTest
@testable import AgentMonitorCore

final class SessionFileStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testConcurrentUpdatesRemainValidAndComplete() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("session.json")
        let queue = DispatchQueue(label: "store-test", attributes: .concurrent)
        let group = DispatchGroup()
        let errorLock = NSLock()
        var errors: [Error] = []

        for _ in 0..<100 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    try SessionFileStore.updateJSONObject(at: file, create: { ["count": 0] }) {
                        $0["count"] = (($0["count"] as? Int) ?? 0) + 1
                    }
                } catch {
                    errorLock.lock(); errors.append(error); errorLock.unlock()
                }
            }
        }
        group.wait()

        XCTAssertTrue(errors.isEmpty)
        let object = try SessionFileStore.readJSONObject(at: file)
        XCTAssertEqual(object["count"] as? Int, 100)
        XCTAssertEqual((try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "tmp" }.count, 0)
    }

    func testCorruptRecordIsQuarantinedAndRecreated() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("session.json")
        try Data("{broken".utf8).write(to: file)

        try SessionFileStore.updateJSONObject(at: file, create: { ["status": "starting"] }) {
            $0["status"] = "working"
        }

        let object = try SessionFileStore.readJSONObject(at: file)
        XCTAssertEqual(object["status"] as? String, "working")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.contains(".corrupt.") })
    }

    func testRuntimePermissionsAreOwnerOnly() throws {
        let directory = try temporaryDirectory().appendingPathComponent("sessions")
        let file = directory.appendingPathComponent("session.json")
        try SessionFileStore.updateJSONObject(at: file, create: { ["session_id": "s"] }) { _ in }

        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(directoryMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)
    }

    func testExplicitQuarantineRemovesUnreadableRecordFromActivePath() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("session.json")
        try Data("not-json".utf8).write(to: file)
        XCTAssertTrue(try SessionFileStore.quarantine(at: file))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .contains { $0.contains(".corrupt.") })
    }
}
