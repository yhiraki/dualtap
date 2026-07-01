// Meter.swift — terminal live meter. It watches each <wav>.level file (updated every
// 0.2s with the current RMS) rather than process liveness, so silence shows up.
import Foundation

// readLevel reads <wav>.level and returns (RMS, age, valid).
private func readLevel(_ path: String) -> (Double, TimeInterval, Bool) {
    let fm = FileManager.default
    guard let attr = try? fm.attributesOfItem(atPath: path),
          let m = attr[.modificationDate] as? Date,
          let s = try? String(contentsOfFile: path, encoding: .utf8),
          let v = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return (0, 0, false)
    }
    return (v, Date().timeIntervalSince(m), true)
}

// bar maps an RMS value to a dBFS (-60..0) bar string.
private func bar(_ rms: Double, _ width: Int) -> String {
    var norm = 0.0
    if rms > 0 { norm = (20 * log10(rms) + 60) / 60 }
    norm = min(max(norm, 0), 1)
    let f = Int(norm * Double(width))
    return String(repeating: "█", count: f) + String(repeating: "·", count: width - f)
}

private func levelLine(_ label: String, _ levelPath: String) -> String {
    let (rms, age, ok) = readLevel(levelPath)
    var tag = ""
    if !ok { tag = "  ⚠ no source" }
    else if age > 2 { tag = "  ⚠ stale (silent/stopped?)" }
    let db = rms > 0 ? 20 * log10(rms) : -99.0
    return String(format: "  %-4@ [%@] %5.0f dB%@", label as NSString, bar(rms, 30) as NSString, db, tag as NSString)
}

// meterFrame renders one frame; a nil rec shows the idle screen.
func meterFrame(_ rec: RecState?, header: String) -> String {
    var b = "\u{1b}[H\u{1b}[2J"
    b += "● dualtap  " + header + "\n"
    b += "────────────────────────────────────────────────────\n"
    if let rec = rec {
        let el = Int(Date().timeIntervalSince(rec.startedAt))
        b += String(format: "🔴 recording: %@\n", rec.title as NSString)
        var line = String(format: "   elapsed %02d:%02d", el / 60, el % 60)
        if let stop = rec.stopAt {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            line += "   stop@ " + f.string(from: stop)
        }
        b += line + "\n\n"
        b += levelLine("mic", rec.dir + "/mic.wav.level") + "\n"
        b += levelLine("sys", rec.dir + "/sys.wav.level") + "\n"
    } else {
        b += "⚪ not recording\n"
    }
    return b
}

// runMeter draws the meter until shouldStop returns true.
func runMeter(header: String, frameRec: @escaping () -> RecState?, shouldStop: @escaping () -> Bool) {
    print("\u{1b}[?25l", terminator: "") // hide cursor
    while !shouldStop() {
        FileHandle.standardOutput.write(meterFrame(frameRec(), header: header).data(using: .utf8)!)
        Thread.sleep(forTimeInterval: 0.15)
    }
    print("\u{1b}[?25h", terminator: "") // show cursor
}

// cmdMonitor watches state.json and renders until interrupted.
func cmdMonitor() {
    let flag = installSignalStop()
    runMeter(header: "monitor   (Ctrl+C to quit)", frameRec: { loadState() }, shouldStop: { flag.get() })
    print("\u{1b}[?25h")
}
