import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !model.hasFullDiskAccess {
                fullDiskAccessCard
            } else if model.knownModes.isEmpty {
                Text("No Focus modes found yet. Create Focus modes in System Settings › Focus, then toggle one to populate this list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // A plain VStack (not a ScrollView) so the rows always lay out with
            // their natural height — a ScrollView here collapses to nothing
            // inside the auto-sizing MenuBarExtra window.
            let rows = mappingRows
            if rows.isEmpty {
                Text("No Focus modes to configure yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows, id: \.key) { row in
                        mappingRow(title: row.title, key: row.key, subtitle: row.subtitle)
                    }
                }
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            FBLog.shared.log("UI render — FDA=\(model.hasFullDiskAccess) modes=\(model.knownModes.count) browsers=\(model.availableBrowsers.count)")
        }
    }

    /// The rows to display: the No-Focus fallback plus every known Focus mode.
    private var mappingRows: [(key: String, title: String, subtitle: String?)] {
        var rows: [(key: String, title: String, subtitle: String?)] = [
            (AppModel.noFocusKey, "No Focus", "Used when no Focus is active")
        ]
        for mode in model.knownModes {
            rows.append((mode.id, mode.name, nil))
        }
        return rows
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus Browser")
                .font(.headline)
            HStack(spacing: 6) {
                Image(systemName: "moon.circle.fill")
                    .foregroundStyle(.tint)
                Text("Active Focus: **\(model.activeFocusName)**")
                Spacer()
                Text("Default: \(model.browserName(for: model.currentDefaultBundleID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    private var fullDiskAccessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Full Disk Access required", systemImage: "lock.shield")
                .font(.subheadline.bold())
            Text("macOS provides no public API to read the active Focus, so Focus Browser reads the system Focus files. Grant Full Disk Access to Focus Browser, then it will detect Focus changes automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Full Disk Access Settings…") {
                model.openFullDiskAccessSettings()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
    }

    private func mappingRow(title: String, key: String, subtitle: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: Binding(
                get: { model.mappings[key] ?? "" },
                set: { model.setBrowser($0.isEmpty ? nil : $0, forFocusKey: key) }
            )) {
                Text("Don't change").tag("")
                ForEach(model.availableBrowsers) { browser in
                    Text(browser.name).tag(browser.bundleID)
                }
            }
            .labelsHidden()
            .frame(width: 170)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)

            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Refresh Browsers") { model.refreshBrowsers() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
