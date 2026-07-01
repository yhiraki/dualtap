// Menubar.swift — menu bar indicator reading state.json and the .level files.
// 🔴 recording with live audio / ⚠️ recording but no audio / ⚪︎ idle
import AppKit
import Foundation

// audioFresh is true if either .level file was updated within the last 3 seconds.
private func audioFresh(_ dir: String) -> Bool {
    let fm = FileManager.default
    for f in ["mic.wav.level", "sys.wav.level"] {
        if let attr = try? fm.attributesOfItem(atPath: dir + "/" + f),
           let m = attr[.modificationDate] as? Date,
           Date().timeIntervalSince(m) < 3 {
            return true
        }
    }
    return false
}

final class MenubarController: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        item.menu = NSMenu()
        update()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in self.update() }
    }

    private func trunc(_ s: String) -> String {
        s.count > 16 ? String(s.prefix(16)) + "…" : s
    }

    private func hhmm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    func update() {
        guard let menu = item.menu else { return }
        menu.removeAllItems()
        if let rec = loadState() {
            if audioFresh(rec.dir) {
                item.button?.title = "🔴 " + trunc(rec.title)
                menu.addItem(NSMenuItem(title: "🔴 recording: " + rec.title, action: nil, keyEquivalent: ""))
            } else {
                item.button?.title = "⚠️ rec?"
                menu.addItem(NSMenuItem(title: "⚠️ recording but no audio: " + rec.title, action: nil, keyEquivalent: ""))
            }
            if let stop = rec.stopAt {
                menu.addItem(NSMenuItem(title: "stop at " + hhmm(stop), action: nil, keyEquivalent: ""))
            }
        } else {
            item.button?.title = "⚪︎"
            menu.addItem(NSMenuItem(title: "idle (not recording)", action: nil, keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}

func cmdMenubar() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // no Dock icon
    let controller = MenubarController()
    _ = controller
    app.run()
}
