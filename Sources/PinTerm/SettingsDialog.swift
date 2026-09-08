import AppKit
import ServiceManagement

@MainActor
final class SettingsDialog {
    let alert = NSAlert()
    private let command: NSTextField
    private let directory: NSTextField
    private let config: NSTextField
    private let restore: NSButton
    private let launch: NSButton
    let skipTmux: NSButton
    let modifierButtons: [(NSEvent.ModifierFlags, NSButton)]

    var selectedDragModifiers: UInt {
        modifierButtons.reduce(0) { $0 | ($1.1.state == .on ? $1.0.rawValue : 0) }
    }

    init(_ settings: AppSettings) {
        alert.messageText = "PinTerm 设置"
        alert.informativeText = "配置与启动命令对新建模块生效，不会重启当前任务。命令留空继承 Ghostty 的 command；未设置时启动 shell。"
        command = NSTextField(string: settings.defaultCommand)
        command.placeholderString = "例如 btop、ssh user@host、/bin/zsh"
        directory = NSTextField(string: settings.defaultDirectory)
        config = NSTextField(string: settings.independentConfig)
        config.placeholderString = "留空继承本机 Ghostty；或填写独立配置绝对路径"
        restore = NSButton(checkboxWithTitle: "启动时恢复上次模块（否则运行默认模块）", target: nil, action: nil)
        restore.state = settings.restoreWindows ? .on : .off
        skipTmux = NSButton(checkboxWithTitle: "不载入 Ghostty 配置中的 tmux 启动命令", target: nil, action: nil)
        skipTmux.state = settings.skipTmux ? .on : .off
        let tmuxNote = NSTextField(wrappingLabelWithString: "忽略含 tmux 的 command / initial-command；保留外观配置。显式模块命令及 .zshrc 等 shell 脚本不受影响。")
        tmuxNote.textColor = .secondaryLabelColor
        launch = NSButton(checkboxWithTitle: "登录 macOS 时自动启动 PinTerm", target: nil, action: nil)
        let status = SMAppService.mainApp.status
        launch.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        let statusText = NSTextField(wrappingLabelWithString: status == .requiresApproval
            ? "登录项等待系统批准；保存后打开系统设置。"
            : "登录项由 macOS 管理；请从固定位置运行打包的 .app。")
        statusText.textColor = .secondaryLabelColor
        let choices: [(NSEvent.ModifierFlags, String)] = [(.command, "⌘ Command"), (.shift, "⇧ Shift"), (.option, "⌥ Option"), (.control, "⌃ Control")]
        modifierButtons = choices.map { flag, title in
            let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            button.state = settings.dragModifiers & flag.rawValue != 0 ? .on : .off
            return (flag, button)
        }
        let modifiers = NSStackView(views: modifierButtons.map { $0.1 })
        modifiers.spacing = 12
        let dragNote = NSTextField(wrappingLabelWithString: "至少选择一个键；按住所选组合 + 左键拖动。保存后立即生效，不触发原生贴边分屏；单键组合可能覆盖终端手势。")
        dragNote.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [
            NSTextField(labelWithString: "默认运行命令"), command,
            NSTextField(labelWithString: "默认工作目录"), directory,
            NSTextField(labelWithString: "独立 Ghostty 配置（可选）"), config,
            skipTmux, tmuxNote, restore, launch, statusText,
            NSTextField(labelWithString: "拖动窗口快捷键"), modifiers, dragNote,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 460, height: 470)
        for field in [command, directory, config, statusText, tmuxNote, dragNote] {
            field.widthAnchor.constraint(equalToConstant: 460).isActive = true
        }
        alert.accessoryView = stack
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
    }

    func run() -> (settings: AppSettings, launchAtLogin: Bool)? {
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var result = AppSettings()
        result.defaultCommand = command.stringValue
        result.defaultDirectory = (directory.stringValue as NSString).expandingTildeInPath
        result.independentConfig = (config.stringValue as NSString).expandingTildeInPath
        result.restoreWindows = restore.state == .on
        result.skipTmux = skipTmux.state == .on
        result.dragModifiers = selectedDragModifiers
        return (result, launch.state == .on)
    }
}
