import AppKit

/// A web browser installed on the system that can handle https URLs.
struct BrowserApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }
}

/// Enumerates installed browsers and reads / sets the system default browser.
enum BrowserManager {
    /// A representative https URL used to ask LaunchServices which apps are browsers.
    private static let probeURL = URL(string: "https://www.apple.com")!

    /// Bundle identifier of this app, so we can exclude ourselves from the list.
    private static var ownBundleID: String? { Bundle.main.bundleIdentifier }

    /// All installed applications that can open https URLs, i.e. web browsers.
    static func installedBrowsers() -> [BrowserApp] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
        var seen = Set<String>()
        var result: [BrowserApp] = []
        for url in urls {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { continue }
            if bundleID == ownBundleID { continue }
            if seen.contains(bundleID) { continue }
            seen.insert(bundleID)
            let name = displayName(for: url, bundle: bundle)
            result.append(BrowserApp(bundleID: bundleID, name: name, url: url))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func displayName(for url: URL, bundle: Bundle) -> String {
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { return name }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String { return name }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// The bundle identifier of the current default browser, if resolvable.
    static func currentDefaultBrowserBundleID() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// Request that macOS make the given app the default web browser.
    ///
    /// macOS presents its own confirmation dialog for this change; there is no
    /// supported way to switch the default browser silently.
    static func setDefaultBrowser(bundleID: String, completion: ((Error?) -> Void)? = nil) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            completion?(NSError(domain: "FocusBrowser", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "App \(bundleID) not found"]))
            return
        }
        // The system presents its "change default browser?" confirmation and
        // waits for it. That prompt can only be shown from a foreground app, so
        // temporarily promote this (normally accessory) app to a regular,
        // active app while the request is in flight; otherwise the prompt is
        // reported as userCanceled.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Setting the http scheme triggers the "default web browser" prompt;
        // it covers https and html at the same time.
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { error in
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
                completion?(error)
            }
        }
    }
}
