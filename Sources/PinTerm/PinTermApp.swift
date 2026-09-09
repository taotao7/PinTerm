import AppKit
import GhosttyTerminal
import ServiceManagement

@main
@MainActor
final class PinTermApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem!
    private(set) var windows: [ModuleWindow] = []
    private var closedModules: [Module] = []
    private let store: ModuleStore
    private var selectedModuleID: UUID?
    private var persistenceEnabled = false
    private var settings = AppSettings()

    private var presetWidgets: [(name: String, command: String)] {
        [(L10n.text("系统监控", "System Monitor"), "btop"),
         (L10n.text("进程监控", "Process Monitor"), "htop"),
         (L10n.text("日历", "Calendar"), "cal; exec \"$SHELL\"")]
    }

    init(store: ModuleStore = .standard) {
        self.store = store
        super.init()
    }

    static func main() {
        if CommandLine.arguments.contains("--verify-resources") {
            guard let root = Bundle.main.resourceURL,
                  let resources = GhosttyRuntimeResources.directoryURL,
                  let terminfo = GhosttyRuntimeResources.terminfoDirectoryURL,
                  resources.path.hasPrefix(root.path + "/"),
                  terminfo.path.hasPrefix(root.path + "/"),
                  FileManager.default.fileExists(atPath: resources.appendingPathComponent("shell-integration/zsh/.zshenv").path),
                  FileManager.default.fileExists(atPath: terminfo.appendingPathComponent("78/xterm-ghostty").path) else {
                print("PinTerm: missing resources or dependency on the build directory")
                exit(1)
            }
            print("PinTerm: bundled Ghostty resources verified")
            return
        }
        let app = NSApplication.shared
        let delegate = PinTermApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildMenus()
        do {
            try restoreModules(using: AppSettings.load())
        } catch {
            persistenceEnabled = false
            report(error, message: L10n.text("无法加载配置；原文件已保留，本次不写入模块配置。可在设置中修正配置文件路径。", "Unable to load configuration. Original files are preserved; module saving is disabled for this run. Check the config path in Settings."))
        }
    }

    func restoreModules(using settings: AppSettings) throws {
        self.settings = settings
        let modules = try store.load()
        closedModules = modules.filter { $0.isClosed == true }
        if settings.restoreWindows {
            for module in modules where module.isClosed != true { try create(module) }
        } else {
            closedModules = modules.map { var module = $0; module.isClosed = true; return module }
        }
        persistenceEnabled = true
        save()
        rebuildMenus()
    }

    func rebuildMenus() {
        let menu = NSMenu()
        menu.delegate = self
        add(L10n.text("自定义模块…", "Custom Widget…"), #selector(customModule), to: menu, key: "n")
        add(L10n.text("设置…", "Settings…"), #selector(showSettings), to: menu, key: ",")
        let presets = NSMenu(title: L10n.text("新建预设组件", "New Preset Widget"))
        for (name, command) in presetWidgets {
            let item = add(name, #selector(preset(_:)), to: presets)
            item.representedObject = command
        }
        let presetItem = NSMenuItem(title: presets.title, action: nil, keyEquivalent: "")
        presetItem.submenu = presets
        menu.addItem(presetItem)
        menu.addItem(.separator())
        addWidgetChoices(to: menu)
        menu.addItem(.separator())
        add(L10n.text("显示所有模块", "Show All Widgets"), #selector(showAll), to: menu)
        add(L10n.text("全部组件置顶", "Pin All Widgets"), #selector(pinAll), to: menu)
        add(L10n.text("当前组件：保持置顶", "Selected Widget: Always on Top"), #selector(togglePin(_:)), to: menu)
        add(L10n.text("当前组件：重命名…", "Selected Widget: Rename…"), #selector(renameCurrent), to: menu)
        add(L10n.text("当前组件：编辑启动设置…", "Selected Widget: Edit Launch Settings…"), #selector(editCurrent), to: menu)
        add(L10n.text("当前窗口：字号 +", "Current Window: Increase Font Size"), #selector(largerFont), to: menu)
        add(L10n.text("当前窗口：字号 −", "Current Window: Decrease Font Size"), #selector(smallerFont), to: menu)
        add(L10n.text("当前窗口：切换透明度", "Current Window: Cycle Opacity"), #selector(cycleOpacity), to: menu)
        add(L10n.text("当前窗口：恢复配置字号与透明度", "Current Window: Reset Font and Opacity"), #selector(resetAppearance), to: menu)
        add(L10n.text("关闭当前模块", "Close Current Widget"), #selector(closeCurrent), to: menu, key: "w")
        menu.addItem(.separator())
        add(L10n.text("关于 PinTerm", "About PinTerm"), #selector(about), to: menu)
        add(L10n.text("许可证与第三方源码…", "Licenses and Third-Party Source…"), #selector(showLicenses), to: menu)
        add(L10n.text("退出 PinTerm", "Quit PinTerm"), #selector(quit), to: menu, key: "q")
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "PinTerm")
        statusItem.menu = menu

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = menu.copy() as? NSMenu
        appItem.submenu?.delegate = self
        mainMenu.addItem(appItem)
        let edit = NSMenu(title: L10n.text("编辑", "Edit"))
        edit.addItem(withTitle: L10n.text("复制", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.text("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let editItem = NSMenuItem(title: L10n.text("编辑", "Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        let windowMenu = NSMenu(title: L10n.text("窗口", "Window"))
        windowMenu.delegate = self
        add(L10n.text("下一个窗口", "Next Window"), #selector(nextWindow), to: windowMenu, key: "`")
        windowMenu.addItem(.separator())
        addWidgetChoices(to: windowMenu)
        let windowItem = NSMenuItem(title: L10n.text("窗口", "Window"), action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func addWidgetChoices(to menu: NSMenu) {
        let heading = NSMenuItem(title: L10n.text("选择组件", "Select Widget"), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        for controller in windows {
            let item = add(controller.module.title, #selector(selectWidget(_:)), to: menu)
            item.representedObject = controller.module.id
            item.state = controller === current ? .on : .off
        }
        if !closedModules.isEmpty {
            let closed = NSMenuItem(title: L10n.text("重新打开组件", "Reopen Widget"), action: nil, keyEquivalent: "")
            closed.submenu = NSMenu(title: closed.title)
            for module in closedModules {
                let item = add(module.title, #selector(reopenWidget(_:)), to: closed.submenu!)
                item.representedObject = module.id
            }
            menu.addItem(closed)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Menu tracking can change the key window. Keep the target shown to the user.
        for item in menu.items where item.action == #selector(togglePin(_:)) {
            item.representedObject = current?.module.id
        }
        menu.update()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(selectWidget(_:)) {
            item.state = (item.representedObject as? UUID) == current?.module.id ? .on : .off
            return windows.contains { $0.module.id == item.representedObject as? UUID }
        }
        if item.action == #selector(togglePin(_:)) {
            let target = pinTarget(item)
            item.state = target?.module.alwaysOnTop == true ? .on : .off
            item.title = L10n.text("保持置顶", "Always on Top") + (target.map { ": " + $0.module.title } ?? "")
            return target != nil
        }
        if [#selector(renameCurrent), #selector(editCurrent), #selector(largerFont), #selector(smallerFont),
            #selector(cycleOpacity), #selector(resetAppearance), #selector(closeCurrent), #selector(nextWindow), #selector(showAll)].contains(item.action) {
            return current != nil
        }
        return true
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @discardableResult
    func create(_ module: Module) throws -> ModuleWindow {
        var module = module
        module.isClosed = nil
        if module.title == module.command, let preset = presetWidgets.first(where: { $0.command == module.command }) {
            module.title = preset.name
        }
        let controller = try makeController(for: module)
        closedModules.removeAll { $0.id == module.id }
        windows.append(controller)
        connect(controller)
        selectedModuleID = module.id
        controller.present()
        rebuildMenus()
        save()
        return controller
    }

    private func makeController(for module: Module) throws -> ModuleWindow {
        let path = module.configFile ?? (settings.independentConfig.isEmpty ? nil : settings.independentConfig)
        let configuration = try GhosttyConfiguration().load(independentFile: path, skipTmux: settings.skipTmux)
        let controller = try ModuleWindow(module: module, configuration: configuration,
            cornerRadius: settings.cornerRadius)
        (controller.window as? TerminalWindow)?.dragModifiers = NSEvent.ModifierFlags(rawValue: settings.dragModifiers)
        return controller
    }

    private func connect(_ controller: ModuleWindow) {
        controller.onChange = { [weak self] in self?.save() }
        controller.onActivate = { [weak self, weak controller] in self?.selectedModuleID = controller?.module.id }
        controller.onClose = { [weak self, weak controller] in
            if let controller {
                var saved = controller.snapshotModule()
                saved.isClosed = true
                self?.closedModules.append(saved)
            }
            self?.windows.removeAll { $0 === controller }
            if self?.selectedModuleID == controller?.module.id { self?.selectedModuleID = self?.windows.last?.module.id }
            self?.save()
            self?.rebuildMenus()
        }
    }

    var current: ModuleWindow? {
        windows.first { $0.window?.isKeyWindow == true }
            ?? windows.first { $0.module.id == selectedModuleID }
            ?? windows.first
    }

    @objc private func selectWidget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let controller = windows.first(where: { $0.module.id == id }) else { return }
        selectedModuleID = id
        controller.present()
    }

    @objc private func reopenWidget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let module = closedModules.first(where: { $0.id == id }) else { return }
        openModule(module)
    }

    private func openModule(_ module: Module) {
        do { try create(module) }
        catch { report(error, message: L10n.text("无法创建终端，请检查 Ghostty 配置。", "Unable to create terminal. Check the Ghostty configuration.")) }
    }

    @objc private func preset(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        if let saved = closedModules.last(where: { $0.command == command }) {
            openModule(saved)
            return
        }
        var module = Module()
        module.title = sender.title
        module.command = command
        openModule(module)
    }

    @objc private func customModule() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        alert.messageText = L10n.text("新建 Ghostty 模块", "New Ghostty Widget")
        alert.informativeText = L10n.text("命令留空继承 Ghostty 的 command（未设置时为 shell）。模块命令会在恢复时重新执行。配置文件留空跟随全局设置。", "Leave the command blank to inherit Ghostty’s command, or use the default shell. Commands run again when restored. Leave the config file blank to use global settings.")
        let name = NSTextField(string: "Terminal")
        let directory = NSTextField(string: settings.defaultDirectory)
        let command = NSTextField(string: settings.defaultCommand)
        let config = NSTextField(string: "")
        config.placeholderString = L10n.text("可选：此模块独立的 Ghostty 配置路径", "Optional: Ghostty config path for this widget")
        command.placeholderString = L10n.text("默认 shell / ssh / dev server", "Default shell / ssh / dev server")
        let stack = NSStackView(views: [NSTextField(labelWithString: L10n.text("名称", "Name")), name,
            NSTextField(labelWithString: L10n.text("工作目录（绝对路径）", "Working Directory (absolute path)")), directory,
            NSTextField(labelWithString: L10n.text("命令", "Command")), command,
            NSTextField(labelWithString: L10n.text("独立配置文件", "Independent Config File")), config])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 215)
        for field in [name, directory, command, config] { field.widthAnchor.constraint(equalToConstant: 400).isActive = true }
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.text("创建", "Create"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let path = (directory.stringValue as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            report(CocoaError(.fileNoSuchFile), message: L10n.text("工作目录不存在。", "The working directory does not exist."))
            return
        }
        var module = settings.newModule()
        module.title = name.stringValue.isEmpty ? "Terminal" : name.stringValue
        module.workingDirectory = path
        module.command = command.stringValue.isEmpty ? nil : command.stringValue
        module.configFile = config.stringValue.isEmpty ? nil : (config.stringValue as NSString).expandingTildeInPath
        openModule(module)
    }

    @objc private func showAll() { windows.forEach { $0.present() } }
    @objc private func nextWindow() {
        guard !windows.isEmpty else { return }
        let index = windows.firstIndex { $0 === current } ?? -1
        windows[(index + 1) % windows.count].present()
    }
    private func pinTarget(_ sender: NSMenuItem) -> ModuleWindow? {
        guard let id = sender.representedObject as? UUID else { return current }
        return windows.first { $0.module.id == id }
    }

    @objc private func pinAll() {
        for controller in windows {
            controller.module.alwaysOnTop = true
            controller.applyAppearance()
            controller.window?.orderFrontRegardless()
        }
        for index in closedModules.indices { closedModules[index].alwaysOnTop = true }
        save()
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let target = pinTarget(sender) else { return }
        target.module.alwaysOnTop.toggle()
        target.applyAppearance()
        if target.module.alwaysOnTop { target.window?.orderFrontRegardless() }
        sender.state = target.module.alwaysOnTop ? .on : .off
    }

    @objc private func renameCurrent() {
        guard let current else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        alert.messageText = L10n.text("重命名组件", "Rename Widget")
        alert.informativeText = L10n.text("名称显示在组件选择菜单中，不会修改运行命令。", "The name appears in the widget selection menu. The running command is unchanged.")
        let name = NSTextField(string: current.module.title)
        name.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = name
        alert.addButton(withTitle: L10n.text("保存", "Save"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        current.module.title = title
        current.window?.title = title
        save()
        rebuildMenus()
    }

    @objc private func editCurrent() {
        guard let current else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        alert.messageText = L10n.text("编辑组件启动设置", "Edit Widget Launch Settings")
        alert.informativeText = L10n.text("保存后将重新启动此组件。命令留空会继承 Ghostty 的启动命令；配置文件留空会跟随全局设置。", "Saving restarts this widget. Leave the command blank to inherit Ghostty’s startup command, or the config file blank to use global settings.")
        let directory = NSTextField(string: current.module.workingDirectory)
        let command = NSTextField(string: current.module.command ?? "")
        let config = NSTextField(string: current.module.configFile ?? "")
        command.placeholderString = L10n.text("默认 shell / ssh / dev server", "Default shell / ssh / dev server")
        config.placeholderString = L10n.text("跟随全局设置", "Use global settings")
        let stack = NSStackView(views: [
            NSTextField(labelWithString: L10n.text("工作目录（绝对路径）", "Working Directory (absolute path)")), directory,
            NSTextField(labelWithString: L10n.text("命令", "Command")), command,
            NSTextField(labelWithString: L10n.text("独立配置文件", "Independent Config File")), config,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 160)
        for field in [directory, command, config] { field.widthAnchor.constraint(equalToConstant: 400).isActive = true }
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.text("保存并重启", "Save and Restart"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var module = current.snapshotModule()
        let path = (directory.stringValue as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            report(CocoaError(.fileNoSuchFile), message: L10n.text("工作目录不存在。", "The working directory does not exist."))
            return
        }
        module.workingDirectory = path
        module.command = command.stringValue.isEmpty ? nil : command.stringValue
        module.configFile = config.stringValue.isEmpty ? nil : (config.stringValue as NSString).expandingTildeInPath

        do {
            let configPath = module.configFile ?? (settings.independentConfig.isEmpty ? nil : settings.independentConfig)
            let configuration = try GhosttyConfiguration().load(independentFile: configPath, skipTmux: settings.skipTmux)
            let validator = TerminalController(configSource: .generated(configuration), theme: .init())
            if let issue = validator.lastConfigurationIssue { throw ConfigurationError(issue) }
        } catch {
            report(error, message: L10n.text("无法应用启动设置，请检查 Ghostty 配置。", "Unable to apply launch settings. Check the Ghostty configuration."))
            return
        }

        let confirmation = NSAlert()
        confirmation.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        confirmation.messageText = L10n.text("重新启动这个组件？", "Restart this widget?")
        confirmation.informativeText = L10n.text("当前终端中的 shell 和任务将结束，窗口布局和外观会保留。", "The shell and tasks in the current terminal will end. Window layout and appearance are preserved.")
        confirmation.addButton(withTitle: L10n.text("重新启动", "Restart"))
        confirmation.addButton(withTitle: L10n.text("取消", "Cancel"))
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        do {
            let replacement = try makeController(for: module)
            guard let index = windows.firstIndex(where: { $0 === current }) else {
                replacement.window?.close()
                return
            }
            current.onClose = nil
            current.onChange = nil
            current.onActivate = nil
            current.terminal.controller = nil
            current.window?.close()
            windows[index] = replacement
            connect(replacement)
            selectedModuleID = module.id
            replacement.present()
            save()
            rebuildMenus()
        } catch {
            report(error, message: L10n.text("无法重新启动组件；原终端仍在运行。", "Unable to restart the widget. The original terminal is still running."))
        }
    }
    @objc private func largerFont() { changeFont(1) }
    @objc private func smallerFont() { changeFont(-1) }

    private func changeFont(_ delta: Float) {
        guard let current else { return }
        current.module.fontSize = min(48, max(8, current.configuredFontSize + delta))
        current.applyAppearance()
    }
    @objc private func cycleOpacity() {
        guard let current else { return }
        let opacity = current.module.opacity ?? 0.94
        current.module.opacity = opacity > 0.95 ? 0.75 : (opacity > 0.8 ? 1 : 0.94)
        current.applyAppearance()
    }
    @objc private func resetAppearance() {
        guard let current else { return }
        current.module.fontSize = nil
        current.module.opacity = nil
        current.applyAppearance()
    }
    @objc private func closeCurrent() { current?.requestClose() }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        guard let result = SettingsDialog(settings).run() else { return }
        do {
            guard result.settings.dragModifiers != 0 else {
                throw ConfigurationError(L10n.text("拖动快捷键至少需要选择一个修饰键。", "Select at least one modifier key for dragging."))
            }
            var isDirectory: ObjCBool = false
            guard result.settings.defaultDirectory.hasPrefix("/"),
                  FileManager.default.fileExists(atPath: result.settings.defaultDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ConfigurationError(L10n.text("默认目录不存在。", "The default directory does not exist."))
            }
            let config = try GhosttyConfiguration().load(independentFile: result.settings.independentConfig.isEmpty ? nil : result.settings.independentConfig,
                skipTmux: result.settings.skipTmux)
            let validator = TerminalController(configSource: .generated(config), theme: .init())
            if let issue = validator.lastConfigurationIssue { throw ConfigurationError(issue) }
            try result.settings.save()
            settings = result.settings
            L10n.language = result.language
            rebuildMenus()
            for controller in windows {
                (controller.window as? TerminalWindow)?.dragModifiers = NSEvent.ModifierFlags(rawValue: settings.dragModifiers)
                controller.setCornerRadius(settings.cornerRadius)
                controller.updateLocalizedText()
            }
            let service = SMAppService.mainApp
            if result.launchAtLogin && service.status != .enabled && service.status != .requiresApproval {
                guard Bundle.main.bundleURL.pathExtension == "app" else {
                    throw ConfigurationError(L10n.text("登录启动需要运行打包后的 PinTerm.app，不能使用 swift run。其他设置已保存。", "Launch at login requires the packaged PinTerm.app, not swift run. Other settings have been saved."))
                }
                try service.register()
            } else if !result.launchAtLogin && (service.status == .enabled || service.status == .requiresApproval) {
                try service.unregister()
            }
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { report(error, message: L10n.text("设置未完全应用", "Some settings could not be applied")) }
    }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: L10n.text("由 Ghostty 驱动的桌面终端", "Ghostty-powered desktop terminals") + "\nhttps://github.com/taotao7/PinTerm"),
        ])
        NSApp.keyWindow?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }

    @objc private func showLicenses() {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/taotao7/PinTerm/blob/main/THIRD_PARTY_NOTICES.md")!)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !windows.isEmpty {
            let alert = NSAlert()
            alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            alert.messageText = L10n.text("退出 PinTerm？", "Quit PinTerm?")
            alert.informativeText = L10n.text("所有终端进程将结束。窗口配置会保留，下次启动会重新执行命令。", "All terminal processes will end. Window settings are preserved; commands run again on the next launch.")
            alert.addButton(withTitle: L10n.text("退出", "Quit"))
            alert.addButton(withTitle: L10n.text("取消", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        save()
        windows.forEach { $0.onClose = nil; $0.onChange = nil; $0.onActivate = nil; $0.terminal.controller = nil }
        return .terminateNow
    }

    private func save() {
        guard persistenceEnabled else { return }
        do { try store.save(windows.map { $0.snapshotModule() } + closedModules) }
        catch {
            persistenceEnabled = false
            report(error, message: L10n.text("无法保存模块；本次已停止自动保存。", "Unable to save widgets. Automatic saving is disabled for this run."))
        }
    }

    private func report(_ error: Error, message: String) {
        let alert = NSAlert(error: error)
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        alert.messageText = message
        if alert.buttons.count == 1 { alert.buttons[0].title = L10n.text("好", "OK") }
        alert.runModal()
    }
}
