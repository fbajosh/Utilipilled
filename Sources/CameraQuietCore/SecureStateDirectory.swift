import Foundation
import Darwin

/// The state folder is a private namespace, not an arbitrary path to follow on each access.
/// Keep its descriptor open so later operations cannot be redirected by replacing its path.
public final class SecureStateDirectory {
    public let url: URL
    public let descriptor: Int32

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.operationError("open private state folder") }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else {
            let error = Self.operationError("inspect state folder"); close(fd); throw error
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              metadata.st_uid == geteuid(), metadata.st_mode & mode_t(0o077) == 0 else {
            close(fd)
            throw QuietError.failure("State folder must be a real directory owned by the current user with private permissions (0700). Inspect the folder before correcting its permissions.")
        }
        descriptor = fd
    }

    deinit { close(descriptor) }

    /// Returns a caller-owned descriptor. Never opens symbolic links, FIFOs or shared files.
    /// O_NONBLOCK prevents a hostile FIFO from blocking before its type can be inspected.
    public func openPrivateRegularFile(_ name: String, flags: Int32, mode: mode_t = 0o600) throws -> Int32 {
        try validateName(name)
        guard flags & O_TRUNC == 0 else { throw QuietError.failure("Unsafe state-file open flags") }
        let fd = openat(descriptor, name, flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode)
        guard fd >= 0 else { throw Self.operationError("open state file \(name)") }
        do { try validateFile(fd); return fd }
        catch { close(fd); throw error }
    }

    public func openExistingPrivateRegularFile(_ name: String) throws -> Int32? {
        try validateName(name)
        let fd = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw Self.operationError("open state file \(name)")
        }
        do { try validateFile(fd); return fd }
        catch { close(fd); throw error }
    }

    public func synchronize() throws {
        guard fsync(descriptor) == 0 else { throw Self.operationError("synchronize state folder") }
    }

    private func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw QuietError.failure("Invalid state filename")
        }
    }

    private func validateFile(_ fd: Int32) throws {
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw Self.operationError("inspect state file") }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_uid == geteuid(),
              metadata.st_mode & mode_t(0o077) == 0, metadata.st_nlink == 1 else {
            throw QuietError.failure("State file must be a private regular file owned by the current user, without symbolic or hard links.")
        }
    }

    static func operationError(_ action: String) -> QuietError {
        QuietError.failure("Could not \(action): \(String(cString: strerror(errno)))")
    }
}
