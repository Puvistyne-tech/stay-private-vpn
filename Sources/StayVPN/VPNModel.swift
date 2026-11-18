import AppKit
import Foundation
import ServiceManagement
import StayVPNCore

@MainActor
final class VPNModel: ObservableObject {
    enum Phase: Equatable {
        case disconnected
        case connecting
        /// Tunnel is up but the server has not answered (yet, or any more).
        case waiting
        case connected
        case disconnecting
    }

    @Published private(set) var phase: Phase = .disconnected
    @Published private(set) var profiles: [String] = []
    @Published private(set) var tunnel: TunnelStatus?
    @Published private(set) var publicIP: String?
    /// Shown instead of the controls when setup is incomplete.
    @Published private(set) var setupMessage: String?
    /// True when the fix for `setupMessage` is installing (or updating) the helper.
    @Published private(set) var canInstallHelper = false
    @Published private(set) var isInstallingHelper = false
    @Published private(set) var speedResult: SpeedResult?
    @Published private(set) var speedError: String?
    @Published private(set) var isTestingSpeed = false
    @Published private(set) var errorMessage: String?
    @Published var selected: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let helper = HelperClient()
    private let store = ProfileStore()
    private var pollTask: Task<Void, Never>?
    private var ipTask: Task<Void, Never>?
    private var didFetchIP = false
    private var helperVerified = false

    var isBusy: Bool { phase == .connecting || phase == .disconnecting }
    var isUp: Bool { phase == .connected || phase == .waiting }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    // MARK: Actions

    func toggle() {
        if isUp { disconnect() } else { connect() }
    }

    func connect() {
        guard let profile = selected, !isBusy else { return }
        errorMessage = nil
        phase = .connecting
        store.lastUsed = profile
        Task {
            do {
                try await helper.up(profile)
                // Give the server a moment to answer before judging the connection.
                for _ in 0..<10 {
                    if let status = try await helper.status().first, status.lastHandshake != nil { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch {
                report(error)
            }
            phase = .disconnected
            await refresh()
            refreshPublicIP()
        }
    }

    func disconnect() {
        guard let profile = tunnel?.profile ?? selected, !isBusy else { return }
        errorMessage = nil
        phase = .disconnecting
        Task {
            do { try await helper.down(profile) } catch { report(error) }
            phase = .disconnected
            await refresh()
            refreshPublicIP()
        }
    }

    func select(_ profile: String) {
        guard !isBusy, profile != selected else { return }
        let wasUp = isUp
        selected = profile
        store.lastUsed = profile
        if wasUp { connect() }  // the helper drops the old tunnel first
    }

    func importConfig() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Import WireGuard config"
        panel.message = "Choose a WireGuard .conf file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        errorMessage = nil
        Task {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= WGConfig.maxBytes else { throw WGConfig.ValidationError.tooLarge }
                try WGConfig.validate(String(decoding: data, as: UTF8.self))
                let name = ProfileName.sanitize(url.lastPathComponent)
                try await helper.importConfig(profile: name, file: url)
                selected = name
                store.lastUsed = name
            } catch {
                report(error)
            }
            await refresh()
        }
    }

    func remove(_ profile: String) {
        guard !isBusy else { return }
        errorMessage = nil
        Task {
            do { try await helper.remove(profile) } catch { report(error) }
            await refresh()
            refreshPublicIP()
        }
    }

    func runSpeedTest() {
        guard !isTestingSpeed else { return }
        isTestingSpeed = true
        speedError = nil
        Task {
            do {
                speedResult = try await SpeedTest.run()
            } catch {
                speedResult = nil
                speedError = error.localizedDescription
            }
            isTestingSpeed = false
        }
    }

    /// Runs the installer bundled in the app through macOS's own administrator
    /// prompt. The password goes to macOS, never to this app.
    func installHelper() {
        guard !isInstallingHelper else { return }
        guard let script = Bundle.main.url(forResource: "install-helper", withExtension: "sh") else {
            errorMessage = "This copy of the app has no bundled installer. In Terminal, from the project folder, run: sudo ./scripts/install-helper.sh"
            return
        }
        isInstallingHelper = true
        errorMessage = nil
        let user = NSUserName()
        Task {
            let failure = await Self.runAsAdministrator(script: script.path, user: user)
            isInstallingHelper = false
            helperVerified = false
            if let failure { errorMessage = failure }
            await refresh()
        }
    }

    /// Returns nil on success, or a message. A cancelled password prompt is not an error.
    private static func runAsAdministrator(script: String, user: String) async -> String? {
        await Task.detached {
            func quoted(_ text: String) -> String {
                "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }
            let source = "do shell script \"/bin/bash \" & quoted form of \(quoted(script)) & \" --user \" & quoted form of \(quoted(user)) "
                + "with prompt \"Stay Private needs to install its helper.\" with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let err = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = err
            do { try process.run() } catch { return error.localizedDescription }
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            if process.terminationStatus == 0 || stderr.contains("-128") { return nil }
            return "Helper install failed: " + stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Could not change launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: State

    func refresh() async {
        do {
            if !helperVerified {
                try await helper.checkVersion()
                helperVerified = true
            }
            let names = try await helper.profiles()
            let active = try await helper.status().first
            setupMessage = nil
            canInstallHelper = false
            profiles = names
            tunnel = active
            if !isBusy {
                let previous = phase
                if let active {
                    phase = active.isLive() ? .connected : .waiting
                    selected = active.profile
                } else {
                    phase = .disconnected
                    if selected == nil || !names.contains(selected ?? "") {
                        selected = store.preferred(among: names, active: nil)
                    }
                }
                if !didFetchIP || (previous == .connected) != (phase == .connected) { refreshPublicIP() }
            }
        } catch let error as HelperError where Self.isSetupProblem(error) {
            showSetup(error)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        if let helperError = error as? HelperError, Self.isSetupProblem(helperError) {
            showSetup(helperError)
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private static func isSetupProblem(_ error: HelperError) -> Bool {
        error == .setupNeeded || error == .updateNeeded || error == .toolsMissing
    }

    private func showSetup(_ error: HelperError) {
        helperVerified = false
        setupMessage = error.localizedDescription
        canInstallHelper = error != .toolsMissing
    }

    private func refreshPublicIP() {
        didFetchIP = true
        ipTask?.cancel()
        ipTask = Task { [weak self] in
            // Routes take a moment to settle after a tunnel change.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            var request = URLRequest(url: URL(string: "https://api.ipify.org")!)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: .ephemeral)
            let text = (try? await session.data(for: request)).map { String(decoding: $0.0, as: UTF8.self) }
            guard !Task.isCancelled else { return }
            let ip = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.publicIP = (ip?.isEmpty == false && (ip?.count ?? 0) <= 45) ? ip : nil
        }
    }
}
