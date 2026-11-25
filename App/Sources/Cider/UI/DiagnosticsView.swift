import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var logText = ""
    @State private var webhelperOK = false
    @State private var confirmKill = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Your Mac")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                        DiagTile(symbol: "cpu", color: .blue, title: "Chip", value: MacSystem.chipName)
                        DiagTile(symbol: "display", color: .purple, title: "GPU (Metal)", value: MacSystem.gpuName)
                        DiagTile(symbol: "apple.logo", color: .gray, title: "System", value: MacSystem.osVersionString)
                        DiagTile(symbol: "memorychip", color: .teal, title: "Memory", value: "\(MacSystem.memoryGB) GB")
                        DiagTile(symbol: "arrow.triangle.2.circlepath", color: MacSystem.isRosettaInstalled ? .green : .red,
                                 title: "Rosetta 2",
                                 value: MacSystem.isRosettaInstalled ? String(localized: "Installed") : String(localized: "Not installed"))
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Game engine")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                        DiagTile(symbol: "wineglass", color: .ciderDeep, title: "Compatibility engine", value: "11.21",
                                 ok: model.paths.runtimeIsPresent)
                        DiagTile(symbol: "cube.transparent", color: .orange, title: "DirectX 10/11", value: "DXMT → Metal")
                        DiagTile(symbol: "square.grid.2x2", color: .indigo, title: "Game data",
                                 value: model.paths.prefixExists ? String(localized: "Ready") : String(localized: "Not created"),
                                 ok: model.paths.prefixExists)
                        DiagTile(symbol: "bag", color: .blue, title: "Steam",
                                 value: model.steamRunning ? String(localized: "Open") : (model.steam.isInstalled ? String(localized: "Installed") : String(localized: "Not installed")),
                                 ok: model.steam.isInstalled)
                        DiagTile(symbol: "rectangle.on.rectangle", color: .green, title: "Steam browser fix",
                                 value: webhelperOK ? String(localized: "Applied") : String(localized: "Pending"), ok: webhelperOK)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Tools")
                    HStack(spacing: 14) {
                        ActionTile(symbol: "wrench.and.screwdriver.fill", color: .blue, title: "Repair environment",
                                   text: "Checks the game engine, re-applies the settings and repairs Steam.") {
                            model.repairEnvironment()
                        }
                        ActionTile(symbol: "xmark.octagon.fill", color: .red, title: "Close Everything",
                                   text: "Quits Steam and any game that got stuck.") {
                            confirmKill = true
                        }
                        ActionTile(symbol: "doc.text.magnifyingglass", color: .gray, title: "Open Logs",
                                   text: "Shows the folder with the technical logs.") {
                            model.reveal(model.paths.wineLog)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionHeader(title: "Log")
                        Button { loadLog() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                            .buttonStyle(.glassyCompact)
                    }
                    ScrollView([.vertical, .horizontal]) {
                        Text(logText.isEmpty ? String(localized: "The log is empty.") : logText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 260)
                    .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
                }
            }
            .padding(30)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Diagnostics")
        .onAppear {
            loadLog()
            webhelperOK = model.steam.isWebhelperPatched
        }
        .confirmationDialog("Close everything?", isPresented: $confirmKill) {
            Button("Quit Steam and Games", role: .destructive) { model.killEverything() }
        } message: {
            Text("Unsaved progress in open games will be lost.")
        }
    }

    private func loadLog() {
        let url = model.paths.wineLog
        guard let h = try? FileHandle(forReadingFrom: url) else { logText = ""; return }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 60_000 ? size - 60_000 : 0)
        let data = (try? h.readToEnd()) ?? Data()
        logText = String(decoding: data, as: UTF8.self)
    }
}

private struct DiagTile: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let value: String
    var ok: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 16)
    }
}

private struct ActionTile: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                IconBadge(symbol: symbol, color: color, size: 36)
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .glassSurface(cornerRadius: 20)
            .scaleEffect(hover ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hover = h } }
    }
}
