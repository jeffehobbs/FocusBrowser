import SwiftUI
import ServiceManagement

/// Central observable state: the browser-per-Focus mappings, current Focus,
/// and the logic that switches the default browser when Focus changes.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    /// Key used in `mappings` for the "no Focus active" fallback.
    static let noFocusKey = "__none__"

    @Published var hasFullDiskAccess = false
    @Published var availableBrowsers: [BrowserApp] = []
    @Published var knownModes: [FocusMode] = []
    @Published var activeModeID: String?
    @Published var currentDefaultBundleID: String?
    @Published var launchAtLogin = false
    @Published var lastError: String?

    /// focus mode id (or noFocusKey) -> chosen browser bundle id
    @Published var mappings: [String: String] = [:] {
        didSet { persistMappings() }
    }

    private let monitor = FocusMonitor()
    private let defaultsKey = "focusBrowserMappings"

    private init() {
        loadMappings()
        refreshBrowsers()
        currentDefaultBundleID = BrowserManager.currentDefaultBrowserBundleID()
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: - Startup

    func startMonitoring() {
        hasFullDiskAccess = FocusMonitor.hasAccess()
        FBLog.shared.log("startMonitoring — FullDiskAccess=\(hasFullDiskAccess), mappings=\(mappings)")
        monitor.onChange = { [weak self] activeID, modes in
            Task { @MainActor in self?.handleFocusChange(activeID: activeID, modes: modes) }
        }
        if hasFullDiskAccess {
            monitor.start()
        } else {
            // Poll for the access grant; once present, begin monitoring.
            scheduleAccessRecheck()
        }
    }

    private func scheduleAccessRecheck() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if FocusMonitor.hasAccess() {
                    self.hasFullDiskAccess = true
                    self.monitor.start()
                    timer.invalidate()
                }
            }
        }
    }

    // MARK: - Focus handling

    var activeFocusName: String {
        guard let id = activeModeID else { return "No Focus" }
        return FocusMonitor.name(for: id, in: knownModes)
    }

    private func handleFocusChange(activeID: String?, modes: [FocusMode]) {
        if !modes.isEmpty { knownModes = modes }
        activeModeID = activeID
        applyBrowserForCurrentFocus()
    }

    /// Switch the default browser to the one configured for the current Focus,
    /// if it differs from the current default.
    func applyBrowserForCurrentFocus() {
        let key = activeModeID ?? Self.noFocusKey
        guard let target = mappings[key], !target.isEmpty else { return }
        let current = BrowserManager.currentDefaultBrowserBundleID()
        currentDefaultBundleID = current
        guard current != target else {
            FBLog.shared.log("apply[\(key)] target=\(target) already default — no change")
            return
        }
        FBLog.shared.log("apply[\(key)] switching default \(current ?? "nil") → \(target)")
        BrowserManager.setDefaultBrowser(bundleID: target) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    let ns = error as NSError
                    let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { " underlying=\($0.domain) \($0.code)" } ?? ""
                    self.lastError = error.localizedDescription
                    FBLog.shared.log("apply[\(key)] error: \(ns.domain) \(ns.code)\(underlying) — \(error.localizedDescription)")
                } else {
                    self.lastError = nil
                    self.currentDefaultBundleID = BrowserManager.currentDefaultBrowserBundleID()
                    FBLog.shared.log("apply[\(key)] now default = \(self.currentDefaultBundleID ?? "nil")")
                }
            }
        }
    }

    // MARK: - Mutations

    func setBrowser(_ bundleID: String?, forFocusKey key: String) {
        if let bundleID { mappings[key] = bundleID } else { mappings.removeValue(forKey: key) }
        // If this mapping applies to the current Focus, act on it immediately.
        let currentKey = activeModeID ?? Self.noFocusKey
        if key == currentKey { applyBrowserForCurrentFocus() }
    }

    func refreshBrowsers() {
        availableBrowsers = BrowserManager.installedBrowsers()
        currentDefaultBundleID = BrowserManager.currentDefaultBrowserBundleID()
    }

    func browserName(for bundleID: String?) -> String {
        guard let bundleID else { return "—" }
        return availableBrowsers.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    // MARK: - Persistence

    private func loadMappings() {
        if let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] {
            mappings = dict
        }
    }

    private func persistMappings() {
        UserDefaults.standard.set(mappings, forKey: defaultsKey)
    }

    // MARK: - System Settings deep link

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
