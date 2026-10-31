import Darwin
import Foundation

/// Filesystem and peer checks protect against other accounts, not arbitrary code running as this user.
enum BridgeSocketIdentity {
    static func prepare(_ url: URL, privateDirectory: Bool) throws -> Int32 {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if privateDirectory {
            var info = stat()
            guard lstat(parent.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR else {
                throw BridgeTransportError.listenerFailed("The bridge directory must be owned by this user and cannot be a symlink.")
            }
            guard chmod(parent.path, 0o700) == 0 else { throw BridgeTransportError.systemCallFailed("chmod directory", errno) }
        }
        let lock = open(url.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw BridgeTransportError.systemCallFailed("open listener lock", errno) }
        do {
            var lockInfo = stat()
            guard fstat(lock, &lockInfo) == 0, lockInfo.st_uid == geteuid(), lockInfo.st_mode & S_IFMT == S_IFREG,
                  flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                throw BridgeTransportError.listenerFailed("Another instance owns this listener, or its lock is unsafe.")
            }
            guard fchmod(lock, 0o600) == 0 else { throw BridgeTransportError.systemCallFailed("chmod listener lock", errno) }
            var existing = stat()
            if lstat(url.path, &existing) == 0 {
                guard existing.st_uid == geteuid(), existing.st_mode & S_IFMT == S_IFSOCK else {
                    throw BridgeTransportError.listenerFailed("Refusing to remove an unrelated socket path.")
                }
                let probe = socket(AF_UNIX, SOCK_STREAM, 0)
                guard probe >= 0 else { throw BridgeTransportError.systemCallFailed("socket probe", errno) }
                defer { close(probe) }
                try makeSocketNonBlocking(probe)
                let failure = try withUnixSocketAddress(path: url.path) { address, length -> Int32 in
                    if Darwin.connect(probe, address, length) == 0 { return 0 }
                    return errno
                }
                guard failure == ECONNREFUSED else {
                    throw BridgeTransportError.listenerFailed("An existing listener is live or cannot be safely inspected.")
                }
                var current = stat()
                guard lstat(url.path, &current) == 0, current.st_dev == existing.st_dev, current.st_ino == existing.st_ino,
                      current.st_uid == geteuid(), current.st_mode & S_IFMT == S_IFSOCK else {
                    throw BridgeTransportError.listenerFailed("The socket path changed during startup.")
                }
                guard unlink(url.path) == 0 else { throw BridgeTransportError.systemCallFailed("unlink stale socket", errno) }
            } else if errno != ENOENT {
                throw BridgeTransportError.systemCallFailed("inspect socket", errno)
            }
            return lock
        } catch {
            close(lock)
            throw error
        }
    }

    static func isCurrentUser(_ descriptor: Int32) -> Bool {
        var user: uid_t = 0
        var group: gid_t = 0
        return getpeereid(descriptor, &user, &group) == 0 && user == geteuid()
    }
}
