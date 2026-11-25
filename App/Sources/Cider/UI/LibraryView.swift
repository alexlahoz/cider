import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var coverSpace
    @State private var search = ""
    @State private var sort: Sort = .name
    @State private var filter: Filter = .all

    enum Sort: String, CaseIterable, Identifiable {
        case name, recent, size
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .name: return "Name"
            case .recent: return "Recently played"
            case .size: return "Size"
            }
        }
    }

    private var filtered: [Game] {
        var list = model.games
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        switch sort {
        case .name: break
        case .recent: list.sort { (model.lastPlayed($0) ?? .distantPast) > (model.lastPlayed($1) ?? .distantPast) }
        case .size: list.sort { $0.sizeOnDisk > $1.sizeOnDisk }
        }
        return list
    }

    private var selectedGame: Game? {
        model.selectedGameID.flatMap { id in model.games.first { $0.appID == id } }
    }

    var body: some View {
        ZStack {
            if model.games.isEmpty {
                EmptyLibraryView()
                    .transition(.opacity)
            } else {
                grid
            }
            if let game = selectedGame {
                GameDetailView(game: game, coverSpace: coverSpace) {
                    withAnimation(.spring(duration: 0.5, bounce: 0.12)) { model.selectedGameID = nil }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                .zIndex(2)
            }
        }
        .navigationTitle(selectedGame == nil ? String(localized: "Library") : "")
        .toolbar {
            if selectedGame == nil {
                ToolbarItem(placement: .primaryAction) {
                    AddGameMenu()
                }
            }
            if selectedGame == nil && !model.games.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Sort")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.reloadLibrary() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Refresh the library")
                }
            }
            // Last, so it sits at the trailing edge (with a gap to the scroll bar).
            SearchToolbarItem(text: $search)
        }
        .onAppear {
            // Debug: `-CiderSearch <text>` starts with a search (used to test the search field).
            if let preset = UserDefaults.standard.string(forKey: "CiderSearch") { search = preset }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let exes = urls.filter { ["exe", "msi"].contains($0.pathExtension.lowercased()) }
            guard !exes.isEmpty else { return false }
            for url in exes {
                if url.pathExtension.lowercased() == "msi" { model.runInstaller(url) } else { model.addCustomGame(exe: url) }
            }
            return true
        }
        .sheet(isPresented: Binding(get: { model.installerResults != nil }, set: { if !$0 { model.installerResults = nil } })) {
            InstallerResultsSheet()
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, played, unplayed
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .played: return "Played"
            case .unplayed: return "Unplayed"
            }
        }
    }

    private var featured: Game? { model.recentlyPlayed.first ?? model.games.first }

    private var visibleGames: [Game] {
        filtered.filter { g in
            switch filter {
            case .all: return true
            case .played: return model.lastPlayed(g) != nil
            case .unplayed: return model.lastPlayed(g) == nil
            }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if search.isEmpty, let featured {
                    ImmersiveHeader(game: featured) { open(featured) }
                } else {
                    Color.clear.frame(height: 76)
                }
                VStack(alignment: .leading, spacing: 44) {
                    if search.isEmpty { LibraryStats() }
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .center) {
                            SectionHeader(title: search.isEmpty ? "Your library" : "Results",
                                          subtitle: String(visibleGames.count))
                            Spacer()
                            FilterChips(selection: $filter)
                        }
                        if visibleGames.isEmpty {
                            Text("No games match this filter.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 210), spacing: 26, alignment: .top)],
                                      alignment: .leading, spacing: 30) {
                                ForEach(visibleGames) { game in
                                    GameCard(game: game, coverSpace: coverSpace,
                                             isSource: model.selectedGameID != game.appID) { open(game) }
                                }
                            }
                        }
                    }
                    if search.isEmpty && model.steamAvailable { DiscoverRow() }
                }
                .padding(.horizontal, 34)
                .padding(.top, search.isEmpty ? 6 : 0)
                .padding(.bottom, 48)
            }
        }
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(AmbientBackground(game: featured))
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    private func open(_ game: Game) {
        withAnimation(.spring(duration: 0.55, bounce: 0.15)) { model.selectedGameID = game.appID }
    }
}

// MARK: - Ambient background

