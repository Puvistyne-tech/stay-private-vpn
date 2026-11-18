import Foundation

/// Checks a WireGuard config before it is handed to the root helper.
/// The helper repeats these checks; this copy exists to give a friendly error early.
public enum WGConfig {
    public enum ValidationError: Error, Equatable, LocalizedError {
        case empty
        case tooLarge
        case missingSection(String)
        case missingKey(String)
        case forbiddenLine(String)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "The config file is empty."
            case .tooLarge:
                return "The config file is too large to be a WireGuard config."
            case .missingSection(let name):
                return "Not a WireGuard config: the [\(name)] section is missing."
            case .missingKey(let key):
                return "The config is missing \(key)."
            case .forbiddenLine(let key):
                return "The config contains a \(key) line, which would run commands as root. Remove it and import again."
            }
        }
    }

    /// Keys that make wg-quick run shell commands or rewrite the file as root.
    public static let forbiddenKeys = ["preup", "postup", "predown", "postdown", "saveconfig"]
    public static let maxBytes = 64 * 1024

    public struct Summary: Equatable {
        public let endpoint: String?
    }

    @discardableResult
    public static func validate(_ text: String) throws -> Summary {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.empty }
        guard text.utf8.count <= maxBytes else { throw ValidationError.tooLarge }

        var section = ""
        var sections = Set<String>()
        var keys = Set<String>()
        var endpoint: String?

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
                sections.insert(section)
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let lower = key.lowercased()

            if forbiddenKeys.contains(lower) { throw ValidationError.forbiddenLine(key) }
            keys.insert("\(section).\(lower)")
            if section == "peer", lower == "endpoint", endpoint == nil { endpoint = value }
        }

        guard sections.contains("interface") else { throw ValidationError.missingSection("Interface") }
        guard sections.contains("peer") else { throw ValidationError.missingSection("Peer") }
        guard keys.contains("interface.privatekey") else { throw ValidationError.missingKey("PrivateKey") }
        guard keys.contains("peer.publickey") else { throw ValidationError.missingKey("the peer's PublicKey") }
        guard keys.contains("peer.endpoint") else { throw ValidationError.missingKey("the peer's Endpoint") }
        return Summary(endpoint: endpoint)
    }
}

/// Profile names become part of a root-owned file name and a network interface
/// name ("sv-<name>", 15 characters at most), so they are kept short and plain.
public enum ProfileName {
    public static let maxLength = 12

    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= maxLength else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard name.allSatisfy(allowed.contains) else { return false }
        return name.first != "-" && name.last != "-"
    }

    /// Turns a file name such as "Proton NL-FREE#12.conf" into a valid profile name.
    public static func sanitize(_ raw: String) -> String {
        var base = raw
        if base.lowercased().hasSuffix(".conf") { base = String(base.dropLast(5)) }
        var out = ""
        for ch in base.lowercased() {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if out.last != "-" {
                out.append("-")
            }
        }
        out = String(out.prefix(maxLength))
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "vpn" : out
    }
}
