import SwiftUI

struct Component: Identifiable {
    let id = UUID()
    let name: String
    let license: String
    let role: LocalizedStringKey
    let url: String?
    let file: String?
}

let bundledComponents: [Component] = [
    Component(name: "Wine 11.21", license: "LGPL-2.1-or-later", role: "Compatibility engine for PC games",
              url: "https://dl.winehq.org/wine/source/11.x/wine-11.21.tar.xz", file: "Wine-COPYING.LIB.txt"),
    Component(name: "Wine para macOS (Gcenx)", license: "LGPL-2.1-or-later", role: "Wine build for Mac",
              url: "https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.21", file: "NOTICE.md"),
    Component(name: "DXMT", license: "MIT", role: "Translates DirectX 10/11 to Metal",
              url: "https://github.com/notpop/dxmt/tree/924a607", file: "DXMT-LICENSE.txt"),
    Component(name: "LLVM 15", license: "Apache-2.0 WITH LLVM-exception", role: "DXMT's shader compiler",
              url: "https://github.com/llvm/llvm-project/tree/llvmorg-15.0.7", file: "LLVM-LICENSE.txt"),
    Component(name: "MoltenVK", license: "Apache-2.0", role: "Vulkan on Metal",
              url: "https://github.com/KhronosGroup/MoltenVK", file: "MoltenVK-LICENSE.txt"),
    Component(name: "steamwebhelper (Cider)", license: "MIT", role: "Steam browser fix",
              url: nil, file: "webhelper_wrapper.c"),
]

struct AboutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                AppIconView(size: 96)
                Text("Cider").font(.system(size: 30, weight: .heavy))
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .foregroundStyle(.secondary)
                Text("Cider is free software. Steam is downloaded directly from Valve and is not part of Cider. Steam is a trademark of Valve Corporation; Cider is not affiliated with Valve or Apple.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            List(bundledComponents) { c in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.body.weight(.semibold))
                        Text(c.role).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(c.license)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    if let file = c.file {
                        Button {
                            NSWorkspace.shared.open(model.paths.licenses.appendingPathComponent(file))
                        } label: { Image(systemName: "doc.text") }
                        .buttonStyle(.borderless)
                        .help("View license")
                    }
                    if let url = c.url.flatMap(URL.init(string:)) {
                        Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(.borderless)
                            .help("Source code")
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 260)

            HStack {
                Button("Open Licenses Folder") { NSWorkspace.shared.open(model.paths.licenses) }
                    .buttonStyle(.glassy)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.prominent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 600, height: 640)
    }
}

struct AppIconView: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
