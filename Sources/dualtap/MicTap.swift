// MicTap — capture the microphone via AVAudioEngine.
// Device selection order: explicit (UID/name) > built-in mic > physical input > default.
// The chosen device is probed for live (non-digital-silence) audio and pinned so a
// default-input switch by another app cannot hijack the recording; configuration changes
// during recording are detected and the engine is reconfigured to continue.
import AVFoundation
import CoreAudio

struct InputDevice {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let transport: UInt32
}

private func propAddr(_ selector: AudioObjectPropertySelector,
                      _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func allDeviceIDs() -> [AudioDeviceID] {
    var addr = propAddr(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func inputChannelCount(_ id: AudioDeviceID) -> Int {
    var addr = propAddr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
}

private func stringProp(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
    var addr = propAddr(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var cf: CFString?
    let st = withUnsafeMutablePointer(to: &cf) {
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
    }
    if st == noErr, let s = cf as String? { return s }
    return ""
}

private func transportType(_ id: AudioDeviceID) -> UInt32 {
    var addr = propAddr(kAudioDevicePropertyTransportType)
    var t: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
    return t
}

func inputDevices() -> [InputDevice] {
    allDeviceIDs().compactMap { id in
        guard inputChannelCount(id) > 0 else { return nil }
        return InputDevice(id: id,
                           name: stringProp(id, kAudioObjectPropertyName),
                           uid: stringProp(id, kAudioDevicePropertyDeviceUID),
                           transport: transportType(id))
    }
}

// Virtual devices (BlackHole / meeting-app virtual inputs / aggregates) are never auto-selected.
private func isVirtual(_ t: UInt32) -> Bool {
    t == kAudioDeviceTransportTypeVirtual || t == kAudioDeviceTransportTypeAggregate
}

final class MicTap {
    private let outURL: URL
    private let levelURL: URL
    private let wantDevice: String?
    private let engine = AVAudioEngine()
    private lazy var input = engine.inputNode
    private let writeLock = NSLock()
    private var stopped = false
    private var file: AVAudioFile?
    private let level = LevelBox()
    private var levelTimer: DispatchSourceTimer?
    private var selected: InputDevice?
    private var fmt: AVAudioFormat!
    private var observer: NSObjectProtocol?

    final class LevelBox { var rms: Double = 0 }

    init(outWav: String, device: String?) {
        outURL = URL(fileURLWithPath: outWav)
        levelURL = URL(fileURLWithPath: outWav + ".level")
        wantDevice = device
    }

    // Order: explicit > built-in > physical > default(fallback). A nil id means "use the
    // default input without pinning". Candidates are returned in order so start() can probe them.
    private func orderedCandidates() -> [(InputDevice?, String)] {
        let devices = inputDevices()
        var out: [(InputDevice?, String)] = []
        var seen = Set<AudioDeviceID>()
        func add(_ d: InputDevice?, _ reason: String) {
            if let d = d {
                if seen.contains(d.id) { return }
                seen.insert(d.id)
            }
            out.append((d, reason))
        }
        if let want = wantDevice, !want.isEmpty {
            if let d = devices.first(where: { $0.uid == want || $0.name == want }) {
                add(d, "explicit device")
            } else {
                logErr("mictap: device '\(want)' not found → falling back to priority order")
            }
        }
        if let d = devices.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) {
            add(d, "built-in mic")
        }
        for d in devices where !isVirtual(d.transport) { add(d, "physical input") }
        add(nil, "default input (fallback)")
        return out
    }

    // Pin the recording device on the input AudioUnit so it does not follow default-input changes.
    private func pinDevice(_ devID: AudioDeviceID) {
        guard let unit = input.audioUnit else {
            logErr("mictap: no input AudioUnit; skipping device pin")
            return
        }
        var dev = devID
        let st = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                      kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        if st != noErr { logErr("mictap: failed to pin device OSStatus=\(st)") }
    }

    // Probe a device by sampling briefly and checking for a non-silent max amplitude:
    // a live mic has a noise floor (maxAbs > 0); a dead/virtual device stays at 0 or delivers no buffers.
    private func probe(_ devID: AudioDeviceID?) -> (alive: Bool, maxAbs: Float, sampleRate: Double, channels: UInt32) {
        let silenceEps: Float = 1e-6
        let probeMaxSec = 2.0
        if let id = devID { pinDevice(id) }
        let pfmt = input.inputFormat(forBus: 0)
        if pfmt.sampleRate <= 0 { return (false, 0, 0, 0) }
        let probeLock = NSLock()
        var maxAbs: Float = 0
        var buffers = 0
        input.installTap(onBus: 0, bufferSize: 4096, format: pfmt) { buffer, _ in
            probeLock.lock(); buffers += 1; probeLock.unlock()
            guard let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let chs = Int(buffer.format.channelCount)
            var m: Float = 0
            for c in 0..<chs {
                let p = ch[c]
                for i in 0..<n { let a = abs(p[i]); if a > m { m = a } }
            }
            probeLock.lock(); if m > maxAbs { maxAbs = m }; probeLock.unlock()
        }
        var started = true
        do { try engine.start() } catch {
            logErr("mictap: probe start failed: \(error)")
            started = false
        }
        if started {
            let deadline = Date().addingTimeInterval(probeMaxSec)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
                probeLock.lock(); let mx = maxAbs; probeLock.unlock()
                if mx > silenceEps { break }
            }
        }
        engine.stop()
        input.removeTap(onBus: 0)
        probeLock.lock(); let b = buffers; let mx = maxAbs; probeLock.unlock()
        return (started && b > 0 && mx > silenceEps, mx, pfmt.sampleRate, pfmt.channelCount)
    }

    func start() throws {
        let candidates = orderedCandidates()
        var reason = ""
        for (cand, why) in candidates {
            let label = cand.map { "\($0.name) [\(why)]" } ?? "system default [\(why)]"
            let r = probe(cand?.id)
            if r.alive {
                selected = cand
                reason = why
                logErr("mictap: using \(label) — alive (maxAbs=\(String(format: "%.5f", r.maxAbs)), \(Int(r.sampleRate))Hz \(r.channels)ch)")
                break
            }
            logErr("mictap: skip \(label) — silent/invalid (maxAbs=\(String(format: "%.5f", r.maxAbs)))")
        }
        if selected == nil && reason == "" {
            let (cand, why) = candidates.first ?? (nil, "default input")
            selected = cand
            reason = why
            logErr("mictap: warning: all inputs silent; recording with \(cand?.name ?? "system default")[\(why)] but the mic may not be captured")
        }

        if let dev = selected {
            pinDevice(dev.id)
            logErr("mictap: input device: \(dev.name) [uid=\(dev.uid)] (\(reason))")
        } else {
            logErr("mictap: input device: system default (\(reason)) — not pinned")
        }

        fmt = input.inputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { throw DTError.msg("cannot get input format (check mic permission)") }
        logErr("mictap: format: \(Int(fmt.sampleRate))Hz \(fmt.channelCount)ch")

        do {
            file = try AVAudioFile(forWriting: outURL, settings: fmt.settings)
        } catch {
            throw DTError.msg("failed to create output WAV: \(error)")
        }

        installTap()

        // A configuration change (switch/unplug) stops AVAudioEngine; detect it and reconfigure.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.writeLock.lock(); let done = self.stopped; self.writeLock.unlock()
            if done { return }
            logErr("mictap: configuration change detected — reconfiguring to continue")
            self.engine.stop()
            self.input.removeTap(onBus: 0)
            if let dev = self.selected { self.pinDevice(dev.id) }
            let newFmt = self.input.inputFormat(forBus: 0)
            if newFmt.sampleRate != self.fmt.sampleRate || newFmt.channelCount != self.fmt.channelCount {
                logErr("mictap: warning: input format changed (\(Int(newFmt.sampleRate))Hz \(newFmt.channelCount)ch); mic may drop")
            }
            self.installTap()
            do { try self.engine.start(); logErr("mictap: resumed") }
            catch { logErr("mictap: resume failed: \(error)") }
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "dualtap.mictap.level"))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [levelURL, level] in
            try? String(format: "%.6f\n", level.rms).write(to: levelURL, atomically: false, encoding: .utf8)
        }
        timer.resume()
        levelTimer = timer

        do { try engine.start() } catch {
            cleanup()
            throw DTError.msg("failed to start AVAudioEngine: \(error)")
        }
        logErr("mictap: recording → \(outURL.path)")
    }

    private func installTap() {
        input.installTap(onBus: 0, bufferSize: 4096, format: input.inputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.writeLock.lock()
            if !self.stopped { try? self.file?.write(from: buffer) }
            self.writeLock.unlock()
            if let ch = buffer.floatChannelData {
                let n = Int(buffer.frameLength)
                let chs = Int(buffer.format.channelCount)
                if n > 0 && chs > 0 {
                    var s = 0.0
                    for c in 0..<chs {
                        let p = ch[c]
                        for i in 0..<n { let f = Double(p[i]); s += f * f }
                    }
                    self.level.rms = (s / Double(n * chs)).squareRoot()
                }
            }
        }
    }

    func stop() { cleanup() }

    private func cleanup() {
        writeLock.lock()
        if stopped { writeLock.unlock(); return }
        stopped = true
        writeLock.unlock()
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        levelTimer?.cancel()
        try? FileManager.default.removeItem(at: levelURL)
        engine.stop()
        input.removeTap(onBus: 0)
        writeLock.lock()
        file = nil // deallocate → finalize the WAV
        writeLock.unlock()
    }
}
