import AppKit
import ServiceManagement

// Keep ownership until the whole filesystem operation finishes, not just an
// earlier idle check. Commands are explicit argv arrays, never shell strings.
if CommandLine.arguments.dropFirst().first == "--while-idle" {
    var command = Array(CommandLine.arguments.dropFirst(2))
    let unregister = command.first == "--unregister-login"
    if unregister { command.removeFirst() }
    guard let executable = command.first, executable.hasPrefix("/") else {
        fputs("Usage: RedClose --while-idle [--unregister-login] /absolute/command [arguments]\n", stderr)
        exit(2)
    }
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RedClose")
    do {
        let result = try whileInstanceIdle(in: support) {
            if unregister {
                switch SMAppService.mainApp.status {
                case .enabled, .requiresApproval: try SMAppService.mainApp.unregister()
                default: break
                }
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        exit(result)
    } catch {
        fputs("RedClose: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let controller = AppController()
app.setActivationPolicy(.accessory)
app.delegate = controller
app.run()
