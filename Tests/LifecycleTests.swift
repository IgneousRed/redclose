import Foundation
import ServiceManagement

@main
enum LifecycleTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("lifecycle")
        var cases = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            cases += 1
        }
        let fm = FileManager.default
        func fixture(_ name: String) throws -> (LegacyLogin, Data) {
            let legacy = LegacyLogin(home: root.appendingPathComponent(name))
            try fm.createDirectory(at: legacy.plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "Label": "local.redclose", "ProgramArguments": [legacy.executable.path]
            ], format: .xml, options: 0)
            try data.write(to: legacy.plist)
            return (legacy, data)
        }

        for scenario in ["register-fails", "bootout-fails", "registered-bootout-fails", "unregister-fails", "entry-changes", "remove-fails", "success", "not-loaded"] {
            let (legacy, original) = try fixture(scenario)
            defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: legacy.plist.deletingLastPathComponent().path) }
            var calls: [String] = []
            var operations = LoginOperations()
            operations.status = { scenario == "registered-bootout-fails" ? .enabled : .notRegistered }
            operations.register = {
                calls.append("register")
                if scenario == "register-fails" { throw SetupError.message("registration rejected") }
            }
            operations.unregister = {
                calls.append("unregister")
                if scenario == "unregister-fails" { throw SetupError.message("unregister rejected") }
            }
            operations.launchctl = { args in
                let command = args[0]
                calls.append(command)
                if command == "print" { return scenario == "not-loaded" ? 1 : 0 }
                if command == "bootout" {
                    if scenario.contains("bootout-fails") || scenario == "unregister-fails" { return 1 }
                    if scenario == "entry-changes" { try Data("changed by another writer".utf8).write(to: legacy.plist) }
                    if scenario == "remove-fails" {
                        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: legacy.plist.deletingLastPathComponent().path)
                    }
                }
                return 0
            }
            let manager = LoginManagement(legacy: legacy, appURL: root.appendingPathComponent("New.app"), operations: operations)
            var failure: Error?
            do { try manager.migrate() } catch { failure = error }
            let succeeds = scenario == "success" || scenario == "not-loaded"
            expect((failure == nil) == succeeds, "Migration result for \(scenario)")
            let backups = try fm.contentsOfDirectory(at: legacy.support, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("legacy-login-") }
            expect(backups.count == 1 && (try? Data(contentsOf: backups[0])) == original, "Original plist backed up for \(scenario)")
            if succeeds {
                expect(!legacy.exists && !calls.contains("unregister"), "Success keeps new registration and removes old entry")
            } else if scenario != "entry-changes" {
                expect((try? Data(contentsOf: legacy.plist)) == original, "Failed migration preserves old entry")
            }
            if scenario == "register-fails" {
                expect(calls == ["print", "register"], "A failed registration must not unregister or stop anything")
            } else if scenario == "registered-bootout-fails" {
                expect(!calls.contains("register") && !calls.contains("unregister"), "Existing registration is never undone")
            } else if scenario == "entry-changes" {
                expect(!calls.contains("bootstrap") && calls.contains("unregister"), "Do not restart an unrecognized changed entry")
                expect(failure?.localizedDescription.contains("not automatically restarted") == true, "Changed-entry recovery limitation is reported")
            } else if scenario == "unregister-fails" {
                expect(failure?.localizedDescription.contains("undoing its registration failed") == true, "Rollback failure is reported, not swallowed")
            } else if scenario == "not-loaded" {
                expect(!calls.contains("bootout"), "An absent old service is not stopped")
            } else if scenario == "remove-fails" {
                expect(calls.contains("bootstrap") && calls.contains("unregister"), "Failed plist removal restarts the unchanged old service and undoes the new registration")
            }
        }

        let (legacy, original) = try fixture("symlink")
        let oldApp = legacy.support.appendingPathComponent("RedClose.app")
        try fm.createDirectory(at: oldApp, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("Alias.app")
        try fm.createSymbolicLink(at: alias, withDestinationURL: oldApp)
        var operations = LoginOperations()
        operations.status = { preconditionFailure("No system query expected for same-copy migration") }
        let manager = LoginManagement(legacy: legacy, appURL: alias, operations: operations)
        expect((try? manager.migrate()) == nil && (try? Data(contentsOf: legacy.plist)) == original,
               "A symlink to the legacy app cannot migrate by stopping itself")

        let lockDirectory = root.appendingPathComponent("lock")
        let competing = InstanceLock()
        let result = try whileInstanceIdle(in: lockDirectory) {
            expect((try? competing.acquire(in: lockDirectory)) == false, "The lock remains held during the whole file operation")
            return Int32(7)
        }
        expect(result == 7 && (try? competing.acquire(in: lockDirectory)) == true, "Command status is preserved and ownership released afterward")
        competing.release()
        do {
            _ = try whileInstanceIdle(in: lockDirectory) { throw SetupError.message("file operation failed") }
        } catch { /* expected */ }
        expect((try? competing.acquire(in: lockDirectory)) == true, "Failed file operations also release ownership")
        competing.release()
        print("PASS: \(cases) isolated migration/rollback and locked-operation checks")
    }
}
