import Foundation

public struct SpeedResult: Equatable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    /// Idle round-trip time in milliseconds, when the test reports it.
    public let latencyMs: Double?

    public init(downloadMbps: Double, uploadMbps: Double, latencyMs: Double?) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.latencyMs = latencyMs
    }

    public var summary: String {
        var text = "↓ \(Self.format(downloadMbps))  ↑ \(Self.format(uploadMbps)) Mbps"
        if let latencyMs { text += "  ·  \(Int(latencyMs.rounded())) ms" }
        return text
    }

    static func format(_ mbps: Double) -> String {
        mbps >= 10 ? String(Int(mbps.rounded())) : String(format: "%.1f", mbps)
    }
}

/// Speed test using macOS's built-in `networkQuality` tool (macOS 12+), which
/// measures against Apple's servers. Free, nothing to install.
public enum SpeedTest {
    public static let toolPath = "/usr/bin/networkQuality"
    /// Upper bound on the test's own runtime, in seconds.
    static let maxSeconds = 20

    public enum Failure: Error, Equatable, LocalizedError {
        case unavailable
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable: return "The speed test needs macOS 12 or later."
            case .failed(let message): return "Speed test failed: \(message)"
            }
        }
    }

    /// Parses the JSON printed by `networkQuality -c`.
    public static func parse(_ data: Data) throws -> SpeedResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.failed("unreadable result")
        }
        func number(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
        guard let down = number("dl_throughput"), let up = number("ul_throughput"), down > 0 || up > 0 else {
            throw Failure.failed("no throughput measured (is the network down?)")
        }
        return SpeedResult(downloadMbps: down / 1_000_000, uploadMbps: up / 1_000_000, latencyMs: number("base_rtt"))
    }

    public static func run() async throws -> SpeedResult {
        guard FileManager.default.isExecutableFile(atPath: toolPath) else { throw Failure.unavailable }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: toolPath)
            process.arguments = ["-c", "-M", String(maxSeconds)]
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            if let result = try? parse(data) { return result }
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed(detail.isEmpty ? "no result (is the network down?)" : String(detail.prefix(160)))
        }.value
    }
}