/// Fills the window with the featured art's dominant colour, fading into the window background.
struct AmbientBackground: View {
    let game: Game?
    @Environment(\.colorScheme) private var scheme
    @State private var tint: Color = .clear

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(stops: [
                .init(color: tint.opacity(scheme == .dark ? 0.95 : 0.55), location: 0),
                .init(color: tint.opacity(scheme == .dark ? 0.55 : 0.25), location: 0.45),
                .init(color: tint.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [tint.opacity(scheme == .dark ? 0.5 : 0.25), .clear],
                           center: UnitPoint(x: 0.85, y: 0.15), startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
        .task(id: game?.appID) {
            guard let game else { tint = .clear; return }
            var img = await ArtworkStore.shared.image(appID: game.artID, kind: .hero)
            if img == nil { img = await ArtworkStore.shared.image(appID: game.artID, kind: .cover) }
            guard let img, let c = AmbientColor.color(for: img, key: game.appID) else { return }
            withAnimation(.easeInOut(duration: 0.8)) { tint = Color(nsColor: c) }
        }
    }
}

// MARK: - Immersive header

struct ImmersiveHeader: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let onOpen: () -> Void
    @State private var details: StoreDetails?

    private let height: CGFloat = 520

    var body: some View {
        let activity = model.activity[game.appID] ?? .idle
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                let minY = geo.frame(in: .global).minY
                ArtworkImage(appID: game.artID, kind: .hero) {
                    ArtworkImage(appID: game.artID, kind: .header) {
                        GeneratedPoster(name: game.name, seed: game.appID, showTitle: false)
                    }
                }
                .frame(width: geo.size.width, height: height + max(0, minY))
                .clipped()
                .offset(y: minY > 0 ? -minY : -minY * 0.4)
            }
            .frame(height: height)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.0), .init(color: .black, location: 0.5),
                                         .init(color: .clear, location: 1.0)], startPoint: .top, endPoint: .bottom))
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.0)], startPoint: .leading, endPoint: .trailing)
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: activity == .running ? "gamecontroller.fill" : "play.circle.fill")
                        Text(activity == .running ? "Playing now" : (model.lastPlayed(game) == nil ? "Featured" : "Keep playing"))
                            .textCase(.uppercase)
                            .tracking(1.1)
                    }
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassCapsule()

                    ArtworkImage(appID: game.artID, kind: .logo, contentMode: .fit) {
                        Text(game.name)
                            .font(.system(size: 46, weight: .heavy))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .frame(maxWidth: 460, maxHeight: 130, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 6)

                    if let text = details?.shortDescription, !text.isEmpty {
                        Text(text)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                            .frame(maxWidth: 520, alignment: .leading)
                    }

                    MetaRow(game: game, details: details)

                    HStack(spacing: 12) {
                        PlayButton(game: game, large: true)
                        Button(action: onOpen) {
                            Label("Details", systemImage: "info.circle")
                        }
                        .buttonStyle(.glassy)
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 20)
                if let shots = details?.screenshots, shots.count >= 2 {
                    ScreenshotStack(shots: Array(shots.prefix(3)))
                        .frame(width: 330, height: 220)
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
        }
        .frame(height: height)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .task(id: game.artID) { details = await StoreInfoStore.shared.details(appID: game.artID) }
    }
}

/// Small chips: genre, graphics path, playtime.
struct MetaRow: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let details: StoreDetails?

    var body: some View {
        let api = Fmt.api(model.graphics(for: game))
        HStack(spacing: 8) {
            if let genre = details?.genres.first { Chip(symbol: "tag.fill", text: genre) }
            Chip(symbol: "cpu", text: api.title, tint: api.ok ? .ciderLime : .orange)
            Chip(symbol: "hourglass", text: Fmt.playtime(minutes: model.playtimeMinutes(game)))
            if let last = model.lastPlayed(game) {
                Chip(symbol: "clock", text: Fmt.relative(last).capitalizedFirst)
            }
        }
    }
}

struct Chip: View {
    let symbol: String
    let text: String
    var tint: Color? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint ?? .secondary)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
    }
}

/// Fanned stack of screenshots shown in the header.
struct ScreenshotStack: View {
    let shots: [StoreDetails.Screenshot]
    @State private var hover = false

    var body: some View {
        ZStack {
            ForEach(Array(shots.enumerated().reversed()), id: \.element.id) { i, shot in
                RemoteImage(url: shot.thumbnail)
                    .frame(width: 300, height: 169)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25)))
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                    .rotationEffect(.degrees(Double(i) * (hover ? 7 : 4)))
                    .offset(x: CGFloat(i) * (hover ? 26 : 14), y: CGFloat(i) * (hover ? -18 : -10))
                    .opacity(i == 0 ? 1 : 0.92)
            }
        }
        .onHover { h in withAnimation(.spring(duration: 0.5, bounce: 0.3)) { hover = h } }
    }
}

