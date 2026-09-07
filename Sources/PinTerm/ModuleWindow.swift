import AppKit
import GhosttyTerminal

@MainActor
final class ModuleWindow: NSWindowController, NSWindowDelegate,
    TerminalSurfaceTitleDelegate, TerminalSurfaceCloseDelegate,
    TerminalSurfaceClipboardConfirmationDelegate {
    var module: Module
    let terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    private let runtime: TerminalController
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?
    private var processExited = false

    var configuredFontSize: Float {
        for line in runtime.renderedConfig.components(separatedBy: .newlines).reversed() {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "font-size",
               let value = Float(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))) {
                return value
            }
        }
        return 13 // Native Ghostty macOS default, not the wrapper's 14pt default.
    }

    init(module: Module, configuration: String) throws {
        self.module = module
        runtime = TerminalController(configSource: .generated(configuration), theme: .init(),
            terminalConfiguration: TerminalConfiguration {
                if let command = module.launchCommand {
                    $0.withCustom("initial-command", command)
                    $0.withCustom("command", command)
                }
                $0.withCustom("working-directory", module.workingDirectory)
                if let fontSize = module.fontSize { $0.withFontSize(fontSize) }
                if let opacity = module.opacity { $0.withBackgroundOpacity(opacity) }
            })
        if let issue = runtime.lastConfigurationIssue { throw ConfigurationError(issue) }
        let window = TerminalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless, .resizable],
            backing: .buffered, defer: false
        )
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.title = module.title
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 320, height: 180)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = module.alwaysOnTop ? .floating : .normal
        let container = NSView()
        window.contentView = container
        terminal.configuration = TerminalSurfaceOptions(
            backend: .exec, workingDirectory: module.workingDirectory,
            command: module.launchCommand, waitAfterCommand: false
        )
        terminal.delegate = self
        terminal.controller = runtime
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        let handle = WindowDragHandle()
        handle.toolTip = "拖动移动窗口；菜单栏可关闭、设置模块"
        handle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(handle)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            handle.topAnchor.constraint(equalTo: container.topAnchor),
            handle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            handle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            handle.heightAnchor.constraint(equalToConstant: 8),
        ])
        if let frame = module.frame {
            let rect = NSRectFromString(frame)
            if rect.width >= 320, rect.height >= 180,
               NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: rect.midX, y: rect.maxY - 20)) }) {
                window.setFrame(rect, display: false)
            } else { window.center() }
        } else { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("Use init(module:)") }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        terminal.acquireProgrammaticFocus()
    }

    func applyAppearance() {
        window?.level = module.alwaysOnTop ? .floating : .normal
        runtime.setTerminalConfiguration(TerminalConfiguration {
            if let command = module.launchCommand {
                $0.withCustom("initial-command", command)
                $0.withCustom("command", command)
            }
            $0.withCustom("working-directory", module.workingDirectory)
            if let opacity = module.opacity { $0.withBackgroundOpacity(opacity) }
            if let fontSize = module.fontSize { $0.withFontSize(fontSize) }
        })
        if let fontSize = module.fontSize {
            terminal.performBindingAction("set_font_size:\(fontSize)")
        } else { terminal.performBindingAction("reset_font_size") }
        onChange?()
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() {
        if let window { module.frame = NSStringFromRect(window.frame) }
        onChange?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !processExited else { return true }
        let alert = NSAlert()
        alert.messageText = "关闭这个终端？"
        alert.informativeText = "此窗口中的 shell 和运行中的任务将被终止，模块也会从恢复列表移除。"
        alert.addButton(withTitle: "关闭终端")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        terminal.controller = nil
        onClose?()
    }

    func requestClose() {
        guard let window, windowShouldClose(window) else { return }
        window.close()
    }

    func terminalDidChangeTitle(_ title: String) { window?.title = "\(module.title) — \(title)" }
    func terminalDidClose(processAlive: Bool) {
        processExited = !processAlive
        // Leave Ghostty's callback before freeing its surface.
        DispatchQueue.main.async { [weak self] in self?.requestClose() }
    }

    func terminalDidRequestClipboardConfirmation(_ request: TerminalClipboardConfirmationRequest) {
        let alert = NSAlert()
        alert.messageText = "允许终端访问剪贴板？"
        alert.informativeText = "终端请求受保护的复制或粘贴操作。仅在信任当前程序时允许。"
        alert.addButton(withTitle: "允许")
        alert.addButton(withTitle: "拒绝")
        guard let window else { request.respond(allow: false); return }
        alert.beginSheetModal(for: window) { response in
            request.respond(allow: response == .alertFirstButtonReturn)
        }
    }
}

private final class TerminalWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class WindowDragHandle: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
