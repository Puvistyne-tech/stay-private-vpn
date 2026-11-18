import Foundation

/// Remembers which profile was used last. The profiles themselves live in
/// /etc/wireguard (root-only) and are listed through the helper.
public struct ProfileStore {
    private let defaults: UserDefaults
    private let key = "lastProfile"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastUsed: String? {
        get { defaults.string(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }

    /// The profile to preselect: the active one, else the last used, else the first.
    public func preferred(among profiles: [String], active: String?) -> String? {
        if let active, profiles.contains(active) { return active }
        if let last = lastUsed, profiles.contains(last) { return last }
        return profiles.first
    }
}
