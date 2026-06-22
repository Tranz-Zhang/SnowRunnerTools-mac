import Foundation
import zlib

public enum PakDeflaterError: Error, CustomStringConvertible {
    case deflateInitFailed(Int32)
    case deflateFailed(Int32)

    public var description: String {
        switch self {
        case let .deflateInitFailed(code):
            return "deflateInit2 failed with code \(code)"
        case let .deflateFailed(code):
            return "deflate failed with code \(code)"
        }
    }
}

public enum PakDeflater {
    public static func deflateRaw(_ input: Data) throws -> Data {
        var stream = z_stream()
        let initResult = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            MAX_MEM_LEVEL,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else {
            throw PakDeflaterError.deflateInitFailed(initResult)
        }
        defer {
            deflateEnd(&stream)
        }

        let outputCount = max(64, Int(compressBound(uLong(input.count))))
        var output = Data(count: outputCount)
        let result = input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCount)
                return deflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END else {
            throw PakDeflaterError.deflateFailed(result)
        }

        return output.prefix(Int(stream.total_out))
    }
}
