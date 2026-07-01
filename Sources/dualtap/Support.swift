// Support.swift — shared paths, logging, recording state (state.json), afconvert.
import Foundation

enum Paths {
    static let home = NSHomeDirectory()
    static let stateDir = home + "/Library/Caches/dualtap"
    static let stagingDir = stateDir + "/staging"
    static let stateFile = stateDir + "/state.json"
    static let afconvert = "/usr/bin/afconvert"
}

enum DTError: Error, CustomStringConvertible {
    case afconvert([String], String)
    case msg(String)
    var description: String {
        switch self {
        case .afconvert(let a, let o): return "afconvert \(a.joined(separator: " ")): \(o)"
        case .msg(let m): return m
        }
    }
}

func logErr(_ s: String) {
    FileHandle.standardError.write(("dualtap: " + s + "\n").data(using: .utf8)!)
}

// RecState is the shared recording state: record writes it, monitor/menubar read it.
struct RecState: Codable {
    var title: String
    var dir: String
    var startedAt: Date
    var stopAt: Date?

    enum CodingKeys: String, CodingKey {
        case title, dir
        case startedAt = "started_at"
        case stopAt = "stop_at"
    }
}

func loadState() -> RecState? {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: Paths.stateFile)) else { return nil }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return try? dec.decode(RecState.self, from: d)
}

func saveState(_ s: RecState?) {
    try? FileManager.default.createDirectory(atPath: Paths.stateDir, withIntermediateDirectories: true)
    let url = URL(fileURLWithPath: Paths.stateFile)
    guard let s = s else {
        try? FileManager.default.removeItem(at: url)
        return
    }
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    enc.outputFormatting = .prettyPrinted
    if let d = try? enc.encode(s) { try? d.write(to: url) }
}

// runAfconvert runs the system afconvert synchronously; non-zero exit throws with its output.
func runAfconvert(_ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: Paths.afconvert)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        throw DTError.afconvert(args, String(data: out, encoding: .utf8) ?? "")
    }
}
