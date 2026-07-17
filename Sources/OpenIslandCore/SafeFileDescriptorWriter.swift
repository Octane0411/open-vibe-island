import Darwin
import Foundation

package enum SafeFileDescriptorWriter {
    /// Writes without allowing an unavailable pipe or descriptor to terminate the hook process.
    package static func write(_ data: Data, to fileDescriptor: Int32 = STDERR_FILENO) {
        guard fcntl(fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            return
        }

        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var offset = 0
            while offset < buffer.count {
                let bytesWritten = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )

                if bytesWritten > 0 {
                    offset += bytesWritten
                } else if bytesWritten == -1, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}
