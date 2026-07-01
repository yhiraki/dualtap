// SysTap — capture all system audio via a Core Audio process tap. No BlackHole.
// Requires the process-tap API (macOS 14.4+); first run prompts for audio recording.
import AudioToolbox
import AVFoundation
import CoreAudio

final class SysTap {
    private let outURL: URL
    private let levelURL: URL
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var extFile: ExtAudioFileRef?
    private var asbd = AudioStreamBasicDescription()
    private let level = LevelBox()
    private var levelTimer: DispatchSourceTimer?
    private var cleanedUp = false
    private let cleanupLock = NSLock()

    final class LevelBox { var rms: Double = 0 }

    init(outWav: String) {
        outURL = URL(fileURLWithPath: outWav)
        levelURL = URL(fileURLWithPath: outWav + ".level")
    }

    func start() throws {
        // 1) system-wide tap over all processes (no exclusions)
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.uuid = UUID()
        tapDesc.name = "dualtap-sys"
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted // do not mute playback while recording

        var st = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard st == noErr, tapID != kAudioObjectUnknown else {
            throw DTError.msg("AudioHardwareCreateProcessTap failed (OSStatus=\(st))")
        }

        // 2) private aggregate device containing only the tap
        let aggUID = UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "dualtap-agg",
            kAudioAggregateDeviceUIDKey as String: aggUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceMainSubDeviceKey as String: "",
            kAudioAggregateDeviceTapListKey as String: [[
                kAudioSubTapUIDKey as String: tapDesc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey as String: true,
            ]],
            kAudioAggregateDeviceSubDeviceListKey as String: [],
        ]
        st = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard st == noErr, aggID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            throw DTError.msg("AudioHardwareCreateAggregateDevice failed (OSStatus=\(st))")
        }

        // 3) read the tap's audio format (usually float32)
        var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        st = AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &sz, &asbd)
        guard st == noErr else { throw DTError.msg("failed to read tap format (OSStatus=\(st))") }

        // 4) open the WAV in the tap's own float format (no conversion)
        st = ExtAudioFileCreateWithURL(
            outURL as CFURL, kAudioFileWAVEType, &asbd, nil,
            AudioFileFlags.eraseFile.rawValue, &extFile)
        guard st == noErr, let ext = extFile else { throw DTError.msg("failed to create output WAV (OSStatus=\(st))") }
        st = ExtAudioFileSetProperty(ext, kExtAudioFileProperty_ClientDataFormat,
                                     UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &asbd)
        guard st == noErr else { throw DTError.msg("failed to set ClientDataFormat (OSStatus=\(st))") }
        ExtAudioFileWriteAsync(ext, 0, nil) // prime the async write buffer before the IOProc runs

        // 5) read from the aggregate device in an IOProc and write with ExtAudioFileWriteAsync
        let bytesPerFrame = max(asbd.mBytesPerFrame, 1)
        let levelBox = level
        let ioQueue = DispatchQueue(label: "dualtap.systap.io")
        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, ioQueue) { (_, inInputData, _, _, _) in
            let abl = inInputData
            let frames = abl.pointee.mBuffers.mDataByteSize / bytesPerFrame
            if frames > 0 {
                _ = ExtAudioFileWriteAsync(ext, frames, abl)
                if let mData = abl.pointee.mBuffers.mData {
                    let n = Int(abl.pointee.mBuffers.mDataByteSize) / 4 // float32
                    if n > 0 {
                        let p = mData.assumingMemoryBound(to: Float.self)
                        var s = 0.0
                        for i in 0..<n { let f = Double(p[i]); s += f * f }
                        levelBox.rms = (s / Double(n)).squareRoot()
                    }
                }
            }
        }
        guard st == noErr, let proc = procID else { throw DTError.msg("failed to create IOProc (OSStatus=\(st))") }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "dualtap.systap.level"))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [levelURL, levelBox] in
            try? String(format: "%.6f\n", levelBox.rms).write(to: levelURL, atomically: false, encoding: .utf8)
        }
        timer.resume()
        levelTimer = timer

        st = AudioDeviceStart(aggID, proc)
        guard st == noErr else { cleanup(); throw DTError.msg("AudioDeviceStart failed (OSStatus=\(st))") }
        logErr("systap: recording → \(outURL.path)")
    }

    func stop() { cleanup() }

    private func cleanup() {
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        if cleanedUp { return }
        cleanedUp = true
        levelTimer?.cancel()
        try? FileManager.default.removeItem(at: levelURL)
        if let proc = procID {
            AudioDeviceStop(aggID, proc)
            AudioDeviceDestroyIOProcID(aggID, proc)
        }
        if let ext = extFile { ExtAudioFileDispose(ext) }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    }
}
