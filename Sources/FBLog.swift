import Foundation

/// Minimal file logger for diagnostics. Writes to ~/Library/Logs/FocusBrowser.log.
final class FBLog {
    static let shared = FBLog()
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/FocusBrowser.log")

    private let queue = DispatchQueue(label: "com.jhobbs.FocusBrowser.log")

    func log(_ message: String) {
        queue.async { [url] in
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: url)
            }
        }
    }

    /// Log a summary of the current Focus state. The undocumented on-disk layout
    /// varies by OS, so if `~/Library/Logs/FocusBrowser.debug` exists we also dump
    /// the raw files to help diagnose parsing on a new macOS version.
    func dumpFocusState(assertions: Data?, config: Data?,
                        rawActive: String?, canonicalActive: String?, modes: [FocusMode]) {
        var out = "focus state — modes(\(modes.count)): \(modes.map { $0.name }.joined(separator: ", "))"
        out += " | active raw=\(rawActive ?? "none") canonical=\(canonicalActive ?? "none")"
        log(out)

        let debugFlag = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FocusBrowser.debug")
        guard FileManager.default.fileExists(atPath: debugFlag.path) else { return }
        func snippet(_ d: Data?) -> String {
            guard let d else { return "<unreadable / no Full Disk Access>" }
            let s = String(data: d, encoding: .utf8) ?? "<non-utf8 \(d.count) bytes>"
            return s.count > 4000 ? String(s.prefix(4000)) + "…(truncated)" : s
        }
        log("RAW Assertions.json:\n\(snippet(assertions))\nRAW ModeConfigurations.json:\n\(snippet(config))")
    }
}
