import AppKit
import PulseCore
import SwiftUI

/// La fenêtre qui annonce une nouvelle version : ouverte au lancement de Pulse
/// quand une mise à jour est trouvée, ou depuis le popover et la notification.
struct UpdateWindow: View {
    let updater: Updater
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 12) {
                if let info = updater.foundUpdate {
                    content(for: info)
                } else {
                    Text("Pulse est à jour")
                        .font(.headline)
                    Text("Vous avez la dernière version (\(updater.currentVersion)).")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Fermer") { close() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private func content(for info: UpdateInfo) -> some View {
        Text("Une nouvelle version de Pulse est disponible")
            .font(.headline)
        Text("Pulse \(info.version) est disponible. Vous avez la version \(updater.currentVersion).")
            .foregroundStyle(.secondary)

        if !info.notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nouveautés")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    Text(info.notes.replacingOccurrences(of: "\r", with: ""))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }

        status

        HStack {
            Button("Ignorer cette version") {
                updater.skip(info)
                close()
            }
            .disabled(updater.isBusy)
            Spacer()
            Button("Plus tard") { close() }
                .keyboardShortcut(.cancelAction)
            Button("Installer et relancer") {
                Task { await updater.install(info) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(updater.isBusy)
        }
    }

    /// Téléchargement, installation, ou erreur.
    @ViewBuilder
    private var status: some View {
        switch updater.phase {
        case .downloading:
            progress("Téléchargement…")
        case .installing:
            progress("Installation… Pulse va redémarrer.")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
        }
    }

    private func close() {
        dismissWindow(id: WindowID.update)
    }
}
