import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let eventTap = EventTapManager()
    private var toggleMenuItem: NSMenuItem!
    private var autoSwitchMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!
    private var permissionTimer: Timer?

    private let autoSwitchDefaultsKey = "autoSwitchEnabled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: autoSwitchDefaultsKey) == nil {
            UserDefaults.standard.set(true, forKey: autoSwitchDefaultsKey)
        }
        eventTap.isAutoSwitchEnabled = UserDefaults.standard.bool(forKey: autoSwitchDefaultsKey)

        setupMenuBar()
        checkAndStartEventTap(promptIfNeeded: true)

        if !AXIsProcessTrusted() {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self.permissionTimer = nil
                    self.checkAndStartEventTap(promptIfNeeded: false)
                }
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(active: true, needsPermission: false)

        let menu = NSMenu()

        permissionMenuItem = NSMenuItem(
            title: "Универсальный доступ: проверка...",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        )
        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)

        menu.addItem(NSMenuItem.separator())

        toggleMenuItem = NSMenuItem(
            title: "Включено",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        toggleMenuItem.state = .on
        menu.addItem(toggleMenuItem)

        autoSwitchMenuItem = NSMenuItem(
            title: "Автопереключение",
            action: #selector(toggleAutoSwitch),
            keyEquivalent: ""
        )
        autoSwitchMenuItem.target = self
        autoSwitchMenuItem.state = eventTap.isAutoSwitchEnabled ? .on : .off
        menu.addItem(autoSwitchMenuItem)

        menu.addItem(NSMenuItem.separator())

        let infoControl = NSMenuItem(
            title: "Control: сменить раскладку (по порядку)",
            action: nil,
            keyEquivalent: ""
        )
        infoControl.isEnabled = false
        menu.addItem(infoControl)

        let infoOption = NSMenuItem(
            title: "Option: перевести слово или выделение",
            action: nil,
            keyEquivalent: ""
        )
        infoOption.isEnabled = false
        menu.addItem(infoOption)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Выйти из MySwitcher",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusIcon(active: Bool, needsPermission: Bool) {
        guard let button = statusItem.button else { return }

        if needsPermission {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Нужен доступ")
            button.title = ""
            return
        }

        let symbolName = active ? "arrow.left.arrow.right" : "pause.circle"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MySwitcher") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = active ? "⇄" : "⇄✕"
        }
    }

    private func checkAndStartEventTap(promptIfNeeded: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted && eventTap.start() {
            permissionMenuItem.title = "Универсальный доступ: разрешён"
            permissionMenuItem.isEnabled = false
            updateStatusIcon(active: eventTap.isEnabled, needsPermission: false)
        } else {
            permissionMenuItem.title = "Выдать универсальный доступ..."
            permissionMenuItem.isEnabled = true
            updateStatusIcon(active: false, needsPermission: true)
        }
    }

    @objc private func requestAccessibility() {
        checkAndStartEventTap(promptIfNeeded: true)
    }

    @objc private func toggleEnabled() {
        eventTap.isEnabled.toggle()
        toggleMenuItem.state = eventTap.isEnabled ? .on : .off
        toggleMenuItem.title = eventTap.isEnabled ? "Включено" : "На паузе"
        updateStatusIcon(active: eventTap.isEnabled, needsPermission: !AXIsProcessTrusted())
    }

    @objc private func toggleAutoSwitch() {
        eventTap.isAutoSwitchEnabled.toggle()
        autoSwitchMenuItem.state = eventTap.isAutoSwitchEnabled ? .on : .off
        UserDefaults.standard.set(eventTap.isAutoSwitchEnabled, forKey: autoSwitchDefaultsKey)
    }

    @objc private func quitApp() {
        eventTap.stop()
        NSApp.terminate(nil)
    }
}
