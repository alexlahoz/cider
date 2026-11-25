import SwiftUI

/// Loads Steam artwork asynchronously and fades it in.
struct ArtworkImage<Placeholder: View>: View {
    let appID: Int
    let kind: ArtworkStore.Kind
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if loaded {
                placeholder()
            } else {
                LoadingShimmer()
            }
        }
        .task(id: "\(appID)-\(kind.rawValue)") {
            let img = await ArtworkStore.shared.image(appID: appID, kind: kind)
            withAnimation(.easeOut(duration: 0.35)) { image = img; loaded = true }
        }
    }
}

/// Vertical cover with a designed fallback (header image, then a generated poster).
struct CoverArt: View {
    let game: Game

    var body: some View {
        ArtworkImage(appID: game.artID, kind: .cover) {
            HeaderPoster(game: game)
        }
    }
}

/// For games without a vertical cover: the landscape header over a blurred copy of itself.
struct HeaderPoster: View {
    let game: Game
    @State private var header: NSImage?

    var body: some View {
        ZStack {
            if let header {
                GeometryReader { geo in
                    Image(nsImage: header).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 30).saturation(1.3).overlay(.black.opacity(0.35))
                        .clipped()
                }
                VStack(spacing: 14) {
                    Image(nsImage: header).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(radius: 12, y: 6)
                    Text(game.name).font(.headline.weight(.heavy)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).lineLimit(3)
                }
                .padding(14)
            } else {
                GeneratedPoster(name: game.name, seed: game.appID)
            }
        }
        .task(id: game.appID) {
            let img = await ArtworkStore.shared.image(appID: game.artID, kind: .header)
            withAnimation(.easeOut(duration: 0.3)) { header = img }
        }
    }
}

/// Poster drawn from the game's name, used when Steam has no artwork.
struct GeneratedPoster: View {
    let name: String
    let seed: Int
    var showTitle = true

    var body: some View {
        let hue = Double((seed &* 2_654_435_761) % 360 + 360) .truncatingRemainder(dividingBy: 360) / 360
        let hue2 = (hue + 0.08).truncatingRemainder(dividingBy: 1)
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.45),
                                    Color(hue: hue2, saturation: 0.7, brightness: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 90))
                .foregroundStyle(.white.opacity(0.07))
                .rotationEffect(.degrees(-14))
                .offset(x: 40, y: -60)
            if showTitle {
                VStack(alignment: .leading) {
                    Spacer()
                    Text(name)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                        .shadow(radius: 6)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct LoadingShimmer: View {
    @State private var phase: CGFloat = -1
    var body: some View {
        Rectangle()
            .fill(.quaternary.opacity(0.5))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
