import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let watcher = RedClose()
    private let instance = InstanceLock()
    private let login = LoginManagement()
    private let defaults: UserDefaults
    private var preferences: Preferences
    private var recoveryWarning: Bool
    private var activity = ActivityLog()
    private var ownsInstance = false
    private var startupFailed = false
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let pauseMenu = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let accessMenu = NSMenuItem(title: "Enable Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
    private var window: NSWindow!
    private let tabs = NSTabView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let accessLabel = NSTextField(wrappingLabelWithString: "")
    private let recoveryLabel = NSTextField(wrappingLabelWithString: "")
    private let loginLabel = NSTextField(wrappingLabelWithString: "")
    private let scopeLabel = NSTextField(wrappingLabelWithString: "")
    private let pauseCheck = NSButton(checkboxWithTitle: "Pause RedClose", target: nil, action: #selector(togglePause))
    private let loginCheck = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: #selector(toggleLogin))
    private let historyCheck = NSButton(checkboxWithTitle: "Record recent activity (memory only)", target: nil,
                                        action: #selector(toggleHistory))
    private let scopePicker = NSPopUpButton()
    private let rulesTable = NSTableView()
    private let diagnosticText = NSTextView()
    private var migrateButton: NSButton!
    private var removeButton: NSButton!
    private var addButton: NSButton!
    private var retryButton: NSButton!
    private var debugPreview = false
    private var previewSuite: String?

    override init() {
        var selectedDefaults = UserDefaults.standard
        #if DEBUG
        if CommandLine.arguments.contains("--ui-smoke-test") {
            let suite = "local.redclose.ui-smoke.\(UUID().uuidString)"
            selectedDefaults = UserDefaults(suiteName: suite)!
            previewSuite = suite
            debugPreview = true
        }
        #endif
        defaults = selectedDefaults
        let loaded = Preferences.load(from: selectedDefaults)
        preferences = loaded.value
        recoveryWarning = loaded.recovered
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if debugPreview && CommandLine.arguments.contains("--light-appearance") { NSApp.appearance = NSAppearance(named: .aqua) }
        #endif
        activity.enabled = preferences.recordActivity
        watcher.allowsApp = { [weak self] id in self?.preferences.allows(bundleID: id) ?? false }
        watcher.onStatus = { [weak self] in self?.refresh() }
        watcher.onActivity = { [weak self] message in
            guard let self, self.activity.enabled else { return }
            self.activity.record(message)
            self.refreshDiagnostics()
        }
        buildMenu()
        buildWindow()
        if !debugPreview { startWatcher() }
        if !debugPreview && !ownsInstance && !login.legacy.exists,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.redclose")
               .first(where: { $0.processIdentifier != getpid() }), let url = running.bundleURL {
            // Finder/open of a second modern copy should reopen the active UI,
            // not present settings that cannot control its monitor.
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
            }
        }
        refresh()
        if debugPreview || !defaults.bool(forKey: "didShowSetup") || !ownsInstance {
            showSettings()
        }
        #if DEBUG
        if debugPreview { runUISmokeTest() }
        #endif
    }

    private func startWatcher() {
        guard !ownsInstance else { return }
        startupFailed = false
        do {
            ownsInstance = try instance.acquire(in: login.legacy.support)
            if ownsInstance {
                // Another copy may have changed preferences while this UI was
                // waiting for ownership. Never enable a stale policy on takeover.
                let loaded = Preferences.load(from: defaults)
                preferences = loaded.value
                recoveryWarning = loaded.recovered
                activity.enabled = preferences.recordActivity
                rulesTable.deselectAll(nil)
                rulesTable.reloadData()
                watcher.start()
                watcher.setEnabled(!preferences.paused)
                if window.isVisible { defaults.set(true, forKey: "didShowSetup") }
            }
        } catch {
            startupFailed = true
            showError(error)
        }
    }

    private var status: String {
        if debugPreview { return canControl ? "Preview — no apps are monitored" : "Preview — another copy is running" }
        if !ownsInstance { return startupFailed ? "Could not start monitoring" : "Another copy of RedClose is running" }
        if preferences.paused { return "Paused" }
        if !watcher.hasPermission { return "Accessibility permission needed" }
        if !watcher.isMonitoring { return "Mouse monitoring unavailable" }
        if preferences.scope == .selected && preferences.selected.isEmpty { return "Active — no apps selected" }
        return "Active"
    }

    private var canControl: Bool {
        #if DEBUG
        if debugPreview && CommandLine.arguments.contains("--simulate-nonowner") { return false }
        #endif
        return ownsInstance || debugPreview
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusMenu.isEnabled = false
        menu.addItem(statusMenu)
        pauseMenu.target = self
        accessMenu.target = self
        menu.addItem(pauseMenu)
        menu.addItem(accessMenu)
        menu.addItem(.separator())
        addMenu("Settings…", action: #selector(showSettings), key: ",", to: menu)
        addMenu("Troubleshooting…", action: #selector(showTroubleshooting), to: menu)
        addMenu("Check for Updates…", action: #selector(checkUpdates), to: menu)
        addMenu("About RedClose", action: #selector(showAbout), to: menu)
        menu.addItem(.separator())
        addMenu("Quit RedClose", action: #selector(quit), key: "q", to: menu)
        statusItem.menu = menu

        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "RedClose")
        addMenu("About RedClose", action: #selector(showAbout), to: appMenu)
        addMenu("Settings…", action: #selector(showSettings), key: ",", to: appMenu)
        appMenu.addItem(.separator())
        addMenu("Quit RedClose", action: #selector(quit), key: "q", to: appMenu)
        appItem.submenu = appMenu
        main.addItem(appItem)
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.submenu?.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu?.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu?.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    private func addMenu(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "RedClose"
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSView()
        window.contentView = root
        tabs.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        let general = makeTab("General")
        general.addArrangedSubview(heading("Close the window. Quit the app."))
        general.addArrangedSubview(body("Click an app’s last red close button and RedClose requests a normal quit. Save prompts remain under the app’s control. When unsure, RedClose leaves the app running."))
        statusLabel.font = .boldSystemFont(ofSize: 15)
        general.addArrangedSubview(statusLabel)
        general.addArrangedSubview(accessLabel)
        retryButton = button("Retry Monitoring", #selector(retryMonitoring))
        general.addArrangedSubview(retryButton)
        general.addArrangedSubview(row([
            button("Open Accessibility Settings…", #selector(openAccessibility)),
            button("Show RedClose in Finder", #selector(revealApp))
        ]))
        general.addArrangedSubview(body("Enable this copy of RedClose under Privacy & Security → Accessibility. If approval stops working after an update, remove its old entry and add this copy again. No Screen Recording access is needed."))
        pauseCheck.target = self
        general.addArrangedSubview(pauseCheck)
        loginCheck.target = self
        general.addArrangedSubview(loginCheck)
        general.addArrangedSubview(loginLabel)
        migrateButton = button("Replace Older Startup Entry…", #selector(migrateLogin))
        general.addArrangedSubview(row([migrateButton, button("Open Login Items…", #selector(openLoginItems))]))
        recoveryLabel.textColor = .systemOrange
        general.addArrangedSubview(recoveryLabel)
        general.addArrangedSubview(row([
            button("Opening an Unverified App…", #selector(showOpeningHelp)),
            button("Remove RedClose…", #selector(showRemoval))
        ]))

        let apps = makeTab("Apps")
        apps.addArrangedSubview(heading("Choose which apps RedClose can quit"))
        scopePicker.addItems(withTitles: ["All apps except those listed below", "Only the apps listed below"])
        scopePicker.target = self
        scopePicker.action = #selector(changeScope)
        scopePicker.setAccessibilityLabel("Apps affected by RedClose")
        apps.addArrangedSubview(scopePicker)
        apps.addArrangedSubview(scopeLabel)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.title = "Application"
        column.width = 520
        rulesTable.addTableColumn(column)
        rulesTable.headerView = nil
        rulesTable.rowHeight = 44
        rulesTable.dataSource = self
        rulesTable.delegate = self
        rulesTable.allowsMultipleSelection = true
        rulesTable.setAccessibilityLabel("Application rules")
        let scroll = NSScrollView()
        scroll.documentView = rulesTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 285).isActive = true
        apps.addArrangedSubview(scroll)
        removeButton = button("Remove Selected", #selector(removeApps))
        addButton = button("Add Applications…", #selector(addApps))
        apps.addArrangedSubview(row([addButton, removeButton]))
        apps.addArrangedSubview(body("Finder, RedClose and protected system apps are always excluded. Rules use the app’s identity, so moving or updating an app does not normally change its rule. Closing tabs and Command-W are not affected."))

        let trouble = makeTab("Troubleshooting")
        trouble.addArrangedSubview(heading("Understand what RedClose is doing"))
        trouble.addArrangedSubview(body("Recent activity is optional and stays in memory: up to 50 events with app names, never window titles, document contents or keystrokes. Turning it off clears it. Nothing is uploaded."))
        historyCheck.target = self
        trouble.addArrangedSubview(historyCheck)
        diagnosticText.isEditable = false
        diagnosticText.isSelectable = true
        diagnosticText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticText.textContainerInset = NSSize(width: 10, height: 10)
        diagnosticText.autoresizingMask = [.width]
        diagnosticText.isHorizontallyResizable = false
        diagnosticText.textContainer?.widthTracksTextView = true
        diagnosticText.setAccessibilityLabel("Diagnostics preview")
        let diagnosticScroll = NSScrollView()
        diagnosticScroll.documentView = diagnosticText
        diagnosticScroll.hasVerticalScroller = true
        diagnosticScroll.borderType = .bezelBorder
        diagnosticScroll.heightAnchor.constraint(equalToConstant: 285).isActive = true
        trouble.addArrangedSubview(diagnosticScroll)
        trouble.addArrangedSubview(row([
            button("Clear Activity", #selector(clearHistory)),
            button("Export This Preview…", #selector(exportDiagnostics))
        ]))
        trouble.addArrangedSubview(body("Review the preview before exporting. An accepted quit request does not prove an app exited: it may still ask you to save. If another copy is running, quit it before opening this one."))
        for stack in [general, apps, trouble] {
            for view in stack.arrangedSubviews {
                view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
                if let text = view as? NSTextField {
                    text.preferredMaxLayoutWidth = 540
                    text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                } else if view is NSScrollView {
                    view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                }
            }
        }
    }

    private func makeTab(_ title: String) -> NSStackView {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let container = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
        ])
        item.view = container
        tabs.addTabViewItem(item)
        return stack
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        return label
    }

    private func body(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let control = NSButton(title: title, target: self, action: action)
        control.bezelStyle = .rounded
        return control
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func refresh() {
        guard window != nil else { return }
        statusLabel.stringValue = status
        statusMenu.title = status
        let symbol = canControl && preferences.paused ? "pause.circle" : (watcher.isMonitoring ? "xmark.circle" : "exclamationmark.circle")
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RedClose: \(status)")
        statusItem.button?.toolTip = "RedClose — \(status)"
        statusItem.button?.setAccessibilityLabel("RedClose: \(status)")
        pauseMenu.title = preferences.paused ? "Resume RedClose" : "Pause RedClose"
        pauseMenu.isEnabled = canControl
        pauseCheck.isEnabled = canControl
        pauseCheck.state = preferences.paused ? .on : .off
        accessMenu.isHidden = watcher.hasPermission
        accessLabel.stringValue = watcher.hasPermission ? "Accessibility access is available." : "Accessibility access has not been confirmed for this copy."
        loginCheck.state = !debugPreview && login.status == .enabled ? .on : .off
        if !debugPreview && login.status == .requiresApproval { loginCheck.state = .mixed }
        loginCheck.isEnabled = canControl && !debugPreview && !login.legacy.exists
        loginLabel.stringValue = debugPreview ? "Login changes are disabled in this preview." : login.detail
        migrateButton.isHidden = debugPreview || !login.legacy.exists
        retryButton.isHidden = debugPreview || ownsInstance
        recoveryLabel.stringValue = recoveryWarning ? "Saved settings could not be read. RedClose is paused. Review your app rules before resuming. Changing a setting saves a recovery copy before replacing the unreadable settings." : ""
        recoveryLabel.isHidden = !recoveryWarning
        scopePicker.selectItem(at: preferences.scope == .allExcept ? 0 : 1)
        scopePicker.isEnabled = canControl
        addButton.isEnabled = canControl
        historyCheck.isEnabled = canControl
        scopeLabel.stringValue = preferences.scope == .allExcept
            ? "Listed apps stay running when their last window closes."
            : (preferences.selected.isEmpty ? "No apps selected. RedClose will not quit any apps." : "Only listed apps can be quit by RedClose.")
        historyCheck.state = preferences.recordActivity ? .on : .off
        removeButton.isEnabled = canControl && rulesTable.selectedRow >= 0
        refreshDiagnostics()
    }

    private func save(_ updated: Preferences) {
        guard canControl else { refresh(); return }
        do {
            try updated.save(to: defaults)
            let rulesChanged = preferences.scope != updated.scope || preferences.rules != updated.rules
            let policyChanged = rulesChanged || preferences.paused != updated.paused
            preferences = updated
            recoveryWarning = false
            activity.enabled = preferences.recordActivity
            if ownsInstance && policyChanged { watcher.setEnabled(!preferences.paused) }
            if rulesChanged {
                rulesTable.deselectAll(nil)
                rulesTable.reloadData()
            }
            refresh()
        } catch { showError(error) }
    }

    @objc private func togglePause() {
        var updated = preferences
        updated.paused.toggle()
        save(updated)
    }

    @objc private func changeScope() {
        var updated = preferences
        updated.scope = scopePicker.indexOfSelectedItem == 0 ? .allExcept : .selected
        save(updated)
    }

    @objc private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Applications"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            var updated = self.preferences
            for url in panel.urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty else {
                    self.showError(SetupError.message("\(url.lastPathComponent) has no app identity and cannot be added."))
                    return
                }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                updated.add(AppRule(bundleID: id, name: name))
            }
            self.save(updated)
        }
    }

    @objc private func removeApps() {
        var updated = preferences
        updated.rules = preferences.rules.enumerated().filter { !rulesTable.selectedRowIndexes.contains($0.offset) }.map(\.element)
        save(updated)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { preferences.rules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = preferences.rules[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "\(rule.name)\n\(rule.bundleID)")
        label.font = .systemFont(ofSize: 12)
        label.frame = NSRect(x: 8, y: 4, width: tableView.bounds.width - 20, height: 36)
        label.autoresizingMask = [.width]
        cell.addSubview(label)
        cell.textField = label
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { refresh() }

    @objc private func toggleLogin() {
        guard canControl && !debugPreview else { return }
        do {
            if login.status == .requiresApproval && loginCheck.state == .on {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                try login.setEnabled(loginCheck.state == .on)
            }
        }
        catch { showError(error) }
        refresh()
    }

    @objc private func retryMonitoring() {
        guard !debugPreview else { return }
        startWatcher()
        refresh()
    }

    @objc private func migrateLogin() {
        guard !debugPreview else { return }
        let alert = NSAlert()
        alert.messageText = "Use this copy of RedClose at login?"
        alert.informativeText = "This stops the older background copy and replaces its startup entry with this app’s login registration. The old app and a backup of its startup entry are kept. You may need to approve the new login item and Accessibility access."
        alert.addButton(withTitle: "Replace Startup Entry")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try login.migrate()
            startWatcher()
            // launchctl may return before the old process releases its lock.
            if !ownsInstance {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.startWatcher()
                    self?.refresh()
                }
            }
        } catch { showError(error) }
        refresh()
    }

    @objc private func openLoginItems() { if !debugPreview { SMAppService.openSystemSettingsLoginItems() } }

    @objc private func openAccessibility() {
        guard !debugPreview else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }

    @objc private func toggleHistory() {
        var updated = preferences
        updated.recordActivity = historyCheck.state == .on
        save(updated)
    }

    @objc private func clearHistory() { activity.clear(); refreshDiagnostics() }

    private var diagnostics: String {
        let version = appVersion()
        return """
        RedClose \(version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Status: \(status)
        Accessibility: \(watcher.hasPermission ? "available" : "not confirmed")
        Other-Space query support: \(spaceQueryAvailable ? "available" : "unavailable — uncertain windows prevent quitting")
        App scope: \(preferences.scope == .allExcept ? "all except listed" : "selected only") (\(preferences.rules.count) rules)
        Launch at login: \(debugPreview ? "preview" : login.detail)
        Activity: \(activity.enabled ? "on, memory only" : "off")

        \(activity.entries.isEmpty ? "No recent activity recorded." : activity.text)
        """
    }

    private func refreshDiagnostics() {
        let text = diagnostics
        if diagnosticText.string != text { diagnosticText.string = text }
    }

    @objc private func exportDiagnostics() {
        // Export exactly what the user just reviewed, even if a new event arrives.
        let text = diagnosticText.string
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "RedClose-diagnostics.txt"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { self?.showError(error) }
        }
    }

    @objc private func checkUpdates() {
        guard let url = releaseURL(from: Bundle.main.object(forInfoDictionaryKey: "RedCloseReleaseURL") as? String) else {
            inform("No public release page yet", "This build has no published update destination. It does not check the network or install updates automatically.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showOpeningHelp() {
        inform("Opening RedClose on your Mac", "RedClose is not signed with an Apple Developer ID or notarized. After trying to open a trusted download, use System Settings → Privacy & Security → Open Anyway if macOS offers it. Then approve Accessibility separately. Managed Macs may disallow this. RedClose does not change your security settings or bypass approval.")
    }

    @objc private func showRemoval() {
        inform("Remove RedClose", "Turn off Launch at login here (or disable the older RedClose entry in Login Items), then choose Quit RedClose from the menu bar. Move the app to the Trash and remove its Accessibility entry in System Settings. Your app rules are kept unless you explicitly remove the preferences. See the included removal guide for older script installations.")
    }

    @objc private func showAbout() {
        let version = appVersion()
        inform("RedClose \(version)", "A small utility for quitting apps after their last red close button is clicked.\n\nBeta: compatibility varies by app. No accounts, telemetry, automatic downloads or Screen Recording. Accessibility is used to identify close buttons and window state.")
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ error: Error) { inform("RedClose could not complete that action", error.localizedDescription) }

    @objc private func showSettings() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
        if ownsInstance && !debugPreview { defaults.set(true, forKey: "didShowSetup") }
    }

    @objc private func showTroubleshooting() { tabs.selectTabViewItem(at: 2); showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }
    func applicationDidBecomeActive(_ notification: Notification) { refresh() }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        instance.release()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        #if DEBUG
        if let previewSuite { defaults.removePersistentDomain(forName: previewSuite) }
        #endif
    }

    #if DEBUG
    private func runUISmokeTest() {
        // Opt-in development mode: no global event monitor, login changes or real preferences.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            if !canControl {
                let original = preferences
                togglePause()
                scopePicker.selectItem(at: 1)
                changeScope()
                precondition(preferences == original && defaults.object(forKey: Preferences.key) == nil)
                precondition(!pauseMenu.isEnabled && !pauseCheck.isEnabled && !scopePicker.isEnabled && !addButton.isEnabled)
                precondition(!historyCheck.isEnabled && !loginCheck.isEnabled)
                captureUITabs()
                print("PASS: inactive-copy UI cannot change policy or login settings")
                NSApp.terminate(nil)
                return
            }
            togglePause()
            precondition(preferences.paused)
            scopePicker.selectItem(at: 1)
            changeScope()
            precondition(!preferences.allows(bundleID: "local.redclose.fixture"))
            var updated = preferences
            updated.paused = false
            updated.add(AppRule(bundleID: "local.redclose.fixture", name: "Example App"))
            updated.recordActivity = true
            save(updated)
            precondition(preferences.allows(bundleID: "local.redclose.fixture"))
            activity.record("Example App kept running: another window remains.")
            refresh()
            rulesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            historyCheck.state = .off
            toggleHistory()
            precondition(rulesTable.selectedRow == 0, "Diagnostics changes must not reload the app table")
            scopePicker.selectItem(at: 0)
            changeScope()
            precondition(rulesTable.selectedRow == -1, "Changing app lists must clear stale row selection")
            scopePicker.selectItem(at: 1)
            changeScope()
            historyCheck.state = .on
            toggleHistory()
            activity.record("Example App kept running: another window remains.")
            refresh()
            captureUITabs()
            historyCheck.state = .off
            toggleHistory()
            precondition(activity.entries.isEmpty)
            print("PASS: isolated UI smoke (pause, scope, rules, selection, diagnostics, three tabs); no monitoring or login changes")
            NSApp.terminate(nil)
        }
    }

    private func captureUITabs() {
        guard let outputIndex = CommandLine.arguments.firstIndex(of: "--snapshot-directory"),
              CommandLine.arguments.indices.contains(outputIndex + 1) else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[outputIndex + 1])
        for index in 0..<tabs.numberOfTabViewItems {
            tabs.selectTabViewItem(at: index)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), directory.appendingPathComponent("tab-\(index).png").path]
            try! capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0, "Window capture failed")
        }
    }
    #endif
}
