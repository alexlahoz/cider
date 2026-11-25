import SwiftUI

struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let coverSpace: Namespace.ID
    let onClose: () -> Void

    @State private var appeared = false
    @State private var fixes: GameLauncher.Fixes?
    @State private var details: StoreDetails?
    @State private var viewing: StoreDetails.Screenshot?
    @State private var renaming = false
    @State private var highlightSettings = false
    @Environment(\.scrollToSettings) private var scrollToSettingsAction
    @State private var newName = ""

    private let heroHeight: CGFloat = 440

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .environment(\.scrollToSettings, {
                        withAnimation(.spring(duration: 0.8, bounce: 0.12)) { proxy.scrollTo("gameSettings", anchor: .top) }
                        Task {
                            try? await Task.sleep(nanoseconds: 550_000_000)
                            withAnimation(.easeInOut(duration: 0.35)) { highlightSettings = true }
                            try? await Task.sleep(nanoseconds: 1_300_000_000)
                            withAnimation(.easeInOut(duration: 0.6)) { highlightSettings = false }
                        }
                    })
                content
                    .padding(.horizontal, 36)
                    .padding(.top, 26)
                    .padding(.bottom, 48)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
            }
        }
        .scrollContentBackground(.hidden)
        // Keep the scroll bar below the toolbar so it never runs under the search field.
        .contentMargins(.top, ToolbarMetrics.height, for: .scrollIndicators)
        .defaultScrollAnchor(.top)
        }
        .background(AmbientBackground(game: game))
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Label("Library", systemImage: "chevron.left")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.glassyCompact)
            .environment(\.colorScheme, .dark)
            .keyboardShortcut(.cancelAction)
            .padding(.leading, 22)
            .padding(.top, 14)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.12)) { appeared = true }
        }
        .task(id: game.appID) {
            let launcher = model.launcher
            let g = game
            fixes = await Task.detached { launcher.detectFixes(for: g) }.value
        }
        .task(id: game.artID) { details = await StoreInfoStore.shared.details(appID: game.artID) }
        .alert("Rename", isPresented: $renaming) {
            TextField("Game name", text: $newName)
            Button("Save") { model.renameCustomGame(game, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cider will look up the artwork with the new name.")
        }
        .overlay {
            if let viewing {
                ScreenshotViewer(shot: viewing, all: details?.screenshots ?? []) {
                    withAnimation(.spring(duration: 0.4)) { self.viewing = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    // MARK: hero

    private var backdrop: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            ArtworkImage(appID: game.artID, kind: .hero) { Color.clear }
                .frame(height: 700)
                .blur(radius: 100)
                .saturation(1.5)
                .opacity(0.4)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                let minY = geo.frame(in: .global).minY
                ArtworkImage(appID: game.artID, kind: .hero) {
                    ArtworkImage(appID: game.artID, kind: .header) {
                        GeneratedPoster(name: game.name, seed: game.appID, showTitle: false)
                    }
                }
                .frame(width: geo.size.width, height: heroHeight + max(0, minY))
                .clipped()
                .offset(y: minY > 0 ? -minY : -minY * 0.35)
                .modifier(BackgroundExtension())
            }
            .frame(height: heroHeight)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.0),
                                         .init(color: .black, location: 0.55),
                                         .init(color: .clear, location: 1.0)],
                                 startPoint: .top, endPoint: .bottom))

            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .bottomLeading, endPoint: .center)
                .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 28) {
                CoverArt(game: game)
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .frame(width: 168, height: 252)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18)))
                    .matchedGeometryEffect(id: game.appID, in: coverSpace, isSource: true)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)

                VStack(alignment: .leading, spacing: 16) {
                    ArtworkImage(appID: game.artID, kind: .logo, contentMode: .fit) {
                        Text(game.name)
                            .font(.system(size: 44, weight: .heavy))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .frame(maxWidth: 420, maxHeight: 130, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 4)

                    HStack(spacing: 12) {
                        PlayButton(game: game, large: true)
                        SettingsJumpButton()
                        Menu {
                            if game.isCustom {
                                Button("Rename…") { newName = game.name; renaming = true }
                                Button("Find Artwork on Steam") { model.refreshArtwork(game) }
                                Divider()
                                Button("Show in Finder") { model.reveal(game.customExe ?? game.installDir) }
                                Divider()
                                Button("Remove from Cider", role: .destructive) { onClose(); model.removeCustomGame(game) }
                            } else {
                                Button("Open in Steam") { model.openSteam("steam://nav/games/details/\(game.appID)") }
                                Button("View in Store") { model.openSteam("steam://store/\(game.appID)") }
                                Button("Game Properties in Steam") { model.openSteam("steam://gameproperties/\(game.appID)") }
                                Divider()
                                Button("Show in Finder") { model.reveal(game.installDir) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.bold))
                                .frame(width: 20, height: 20)
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.glassy)
                        .fixedSize()
                        .help("More options")

                        statusLine
                    }
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 4)
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.activity[game.appID] ?? .idle {
        case .running: EmptyView()
        case .launching:
            Text("Opening Steam and the game…").font(.callout).foregroundStyle(.secondary)
        case .idle:
            if game.isUpdating {
                StatusPill(kind: .updating, text: "Updating")
            } else if !game.isInstalled {
                Text("Not fully installed").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: content

    private var content: some View {
        VStack(alignment: .leading, spacing: 30) {
            facts
            if let details {
                AboutCard(details: details)
                if !details.screenshots.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Screenshots")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(details.screenshots) { shot in
                                    ScreenshotThumb(shot: shot) {
                                        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { viewing = shot }
                                    }
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 2)
                        }
                        .scrollClipDisabled()
                    }
                }
            }
            HStack(alignment: .top, spacing: 22) {
                GameSettingsCard(game: game)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.cider, lineWidth: highlightSettings ? 3 : 0)
                            .shadow(color: .cider.opacity(highlightSettings ? 0.6 : 0), radius: 16)
                    )
                    .scaleEffect(highlightSettings ? 1.01 : 1)
                    .id("gameSettings")
                compatibilityCard
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var facts: some View {
        let api = Fmt.api(model.graphics(for: game))
        return HStack(spacing: 14) {
            FactTile(symbol: "clock.fill", color: .cider, title: "Last played",
                     value: Fmt.relative(model.lastPlayed(game)).capitalizedFirst)
            FactTile(symbol: "hourglass", color: .purple, title: "Playtime",
                     value: Fmt.playtime(minutes: model.playtimeMinutes(game)))
            FactTile(symbol: "internaldrive.fill", color: .blue, title: "Size",
                     value: Fmt.size(game.sizeOnDisk))
            FactTile(symbol: "cpu.fill", color: api.ok ? .green : .orange, title: "Graphics",
                     value: api.title, detail: api.detail)
        }
    }

    private var compatibilityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                IconBadge(symbol: "wand.and.stars", color: .ciderDeep, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Automatic tuning").font(.headline)
                    Text("Cider sets this game up for you. Nothing to do.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                FixRow(symbol: "sparkles.rectangle.stack", title: "Graphics", detail: graphicsDetail)
                if let fixes {
                    FixRow(symbol: fixes.dlls.isEmpty ? "checkmark.seal" : "shippingbox",
                           title: "Game components",
                           detail: fixes.dlls.isEmpty
                            ? String(localized: "Doesn't need any special tweaks.")
                            : String(localized: "Uses the components the game ships with, to avoid unexpected crashes."))
                } else {
                    HStack { ProgressView().controlSize(.small); Text("Analyzing the game…").foregroundStyle(.secondary) }
                }
                if model.skipsAntiCheat(game) {
                    FixRow(symbol: "shield.slash", title: "Anti-cheat",
                           detail: String(localized: "Opens directly in anti-cheat-free mode."))
                }
                if let scale = model.settings(for: game).renderScale, scale > 1 {
                    FixRow(symbol: "arrow.up.left.and.down.right.magnifyingglass", title: "Resolution",
                           detail: String(localized: "Rendered at \(String(Int((100 / scale).rounded()))) % and macOS scales the image up: smoother play."))
                }
                if let exe = game.customExe {
                    FixRow(symbol: "folder", title: "Game you added",
                           detail: exe.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22)
    }

    private var graphicsDetail: String {
        guard let info = model.graphics(for: game) else { return String(localized: "Analyzing…") }
        switch info.api {
        case .dx11, .dx10:
            return info.is64Bit
                ? String(localized: "Translated to Metal, your Mac's graphics technology, at full performance.")
                : String(localized: "Older 32-bit game: limited compatibility, it may run slowly.")
        case .dx9, .dx8: return String(localized: "Translated to your Mac's graphics technology.")
        case .dx12: return String(localized: "Uses DirectX 12, which Cider doesn't support yet: it may not start.")
        case .vulkan: return String(localized: "Translated to Metal, your Mac's graphics technology.")
        case .openGL: return String(localized: "Uses your Mac's graphics technology directly.")
        case .unknown: return String(localized: "Standard setup.")
        }
    }
}

/// Lets the hero's "Settings" button scroll the page down to the game settings.
private struct ScrollToSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var scrollToSettings: () -> Void {
        get { self[ScrollToSettingsKey.self] }
        set { self[ScrollToSettingsKey.self] = newValue }
    }
}

