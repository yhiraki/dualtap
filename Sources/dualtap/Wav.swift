// Wav.swift — minimal 16-bit PCM WAV I/O used to interleave two mono tracks.
import Foundation

// readMonoWAV reads a 16-bit PCM mono WAV (as produced by afconvert normalization).
func readMonoWAV(_ path: String) throws -> (sampleRate: UInt32, samples: [Int16]) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let b = [UInt8](data)
    func u16(_ o: Int) -> UInt16 { UInt16(b[o]) | (UInt16(b[o + 1]) << 8) }
    func u32(_ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
    guard b.count >= 12,
          String(bytes: b[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: b[8..<12], encoding: .ascii) == "WAVE" else {
        throw DTError.msg("\(path): not RIFF/WAVE")
    }
    var sr: UInt32 = 0
    var ch: UInt16 = 0
    var bits: UInt16 = 0
    var dataStart = 0
    var dataLen = 0
    var pos = 12
    while pos + 8 <= b.count {
        let id = String(bytes: b[pos..<pos + 4], encoding: .ascii) ?? ""
        let sz = Int(u32(pos + 4))
        let body = pos + 8
        switch id {
        case "fmt ":
            ch = u16(body + 2)
            sr = u32(body + 4)
            bits = u16(body + 14)
        case "data":
            dataStart = body
            dataLen = sz
        default:
            break
        }
        pos = body + sz
        if sz % 2 == 1 { pos += 1 }
    }
    guard bits == 16, ch == 1 else {
        throw DTError.msg("\(path): expected 16-bit mono, got \(bits)-bit/\(ch)ch")
    }
    guard dataStart != 0 else { throw DTError.msg("\(path): no data chunk") }
    if dataStart + dataLen > b.count { dataLen = b.count - dataStart }
    let n = dataLen / 2
    var s = [Int16](repeating: 0, count: n)
    for i in 0..<n { s[i] = Int16(bitPattern: u16(dataStart + i * 2)) }
    return (sr, s)
}

// writeStereoWAV writes left/right into separate L/R channels (the shorter side is
// zero-padded). Channels are kept separate, not mixed.
func writeStereoWAV(_ path: String, sampleRate: UInt32, left: [Int16], right: [Int16]) throws {
    let n = max(left.count, right.count)
    let dataLen = n * 2 * 2 // 2ch * 2 bytes
    var buf = [UInt8](repeating: 0, count: 44 + dataLen)
    func putU16(_ o: Int, _ v: UInt16) { buf[o] = UInt8(v & 0xff); buf[o + 1] = UInt8(v >> 8) }
    func putU32(_ o: Int, _ v: UInt32) {
        buf[o] = UInt8(v & 0xff); buf[o + 1] = UInt8((v >> 8) & 0xff)
        buf[o + 2] = UInt8((v >> 16) & 0xff); buf[o + 3] = UInt8((v >> 24) & 0xff)
    }
    func putStr(_ o: Int, _ s: String) { for (i, c) in Array(s.utf8).enumerated() { buf[o + i] = c } }
    putStr(0, "RIFF"); putU32(4, UInt32(36 + dataLen)); putStr(8, "WAVE")
    putStr(12, "fmt "); putU32(16, 16); putU16(20, 1); putU16(22, 2)
    putU32(24, sampleRate); putU32(28, sampleRate * 4); putU16(32, 4); putU16(34, 16)
    putStr(36, "data"); putU32(40, UInt32(dataLen))
    for i in 0..<n {
        let l = i < left.count ? left[i] : 0
        let r = i < right.count ? right[i] : 0
        let off = 44 + i * 4
        putU16(off, UInt16(bitPattern: l))
        putU16(off + 2, UInt16(bitPattern: r))
    }
    try Data(buf).write(to: URL(fileURLWithPath: path))
}
