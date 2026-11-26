import Foundation

func appVersion(in bundle: Bundle = .main) -> String {
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    guard let channel = bundle.object(forInfoDictionaryKey: "RedCloseReleaseChannel") as? String, !channel.isEmpty else { return version }
    return "\(version)-\(channel)"
}

enum AppScope: String, Codable {
    case allExcept, selected
}

struct AppRule: Codable, Equatable {
    let bundleID: String
    var name: String
}

struct Preferences: Codable, Equatable {
    var version = 1
    var paused = false
    var scope = AppScope.allExcept
    // Separate lists retain user intent when switching between the two modes.
    var excluded: [AppRule] = []
    var selected: [AppRule] = []
    var recordActivity = false

    var rules: [AppRule] {
        get { scope == .allExcept ? excluded : selected }
        set {
            if scope == .allExcept { excluded = newValue } else { selected = newValue }
        }
    }

    func allows(bundleID: String?) -> Bool {
        guard !paused, let bundleID, !bundleID.isEmpty else { return false }
        let listed = rules.contains { $0.bundleID == bundleID }
        return scope == .allExcept ? !listed : listed
    }

    mutating func add(_ rule: AppRule) {
        guard !rule.bundleID.isEmpty else { return }
        var updated = rules.filter { $0.bundleID != rule.bundleID }
        updated.append(rule)
        rules = updated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static let key = "preferences.v1"

    static func load(from defaults: UserDefaults) -> (value: Preferences, recovered: Bool) {
        guard defaults.object(forKey: key) != nil else { return (Preferences(), false) }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data), decoded.version == 1 else {
            // Never silently enable all apps after encountering unreadable preferences.
            var safe = Preferences()
            safe.paused = true
            return (safe, true)
        }
        return (decoded, false)
    }

    func save(to defaults: UserDefaults) throws {
        let encoded = try JSONEncoder().encode(self)
        if Self.load(from: defaults).recovered, let original = defaults.object(forKey: Self.key) {
            defaults.set(original, forKey: "preferences.recovery.\(UUID().uuidString)")
        }
        defaults.set(encoded, forKey: Self.key)
    }
}

struct ActivityEntry {
    let date: Date
    let message: String
}

struct ActivityLog {
    static let limit = 50
    private(set) var entries: [ActivityEntry] = []
    var enabled = false {
        didSet { if !enabled { clear() } }
    }

    mutating func record(_ message: String, at date: Date = Date()) {
        guard enabled else { return }
        entries.append(ActivityEntry(date: date, message: message))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    mutating func clear() { entries.removeAll() }

    var text: String {
        let format = DateFormatter()
        format.dateStyle = .none
        format.timeStyle = .medium
        return entries.map { "\(format.string(from: $0.date))  \($0.message)" }.joined(separator: "\n")
    }
}

// Release hosting is a publication decision, not a guessed repository address.
func releaseURL(from string: String?) -> URL? {
    guard let string, let url = URL(string: string), url.scheme == "https",
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
    return url
}
