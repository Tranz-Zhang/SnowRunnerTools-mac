import Foundation
import zlib

public enum PakInflaterError: Error, CustomStringConvertible {
    case inflateInitFailed(Int32)
    case inflateFailed(Int32)
    case sizeMismatch(expected: UInt32, actual: Int)

    public var description: String {
        switch self {
        case let .inflateInitFailed(code):
            return "inflateInit2 failed with code \(code)"
        case let .inflateFailed(code):
            return "inflate failed with code \(code)"
        case let .sizeMismatch(expected, actual):
            return "Inflated size mismatch: expected \(expected), got \(actual)"
        }
    }
}

public enum PakInflater {
    public static func inflateRawDeflate(_ compressed: Data, expectedSize: UInt32) throws -> Data {
        var stream = z_stream()
        let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else {
            throw PakInflaterError.inflateInitFailed(initResult)
        }
        defer {
            inflateEnd(&stream)
        }

        let outputCount = Int(expectedSize)
        var output = Data(count: outputCount)
        let result = compressed.withUnsafeBytes { compressedBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: compressedBuffer.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCount)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END else {
            throw PakInflaterError.inflateFailed(result)
        }

        let actualSize = Int(stream.total_out)
        guard actualSize == Int(expectedSize) else {
            throw PakInflaterError.sizeMismatch(expected: expectedSize, actual: actualSize)
        }

        return output
    }
}
