import SwiftUI

struct SteamView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.steamAvailable { installed } else { notInstalled }
    }

    private var notInstalled: some View {
        ZStack {
            BubblesView(count: 16, color: .cider, speed: 0.5).opacity(0.4)
            VStack(spacing: 20) {
                IconBadge(symbol: "bag.fill", color: Color(red: 0.12, green: 0.36, blue: 0.62), size: 88)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                Text("Steam isn't installed").font(.largeTitle.weight(.bold))
                Text("Install it to play your Steam library or buy new games. Games you add with the + button work without Steam.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Button { model.installSteam() } label: {
                    Label("Install Steam", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.prominentLarge)
                Text("Downloaded directly from Valve (about 400 MB).")
                    .font(.callout).foregroundStyle(.tertiary)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Steam")
    }

    private var installed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Go to")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                        SteamTile(symbol: "bag.fill", color: .blue, title: "Store",
                                  text: "Discover, buy and download games.") { model.openSteam("steam://store") }
                        SteamTile(symbol: "books.vertical.fill", color: .purple, title: "Steam Library",
                                  text: "Install the games you already own.") { model.openSteam("steam://open/games") }
                        SteamTile(symbol: "arrow.down.circle.fill", color: .green, title: "Downloads",
                                  text: "Check installation progress.") { model.openSteam("steam://open/downloads") }
                        SteamTile(symbol: "gearshape.2.fill", color: .gray, title: "Steam Settings",
                                  text: "Account, storage and downloads.") { model.openSteam("steam://open/settings") }
                    }
                }
                tips
            }
            .padding(30)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Steam")
    }

    private var header: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.11, green: 0.16, blue: 0.27), Color(red: 0.06, green: 0.32, blue: 0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                if let user = model.steamUser {
                    Text(String((user.personaName.isEmpty ? user.accountName : user.personaName).prefix(1)).uppercased())
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 78, height: 78)
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(model.steamRunning ? Color.green : Color.gray)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 3))
            }

            VStack(alignment: .leading, spacing: 6) {
                if let user = model.steamUser {
                    Text(user.personaName.isEmpty ? user.accountName : user.personaName)
                        .font(.title.weight(.bold))
                } else {
                    Text("Not signed in").font(.title.weight(.bold))
                }
                Text(model.steamRunning ? "Steam is open" : "Steam is closed")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.steamRunning {
                Button("Show Steam") { model.openSteam() }
                    .buttonStyle(.prominent)
                Button("Quit Steam") { model.quitSteam() }
                    .buttonStyle(.glassy)
            } else {
                Button {
                    model.openSteam()
                } label: {
                    Label(model.steamUser == nil ? "Sign In" : "Open Steam", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.prominentLarge)
            }
        }
        .padding(26)
        .glassSurface(cornerRadius: 26)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Good to know")
            VStack(alignment: .leading, spacing: 14) {
                Tip(symbol: "sparkles", text: "Games you install from Steam show up in your Cider Library automatically.")
                Tip(symbol: "macwindow", text: "You can close the Steam window any time: Cider reopens it when you play.")
                Tip(symbol: "exclamationmark.shield", text: "Games with kernel-level anti-cheat or that require DirectX 12 don't work.")
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 20)
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.ciderGradient).frame(width: 20)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SteamTile: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                IconBadge(symbol: symbol, color: color, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .offset(x: hover ? 2 : 0, y: hover ? -2 : 0)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .glassSurface(cornerRadius: 22)
            .scaleEffect(hover ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hover = h } }
    }
}
