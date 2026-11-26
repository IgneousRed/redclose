import Foundation

@main
enum AppTests {
    static func main() throws {
        var cases = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            cases += 1
        }
        let suite = "local.redclose.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var prefs = Preferences.load(from: defaults).value
        expect(prefs.allows(bundleID: "example.editor"), "Fresh install retains all-app behavior")
        expect(!prefs.allows(bundleID: nil), "Apps without identity are not eligible")
        expect(!prefs.allows(bundleID: ""), "Empty identity is not eligible")
        prefs.add(AppRule(bundleID: "example.music", name: "Music"))
        expect(!prefs.allows(bundleID: "example.music"), "Excluded music app stays running")
        prefs.add(AppRule(bundleID: "example.music", name: "Music renamed"))
        expect(prefs.rules.count == 1 && prefs.rules[0].name == "Music renamed", "Identity deduplicates rules")
        prefs.scope = .selected
        expect(!prefs.allows(bundleID: "example.editor"), "Empty selection affects nothing")
        prefs.add(AppRule(bundleID: "example.editor", name: "Editor"))
        expect(prefs.allows(bundleID: "example.editor"), "Selected app is eligible")
        expect(!prefs.allows(bundleID: "example.music"), "Unselected app is ineligible")
        prefs.paused = true
        expect(!prefs.allows(bundleID: "example.editor"), "Pause overrides selection")
        try prefs.save(to: defaults)
        expect(Preferences.load(from: defaults).value == prefs, "All preferences survive relaunch")
        prefs.paused = false
        prefs.scope = .allExcept
        expect(!prefs.allows(bundleID: "example.music") && prefs.selected.count == 1, "Switching modes retains both lists")
        defaults.set(Data("invalid".utf8), forKey: Preferences.key)
        let recovered = Preferences.load(from: defaults)
        expect(recovered.recovered && recovered.value.paused, "Corrupt settings fail closed")
        expect(defaults.data(forKey: Preferences.key) == Data("invalid".utf8), "Unreadable settings are preserved for recovery")
        try Preferences().save(to: defaults)
        let recoveryCopies = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("preferences.recovery.") }
        expect(recoveryCopies.count == 1 && recoveryCopies.values.first as? Data == Data("invalid".utf8),
               "Any preference writer preserves unreadable settings before replacing them")
        prefs.version = 99
        try prefs.save(to: defaults)
        expect(Preferences.load(from: defaults).value.paused, "Unknown future schema fails closed")

        var log = ActivityLog()
        log.record("not retained")
        expect(log.entries.isEmpty, "Activity recording defaults off")
        log.enabled = true
        for index in 0..<60 { log.record("event \(index)") }
        expect(log.entries.count == 50 && log.entries.first?.message == "event 10", "Activity is bounded")
        log.enabled = false
        expect(log.entries.isEmpty, "Disabling recording clears it")
        log.enabled = true
        log.record("example")
        log.clear()
        expect(log.entries.isEmpty, "Clear removes all history")

        expect(releaseURL(from: nil) == nil && releaseURL(from: "") == nil, "Missing release URL never invents a destination")
        expect(releaseURL(from: "http://example.com") == nil, "Update link must use HTTPS")
        expect(releaseURL(from: "https://user:password@example.com") == nil, "Update link cannot contain credentials")
        expect(releaseURL(from: "https://example.com/releases")?.host == "example.com", "Public HTTPS release link accepted")

        let temporary = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("lock-test")
        let first = InstanceLock()
        let second = InstanceLock()
        expect(tryAcquire(first, temporary), "First instance owns the monitor")
        expect(!tryAcquire(second, temporary), "Second instance cannot monitor simultaneously")
        first.release()
        expect(tryAcquire(second, temporary), "Ownership can transfer after quit")
        second.release()
        let legacy = LegacyLogin(home: temporary)
        let object: [String: Any] = ["Label": "local.redclose", "ProgramArguments": [legacy.executable.path]]
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try legacy.validate(data)
        cases += 1
        var unknown = object
        unknown["ProgramArguments"] = ["/not/redclose"]
        let unknownData = try PropertyListSerialization.data(fromPropertyList: unknown, format: .xml, options: 0)
        expect((try? legacy.validate(unknownData)) == nil, "Unknown startup entry cannot be migrated")
        var overridden = object
        overridden["Program"] = "/not/redclose"
        let overrideData = try PropertyListSerialization.data(fromPropertyList: overridden, format: .xml, options: 0)
        expect((try? legacy.validate(overrideData)) == nil, "Program override cannot bypass migration validation")
        print("PASS: \(cases) app settings, privacy, update, ownership and migration checks")
    }

    static func tryAcquire(_ lock: InstanceLock, _ directory: URL) -> Bool {
        (try? lock.acquire(in: directory)) ?? false
    }
}
