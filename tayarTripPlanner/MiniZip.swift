//
//  MiniZip.swift
//  tayarTripPlanner
//
//  Minimal read-only ZIP extraction (enough for .xlsx files) using the
//  Compression framework — avoids any third-party dependency.
//

import Foundation
import Compression

nonisolated enum MiniZip {
    struct Entry {
        let name: String
        let method: Int             // 0 = stored, 8 = deflate
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    static func entries(in data: Data) -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { return [] }

        // Locate End Of Central Directory record (scan backwards, max 64 KB comment).
        var eocd = -1
        let lowerBound = max(0, bytes.count - 22 - 65536)
        var i = bytes.count - 22
        while i >= lowerBound {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { return [] }

        let entryCount = u16(bytes, eocd + 10)
        var offset = u32(bytes, eocd + 16)
        var result: [Entry] = []
        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count,
                  bytes[offset] == 0x50, bytes[offset + 1] == 0x4B,
                  bytes[offset + 2] == 0x01, bytes[offset + 3] == 0x02 else { break }
            let method = u16(bytes, offset + 10)
            let compressed = u32(bytes, offset + 20)
            let uncompressed = u32(bytes, offset + 24)
            let nameLength = u16(bytes, offset + 28)
            let extraLength = u16(bytes, offset + 30)
            let commentLength = u16(bytes, offset + 32)
            let localOffset = u32(bytes, offset + 42)
            let nameBytes = Array(bytes[(offset + 46)..<(offset + 46 + nameLength)])
            let name = String(bytes: nameBytes, encoding: .utf8) ?? ""
            result.append(Entry(name: name, method: method, compressedSize: compressed,
                                uncompressedSize: uncompressed, localHeaderOffset: localOffset))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    static func extract(_ name: String, from data: Data) -> Data? {
        guard let entry = entries(in: data).first(where: { $0.name == name }) else { return nil }
        let bytes = [UInt8](data)
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count,
              bytes[header] == 0x50, bytes[header + 1] == 0x4B,
              bytes[header + 2] == 0x03, bytes[header + 3] == 0x04 else { return nil }
        let nameLength = u16(bytes, header + 26)
        let extraLength = u16(bytes, header + 28)
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { return nil }
        let payload = Array(bytes[start..<(start + entry.compressedSize)])

        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            // Compression's COMPRESSION_ZLIB is raw DEFLATE, which is what ZIP stores.
            let capacity = max(entry.uncompressedSize, 1)
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { dst in
                payload.withUnsafeBufferPointer { src in
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        src.baseAddress!, payload.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            guard written > 0 else { return nil }
            output.removeSubrange(written..<output.count)
            return output
        default:
            return nil
        }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
    }
}
