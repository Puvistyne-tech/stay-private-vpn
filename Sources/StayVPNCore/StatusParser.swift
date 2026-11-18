import Foundation

public struct TunnelStatus: Equatable {
    public let profile: String
    public let endpoint: String?
    /// Time of the last successful handshake with the server; nil if there has been none yet.
    public let lastHandshake: Date?
    public let bytesReceived: UInt64
    public let bytesSent: UInt64

    public init(profile: String, endpoint: String?, lastHandshake: Date?, bytesReceived: UInt64, bytesSent: UInt64) {
        self.profile = profile
        self.endpoint = endpoint
        self.lastHandshake = lastHandshake
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
    }

    /// WireGuard re-handshakes about every two minutes while traffic flows.
    /// Three minutes of silence means the server is no longer answering.
    public func isLive(now: Date = Date()) -> Bool {
        guard let lastHandshake else { return false }
        return now.timeIntervalSince(lastHandshake) < 180
    }
}

/// Parses the output of `stayvpn-helper status`: blocks of `key=value`
/// lines, one block per active tunnel, each ended by a `--` line.
public enum StatusParser {
    public static func parse(_ output: String) -> [TunnelStatus] {
        var result: [TunnelStatus] = []
        var fields: [String: String] = [:]

        func flush() {
            defer { fields = [:] }
            guard let profile = fields["profile"], !profile.isEmpty else { return }
            let epoch = TimeInterval(fields["handshake"] ?? "") ?? 0
            let endpoint = fields["endpoint"].flatMap { $0.isEmpty || $0 == "(none)" ? nil : $0 }
            result.append(TunnelStatus(
                profile: profile,
                endpoint: endpoint,
                lastHandshake: epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil,
                bytesReceived: UInt64(fields["rx"] ?? "") ?? 0,
                bytesSent: UInt64(fields["tx"] ?? "") ?? 0
            ))
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "--" { flush(); continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            fields[String(trimmed[..<eq])] = String(trimmed[trimmed.index(after: eq)...])
        }
        flush()
        return result
    }

    /// Parses the output of `stayvpn-helper list`: one profile name per line.
    public static func parseProfiles(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(ProfileName.isValid)
            .sorted()
    }
}
