// Schedule.swift — pure parsers for the record start/stop scheduling options.
import Foundation

// parseDuration parses "90", "45s", "5m", "1h", or combos like "1h30m15s" into seconds.
// A bare number is seconds. Returns nil if malformed or negative.
public func parseDuration(_ s: String) -> TimeInterval? {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return nil }
    if let secs = Double(t) { return secs >= 0 ? secs : nil }
    var total = 0.0
    var num = ""
    for ch in t {
        if ch.isNumber || ch == "." {
            num.append(ch)
            continue
        }
        guard let v = Double(num) else { return nil }
        switch ch {
        case "s", "S": total += v
        case "m", "M": total += v * 60
        case "h", "H": total += v * 3600
        default: return nil
        }
        num = ""
    }
    return num.isEmpty ? total : nil  // trailing number without a unit is invalid
}

// parseClockTime parses "HH:mm" or "HH:mm:ss" (24h, local) and returns the next
// occurrence at or after `now` (rolling to tomorrow if the time already passed today).
public func parseClockTime(_ s: String, now: Date, calendar: Calendar) -> Date? {
    let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2 || parts.count == 3 else { return nil }
    guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    let sec = parts.count == 3 ? Int(parts[2]) : 0
    guard let sec = sec else { return nil }
    guard (0..<24).contains(h), (0..<60).contains(m), (0..<60).contains(sec) else { return nil }
    var comp = calendar.dateComponents([.year, .month, .day], from: now)
    comp.hour = h; comp.minute = m; comp.second = sec
    guard let candidate = calendar.date(from: comp) else { return nil }
    if candidate > now { return candidate }
    return calendar.date(byAdding: .day, value: 1, to: candidate)
}
