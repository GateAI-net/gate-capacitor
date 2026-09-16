import Foundation

enum DERParsingError: Error {
    case invalidFormat
    case unsupportedLength
}

enum DER {
    static func ecdsaSignatureToRaw(_ data: Data, coordinateOctetLength: Int) throws -> Data {
        guard data.first == 0x30 else {
            throw DERParsingError.invalidFormat
        }

        var index = 1
        let sequenceLength = try readLength(from: data, index: &index)
        guard sequenceLength == data.count - index else {
            throw DERParsingError.invalidFormat
        }

        guard index < data.count, data[index] == 0x02 else {
            throw DERParsingError.invalidFormat
        }
        index += 1
        let rLength = try readLength(from: data, index: &index)
        guard index + rLength <= data.count else {
            throw DERParsingError.invalidFormat
        }
        let rBytes = data[index..<(index + rLength)]
        index += rLength

        guard index < data.count, data[index] == 0x02 else {
            throw DERParsingError.invalidFormat
        }
        index += 1
        let sLength = try readLength(from: data, index: &index)
        guard index + sLength <= data.count else {
            throw DERParsingError.invalidFormat
        }
        let sBytes = data[index..<(index + sLength)]

        let r = try leftPad(Array(rBytes), to: coordinateOctetLength)
        let s = try leftPad(Array(sBytes), to: coordinateOctetLength)
        var combined = Data()
        combined.append(r)
        combined.append(s)
        return combined
    }

    private static func readLength(from data: Data, index: inout Int) throws -> Int {
        guard index < data.count else {
            throw DERParsingError.invalidFormat
        }

        let first = data[index]
        index += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7F)
        guard byteCount > 0 && byteCount <= 4 else {
            throw DERParsingError.unsupportedLength
        }
        guard index + byteCount <= data.count else {
            throw DERParsingError.invalidFormat
        }

        var value: Int = 0
        for _ in 0..<byteCount {
            value = (value << 8) | Int(data[index])
            index += 1
        }
        return value
    }

    private static func leftPad(_ bytes: [UInt8], to size: Int) throws -> Data {
        var trimmed = bytes
        while trimmed.first == 0 && trimmed.count > 1 {
            trimmed.removeFirst()
        }
        guard trimmed.count <= size else {
            throw DERParsingError.invalidFormat
        }
        let padding = [UInt8](repeating: 0, count: size - trimmed.count)
        return Data(padding + trimmed)
    }
}
