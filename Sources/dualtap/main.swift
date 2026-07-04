// dualtap — record microphone and system audio together on macOS, no BlackHole.
//
// usage:
//   dualtap record [options] [output]   record until Ctrl+C, then combine
//   dualtap monitor                     live meter for an in-progress recording
//   dualtap devices                     list input devices
//   dualtap menubar                     menu bar recording indicator
//   dualtap --help | --version
import CoreAudio
import DualtapCore
import Foundation

func usage() {
    print("""
    dualtap \(version) — record mic + system audio together on macOS

    usage:
      dualtap record [options] [output]
      dualtap monitor
      dualtap devices
      dualtap menubar

    record options:
      -o, --output PATH        output file (default ./dualtap-<timestamp>.<ext>)
      -f, --format wav|m4a     container (default wav)
      -t, --tracks MODE        combined | separate | both (default combined: L=mic R=sys)
      -r, --rate HZ            resample both sources to HZ (default 48000)
          --transcribe         preset for speech-to-text: 16k m4a, combined
          --mic-device NAME    pin mic by device name or UID (default: auto-probe)
          --no-mic             record system audio only
          --no-system          record microphone only
          --title NAME         label shown in monitor/menubar
      -x, --exec CMD           run CMD after saving ({} or $DUALTAP_OUTPUT = output path)
          --delay DUR          wait DUR before starting (e.g. 10s, 5m, 1h30m)
          --start-at TIME      wait until wall-clock TIME to start (HH:mm[:ss])
          --duration DUR       auto-stop DUR after recording starts (alias --for)
          --stop-at TIME       auto-stop at wall-clock TIME (HH:mm[:ss])
    """)
}

func parseRecord(_ args: [String]) -> RecordOptions {
    var o = RecordOptions()
    var formatSet = false, rateSet = false, tracksSet = false
    var delaySecs: TimeInterval?
    var startAtStr: String?
    var stopAtStr: String?
    var i = 0
    func next(_ name: String) -> String {
        i += 1
        guard i < args.count else { logErr("missing value for \(name)"); exit(2) }
        return args[i]
    }
    while i < args.count {
        let a = args[i]
        switch a {
        case "-o", "--output": o.output = next(a)
        case "-f", "--format":
            guard let c = Container(rawValue: next(a)) else { logErr("bad --format (wav|m4a)"); exit(2) }
            o.container = c; formatSet = true
        case "-t", "--tracks":
            guard let t = Tracks(rawValue: next(a)) else { logErr("bad --tracks (combined|separate|both)"); exit(2) }
            o.tracks = t; tracksSet = true
        case "-r", "--rate":
            guard let r = Int(next(a)), r > 0 else { logErr("bad --rate"); exit(2) }
            o.rate = r; rateSet = true
        case "--transcribe":
            if !formatSet { o.container = .m4a }
            if !rateSet { o.rate = 16000 }
            if !tracksSet { o.tracks = .combined }
        case "--mic-device": o.micDevice = next(a)
        case "--no-mic": o.noMic = true
        case "--no-system": o.noSystem = true
        case "--title": o.title = next(a)
        case "-x", "--exec": o.exec = next(a)
        case "--delay":
            guard let d = parseDuration(next(a)) else { logErr("bad --delay (e.g. 10s, 5m, 1h30m)"); exit(2) }
            delaySecs = d
        case "--start-at": startAtStr = next(a)
        case "--duration", "--for":
            guard let d = parseDuration(next(a)) else { logErr("bad --duration (e.g. 30s, 45m, 1h)"); exit(2) }
            o.duration = d
        case "--stop-at": stopAtStr = next(a)
        default:
            if a.hasPrefix("-") { logErr("unknown option: \(a)"); exit(2) }
            o.output = a // trailing positional output
        }
        i += 1
    }

    if delaySecs != nil && startAtStr != nil {
        logErr("--delay and --start-at are mutually exclusive"); exit(2)
    }
    let now = Date()
    if let d = delaySecs { o.startAt = now.addingTimeInterval(d) }
    if let s = startAtStr {
        guard let d = parseClockTime(s, now: now, calendar: .current) else { logErr("bad --start-at (HH:mm or HH:mm:ss)"); exit(2) }
        o.startAt = d
    }
    if let s = stopAtStr {
        guard let d = parseClockTime(s, now: now, calendar: .current) else { logErr("bad --stop-at (HH:mm or HH:mm:ss)"); exit(2) }
        o.stopAt = d
    }
    return o
}

func cmdDevices() {
    for d in inputDevices() {
        let virt = (d.transport == kAudioDeviceTransportTypeVirtual || d.transport == kAudioDeviceTransportTypeAggregate) ? " (virtual)" : ""
        print("\(d.name)  [uid=\(d.uid)]  \(inputChannelCount(d.id))ch\(virt)")
    }
}

let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first {
case "record": cmdRecord(parseRecord(Array(argv.dropFirst())))
case "monitor": cmdMonitor()
case "devices": cmdDevices()
case "menubar": cmdMenubar()
case "--version", "-v": print(version)
case "--help", "-h", "help", nil: usage()
default:
    logErr("unknown command: \(argv.first ?? "")")
    usage()
    exit(2)
}
