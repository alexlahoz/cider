import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var ns

    private var setup: SetupModel { model.setup }

    var body: some View {
        ZStack {
            OnboardingBackground()
            BubblesView(count: 34, color: .white, speed: 0.8)
                .opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                switch setup.phase {
                case .welcome:
                    welcome.transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.96).combined(with: .opacity)))
                case .finished:
                    finished.transition(.scale(scale: 0.9).combined(with: .opacity))
                default:
                    progressPanel.transition(.scale(scale: 1.04).combined(with: .opacity))
                }
                Spacer(minLength: 20)
            }
            .padding(40)
            .environment(\.colorScheme, .dark)
        }
        .animation(.spring(duration: 0.6, bounce: 0.18), value: setup.phase)
        .ignoresSafeArea()
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(HideWindowTitle())
    }

    // MARK: welcome

    private var welcome: some View {
        VStack(spacing: 26) {
            AppIconView(size: 148)
                .matchedGeometryEffect(id: "icon", in: ns)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
            VStack(spacing: 12) {
                Text("Welcome to Cider")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Play your PC games on your Mac.\nNo hassle.")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.82))
            }
            HStack(spacing: 14) {
                Feature(symbol: "bolt.fill", title: "DirectX 11 on Metal", text: "Graphics translated natively.")
                Feature(symbol: "lock.shield.fill", title: "Neatly contained", text: "Your games, neatly contained inside Cider.")
                Feature(symbol: "wand.and.stars", title: "Automatic fixes", text: "Every game, tuned when it opens.")
            }
            .padding(.top, 8)
            VStack(spacing: 12) {
                Button {
                    setup.start()
                } label: {
                    HStack(spacing: 10) {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.prominentLarge)
                .keyboardShortcut(.defaultAction)
                Text("If you like, Cider will install Steam (about 400 MB). You need an Internet connection and about 2 GB free.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: 820)
    }

    // MARK: progress

    private var progressPanel: some View {
        VStack(spacing: 30) {
            HStack(spacing: 14) {
                AppIconView(size: 52)
                    .matchedGeometryEffect(id: "icon", in: ns)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setting up Cider").font(.title2.weight(.bold))
                    Text("This only happens once. You can leave it working.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Stepper(setup: setup)

            stepBody
                .frame(maxWidth: .infinity, minHeight: 210)
                .id(setup.currentStep)
                .transition(.push(from: .trailing).combined(with: .opacity))
        }
        .padding(34)
        .frame(width: 700)
        .glassSurface(cornerRadius: 32)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch setup.phase {
        case .needsRosetta:
            StepCard(symbol: "cpu", tint: .cider, title: "Rosetta 2 is required",
                     message: "PC games are made for Intel processors. Rosetta 2 is Apple's free tool that translates them for your chip. It's installed once and macOS will ask for your password.") {
                HStack {
                    Button("Install Rosetta 2") { setup.installRosetta() }
                        .buttonStyle(.prominent)
                    Button("Learn More") {
                        NSWorkspace.shared.open(URL(string: "https://support.apple.com/102527")!)
                    }
                    .buttonStyle(.glassy)
                }
            }
        case .failed(let step, let message):
            StepCard(symbol: "exclamationmark.triangle.fill", tint: .red, title: "Something went wrong",
                     message: LocalizedStringKey(stringLiteral: failureText(step, message))) {
                HStack {
                    Button("Try Again") { setup.retry() }
                        .buttonStyle(.prominent)
                    if step == .steam || step == .login {
                        Button("Continue without Steam") { setup.skipSteam() }
                            .buttonStyle(.glassy)
                    }
                    Button("View Log") { NSWorkspace.shared.open(model.paths.wineLog) }
                        .buttonStyle(.glassy)
                }
            }
        case .waitingForLogin:
            StepCard(symbol: "person.crop.circle.badge.checkmark", tint: .cider, title: "Sign in to Steam",
                     message: "We've opened Steam in a new window. Sign in with your account (you can use the QR code in the Steam app). Cider will continue on its own once it detects your session.") {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for you to sign in…").foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("I can't see the Steam window") { setup.reopenSteamForLogin() }
                            .buttonStyle(.glassy)
                        Button("I'll do it later") { setup.skipLogin() }
                            .buttonStyle(.glassy)
                    }
                }
            }
        case .running(let step):
            VStack(spacing: 18) {
                RunningStep(step: step, progress: setup.progress, detail: setup.detail)
                if step == .steam {
                    Button("Not now, continue without Steam") { setup.skipSteam() }
                        .buttonStyle(.glassyCompact)
                        .help("You can install Steam later from the Steam section")
                }
            }
        default:
            EmptyView()
        }
    }

    private func failureText(_ step: SetupModel.Step, _ message: String) -> String {
        let where_: String
        switch step {
        case .mac: where_ = String(localized: "while checking your Mac")
        case .windows: where_ = String(localized: "while preparing the engine")
        case .steam: where_ = String(localized: "while installing Steam")
        case .login: where_ = String(localized: "while opening Steam")
        }
        return String(localized: "A step failed \(where_): \(message)")
    }

    // MARK: finished

    private var finished: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(.ciderGradient).frame(width: 128, height: 128)
                    .shadow(color: .ciderDeep.opacity(0.6), radius: 30, y: 10)
                Image(systemName: "checkmark")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 10) {
                Text("All set!")
                    .font(.system(size: 50, weight: .heavy))
                Text(setup.skipped.contains(.steam)
                     ? String(localized: "Add your games with the + button in the Library. You can install Steam any time from the Steam section.")
                     : model.steamUser.map { String(localized: "Hi, \($0.personaName.isEmpty ? $0.accountName : $0.personaName). Your Mac is ready to play.") }
                     ?? String(localized: "Your Mac is ready to play."))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Button {
                model.finishOnboarding()
            } label: {
                HStack(spacing: 10) {
                    Text("Go to My Library")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.prominentLarge)
            .keyboardShortcut(.defaultAction)
        }
        .foregroundStyle(.white)
    }
}

private struct Feature: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.ciderGradient)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 210, height: 96, alignment: .topLeading)
        .padding(18)
        .glassSurface(cornerRadius: 20)
    }
}

