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
    let languagePicker: NSPopUpButton
    let modifierButtons: [(NSEvent.ModifierFlags, NSButton)]

    var selectedDragModifiers: UInt {
        modifierButtons.reduce(0) { $0 | ($1.1.state == .on ? $1.0.rawValue : 0) }
    }

    init(_ settings: AppSettings) {
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        alert.messageText = L10n.text("PinTerm 设置", "PinTerm Settings")
        alert.informativeText = L10n.text("配置与启动命令对新建模块生效，不会重启当前任务。命令留空继承 Ghostty 的 command；未设置时启动 shell。", "Configuration and startup commands apply to new modules without restarting current tasks. Leave the command empty to inherit Ghostty’s command, or start a shell if none is set.")
        languagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
        for language in AppLanguage.allCases {
            switch language {
            case .system: languagePicker.addItem(withTitle: "跟随系统 / System")
            case .chinese: languagePicker.addItem(withTitle: "简体中文")
            case .english: languagePicker.addItem(withTitle: "English")
            }
        }
        languagePicker.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.language) ?? 0)
        command = NSTextField(string: settings.defaultCommand)
        command.placeholderString = L10n.text("例如 btop、ssh user@host、/bin/zsh", "For example: btop, ssh user@host, /bin/zsh")
        directory = NSTextField(string: settings.defaultDirectory)
        config = NSTextField(string: settings.independentConfig)
        config.placeholderString = L10n.text("留空继承本机 Ghostty；或填写独立配置绝对路径", "Leave empty to inherit Ghostty, or enter an absolute config path")
        restore = NSButton(checkboxWithTitle: L10n.text("启动时恢复上次模块（否则仅显示菜单栏）", "Restore previous modules on launch (otherwise menu bar only)"), target: nil, action: nil)
        restore.state = settings.restoreWindows ? .on : .off
        skipTmux = NSButton(checkboxWithTitle: L10n.text("不载入 Ghostty 配置中的 tmux 启动命令", "Skip tmux startup commands in the Ghostty configuration"), target: nil, action: nil)
        skipTmux.state = settings.skipTmux ? .on : .off
        let tmuxNote = NSTextField(wrappingLabelWithString: L10n.text("忽略含 tmux 的 command / initial-command；保留外观配置。显式模块命令及 .zshrc 等 shell 脚本不受影响。", "Ignore command / initial-command entries containing tmux, but keep appearance settings. Explicit module commands and shell scripts such as .zshrc are unaffected."))
        tmuxNote.textColor = .secondaryLabelColor
        launch = NSButton(checkboxWithTitle: L10n.text("登录 macOS 时自动启动 PinTerm", "Launch PinTerm automatically when logging in to macOS"), target: nil, action: nil)
        let status = SMAppService.mainApp.status
        launch.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        let statusText = NSTextField(wrappingLabelWithString: status == .requiresApproval
            ? L10n.text("登录项等待系统批准；保存后打开系统设置。", "The login item needs system approval. System Settings will open after saving.")
            : L10n.text("登录项由 macOS 管理；请从固定位置运行打包的 .app。", "Login items are managed by macOS. Run the packaged .app from a fixed location."))
        statusText.textColor = .secondaryLabelColor
        let choices: [(NSEvent.ModifierFlags, String)] = [(.command, "⌘ Command"), (.shift, "⇧ Shift"), (.option, "⌥ Option"), (.control, "⌃ Control")]
        modifierButtons = choices.map { flag, title in
            let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            button.state = settings.dragModifiers & flag.rawValue != 0 ? .on : .off
            return (flag, button)
        }
        let modifiers = NSStackView(views: modifierButtons.map { $0.1 })
        modifiers.spacing = 12
        let dragNote = NSTextField(wrappingLabelWithString: L10n.text("至少选择一个键；按住所选组合 + 左键拖动。保存后立即生效，不触发原生贴边分屏；单键组合可能覆盖终端手势。", "Select at least one key, then hold the combination and drag with the left mouse button. Changes apply immediately after saving, without triggering native window tiling. Single-key combinations may override terminal gestures."))
        dragNote.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [
            NSTextField(labelWithString: L10n.text("界面语言", "Interface language")), languagePicker,
            NSTextField(labelWithString: L10n.text("默认运行命令", "Default command")), command,
            NSTextField(labelWithString: L10n.text("默认工作目录", "Default working directory")), directory,
            NSTextField(labelWithString: L10n.text("独立 Ghostty 配置（可选）", "Separate Ghostty configuration (optional)")), config,
            skipTmux, tmuxNote, restore, launch, statusText,
            NSTextField(labelWithString: L10n.text("拖动窗口快捷键", "Window drag shortcut")), modifiers, dragNote,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let width: CGFloat = 520
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        for field in [command, directory, config, statusText, tmuxNote, dragNote] {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        for note in [statusText, tmuxNote, dragNote] {
            note.preferredMaxLayoutWidth = width
            note.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        stack.frame = NSRect(x: 0, y: 0, width: width, height: stack.fittingSize.height)
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.text("保存", "Save"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
    }

    func run() -> (settings: AppSettings, launchAtLogin: Bool, language: AppLanguage)? {
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var result = AppSettings()
        result.defaultCommand = command.stringValue
        result.defaultDirectory = (directory.stringValue as NSString).expandingTildeInPath
        result.independentConfig = (config.stringValue as NSString).expandingTildeInPath
        result.restoreWindows = restore.state == .on
        result.skipTmux = skipTmux.state == .on
        result.dragModifiers = selectedDragModifiers
        let selectedIndex = languagePicker.indexOfSelectedItem
        let language = AppLanguage.allCases.indices.contains(selectedIndex)
            ? AppLanguage.allCases[selectedIndex] : .system
        return (result, launch.state == .on, language)
    }
}
