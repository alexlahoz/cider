import SwiftUI

extension Color {
    /// Green-apple cider: the app accent.
    static let cider = Color(red: 0.45, green: 0.82, blue: 0.22)
    static let ciderDeep = Color(red: 0.12, green: 0.60, blue: 0.30)
    static let ciderLime = Color(red: 0.80, green: 0.92, blue: 0.32)
    static let ciderInk = Color(red: 0.03, green: 0.09, blue: 0.05)
}

extension ShapeStyle where Self == LinearGradient {
    static var ciderGradient: LinearGradient {
        LinearGradient(colors: [.cider, .ciderDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Glass / material surfaces

extension View {
    /// Liquid Glass on macOS 26+, translucent material before that.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular,
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    /// A quieter card used for grouped content.
    func cardSurface(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            if let tint {
                self.background(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
            } else {
                self.background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
            }
        }
    }
}

// MARK: - Buttons

/// Big accent button (Play, Get started…).
struct ProminentButtonStyle: ButtonStyle {
    var large = false
    /// Red variant, for actions such as closing a running game.
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.bold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 30 : 18)
            .padding(.vertical, large ? 14 : 8)
            .background {
                Capsule().fill(destructive ? Self.destructiveGradient : LinearGradient.ciderGradient)
                    .overlay(
                        Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    )
                    .shadow(color: (destructive ? Color.red : .ciderDeep).opacity(isEnabled ? 0.45 : 0), radius: large ? 18 : 10, y: large ? 8 : 4)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private static let destructiveGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.30, blue: 0.27), Color(red: 0.78, green: 0.16, blue: 0.16)],
        startPoint: .top, endPoint: .bottom)
}

/// Translucent secondary button.
struct GlassButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 8)
            .glassCapsule()
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
    static var prominentLarge: ProminentButtonStyle { ProminentButtonStyle(large: true) }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glassy: GlassButtonStyle { GlassButtonStyle() }
    static var glassyCompact: GlassButtonStyle { GlassButtonStyle(compact: true) }
}

// MARK: - Small components

struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.title2.weight(.bold))
            if let subtitle {
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct StatusPill: View {
    enum Kind { case playing, launching, updating, info }
    let kind: Kind
    let text: LocalizedStringKey

    var color: Color {
        switch kind {
        case .playing: return .green
        case .launching: return .cider
        case .updating: return .blue
        case .info: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Static on purpose: a looping animation here kept Cider redrawing (and the
            // window server compositing its glass) the whole time a game was running.
            Circle().fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color, radius: 3)
            Text(text).font(.caption.weight(.bold)).textCase(.uppercase).tracking(0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .foregroundStyle(.white)
    }
}

/// Whether Cider is the frontmost app (continuous animations pause when it isn't).
@Observable
@MainActor
final class AppActivity {
    static let shared = AppActivity()
    var isActive = true

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = true }
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = false }
        }
        nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = false }
        }
    }
}

struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: color.opacity(0.3), radius: 3, y: 1)
    }
}

/// Rising bubbles, the Cider motif.
struct BubblesView: View {
    var count = 26
    var color: Color = .white
    var speed: Double = 1

    private struct Bubble {
        let x: Double, size: Double, speed: Double, phase: Double, wobble: Double
    }

    private let bubbles: [Bubble]

    init(count: Int = 26, color: Color = .white, speed: Double = 1, seed: UInt64 = 7) {
        self.count = count
        self.color = color
        self.speed = speed
        var rng = SplitMix(seed: seed)
        bubbles = (0..<count).map { _ in
            Bubble(x: rng.next(), size: 4 + rng.next() * 16, speed: 0.04 + rng.next() * 0.08,
                   phase: rng.next(), wobble: 4 + rng.next() * 10)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !AppActivity.shared.isActive)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate * speed
                for b in bubbles {
                    let progress = (b.phase + t * b.speed).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.05 - progress * 1.15)
                    let x = b.x * size.width + sin(t * 1.3 + b.phase * 12) * b.wobble
                    let r = b.size * (0.7 + progress * 0.5)
                    let rect = CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)
                    let alpha = min(1, progress * 4) * min(1, (1 - progress) * 3)
                    ctx.opacity = alpha * 0.55
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.2)
                    ctx.opacity = alpha * 0.35
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.22, dy: r * 0.22).offsetBy(dx: -r * 0.12, dy: -r * 0.12)),
                             with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z % 1_000_000) / 1_000_000
    }
}

// MARK: - Formatting

enum Fmt {
    static func size(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    static func playtime(minutes: Int) -> String {
        if minutes <= 0 { return String(localized: "Unplayed") }
        if minutes < 60 { return String(localized: "\(String(minutes)) min") }
        let hours = Double(minutes) / 60
        return "\((hours < 10 ? hours : hours.rounded()).formatted(.number.precision(.fractionLength(0...1)))) h"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return String(localized: "Never") }
        if abs(date.timeIntervalSinceNow) < 120 { return String(localized: "Just now") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func display(_ mode: DisplayMode) -> String {
        switch mode {
        case .native, .fullscreen: return String(localized: "macOS window")
        case .window(let w, let h): return String(localized: "Fixed window \(String(w))×\(String(h))")
        }
    }

    static func api(_ info: GraphicsInfo?) -> (title: String, detail: String, ok: Bool) {
        guard let info else { return (String(localized: "Detecting…"), "", true) }
        let bits = info.is64Bit ? "64 bits" : "32 bits"
        switch info.api {
        case .dx11, .dx10:
            if info.is64Bit {
                return ("DirectX \(info.api == .dx11 ? "11" : "10") → Metal", String(localized: "Best performance"), true)
            }
            return ("DirectX \(info.api == .dx11 ? "11" : "10")", String(localized: "Limited compatibility"), false)
        case .dx9: return ("DirectX 9", String(localized: "Supported"), true)
        case .dx8: return ("DirectX 8", String(localized: "Supported"), true)
        case .dx12: return ("DirectX 12", String(localized: "Not supported"), false)
        case .vulkan: return ("Vulkan → Metal", String(localized: "Supported"), true)
        case .openGL: return ("OpenGL", String(localized: "Supported"), true)
        case .unknown: return (String(localized: "Unknown"), bits, true)
        }
    }
}
