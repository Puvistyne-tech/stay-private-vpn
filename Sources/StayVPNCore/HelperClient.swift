import Foundation

public enum HelperError: Error, Equatable, LocalizedError {
    /// The helper or its sudoers rule is not installed yet.
    case setupNeeded
    /// The installed helper is older than this app expects.
    case updateNeeded
    /// `wg` / `wg-quick` are not installed.
    case toolsMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .setupNeeded:
            return "One-time setup: Stay Private needs to install a small helper so it can switch the VPN on and off without asking for your password each time."
        case .updateNeeded:
            return "The Stay Private helper needs updating to match this version of the app."
        case .toolsMissing:
            return "WireGuard tools are missing. In Terminal, run: brew install wireguard-tools"
        case .failed(let message):
            return message
        }
    }
}

/// Runs the root helper through `sudo -n` (never prompts for a password).
public struct HelperClient: Sendable {
    public static let helperPath = "/usr/local/libexec/stayvpn-helper"
    static let toolsMissingExitCode: Int32 = 3
    /// Must match VERSION in helper/stayvpn-helper.
    public static let expectedVersion = 2

    public init() {}

    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Self.helperPath)
    }

    /// Throws `.updateNeeded` when the installed helper is not the version this app was built with.
    public func checkVersion() async throws {
        let installed: Int?
        do {
            installed = Int(try await run(["version"]).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch HelperError.failed {
            installed = nil  // version 1 had no `version` command
        }
        if installed != Self.expectedVersion { throw HelperError.updateNeeded }
    }

    public func status() async throws -> [TunnelStatus] {
        StatusParser.parse(try await run(["status"]))
    }

    public func profiles() async throws -> [String] {
        StatusParser.parseProfiles(try await run(["list"]))
    }

    public func up(_ profile: String) async throws { _ = try await run(["up", profile]) }
    public func down(_ profile: String) async throws { _ = try await run(["down", profile]) }
    public func remove(_ profile: String) async throws { _ = try await run(["remove", profile]) }

    public func importConfig(profile: String, file: URL) async throws {
        _ = try await run(["import", profile, file.path])
    }

    @discardableResult
    public func run(_ arguments: [String]) async throws -> String {
        guard isInstalled else { throw HelperError.setupNeeded }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", Self.helperPath] + arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            try process.run()
            // Output is small (a few lines), so reading each pipe in turn cannot deadlock.
            let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()

            if process.terminationStatus == 0 { return stdout }
            throw Self.error(exitCode: process.terminationStatus, stderr: stderr)
        }.value
    }

    static func error(exitCode: Int32, stderr: String) -> HelperError {
        if exitCode == toolsMissingExitCode { return .toolsMissing }
        if stderr.contains("a password is required") || stderr.contains("not allowed to") {
            return .setupNeeded
        }
        // Prefer the helper's own "error: ..." line; otherwise the last thing printed.
        let lines = stderr.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let own = lines.last(where: { $0.hasPrefix("error: ") }) {
            return .failed(String(own.dropFirst("error: ".count)))
        }
        return .failed(lines.last ?? "The helper failed (exit code \(exitCode)).")
    }
}
