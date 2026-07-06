import Foundation

/// A named Focus mode discovered from the system's Focus configuration.
struct FocusMode: Identifiable, Hashable {
    let id: String            // canonical identifier
    let name: String
    var aliases: Set<String> = []   // other ids that refer to this same mode

    /// True if `raw` names this mode via its canonical id or any alias.
    func matches(_ raw: String) -> Bool { raw == id || aliases.contains(raw) }
}

/// Watches the (undocumented, TCC-protected) Focus state files and reports the
/// currently active Focus. Requires Full Disk Access to read.
///
/// macOS has no public API to read the *named* active Focus, so we read the
/// same files the system maintains:
///   ~/Library/DoNotDisturb/DB/Assertions.json         — active mode identifier
///   ~/Library/DoNotDisturb/DB/ModeConfigurations.json — id -> name mapping
final class FocusMonitor {
    static let dbDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    static let assertionsURL = dbDirectory.appendingPathComponent("Assertions.json")
    static let configurationsURL = dbDirectory.appendingPathComponent("ModeConfigurations.json")

    /// Called on the main queue whenever the active Focus may have changed.
    /// Passes the active mode identifier (nil when no Focus is active) and the
    /// full id -> name map of known Focus modes.
    var onChange: ((_ activeModeID: String?, _ modes: [FocusMode]) -> Void)?

    private var dirSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var pollTimer: Timer?
    private var lastActiveID: String?? = nil // double optional: nil = never reported

    // MARK: - Access check

    /// Whether we can currently read the Focus database (i.e. Full Disk Access
    /// has been granted). Reading a TCC-protected file throws when denied.
    static func hasAccess() -> Bool {
        do {
            _ = try Data(contentsOf: assertionsURL)
            return true
        } catch {
            let ns = error as NSError
            // A "no such file" is fine (no Focus ever set); permission errors mean no access.
            if ns.domain == NSCocoaErrorDomain,
               ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError {
                return true
            }
            return false
        }
    }

    // MARK: - Lifecycle

