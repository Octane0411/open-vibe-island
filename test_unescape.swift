import Foundation

func unescapeLSOF(_ string: String) -> String {
    var result = ""
    var i = string.startIndex
    var bytes: [UInt8] = []
    
    func flushBytes() {
        if !bytes.isEmpty {
            if let s = String(bytes: bytes, encoding: .utf8) {
                result += s
            } else {
                for b in bytes {
                    result += String(format: "\\x%02x", b)
                }
            }
            bytes.removeAll()
        }
    }
    
    while i < string.endIndex {
        if string[i] == "\\" {
            let nextI = string.index(after: i)
            if nextI < string.endIndex, string[nextI] == "x" {
                let hexStart = string.index(after: nextI)
                if let hexEnd = string.index(hexStart, offsetBy: 2, limitedBy: string.endIndex) {
                    let hexStr = string[hexStart..<hexEnd]
                    if let byte = UInt8(hexStr, radix: 16) {
                        bytes.append(byte)
                        i = hexEnd
                        continue
                    }
                }
            }
        }
        flushBytes()
        result.append(string[i])
        i = string.index(after: i)
    }
    flushBytes()
    return result
}

let input = "\\xe6\\x9c\\xaa\\xe5\\x91\\xbd\\xe5\\x90\\x8d\\xe6\\x96\\x87\\xe4\\xbb\\xb6\\xe5\\xa4\\xb9"
print(unescapeLSOF(input))