private struct SettingsJumpButton: View {
    @Environment(\.scrollToSettings) private var scrollToSettings
    var body: some View {
        Button(action: scrollToSettings) {
            Label("Settings", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.glassy)
        .help("Go to this game's settings")
    }
}

/// macOS 26: let the hero art extend under the sidebar / toolbar glass.
private struct BackgroundExtension: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}

struct FactTile: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(16)
        .glassSurface(cornerRadius: 18)
    }
}

struct FixRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GameSettingsCard: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let s = model.settings(for: game)
        VStack(alignment: .leading, spacing: 18) {
            Label {
                Text("Game settings").font(.headline)
            } icon: {
                IconBadge(symbol: "slider.horizontal.3", color: .blue, size: 26)
            }

            SettingLine(title: "Window", subtitle: "How the game opens on your Mac") {
                Picker("", selection: Binding(
                    get: { s.display },
                    set: { v in model.updateSettings(for: game) { $0.display = v } })) {
                    Text("Default (\(Fmt.display(model.state.settings.defaultDisplay)))").tag(DisplayMode?.none)
                    Divider()
                    ForEach(DisplayMode.presets, id: \.self) { mode in
                        Text(Fmt.display(mode)).tag(DisplayMode?.some(mode))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider().opacity(0.5)
            SettingLine(title: "Open in a window", subtitle: windowedHint) {
                Toggle("", isOn: Binding(
                    get: { model.opensWindowed(game) },
                    set: { v in model.updateSettings(for: game) { $0.windowed = v } }))
                    .toggleStyle(.switch).labelsHidden()
            }
            Divider().opacity(0.5)
            SettingLine(title: "Render resolution", subtitle: renderHint(s.renderScale)) {
                Picker("", selection: Binding(
                    get: { s.renderScale ?? 1 },
                    set: { v in model.updateSettings(for: game) { $0.renderScale = v > 1 ? v : nil } })) {
                    Text("100 % (native)").tag(1.0)
                    Text(verbatim: "75 %").tag(4.0 / 3.0)
                    Text(verbatim: "67 %").tag(1.5)
                    Text(verbatim: "50 %").tag(2.0)
                }
                .labelsHidden()
                .fixedSize()
            }
            if model.hasAntiCheatFreeMode(game) {
                Divider().opacity(0.5)
                SettingLine(title: "Open without anti-cheat", subtitle: "EasyAntiCheat doesn't work on Mac. Play without it (no anti-cheat multiplayer)") {
                    Toggle("", isOn: Binding(
                        get: { s.skipAntiCheat ?? true },
                        set: { v in model.updateSettings(for: game) { $0.skipAntiCheat = v } }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            Divider().opacity(0.5)
            SettingLine(title: "Show FPS", subtitle: "Shows frames per second while you play") {
                Toggle("", isOn: Binding(
                    get: { s.fpsHUD ?? model.state.settings.fpsHUD },
                    set: { v in model.updateSettings(for: game) { $0.fpsHUD = v } }))
                    .toggleStyle(.switch).labelsHidden()
            }
            Text("Changes apply the next time you press Play.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22)
    }
}

extension GameSettingsCard {
    func renderHint(_ scale: Double?) -> LocalizedStringKey {
        guard let scale, scale > 1, let screen = NSScreen.main?.frame.size else {
            return "Lower resolution = more FPS. macOS scales the image to the window"
        }
        let w = Int((screen.width / scale).rounded()), h = Int((screen.height / scale).rounded())
        return "In full screen it renders at \(String(w))×\(String(h)). Steam will look enlarged too"
    }

    var windowedHint: LocalizedStringKey {
        if GameWindowConfig.isSupported(game.appID) { return "Cider adjusts the game's settings. Full screen: green button" }
        switch GameWindowConfig.engine(of: game.installDir) {
        case .unity, .unreal, .source: return "Cider asks the game when launching it. Full screen: green button"
        case .unknown: return "If the game ignores it, choose \"Windowed\" in its video options"
        }
    }
}

struct SettingLine<Control: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

struct AboutCard: View {
    let details: StoreDetails

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("About the game").font(.headline)
                Text(details.shortDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !details.genres.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(details.genres.prefix(4), id: \.self) { g in
                            Text(g).font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.cider.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.cider)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if !details.developers.isEmpty { InfoLine(title: "Developer", value: details.developers.joined(separator: ", ")) }
                if !details.publishers.isEmpty { InfoLine(title: "Publisher", value: details.publishers.joined(separator: ", ")) }
                if !details.releaseDate.isEmpty { InfoLine(title: "Release date", value: details.releaseDate) }
                if let c = details.controllerSupport {
                    InfoLine(title: "Controller", value: c == "full" ? String(localized: "Supported") : String(localized: "Partial"))
                }
                if let score = details.metacritic {
                    HStack(spacing: 8) {
                        Text(String(score))
                            .font(.callout.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 28)
                            .background(score >= 75 ? Color.green : (score >= 50 ? .yellow : .red),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(verbatim: "Metacritic").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 260, alignment: .leading)
        }
        .padding(22)
        .glassSurface(cornerRadius: 22)
    }
}

private struct InfoLine: View {
    let title: LocalizedStringKey
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.4)
            Text(value).font(.callout.weight(.medium)).lineLimit(2)
        }
    }
}

struct ScreenshotThumb: View {
    let shot: StoreDetails.Screenshot
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            RemoteImage(url: shot.thumbnail)
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(hover ? 0.4 : 0.12)))
                .shadow(color: .black.opacity(hover ? 0.4 : 0.2), radius: hover ? 16 : 8, y: hover ? 10 : 4)
                .scaleEffect(hover ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hover = h } }
    }
}

struct ScreenshotViewer: View {
    @State var shot: StoreDetails.Screenshot
    let all: [StoreDetails.Screenshot]
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.82)).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            RemoteImage(url: shot.full)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(radius: 40)
                .padding(60)
                .id(shot.id)
                .transition(.opacity)
            HStack {
                navButton("chevron.left", offset: -1).keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                navButton("chevron.right", offset: 1).keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(.horizontal, 20)
            Button(action: onClose) { Image(systemName: "xmark").font(.headline) }
                .buttonStyle(.glassyCompact)
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(22)
        }
        .environment(\.colorScheme, .dark)
    }

    private func navButton(_ symbol: String, offset: Int) -> some View {
        Button {
            guard let i = all.firstIndex(of: shot), !all.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.25)) { shot = all[(i + offset + all.count) % all.count] }
        } label: {
            Image(systemName: symbol).font(.title2.weight(.semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(.glassyCompact)
    }
}