struct RemoteImage: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            } else {
                LoadingShimmer()
            }
        }
        .task(id: url) {
            let img = await RemoteImageCache.shared.image(url)
            withAnimation(.easeOut(duration: 0.3)) { image = img }
        }
    }
}

// MARK: - Stats

struct LibraryStats: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let minutes = model.games.reduce(0) { $0 + model.playtimeMinutes($1) }
        let bytes = model.games.reduce(Int64(0)) { $0 + $1.sizeOnDisk }
        HStack(spacing: 16) {
            StatTile(symbol: "square.stack.3d.up.fill", color: .ciderDeep, value: String(model.games.count),
                     label: model.games.count == 1 ? "game installed" : "games installed")
            StatTile(symbol: "hourglass", color: .purple, value: Fmt.playtime(minutes: minutes), label: "played in total")
            StatTile(symbol: "internaldrive.fill", color: .blue, value: Fmt.size(bytes), label: "on your disk")
            StatTile(symbol: model.steamRunning ? "checkmark.seal.fill" : "moon.zzz.fill",
                     color: model.steamRunning ? .green : .gray,
                     value: model.steamUser.map { $0.personaName.isEmpty ? $0.accountName : $0.personaName } ?? String(localized: "Steam"),
                     label: !model.steamAvailable ? "Steam not installed" : (model.steamRunning ? "Steam connected" : "Steam idle"))
        }
    }
}

struct StatTile: View {
    let symbol: String
    let color: Color
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Filters

struct FilterChips: View {
    @Binding var selection: LibraryView.Filter
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LibraryView.Filter.allCases) { f in
                Button {
                    withAnimation(.spring(duration: 0.35)) { selection = f }
                } label: {
                    Text(f.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(selection == f ? Color.white : Color.primary.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if selection == f {
                                Capsule().fill(.ciderGradient).matchedGeometryEffect(id: "chip", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCapsule()
    }
}

// MARK: - Discover

struct DiscoverRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Discover on Steam")
            HStack(spacing: 18) {
                DiscoverCard(symbol: "tag.fill", title: "Deals", subtitle: "This week's sales",
                             colors: [Color(red: 0.95, green: 0.55, blue: 0.15), Color(red: 0.80, green: 0.18, blue: 0.30)]) {
                    model.openSteam("steam://openurl/https://store.steampowered.com/specials")
                }
                DiscoverCard(symbol: "gift.fill", title: "Free to play", subtitle: "Without paying a thing",
                             colors: [.cider, .ciderDeep]) {
                    model.openSteam("steam://openurl/https://store.steampowered.com/genre/Free%20to%20Play/")
                }
                DiscoverCard(symbol: "chart.line.uptrend.xyaxis", title: "Top sellers", subtitle: "What everyone is playing",
                             colors: [Color(red: 0.25, green: 0.45, blue: 0.95), Color(red: 0.45, green: 0.20, blue: 0.75)]) {
                    model.openSteam("steam://openurl/https://store.steampowered.com/search/?filter=topsellers")
                }
            }
        }
    }
}

struct DiscoverCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let colors: [Color]
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                BubblesView(count: 10, color: .white, speed: hover ? 1.4 : 0.5, seed: UInt64(colors.count * 31 + 7))
                    .opacity(0.5)
                Image(systemName: symbol)
                    .font(.system(size: 92, weight: .bold))
                    .foregroundStyle(.white.opacity(0.18))
                    .rotationEffect(.degrees(-12))
                    .offset(x: hover ? -6 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.bold))
                    Text(subtitle).font(.callout).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .shadow(color: colors.last!.opacity(hover ? 0.45 : 0.2), radius: hover ? 20 : 10, y: hover ? 12 : 6)
            .scaleEffect(hover ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.35)) { hover = h } }
    }
}

// MARK: - Card

