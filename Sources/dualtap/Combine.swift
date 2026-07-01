// Combine.swift — post-processing after stop: normalize each source to 16-bit mono at a
// common rate, then interleave L=mic/R=sys for combined, or emit separate files.
import Foundation

enum Tracks: String { case combined, separate, both }
enum Container: String { case wav, m4a }

struct CombineOptions {
    var output: String        // output path for the combined track
    var container: Container
    var tracks: Tracks
    var rate: Int             // common sample rate
    var hasMic: Bool
    var hasSys: Bool
}

// combine post-processes the staging dir's mic.wav/sys.wav into the final output(s).
func combine(dir: String, opts: CombineOptions) throws {
    let mic = dir + "/mic.wav"
    let sys = dir + "/sys.wav"
    let mic16 = dir + "/mic16.wav"
    let sys16 = dir + "/sys16.wav"

    // 1) normalize each source to LEI16 mono at the target rate
    if opts.hasMic {
        try runAfconvert(["-f", "WAVE", "-d", "LEI16@\(opts.rate)", "-c", "1", mic, mic16])
    }
    if opts.hasSys {
        try runAfconvert(["-f", "WAVE", "-d", "LEI16@\(opts.rate)", "-c", "1", sys, sys16])
    }

    let ext = opts.container.rawValue
    let base = stripExt(opts.output)

    // 2) combined: L=mic / R=sys
    if opts.tracks == .combined || opts.tracks == .both {
        if opts.hasMic && opts.hasSys {
            let (sr, micS) = try readMonoWAV(mic16)
            let (_, sysS) = try readMonoWAV(sys16)
            let stereo = dir + "/stereo.wav"
            try writeStereoWAV(stereo, sampleRate: sr, left: micS, right: sysS)
            try encode(stereo, to: opts.output, container: opts.container)
        } else {
            // only one source present: emit it as mono (cannot make an L/R pair)
            let only = opts.hasMic ? mic16 : sys16
            try encode(only, to: opts.output, container: opts.container)
        }
    }

    // 3) separate: individual tracks
    if opts.tracks == .separate || opts.tracks == .both {
        if opts.hasMic { try encode(mic16, to: "\(base).mic.\(ext)", container: opts.container) }
        if opts.hasSys { try encode(sys16, to: "\(base).sys.\(ext)", container: opts.container) }
    }
}

// encode emits a 16-bit WAV into the final container: copy for wav, AAC via afconvert for m4a.
private func encode(_ srcWav: String, to out: String, container: Container) throws {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    switch container {
    case .wav:
        try? fm.removeItem(atPath: out)
        try fm.copyItem(atPath: srcWav, toPath: out)
    case .m4a:
        try runAfconvert(["-f", "m4af", "-d", "aac", srcWav, out])
    }
}

private func stripExt(_ path: String) -> String {
    let ns = path as NSString
    return ns.pathExtension.isEmpty ? path : ns.deletingPathExtension
}