    func start() {
        stop()
        startDirectoryWatch()
        // Safety-net poll in case the directory watch misses an atomic replace.
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.evaluate(force: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        evaluate(force: true)
    }

    func stop() {
        dirSource?.cancel()
        dirSource = nil
        if dirFD >= 0 { close(dirFD); dirFD = -1 }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startDirectoryWatch() {
        let fd = open(Self.dbDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return } // will fall back to polling
        dirFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main)
        source.setEventHandler { [weak self] in
            self?.evaluate(force: false)
        }
        source.setCancelHandler { [weak self] in
            if let self, self.dirFD >= 0 { close(self.dirFD); self.dirFD = -1 }
        }
        source.resume()
        dirSource = source
    }

    // MARK: - Reading

    /// Re-read the Focus files and fire onChange if the active mode changed.
    func evaluate(force: Bool) {
        let assertionsData = try? Data(contentsOf: Self.assertionsURL)
        let configData = try? Data(contentsOf: Self.configurationsURL)

        let modes: [FocusMode]
        if let configData, let json = try? JSONSerialization.jsonObject(with: configData) {
            modes = Self.parseModes(from: json)
        } else { modes = [] }

        var rawActive: String?
        if let assertionsData, let json = try? JSONSerialization.jsonObject(with: assertionsData) {
            rawActive = Self.parseActiveModeID(from: json)
        }
        let active = rawActive.map { Self.canonicalID($0, in: modes) }

        if force {
            FBLog.shared.dumpFocusState(
                assertions: assertionsData, config: configData,
                rawActive: rawActive, canonicalActive: active, modes: modes)
        }
        if force || lastActiveID != .some(active) {
            if !force { FBLog.shared.log("Focus changed → \(active ?? "none") (raw \(rawActive ?? "nil"))") }
            lastActiveID = .some(active)
            onChange?(active, modes)
        }
    }

    /// Parse Assertions.json for the active mode identifier. Returns nil when no
    /// Focus is active.
    static func readActiveModeID() -> String? {
        guard let data = try? Data(contentsOf: assertionsURL),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parseActiveModeID(from: json)
    }

    /// Pure parser for the *currently active* Focus.
    ///
    /// Assertions.json holds two kinds of records: `storeAssertionRecords` are
    /// live (a Focus is on) and `storeInvalidationRecords` are ended assertions.
    /// We must read only the live ones — otherwise an ended "Do Not Disturb"
    /// record looks like an active Focus. When no live assertion exists, no
    /// Focus is active and we return nil. If several are live, prefer the most
    /// recently started.
    static func parseActiveModeID(from json: Any) -> String? {
        let liveArrays = allValues(forKey: "storeAssertionRecords", in: json)
            .compactMap { $0 as? [Any] }
        var best: (id: String, ts: Double)?
        for records in liveArrays {
            for record in records {
                guard let id = firstString(forKey: "assertionDetailsModeIdentifier", in: record) else { continue }
                let ts = (firstValue(forKey: "assertionStartDateTimestamp", in: record) as? Double) ?? 0
                if best == nil || ts > best!.ts { best = (id, ts) }
            }
        }
        return best?.id
    }

    /// Parse ModeConfigurations.json into the set of known Focus modes.
    static func readModes() -> [FocusMode] {
        guard let data = try? Data(contentsOf: configurationsURL),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return parseModes(from: json)
    }

    /// Pure parser for the mode-configuration structure. Each mode's canonical
    /// id is its inner `identifier` (reverse-DNS, stable) when present, else the
    /// dictionary key; both are kept as aliases so any id the system reports in
    /// Assertions.json resolves back to the same mode.
    static func parseModes(from json: Any) -> [FocusMode] {
        guard let configs = firstValue(forKey: "modeConfigurations", in: json) as? [String: Any] else {
            return []
        }
        var result: [FocusMode] = []
        var seenNames = Set<String>()
        for (key, value) in configs.sorted(by: { $0.key < $1.key }) {
            let mode = (value as? [String: Any])?["mode"] as? [String: Any]
            let name = (mode?["name"] as? String) ?? (firstString(forKey: "name", in: value) ?? "")
            guard !name.isEmpty, !seenNames.contains(name) else { continue }
            seenNames.insert(name)
            let inner = mode?["identifier"] as? String
            let canonical = inner ?? key
            var aliases: Set<String> = [key]
            if let inner { aliases.insert(inner) }
            // The active assertion typically reports the reverse-DNS modeIdentifier.
            if let modeIdent = mode?["modeIdentifier"] as? String { aliases.insert(modeIdent) }
            result.append(FocusMode(id: canonical, name: name, aliases: aliases))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolve any raw id the system reports to the canonical id of its mode.
    static func canonicalID(_ raw: String, in modes: [FocusMode]) -> String {
        modes.first { $0.matches(raw) }?.id ?? raw
    }

    /// Human-readable name for a mode id (canonical or alias), falling back to the raw id.
    static func name(for modeID: String, in modes: [FocusMode]) -> String {
        modes.first { $0.matches(modeID) }?.name ?? modeID
    }

    // MARK: - Defensive JSON search

    private static func firstValue(forKey key: String, in json: Any) -> Any? {
        if let dict = json as? [String: Any] {
            if let v = dict[key] { return v }
            for (_, v) in dict {
                if let found = firstValue(forKey: key, in: v) { return found }
            }
        } else if let arr = json as? [Any] {
            for v in arr {
                if let found = firstValue(forKey: key, in: v) { return found }
            }
        }
        return nil
    }

    private static func firstString(forKey key: String, in json: Any) -> String? {
        firstValue(forKey: key, in: json) as? String
    }

    /// Every value found for `key` anywhere in the structure.
    private static func allValues(forKey key: String, in json: Any) -> [Any] {
        var out: [Any] = []
        if let dict = json as? [String: Any] {
            for (k, v) in dict {
                if k == key { out.append(v) }
                out.append(contentsOf: allValues(forKey: key, in: v))
            }
        } else if let arr = json as? [Any] {
            for v in arr { out.append(contentsOf: allValues(forKey: key, in: v)) }
        }
        return out
    }
}