struct GameCard: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let coverSpace: Namespace.ID
    let isSource: Bool
    let onOpen: () -> Void

    @State private var hover = false
    @State private var point = CGPoint(x: 0.5, y: 0.5)
    @State private var cardSize = CGSize(width: 190, height: 285)

    var body: some View {
        let activity = model.activity[game.appID] ?? .idle
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                CoverArt(game: game)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: (point.x - 0.5) * -10, y: (point.y - 0.5) * -10)
                    .scaleEffect(1.06)
                    .clipped()

                // Specular glare following the pointer.
                RadialGradient(colors: [.white.opacity(hover ? 0.28 : 0), .clear],
                               center: UnitPoint(x: point.x, y: point.y), startRadius: 0, endRadius: 220)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)

                LinearGradient(colors: [.clear, .black.opacity(hover || activity != .idle ? 0.65 : 0)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        switch activity {
                        case .running: StatusPill(kind: .playing, text: "Playing")
                        case .launching: StatusPill(kind: .launching, text: "Opening")
                        case .idle:
                            if game.isUpdating { StatusPill(kind: .updating, text: "Updating") }
                        }
                        Spacer()
                    }
                    Spacer()
                    if hover || activity != .idle {
                        PlayButton(game: game, large: false)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(12)
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { cardSize = g.size }
                    .onChange(of: g.size) { _, new in cardSize = new }
            })
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(hover ? 0.4 : 0.14), .white.opacity(0.03)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .matchedGeometryEffect(id: game.appID, in: coverSpace, isSource: isSource)
            .shadow(color: .black.opacity(hover ? 0.42 : 0.22), radius: hover ? 22 : 10, y: hover ? 16 : 6)
            .rotation3DEffect(.degrees(hover ? (0.5 - point.y) * 9 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(hover ? (point.x - 0.5) * 9 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(hover ? 1.045 : 1)
            .brightness(hover ? 0.03 : 0)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc):
                    withAnimation(.spring(duration: 0.35)) {
                        hover = true
                        point = CGPoint(x: loc.x / max(cardSize.width, 1), y: loc.y / max(cardSize.height, 1))
                    }
                case .ended:
                    withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                        hover = false
                        point = CGPoint(x: 0.5, y: 0.5)
                    }
                }
            }
            .onTapGesture(perform: onOpen)
            .zIndex(hover ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle(activity))
                    .font(.caption)
                    .foregroundStyle(activity == .running ? .green : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contextMenu {
            Button("Play") { model.play(game) }
            Button("View Details", action: onOpen)
            Divider()
            Button("Show in Finder") { model.reveal(game.customExe ?? game.installDir) }
            if game.isCustom {
                Button("Remove from Cider", role: .destructive) { model.removeCustomGame(game) }
            } else {
                Button("Open in Steam") { model.openSteam("steam://nav/games/details/\(game.appID)") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func subtitle(_ a: GameActivity) -> String {
        switch a {
        case .running: return String(localized: "Playing now")
        case .launching: return String(localized: "Opening…")
        case .idle:
            if game.isUpdating { return String(localized: "Updating in Steam") }
            if let last = model.lastPlayed(game) { return Fmt.relative(last).capitalizedFirst }
            if game.isCustom { return String(localized: "Outside Steam") }
            return Fmt.size(game.sizeOnDisk)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Toolbar search field. Unlike `.searchable`, it keeps a gap to the window's right edge so it
/// never sits on top of the scroll bar.
struct SearchToolbarItem: ToolbarContent {
    @Binding var text: String

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ToolbarSearchField(text: $text)
        }
    }
}

private struct ToolbarSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search games", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { text = ""; focused = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 280, height: 34)
        .glassCapsule()
        .padding(.trailing, 22)
        .background {
            Button("") { focused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// Play button with launching/running states. While the game runs, hovering turns it into
/// "Close Game" (with a confirmation).
struct PlayButton: View {
    @Environment(AppModel.self) private var model
    let game: Game
    var large: Bool
    @State private var hover = false
    @State private var confirmClose = false

    var body: some View {
        let activity = model.activity[game.appID] ?? .idle
        let closing = model.closing.contains(game.appID)
        let offersClose = activity == .running && !closing && hover
        Button {
            switch activity {
            case .idle: model.play(game)
            case .running: confirmClose = true
            case .launching: break
            }
        } label: {
            HStack(spacing: 8) {
                if closing {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Closing")
                } else {
                    switch activity {
                    case .idle:
                        Image(systemName: "play.fill")
                        Text("Play")
                    case .launching:
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Opening")
                    case .running:
                        Image(systemName: offersClose ? "xmark.circle.fill" : "gamecontroller.fill")
                            .contentTransition(.symbolEffect(.replace))
                        // Both titles share the space, so the button keeps its width on hover.
                        ZStack {
                            Text("Playing").opacity(offersClose ? 0 : 1)
                            Text("Close Game").opacity(offersClose ? 1 : 0)
                        }
                    }
                }
            }
            .frame(maxWidth: large ? nil : .infinity)
            .contentTransition(.opacity)
        }
        .buttonStyle(ProminentButtonStyle(large: large, destructive: offersClose))
        .disabled(activity == .launching || closing || (activity == .idle && !game.isInstalled))
        .keyboardShortcut(large && activity == .idle ? .defaultAction : nil)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
        .help(activity == .running ? Text("Close \(game.name)") : Text(verbatim: ""))
        .confirmationDialog(Text("Close \(game.name)?"), isPresented: $confirmClose) {
            Button("Close Game", role: .destructive) { model.stopGame(game) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything you haven't saved in the game will be lost.")
        }
    }
}

// MARK: - Empty state

struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var float = false

    var body: some View {
        ZStack {
            BubblesView(count: 18, color: .cider, speed: 0.6)
                .opacity(0.5)
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.cider.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 140))
                        .frame(width: 280, height: 280)
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.2)))
                            .frame(width: 92, height: 138)
                            .rotationEffect(.degrees(Double(i - 1) * 12))
                            .offset(x: CGFloat(i - 1) * 54, y: abs(CGFloat(i - 1)) * 12)
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                    }
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.ciderGradient)
                        .frame(width: 92, height: 92)
                        .glassSurface(cornerRadius: 28)
                        .offset(y: float ? -6 : 6)
                }
                .frame(height: 240)

                VStack(spacing: 8) {
                    Text("Your library is empty")
                        .font(.largeTitle.weight(.bold))
                    Text(model.steamAvailable
                         ? "Open Steam to install your first game, or add one you downloaded with the + button."
                         : "Add a game you downloaded, or install Steam to play your Steam library.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                HStack(spacing: 12) {
                    if model.steamAvailable {
                        Button { model.openSteam("steam://store") } label: {
                            Label("Open the Steam Store", systemImage: "bag.fill")
                        }
                        .buttonStyle(.prominentLarge)
                        AddGameMenu(compact: false)
                    } else {
                        AddGameMenu(compact: false, prominent: true)
                        Button { model.installSteam() } label: {
                            Label("Install Steam", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.glassy)
                    }
                }
                .padding(.top, 6)
            }
            .padding(40)
        }
        .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever()) { float = true } }
    }
}

