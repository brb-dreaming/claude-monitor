import Darwin
import Foundation

public enum SessionFileStoreError: Error, Equatable {
    case invalidJSONObject
    case openFailed(Int32)
    case lockFailed(Int32)
    case writeFailed(Int32)
    case renameFailed(Int32)
}

/// Cross-process JSON persistence for the hook scripts and the Swift app.
///
/// Every writer locks the same per-record file in `sessions/.locks`, performs
/// its read/modify/write while holding that lock, and promotes a unique temp
/// file with `rename(2)`. Runtime directories and records are owner-only.
public enum SessionFileStore {
    public static func ensurePrivateDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directory.path, 0o700) == 0 else {
            throw SessionFileStoreError.openFailed(errno)
        }
    }

    @discardableResult
    public static func updateJSONObject(
        at fileURL: URL,
        create: () -> [String: Any],
        mutation: (inout [String: Any]) throws -> Void
    ) throws -> [String: Any] {
        try withRecordLock(for: fileURL) {
            var object: [String: Any]
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    object = try readJSONObjectUnlocked(at: fileURL)
                } catch {
                    try quarantineCorruptFileUnlocked(at: fileURL)
                    object = create()
                }
            } else {
                object = create()
            }
            try mutation(&object)
            try writeJSONObjectUnlocked(object, to: fileURL)
            return object
        }
    }

    @discardableResult
    public static func createJSONObjectIfAbsent(
        _ object: [String: Any],
        at fileURL: URL
    ) throws -> Bool {
        try withRecordLock(for: fileURL) {
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                return false
            }
            try writeJSONObjectUnlocked(object, to: fileURL)
            return true
        }
    }

    @discardableResult
    public static func updateJSONObjectIfPresent(
        at fileURL: URL,
        mutation: (inout [String: Any]) throws -> Void
    ) throws -> Bool {
        try withRecordLock(for: fileURL) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return false
            }
            var object: [String: Any]
            do {
                object = try readJSONObjectUnlocked(at: fileURL)
            } catch {
                try quarantineCorruptFileUnlocked(at: fileURL)
                return false
            }
            try mutation(&object)
            try writeJSONObjectUnlocked(object, to: fileURL)
            return true
        }
    }

    public static func readJSONObject(at fileURL: URL) throws -> [String: Any] {
        try withRecordLock(for: fileURL) {
            try readJSONObjectUnlocked(at: fileURL)
        }
    }

    @discardableResult
    public static func remove(
        at fileURL: URL,
        if predicate: (([String: Any]) -> Bool)? = nil
    ) throws -> Bool {
        try withRecordLock(for: fileURL) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return false
            }
            if let predicate {
                let object = try readJSONObjectUnlocked(at: fileURL)
                guard predicate(object) else { return false }
            }
            try FileManager.default.removeItem(at: fileURL)
            return true
        }
    }

    public static func repairPermissions(in directory: URL) throws {
        try ensurePrivateDirectory(directory)
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true,
                  entry.pathExtension == "json" || entry.pathExtension == "permission" else {
                continue
            }
            _ = chmod(entry.path, 0o600)
        }
    }

    @discardableResult
    public static func quarantine(at fileURL: URL) throws -> Bool {
        try withRecordLock(for: fileURL) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return false
            }
            try quarantineCorruptFileUnlocked(at: fileURL)
            return true
        }
    }

    private static func withRecordLock<T>(for fileURL: URL, body: () throws -> T) throws -> T {
        let directory = fileURL.deletingLastPathComponent()
        try ensurePrivateDirectory(directory)
        let locksDirectory = directory.appendingPathComponent(".locks", isDirectory: true)
        try ensurePrivateDirectory(locksDirectory)
        let lockURL = locksDirectory.appendingPathComponent(fileURL.lastPathComponent + ".lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SessionFileStoreError.openFailed(errno) }
        _ = fchmod(fd, S_IRUSR | S_IWUSR)
        guard flock(fd, LOCK_EX) == 0 else {
            let lockError = errno
            Darwin.close(fd)
            throw SessionFileStoreError.lockFailed(lockError)
        }
        defer {
            _ = flock(fd, LOCK_UN)
            Darwin.close(fd)
        }
        return try body()
    }

    private static func readJSONObjectUnlocked(at fileURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SessionFileStoreError.invalidJSONObject
        }
        return object
    }

    private static func writeJSONObjectUnlocked(_ object: [String: Any], to fileURL: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw SessionFileStoreError.invalidJSONObject
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let fd = open(tempURL.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SessionFileStoreError.openFailed(errno) }
        var closeNeeded = true
        defer {
            if closeNeeded { Darwin.close(fd) }
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try data.withUnsafeBytes { rawBuffer in
                guard var base = rawBuffer.baseAddress else { return }
                var remaining = rawBuffer.count
                while remaining > 0 {
                    let count = Darwin.write(fd, base, remaining)
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw SessionFileStoreError.writeFailed(errno)
                    }
                    remaining -= count
                    base = base.advanced(by: count)
                }
            }
            _ = fsync(fd)
            Darwin.close(fd)
            closeNeeded = false
            guard rename(tempURL.path, fileURL.path) == 0 else {
                throw SessionFileStoreError.renameFailed(errno)
            }
            _ = chmod(fileURL.path, 0o600)
        } catch {
            throw error
        }
    }

    private static func quarantineCorruptFileUnlocked(at fileURL: URL) throws {
        let quarantineURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).corrupt.\(UUID().uuidString)"
        )
        guard rename(fileURL.path, quarantineURL.path) == 0 else {
            throw SessionFileStoreError.renameFailed(errno)
        }
        _ = chmod(quarantineURL.path, 0o600)
    }
}
