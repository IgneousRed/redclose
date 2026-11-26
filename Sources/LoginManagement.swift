import AppKit
import Darwin
import ServiceManagement

enum SetupError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

final class InstanceLock {
    private var descriptor: Int32 = -1

    func acquire(in directory: URL) throws -> Bool {
        if descriptor >= 0 { return true }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = Darwin.open(directory.appendingPathComponent("instance.lock").path,
                             O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SetupError.message("Could not open the RedClose instance lock.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(fd)
            if code == EWOULDBLOCK { return false }
            throw SetupError.message("Could not lock the RedClose runtime directory.")
        }
        descriptor = fd
        return true
    }

    func release() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }

    deinit { release() }
}

struct LegacyLogin {
    let home: URL
    var plist: URL { home.appendingPathComponent("Library/LaunchAgents/local.redclose.plist") }
    var support: URL { home.appendingPathComponent("Library/Application Support/RedClose") }
    var executable: URL { support.appendingPathComponent("RedClose.app/Contents/MacOS/RedClose") }
    var exists: Bool { FileManager.default.fileExists(atPath: plist.path) }

    func validate(_ data: Data) throws {
        guard let object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              object["Label"] as? String == "local.redclose",
              object["ProgramArguments"] as? [String] == [executable.path],
              object["Program"] == nil else {
            throw SetupError.message("The old login entry is not a recognized RedClose installation. It has not been changed.")
        }
    }
}

// Platform operations are injectable so rollback can be exercised without
// registering login items or stopping the user's working installation.
struct LoginOperations {
    var status: () -> SMAppService.Status = { SMAppService.mainApp.status }
    var register: () throws -> Void = { try SMAppService.mainApp.register() }
    var unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
    var launchctl: ([String]) throws -> Int32 = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

func whileInstanceIdle(in directory: URL, perform: () throws -> Int32) throws -> Int32 {
    let lock = InstanceLock()
    guard try lock.acquire(in: directory) else {
        throw SetupError.message("Quit every running copy of RedClose before replacing or removing it.")
    }
    defer { lock.release() }
    return try perform()
}

final class LoginManagement {
    let legacy: LegacyLogin
    private let appURL: URL
    private let operations: LoginOperations
    var status: SMAppService.Status { operations.status() }

    init(legacy: LegacyLogin = LegacyLogin(home: FileManager.default.homeDirectoryForCurrentUser),
         appURL: URL = Bundle.main.bundleURL, operations: LoginOperations = LoginOperations()) {
        self.legacy = legacy
        self.appURL = appURL
        self.operations = operations
    }

    var detail: String {
        if legacy.exists { return "An older startup entry exists. Replace it before enabling login for this copy." }
        switch status {
        case .enabled: return "This copy will open when you log in."
        case .requiresApproval: return "Allow RedClose in System Settings → General → Login Items."
        case .notRegistered: return "RedClose will not open automatically."
        case .notFound: return "Move RedClose to Applications, then try again."
        @unknown default: return "Login status is unavailable. Check System Settings."
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard !legacy.exists else {
            throw SetupError.message("Replace the older startup entry first so two copies cannot start at login.")
        }
        if enabled { try operations.register() }
        else { try operations.unregister() }
    }

    // Called only after the user confirms migration. Preserve the old plist and app.
    func migrate() throws {
        let source = try Data(contentsOf: legacy.plist)
        try legacy.validate(source)
        guard appURL.resolvingSymlinksInPath().path != legacy.support.appendingPathComponent("RedClose.app").resolvingSymlinksInPath().path else {
            throw SetupError.message("Move this app to Applications and open that copy before replacing the old startup entry.")
        }
        try FileManager.default.createDirectory(at: legacy.support, withIntermediateDirectories: true)
        let backup = legacy.support.appendingPathComponent("legacy-login-\(UUID().uuidString).plist")
        try source.write(to: backup, options: .atomic)
        let wasRegistered = status == .enabled || status == .requiresApproval
        let service = "gui/\(getuid())/local.redclose"
        let wasLegacyLoaded = try operations.launchctl(["print", service]) == 0
        var stoppedLegacy = false
        var registeredHere = false
        do {
            if !wasRegistered {
                try operations.register()
                registeredHere = true
            }
            if wasLegacyLoaded {
                guard try operations.launchctl(["bootout", service]) == 0 else {
                    throw SetupError.message("The old startup service could not be stopped. Its entry and app are preserved.")
                }
                stoppedLegacy = true
            }
            // Do not remove an entry that changed while the confirmation was open.
            guard try Data(contentsOf: legacy.plist) == source else {
                throw SetupError.message("The old startup entry changed during migration. It was not removed.")
            }
            try FileManager.default.removeItem(at: legacy.plist)
        } catch {
            // A backup is retained even on failure; never overwrite the old app.
            var recoveryErrors: [String] = []
            if stoppedLegacy {
                if (try? Data(contentsOf: legacy.plist)) == source {
                    if (try? operations.launchctl(["bootstrap", "gui/\(getuid())", legacy.plist.path])) != 0 {
                        recoveryErrors.append("The old service could not be restarted; its plist and backup are preserved.")
                    }
                } else {
                    recoveryErrors.append("The old entry changed, so it was not automatically restarted.")
                }
            }
            if registeredHere {
                do { try operations.unregister() }
                catch { recoveryErrors.append("Disable the new login item in System Settings; undoing its registration failed.") }
            }
            if !recoveryErrors.isEmpty {
                throw SetupError.message(error.localizedDescription + "\n\n" + recoveryErrors.joined(separator: "\n"))
            }
            throw error
        }
    }

}