/// Horizontal 4-step indicator.
private struct Stepper: View {
    let setup: SetupModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SetupModel.Step.allCases) { step in
                let skipped = setup.skipped.contains(step)
                let done = setup.completed.contains(step)
                let active = setup.currentStep == step && !done && !skipped
                if step != .mac {
                    Capsule()
                        .fill(done || active ? AnyShapeStyle(.ciderGradient) : AnyShapeStyle(.white.opacity(0.12)))
                        .frame(height: 3)
                        .padding(.horizontal, 10)
                }
                ZStack {
                    Circle()
                        .fill(done ? AnyShapeStyle(.ciderGradient) : AnyShapeStyle(.white.opacity(active ? 0.18 : 0.08)))
                        .overlay(Circle().strokeBorder(.white.opacity(active ? 0.6 : 0.15), lineWidth: active ? 2 : 1))
                        .shadow(color: active ? .cider.opacity(0.6) : .clear, radius: 12)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                            .transition(.scale.combined(with: .opacity))
                    } else if skipped {
                        Image(systemName: "forward.fill").font(.system(size: 15, weight: .semibold))
                            .opacity(0.45)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: step.symbol).font(.system(size: 18, weight: .semibold))
                            .opacity(active ? 1 : 0.5)
                    }
                }
                .frame(width: 46, height: 46)
                .overlay(alignment: .top) {
                    Text(step.title)
                        .font(.caption.weight(active ? .bold : .medium))
                        .foregroundStyle(active || done ? .primary : .secondary)
                        .fixedSize()
                        .offset(y: 56)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 26)
    }
}

private struct RunningStep: View {
    let step: SetupModel.Step
    let progress: Double?
    let detail: String

    @State private var glow = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.cider.opacity(0.45), .clear], center: .center, startRadius: 4, endRadius: 70))
                    .frame(width: 140, height: 140)
                    .scaleEffect(glow ? 1.1 : 0.85)
                Image(systemName: step.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffectPulse()
            }
            .frame(height: 96)
            .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever()) { glow = true } }

            Text(step.title).font(.title2.weight(.bold))
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .frame(minHeight: 22)
            CiderProgressBar(value: progress)
                .frame(width: 460)
        }
    }
}

struct CiderProgressBar: View {
    let value: Double?
    @State private var phase: CGFloat = -0.4

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    if let value {
                        Capsule()
                            .fill(.ciderGradient)
                            .frame(width: max(12, geo.size.width * value))
                            .overlay(shimmer.clipShape(Capsule()))
                            .shadow(color: .cider.opacity(0.6), radius: 8)
                            .animation(.spring(duration: 0.6), value: value)
                    } else {
                        Capsule()
                            .fill(.ciderGradient)
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: phase * geo.size.width)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            if let value {
                Text(verbatim: "\(Int((value * 100).rounded())) %")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { phase = 0.9 }
        }
    }

    private var shimmer: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 80)
            .offset(x: phase * 400)
    }
}

private struct StepCard<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 60)
            Text(title).font(.title2.weight(.bold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
            actions().padding(.top, 4)
        }
    }
}

struct OnboardingBackground: View {
    @State private var t = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.17, blue: 0.08), Color(red: 0.01, green: 0.05, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.ciderDeep.opacity(0.6)).frame(width: 700).blur(radius: 160)
                .offset(x: t ? -260 : -120, y: t ? -220 : -120)
            Circle().fill(Color.cider.opacity(0.35)).frame(width: 600).blur(radius: 150)
                .offset(x: t ? 300 : 200, y: t ? 160 : 260)
            Circle().fill(Color.ciderLime.opacity(0.22)).frame(width: 500).blur(radius: 150)
                .offset(x: t ? 120 : 320, y: t ? -260 : -160)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever()) { t = true } }
    }
}

extension View {
    @ViewBuilder
    func symbolEffectPulse() -> some View {
        self.symbolEffect(.pulse, options: .repeating)
    }
}

private struct HideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
        }
    }
}