// MARK: - Games from outside Steam

/// "+" menu: add an .exe or run an installer.
struct AddGameMenu: View {
    @Environment(AppModel.self) private var model
    var compact = true
    var prominent = false

    var body: some View {
        Menu {
            Button {
                pick(types: ["exe"]) { model.addCustomGame(exe: $0) }
            } label: { Label("Add Game (.exe)…", systemImage: "plus.app") }
            Button {
                pick(types: ["exe", "msi"]) { model.runInstaller($0) }
            } label: { Label("Install with an Installer (.exe, .msi)…", systemImage: "shippingbox") }
            .disabled(model.installerRunning)
        } label: {
            if compact {
                Label("Add Game", systemImage: "plus")
            } else if prominent {
                Label("Add a Game", systemImage: "plus")
            } else {
                Text("Add a Game from Outside Steam")
            }
        }
        .menuIndicator(compact || prominent ? .hidden : .visible)
        .fixedSize()
        .help("Add a PC game from outside Steam")
        .modifier(GlassyMenu(enabled: !compact, prominent: prominent))
    }

    private func pick(types: [String], _ action: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose the game")
        panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { action(url) }
    }
}

private struct GlassyMenu: ViewModifier {
    let enabled: Bool
    var prominent = false
    func body(content: Content) -> some View {
        if prominent { content.buttonStyle(.prominentLarge) }
        else if enabled { content.buttonStyle(.glassy) } else { content }
    }
}

/// After an installer finishes: pick which new executable is the game.
struct InstallerResultsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: URL?

    var body: some View {
        let results = model.installerResults ?? []
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconBadge(symbol: "shippingbox.fill", color: .ciderDeep, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installation finished").font(.title2.weight(.bold))
                    Text(results.isEmpty ? "I couldn't find new executables. Choose the game's yourself."
                                         : "Choose the game's executable to add it to your library.")
                        .foregroundStyle(.secondary)
                }
            }
            if !results.isEmpty {
                List(results, id: \.self, selection: $selection) { url in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppModel.guessName(for: url)).font(.body.weight(.semibold))
                        Text(url.resolvingSymlinksInPath().path
                            .replacingOccurrences(of: model.paths.driveC.resolvingSymlinksInPath().path, with: "C:"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    .tag(url)
                }
                .frame(minHeight: 220)
            }
            HStack {
                Button("Choose Another…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "exe")].compactMap { $0 }
                    panel.directoryURL = model.paths.driveC
                    if panel.runModal() == .OK, let url = panel.url {
                        model.addCustomGame(exe: url)
                        dismiss()
                    }
                }
                .buttonStyle(.glassy)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glassy)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let selection { model.addCustomGame(exe: selection) }
                    dismiss()
                }
                .buttonStyle(.prominent)
                .disabled(selection == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { selection = results.first }
    }
}
