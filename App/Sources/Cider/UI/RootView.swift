import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            if model.showOnboarding {
                OnboardingView()
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 1.08).combined(with: .opacity)))
                    .zIndex(1)
            } else {
                MainView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let busy = model.busyMessage {
                BusyOverlay(message: busy)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4), value: model.busyMessage != nil)
        .sheet(isPresented: $model.showAbout) { AboutView() }
        .sheet(isPresented: Binding(get: { model.updater.showSheet }, set: { model.updater.showSheet = $0 })) {
            UpdateSheet()
        }
        .tint(.cider)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            Group {
                switch model.selection {
                case .library: LibraryView()
                case .steam: SteamView()
                case .settings: SettingsView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .frame(minWidth: 700, minHeight: 520)
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.selection }, set: { if let v = $0 { model.selection = v; model.selectedGameID = nil } })) {
            Section {
                ForEach([SidebarItem.library, .steam]) { item in
                    row(item)
                }
            }
            if !model.recentlyPlayed.isEmpty {
                Section("Recent") {
                    ForEach(model.recentlyPlayed.prefix(4)) { game in
                        Button {
                            model.selection = .library
                            withAnimation(.spring(duration: 0.55, bounce: 0.15)) { model.selectedGameID = game.appID }
                        } label: {
                            HStack(spacing: 10) {
                                ArtworkImage(appID: game.artID, kind: .cover) { GeneratedPoster(name: game.name, seed: game.appID, showTitle: false) }
                                    .frame(width: 22, height: 33)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                Text(game.name).lineLimit(1)
                                Spacer(minLength: 0)
                                if model.activity[game.appID] == .running {
                                    Circle().fill(.green).frame(width: 7, height: 7)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                ForEach([SidebarItem.settings, .diagnostics]) { item in
                    row(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                AppIconView(size: 30)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Cider").font(.headline.weight(.heavy))
                    Text("PC games on your Mac").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let release = model.updater.availableRelease {
                    UpdateBanner(version: release.version)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                SteamStatusFooter()
            }
            .padding(12)
            .animation(.spring(duration: 0.5), value: model.updater.availableRelease?.version)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
    }
}

struct SteamStatusFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.selection = .steam
            model.selectedGameID = nil
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 0.11, green: 0.16, blue: 0.27), Color(red: 0.06, green: 0.32, blue: 0.55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(initial).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(model.steamRunning ? .green : .gray).frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(!model.steamAvailable ? "Steam not installed" : (model.steamRunning ? "Steam open" : "Steam closed"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .glassSurface(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private var name: String {
        guard let u = model.steamUser else {
            return model.steamAvailable ? String(localized: "Signed out") : String(localized: "No Steam")
        }
        return u.personaName.isEmpty ? u.accountName : u.personaName
    }

    private var initial: String {
        guard let u = model.steamUser else { return "?" }
        return String((u.personaName.isEmpty ? u.accountName : u.personaName).prefix(1)).uppercased()
    }
}

struct ToastView: View {
    let toast: AppModel.Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .orange : .green)
            Text(toast.message).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 18)
        .frame(maxWidth: 560)
    }
}

struct BusyOverlay: View {
    let message: LocalizedStringKey
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(message).font(.headline)
            }
            .padding(30)
            .glassSurface(cornerRadius: 24)
        }
    }
}
