import SwiftUI
import StayVPNCore

struct MenuView: View {
    @ObservedObject var model: VPNModel
    @State private var showingGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingGuide {
                GuideView(onImport: { showingGuide = false; model.importConfig() },
                          onClose: { showingGuide = false })
            } else {
                mainContent
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    @ViewBuilder private var mainContent: some View {
            header
            if let setup = model.setupMessage {
                setupView(setup)
            } else {
                connectButton
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Divider()
                profilesSection
                Divider()
                speedSection
            }
            Divider()
            footer
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(statusTitle).font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 10) {
                Text("IP \(model.publicIP ?? "—")")
                if let tunnel = model.tunnel {
                    Spacer()
                    Text("↓ \(bytes(tunnel.bytesReceived))  ↑ \(bytes(tunnel.bytesSent))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var connectButton: some View {
        Button(action: model.toggle) {
            Text(buttonTitle).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(model.isUp ? .gray : .accentColor)
        .disabled(model.isBusy || model.selected == nil)
        .keyboardShortcut(.defaultAction)
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Profiles").font(.caption).foregroundStyle(.secondary)
            if model.profiles.isEmpty {
                Text("No profiles yet. Import a WireGuard .conf file to get started, or see “How to get a config” below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            ForEach(model.profiles, id: \.self) { profile in
                ProfileRow(name: profile, isSelected: profile == model.selected) {
                    model.select(profile)
                }
                .disabled(model.isBusy)
                .contextMenu {
                    Button("Remove “\(profile)”", role: .destructive) { model.remove(profile) }
                }
            }
            HStack {
                Button("Import config…", action: model.importConfig)
                    .buttonStyle(.link)
                    .disabled(model.isBusy)
                Spacer()
                Button("How to get a config") { showingGuide = true }
                    .buttonStyle(.link)
            }
            .padding(.top, 4)
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(model.isTestingSpeed ? "Testing…" : "Speed test", action: model.runSpeedTest)
                    .disabled(model.isTestingSpeed)
                if model.isTestingSpeed {
                    ProgressView().controlSize(.small)
                    Text("about 20 seconds").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let result = model.speedResult, !model.isTestingSpeed {
                Text(result.summary).font(.callout.monospacedDigit())
            }
            if let error = model.speedError, !model.isTestingSpeed {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setupView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                if model.canInstallHelper {
                    Button(model.isInstallingHelper ? "Installing…" : "Install helper…", action: model.installHelper)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isInstallingHelper)
                }
                Button("Check again") { Task { await model.refresh() } }
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .font(.callout)
    }

    // MARK: Text

    private var statusTitle: String {
        let name = model.tunnel?.profile ?? model.selected ?? ""
        switch model.phase {
        case .connected: return "Connected · \(name)"
        case .waiting: return "No response · \(name)"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .disconnected: return "Not connected"
        }
    }

    private var buttonTitle: String {
        switch model.phase {
        case .connected, .waiting, .disconnecting: return "Disconnect"
        case .disconnected, .connecting: return "Connect"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .connected: return .green
        case .waiting, .connecting, .disconnecting: return .orange
        case .disconnected: return .secondary
        }
    }

    private func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .binary)
    }
}

private struct ProfileRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .opacity(isSelected ? 1 : 0)
                Text(name)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
