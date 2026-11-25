import SwiftUI

/// Small card above the Steam footer when a new version is out.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    let version: String

    var body: some View {
        Button {
            model.updater.showSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.ciderGradient)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cider \(version) is available").font(.callout.weight(.semibold)).lineLimit(1)
                    Text("Click to update").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .glassSurface(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}

/// Check / download / install flow.
struct UpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var updater: Updater { model.updater }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppIconView(size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title2.weight(.bold))
                    Text("You have version \(updater.currentVersion).")
                        .foregroundStyle(.secondary)
                }
            }
            content
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: LocalizedStringKey {
        switch updater.state {
        case .checking, .idle: return "Checking for updates…"
        case .upToDate: return "Cider is up to date"
        case .available(let r), .downloading(let r, _), .installing(let r): return "Cider \(r.version) is available"
        case .failed: return "Couldn't update"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .checking, .idle:
            ProgressView().controlSize(.small)
        case .upToDate:
            Text("You already have the latest version.").foregroundStyle(.secondary)
        case .available(let r):
            notes(r)
        case .downloading(let r, let p):
            notes(r)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: p).tint(.cider)
                Text("Downloading… \(String(Int(p * 100))) %").font(.caption).foregroundStyle(.secondary)
            }
        case .installing(let r):
            notes(r)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing. Cider will restart by itself.").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.secondary)
        }
    }

    /// Release notes come as Markdown (from CHANGELOG.md): show "### Added" headings as bold lines.
    private func formattedNotes(_ notes: String) -> AttributedString {
        let text = notes.isEmpty ? String(localized: "Improvements and fixes.") : notes
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { return line }
            return "**" + trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + "**"
        }
        let markdown = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func notes(_ release: Updater.Release) -> some View {
        ScrollView {
            Text(formattedNotes(release.notes))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 220)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }

    @ViewBuilder
    private var buttons: some View {
        switch updater.state {
        case .available(let r):
            Button("Later") { dismiss() }
                .buttonStyle(.glassy)
                .keyboardShortcut(.cancelAction)
            Button("Update Now") {
                updater.install(r) { await model.prepareForUpdate() }
            }
            .buttonStyle(.prominent)
            .keyboardShortcut(.defaultAction)
        case .downloading, .installing:
            EmptyView()
        case .failed:
            Button("Close") { dismiss() }.buttonStyle(.glassy)
            Button("Try Again") { Task { await updater.check(userInitiated: true) } }
                .buttonStyle(.prominent)
        default:
            Button("Close") { dismiss() }
                .buttonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
