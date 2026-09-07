import AppKit
import GhosttyTerminal
import ServiceManagement

@main
@MainActor
final class PinTermApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var windows: [ModuleWindow] = []
    private let store = ModuleStore.standard
    private var persistenceEnabled = false
    private var settings = AppSettings()

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
        let menu = NSMenu()
        add("新建默认模块", #selector(newShell), to: menu, key: "n")
        add("自定义模块…", #selector(customModule), to: menu)
        add("设置…", #selector(showSettings), to: menu, key: ",")
        for command in ["btop", "htop", "cal; exec \"$SHELL\""] {
            let item = add(command, #selector(preset(_:)), to: menu)
            item.representedObject = command
        }
        menu.addItem(.separator())
        add("显示所有模块", #selector(showAll), to: menu)
        add("当前窗口：切换置顶", #selector(togglePin), to: menu)
        add("当前窗口：字号 +", #selector(largerFont), to: menu)
        add("当前窗口：字号 −", #selector(smallerFont), to: menu)
        add("当前窗口：切换透明度", #selector(cycleOpacity), to: menu)
        add("当前窗口：恢复配置字号与透明度", #selector(resetAppearance), to: menu)
        add("关闭当前模块", #selector(closeCurrent), to: menu, key: "w")
        menu.addItem(.separator())
        add("关于 PinTerm", #selector(about), to: menu)
        add("许可证与第三方源码…", #selector(showLicenses), to: menu)
        add("退出 PinTerm", #selector(quit), to: menu, key: "q")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "PinTerm")
        statusItem.menu = menu

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = menu.copy() as? NSMenu
        mainMenu.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        let windowMenu = NSMenu(title: "窗口")
        add("下一个窗口", #selector(nextWindow), to: windowMenu, key: "`")
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        do {
            settings = try AppSettings.load()
            let modules = try store.load()
            if !settings.restoreWindows || modules.isEmpty { try create(settings.newModule()) }
            else { try modules.forEach(create) }
            persistenceEnabled = true
            save()
        } catch {
            persistenceEnabled = false
            report(error, message: "无法加载配置；原文件已保留，本次不写入模块配置。可在设置中修正配置文件路径。")
        }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func create(_ module: Module) throws {
        let path = module.configFile ?? (settings.independentConfig.isEmpty ? nil : settings.independentConfig)
        let configuration = try GhosttyConfiguration().load(independentFile: path, skipTmux: settings.skipTmux)
        let controller = try ModuleWindow(module: module, configuration: configuration)
        windows.append(controller)
        controller.onChange = { [weak self] in self?.save() }
        controller.onClose = { [weak self, weak controller] in
            self?.windows.removeAll { $0 === controller }
            self?.save()
        }
        controller.present()
        save()
    }

    private var current: ModuleWindow? {
        windows.first { $0.window?.isKeyWindow == true } ?? windows.first { $0.window?.isMainWindow == true }
    }

    private func openModule(_ module: Module) {
        do { try create(module) }
        catch { report(error, message: "无法创建终端，请检查 Ghostty 配置。") }
    }

    @objc private func newShell() { openModule(settings.newModule()) }
    @objc private func preset(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        var module = Module()
        module.title = command
        module.command = command
        openModule(module)
    }

    @objc private func customModule() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "新建 Ghostty 模块"
        alert.informativeText = "命令留空继承 Ghostty 的 command（未设置时为 shell）。模块命令会在恢复时重新执行。配置文件留空跟随全局设置。"
        let name = NSTextField(string: "Terminal")
        let directory = NSTextField(string: settings.defaultDirectory)
        let command = NSTextField(string: settings.defaultCommand)
        let config = NSTextField(string: "")
        config.placeholderString = "可选：此模块独立的 Ghostty 配置路径"
        command.placeholderString = "默认 shell / ssh / dev server"
        let stack = NSStackView(views: [NSTextField(labelWithString: "名称"), name,
            NSTextField(labelWithString: "工作目录（绝对路径）"), directory,
            NSTextField(labelWithString: "命令"), command,
            NSTextField(labelWithString: "独立配置文件"), config])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 215)
        for field in [name, directory, command, config] { field.widthAnchor.constraint(equalToConstant: 400).isActive = true }
        alert.accessoryView = stack
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let path = (directory.stringValue as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            report(CocoaError(.fileNoSuchFile), message: "工作目录不存在。")
            return
        }
        var module = Module()
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
    @objc private func togglePin() {
        guard let current else { return }
        current.module.alwaysOnTop.toggle()
        current.applyAppearance()
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
            var isDirectory: ObjCBool = false
            guard result.settings.defaultDirectory.hasPrefix("/"),
                  FileManager.default.fileExists(atPath: result.settings.defaultDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ConfigurationError("默认目录不存在。")
            }
            let config = try GhosttyConfiguration().load(independentFile: result.settings.independentConfig.isEmpty ? nil : result.settings.independentConfig,
                skipTmux: result.settings.skipTmux)
            let validator = TerminalController(configSource: .generated(config), theme: .init())
            if let issue = validator.lastConfigurationIssue { throw ConfigurationError(issue) }
            try result.settings.save()
            settings = result.settings
            let service = SMAppService.mainApp
            if result.launchAtLogin && service.status != .enabled && service.status != .requiresApproval {
                guard Bundle.main.bundleURL.pathExtension == "app" else {
                    throw ConfigurationError("登录启动需要运行打包后的 PinTerm.app，不能使用 swift run。其他设置已保存。")
                }
                try service.register()
            } else if !result.launchAtLogin && (service.status == .enabled || service.status == .requiresApproval) {
                try service.unregister()
            }
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { report(error, message: "设置未完全应用") }
    }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Ghostty-powered desktop terminals\nhttps://github.com/taotao7/PinTerm"),
        ])
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
            alert.messageText = "退出 PinTerm？"
            alert.informativeText = "所有终端进程将结束。窗口配置会保留，下次启动会重新执行命令。"
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        save()
        windows.forEach { $0.onClose = nil; $0.onChange = nil; $0.terminal.controller = nil }
        return .terminateNow
    }

    private func save() {
        guard persistenceEnabled else { return }
        do { try store.save(windows.map(\.module)) }
        catch {
            persistenceEnabled = false
            report(error, message: "无法保存模块；本次已停止自动保存。")
        }
    }

    private func report(_ error: Error, message: String) {
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }
}
