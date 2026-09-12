import Foundation

/// Runs the short-lived helper processes (ps, tmux, tty, osascript) used by
/// hook runtime context resolution.
///
/// Foundation's `Process.waitUntilExit()` polls the run loop and costs a
/// fixed ~67ms per call on macOS no matter how fast the child is, which
/// dominates hook latency once an event resolves its context through a dozen
/// helpers. `posix_spawn` plus `waitpid` has no such overhead (~2ms per call)
/// and gives every call a hard deadline, so a wedged child can never stall a
/// hook.
enum SubprocessRunner {
    /// Outcome of a finished child process.
    struct Result: Sendable {
        let exitStatus: Int32
        let standardOutput: String?
        let timedOut: Bool
    }

    /// Default deadline for helper commands. `ps`, `tmux`, and `tty` finish in
    /// milliseconds; a call still running after this has wedged.
    static let defaultTimeout: TimeInterval = 1.0

    /// Runs the executable and waits for it to finish, or returns nil when the
    /// process could not be spawned. When the deadline passes the child is
    /// killed with SIGKILL and the result is marked `timedOut`.
    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = SubprocessRunner.defaultTimeout
    ) -> Result? {
        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            closeDescriptor(stdoutPipe[0])
            closeDescriptor(stdoutPipe[1])
            closeDescriptor(stderrPipe[0])
            closeDescriptor(stderrPipe[1])
            return nil
        }

        let stdoutRead = stdoutPipe[0]
        let stdoutWrite = stdoutPipe[1]
        let stderrRead = stderrPipe[0]
        let stderrWrite = stderrPipe[1]
        defer {
            closeDescriptor(stdoutRead)
            closeDescriptor(stderrRead)
        }
        setNonBlocking(stdoutRead)
        setNonBlocking(stderrRead)

        var fileActions: posix_spawn_file_actions_t?
        _ = posix_spawn_file_actions_init(&fileActions)
        defer {
            _ = posix_spawn_file_actions_destroy(&fileActions)
        }
        _ = posix_spawn_file_actions_addclose(&fileActions, stdoutRead)
        _ = posix_spawn_file_actions_addclose(&fileActions, stderrRead)
        _ = posix_spawn_file_actions_adddup2(&fileActions, stdoutWrite, STDOUT_FILENO)
        _ = posix_spawn_file_actions_adddup2(&fileActions, stderrWrite, STDERR_FILENO)
        _ = posix_spawn_file_actions_addclose(&fileActions, stdoutWrite)
        _ = posix_spawn_file_actions_addclose(&fileActions, stderrWrite)

        let argumentStrings: [String] = [executablePath] + arguments
        var argv: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { strdup($0) }
        argv.append(nil)

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, executablePath, &fileActions, nil, &argv, environ)
        for pointer in argv {
            if let pointer {
                free(pointer)
            }
        }

        guard spawnStatus == 0 else {
            closeDescriptor(stdoutRead)
            closeDescriptor(stdoutWrite)
            closeDescriptor(stderrRead)
            closeDescriptor(stderrWrite)
            return nil
        }
        // The child holds the write ends now; without closing them here the
        // reads below would never see EOF.
        closeDescriptor(stdoutWrite)
        closeDescriptor(stderrWrite)

        let deadline = Date().addingTimeInterval(timeout)
        var stdoutData = Data()
        var stderrData = Data()
        var stdoutClosed = false
        var stderrClosed = false
        var exitStatus: Int32?
        var timedOut = false
        var pollsAfterExit = 0

        while true {
            var descriptors = [
                pollfd(fd: stdoutClosed ? -1 : stdoutRead, events: Int16(POLLIN), revents: 0),
                pollfd(fd: stderrClosed ? -1 : stderrRead, events: Int16(POLLIN), revents: 0),
            ]
            _ = poll(&descriptors, 2, 20)

            if !stdoutClosed {
                stdoutClosed = drain(stdoutRead, into: &stdoutData)
            }
            if !stderrClosed {
                stderrClosed = drain(stderrRead, into: &stderrData)
            }

            if exitStatus == nil {
                var rawStatus: Int32 = 0
                if waitpid(pid, &rawStatus, WNOHANG) == pid {
                    exitStatus = terminationStatus(from: rawStatus)
                } else if Date() >= deadline {
                    timedOut = true
                    _ = kill(pid, SIGKILL)
                    var killedStatus: Int32 = 0
                    _ = waitpid(pid, &killedStatus, 0)
                    exitStatus = terminationStatus(from: killedStatus)
                }
            }

            if let status = exitStatus {
                if stdoutClosed && stderrClosed {
                    return Result(
                        exitStatus: status,
                        standardOutput: String(data: stdoutData, encoding: .utf8),
                        timedOut: timedOut
                    )
                }
                // The child is dead but a stream has not drained yet; give it
                // a bounded grace period instead of hanging.
                pollsAfterExit += 1
                if pollsAfterExit > 50 {
                    return Result(
                        exitStatus: status,
                        standardOutput: String(data: stdoutData, encoding: .utf8),
                        timedOut: timedOut
                    )
                }
            }
        }
    }

    /// Runs the executable and returns its trimmed stdout, or nil when the
    /// process fails to launch, exits non-zero, exceeds the deadline, or
    /// produces no output.
    static func output(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = SubprocessRunner.defaultTimeout
    ) -> String? {
        guard let result = run(executablePath: executablePath, arguments: arguments, timeout: timeout),
              result.exitStatus == 0,
              let trimmed = result.standardOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func drain(_ descriptor: Int32, into data: inout Data) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count == 0 {
                return true
            } else if errno == EINTR {
                continue
            } else {
                return false
            }
        }
    }

    private static func setNonBlocking(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0 else { return }
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    }

    private static func closeDescriptor(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        _ = close(descriptor)
    }

    private static func terminationStatus(from waitStatus: Int32) -> Int32 {
        let signal = waitStatus & 0x7f
        if signal == 0 {
            return (waitStatus >> 8) & 0xff
        }
        return signal
    }
}
