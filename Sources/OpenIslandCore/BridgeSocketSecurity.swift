import Darwin
import Foundation

enum BridgeSocketSecurity {
    static func isCurrentUser(_ descriptor: Int32) -> Bool {
        var user: uid_t = 0
        var group: gid_t = 0
        return getpeereid(descriptor, &user, &group) == 0 && user == geteuid()
    }

    static func listen(at url: URL) throws -> Int32 {
        try preparePath(url)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor != -1 else { throw failure("socket") }
        do {
            try withUnixSocketAddress(path: url.path) { address, length in
                guard bind(descriptor, address, length) == 0 else { throw failure("bind") }
            }
            guard chmod(url.path, 0o600) == 0 else { throw failure("chmod") }
            guard Darwin.listen(descriptor, 16) == 0 else { throw failure("listen") }
            try makeSocketNonBlocking(descriptor)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func preparePath(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if url == BridgeSocketLocation.defaultURL {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var directory = stat()
            guard lstat(parent.path, &directory) == 0,
                  directory.st_uid == geteuid(),
                  directory.st_mode & S_IFMT == S_IFDIR else {
                throw BridgeTransportError.listenerFailed("Unsafe bridge directory")
            }
            guard chmod(parent.path, 0o700) == 0 else { throw failure("chmod") }
        }
        try removeStaleSocket(url)
    }

    private static func removeStaleSocket(_ url: URL) throws {
        var existing = stat()
        guard lstat(url.path, &existing) == 0 else {
            if errno == ENOENT { return }
            throw failure("lstat")
        }
        guard existing.st_uid == geteuid(), existing.st_mode & S_IFMT == S_IFSOCK else {
            throw BridgeTransportError.listenerFailed("Refusing to replace a non-owned socket")
        }
        guard unlink(url.path) == 0 else { throw failure("unlink") }
    }

    private static func failure(_ operation: String) -> BridgeTransportError {
        .systemCallFailed(operation, errno)
    }
}
