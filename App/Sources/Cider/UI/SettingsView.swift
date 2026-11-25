import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    @State private var dataSize: String = "…"

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsGroup(title: "Games") {
                    SettingsRow(symbol: "macwindow", color: .blue, title: "Default window",
                                subtitle: "\"macOS window\": each game in its own window. \"Fixed window\": Steam and the game inside a window of a set size") {
                        Picker("", selection: Binding(get: { model.state.settings.defaultDisplay.normalized },
                                                      set: { model.state.settings.defaultDisplay = $0 })) {
                            ForEach(DisplayMode.presets, id: \.self) { Text(Fmt.display($0)).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    SettingsRow(symbol: "arrow.up.left.and.arrow.down.right", color: .green, title: "macOS window controls",
                                subtitle: "Minimize, resize and full screen on the game window, even if the game doesn't offer them") {
                        Toggle("", isOn: Binding(get: { model.state.settings.resizableWindows ?? true },
                                                 set: { model.state.settings.resizableWindows = $0 }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(symbol: "eye.slash", color: .indigo, title: "Hide Cider while playing",
                                subtitle: "Leaves every resource to the game. Cider comes back when you close it") {
                        Toggle("", isOn: Binding(get: { model.state.settings.hideWhilePlaying ?? true },
                                                 set: { model.state.settings.hideWhilePlaying = $0 }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow(symbol: "speedometer", color: .orange, title: "Show FPS",
                                subtitle: "Shows Metal's performance HUD in games") {
                        Toggle("", isOn: $model.state.settings.fpsHUD).toggleStyle(.switch).labelsHidden()
                    }
                }

                SettingsGroup(title: "Steam") {
                    SettingsRow(symbol: "globe", color: .teal, title: "Steam language",
                                subtitle: "Applies the next time Steam opens") {
                        Picker("", selection: $model.state.settings.steamLanguage) {
                            Text("Automatic").tag(SteamLanguage.automatic)
                            Divider()
                            Text(verbatim: "Español").tag(SteamLanguage.spanish)
                            Text(verbatim: "Español (Latinoamérica)").tag(SteamLanguage.latam)
                            Text(verbatim: "English").tag(SteamLanguage.english)
                            Text(verbatim: "Français").tag(SteamLanguage.french)
                            Text(verbatim: "Deutsch").tag(SteamLanguage.german)
                            Text(verbatim: "Italiano").tag(SteamLanguage.italian)
                            Text(verbatim: "Português").tag(SteamLanguage.portuguese)
                            Text(verbatim: "Português (Brasil)").tag(SteamLanguage.brazilian)
                        }
                        .labelsHidden().fixedSize()
                    }
                }

                SettingsGroup(title: "Storage") {
                    SettingsRow(symbol: "externaldrive.fill", color: .gray, title: "Cider data",
                                subtitle: LocalizedStringKey(stringLiteral: model.demoMode ? "~/Library/Application Support/Cider" : model.paths.data.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))) {
                        HStack(spacing: 10) {
                            Text(dataSize).foregroundStyle(.secondary).monospacedDigit()
                            Button("Show in Finder") { model.reveal(model.paths.data) }
                                .buttonStyle(.glassyCompact)
                        }
                    }
                    SettingsRow(symbol: "internaldrive", color: .indigo, title: "Game files",
                                subtitle: "Where Cider keeps Steam and your games") {
                        Button("Open") { NSWorkspace.shared.open(model.paths.driveC) }
                            .buttonStyle(.glassyCompact)
                    }
                }

                SettingsGroup(title: "About") {
                    SettingsRow(symbol: "info.circle.fill", color: .cider, title: "Cider \(appVersion)",
                                subtitle: "Free software based on Wine and DXMT") {
                        HStack(spacing: 8) {
                            Button("Check for Updates") {
                                Task { await model.updater.check(userInitiated: true) }
                                model.updater.showSheet = true
                            }
                            .buttonStyle(.glassyCompact)
                            Button("Licenses") { model.showAbout = true }
                                .buttonStyle(.glassyCompact)
                        }
                    }
                }

                SettingsGroup(title: "Danger zone") {
                    SettingsRow(symbol: "trash.fill", color: .red, title: "Reset Cider",
                                subtitle: "Deletes Cider's game engine, Steam and installed games. You'll have to start over") {
                        Button("Reset…", role: .destructive) { confirmReset = true }
                            .buttonStyle(.glassyCompact)
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Settings")
        .confirmationDialog("Reset Cider?", isPresented: $confirmReset) {
            Button("Delete Everything and Start Over", role: .destructive) { model.resetEverything() }
        } message: {
            Text("Steam, the games installed in Cider and their local saves will be deleted. Steam Cloud saves aren't lost.")
        }
        .task { await computeSize() }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func computeSize() async {
        let url = model.paths.data
        let bytes = await Task.detached(priority: .utility) { () -> Int64 in
            var total: Int64 = 0
            if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []) {
                for case let f as URL in e {
                    total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
                }
            }
            return total
        }.value
        dataSize = Fmt.size(bytes)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedLayout()) { content() }
            }
            .glassSurface(cornerRadius: 18)
        }
    }
}

/// Inserts hairline dividers between rows.
private struct DividedLayout: _VariadicView_MultiViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last {
                Divider().padding(.leading, 58)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
