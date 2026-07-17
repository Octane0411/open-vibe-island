import Foundation
import Testing
@testable import OpenIslandCore

struct SafeFileDescriptorWriterTests {
    @Test
    func writesToAvailablePipe() throws {
        let pipe = Pipe()
        let data = Data("hook diagnostic\n".utf8)

        SafeFileDescriptorWriter.write(data, to: pipe.fileHandleForWriting.fileDescriptor)
        try pipe.fileHandleForWriting.close()

        #expect(try pipe.fileHandleForReading.readToEnd() == data)
    }

    @Test
    func ignoresClosedFileDescriptor() throws {
        let pipe = Pipe()
        let fileDescriptor = pipe.fileHandleForWriting.fileDescriptor
        try pipe.fileHandleForWriting.close()

        SafeFileDescriptorWriter.write(Data("discarded".utf8), to: fileDescriptor)
    }

    @Test
    func ignoresPipeWithoutReader() throws {
        let pipe = Pipe()
        try pipe.fileHandleForReading.close()

        SafeFileDescriptorWriter.write(
            Data("discarded".utf8),
            to: pipe.fileHandleForWriting.fileDescriptor
        )
        try pipe.fileHandleForWriting.close()
    }
}
