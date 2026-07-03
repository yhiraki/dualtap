// Record.swift — run mic and system capture together, stop on signal, then combine.
import Foundation

struct RecordOptions {
    var title = "recording"
    var output: String?
    var container: Container = .wav
    var tracks: Tracks = .combined
    var rate: Int?
    var micDevice: String?
    var noMic = false
    var noSystem = false
    var exec: String?
}

// Flag is a lock-guarded stop flag set from a signal handler and polled by the meter loop.
final class Flag {
    private let lock = NSLock()
    private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return v }
}

private var signalSources: [DispatchSourceSignal] = []

// installSignalStop traps SIGINT/SIGTERM on a background queue so the flag flips
// even while the main thread is blocked drawing the meter.
func installSignalStop() -> Flag {
    let flag = Flag()
    let q = DispatchQueue(label: "dualtap.signal")
    for s in [SIGINT, SIGTERM] {
        signal(s, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: s, queue: q)
        src.setEventHandler { flag.set() }
        src.resume()
        signalSources.append(src)
    }
    return flag
}

func cmdRecord(_ o: RecordOptions) {
    if o.noMic && o.noSystem {
        logErr("nothing to record: --no-mic and --no-system are both set")
        exit(2)
    }
    let ts: String = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }()
    let dir = Paths.stagingDir + "/" + ts
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    var sys: SysTap?
    var mic: MicTap?
    do {
        if !o.noSystem {
            let s = SysTap(outWav: dir + "/sys.wav")
            try s.start()
            sys = s
        }
        if !o.noMic {
            let m = MicTap(outWav: dir + "/mic.wav", device: o.micDevice)
            try m.start()
            mic = m
        }
    } catch {
        logErr("failed to start: \(error)")
        sys?.stop(); mic?.stop()
        try? FileManager.default.removeItem(atPath: dir)
        exit(1)
    }

    saveState(RecState(title: o.title, dir: dir, startedAt: Date(), stopAt: nil))
    let flag = installSignalStop()

    if isatty(1) != 0 {
        runMeter(header: "record   (Ctrl+C to stop and save)",
                 frameRec: { loadState() }, shouldStop: { flag.get() })
        print("\u{1b}[?25h")
    } else {
        logErr("recording... send SIGINT/SIGTERM to stop")
        while !flag.get() { Thread.sleep(forTimeInterval: 0.2) }
    }

    mic?.stop()
    sys?.stop()
    saveState(nil)

    let hasMic = !o.noMic && FileManager.default.fileExists(atPath: dir + "/mic.wav")
    let hasSys = !o.noSystem && FileManager.default.fileExists(atPath: dir + "/sys.wav")
    waitSettle(dir: dir, hasMic: hasMic, hasSys: hasSys)

    let ext = o.container.rawValue
    let output = o.output ?? (FileManager.default.currentDirectoryPath + "/dualtap-\(ts).\(ext)")
    let rate = o.rate ?? 48000
    let opts = CombineOptions(output: output, container: o.container, tracks: o.tracks,
                              rate: rate, hasMic: hasMic, hasSys: hasSys)
    do {
        try combine(dir: dir, opts: opts)
    } catch {
        logErr("combine failed: \(error)")
        logErr("raw tracks kept in \(dir)")
        exit(1)
    }
    try? FileManager.default.removeItem(atPath: dir)
    logErr("done → \(output)")

    if let cmd = o.exec {
        runExec(cmd, output: output)
    }
}

// runExec runs a post-processing command after the recording is saved. The command
// is passed to /bin/sh -c; "{}" is replaced with the output path and the same path
// is exported as $DUALTAP_OUTPUT. A non-zero exit is reported but not fatal.
private func runExec(_ cmd: String, output: String) {
    let script = cmd.replacingOccurrences(of: "{}", with: shellQuote(output))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", script]
    var env = ProcessInfo.processInfo.environment
    env["DUALTAP_OUTPUT"] = output
    p.environment = env
    do {
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            logErr("exec exited \(p.terminationStatus): \(cmd)")
        }
    } catch {
        logErr("exec failed to start: \(error)")
    }
}

// shellQuote wraps a string in single quotes safe for /bin/sh.
private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// waitSettle waits until the WAV files stop growing so the stopped taps can finalize.
private func waitSettle(dir: String, hasMic: Bool, hasSys: Bool) {
    let fm = FileManager.default
    for _ in 0..<60 {
        Thread.sleep(forTimeInterval: 1)
        func settled(_ p: String) -> Bool {
            guard let a = try? fm.attributesOfItem(atPath: p), let m = a[.modificationDate] as? Date else { return false }
            return Date().timeIntervalSince(m) > 2
        }
        let micOk = !hasMic || settled(dir + "/mic.wav")
        let sysOk = !hasSys || settled(dir + "/sys.wav")
        if micOk && sysOk { return }
    }
}
