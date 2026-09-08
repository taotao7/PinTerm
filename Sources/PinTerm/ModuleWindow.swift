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
    var onActivate: (() -> Void)?
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
        window.isReleasedWhenClosed = false
        window.title = module.title
        window.isExcludedFromWindowsMenu = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        // Fully transparent margins are click-through at the WindowServer level,
        // even though AppKit still shows their resize cursors.
        window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        window.minSize = NSSize(width: 80, height: 48)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = module.alwaysOnTop ? .statusBar : .normal
        let container = WindowContentView()
        window.contentView = container
        terminal.configuration = TerminalSurfaceOptions(
            backend: .exec, workingDirectory: module.workingDirectory,
            command: module.launchCommand, waitAfterCommand: false
        )
        terminal.delegate = self
        terminal.controller = runtime
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        let handle = WindowTopEdge()
        handle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(handle)
        updateLocalizedText()
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
            if rect.width.isFinite, rect.height.isFinite, rect.origin.x.isFinite, rect.origin.y.isFinite,
               rect.width >= window.minSize.width, rect.height >= window.minSize.height {
                window.setFrame(rect, display: false)
                if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: rect.midX, y: rect.maxY - 20)) }) {
                    // A disconnected display should change the position, not discard the saved size.
                    window.center()
                }
            } else { window.center() }
        } else { window.center() }
        window.delegate = self
        snapshotModule()
    }

    required init?(coder: NSCoder) { fatalError("Use init(module:)") }

    func updateLocalizedText() {
        window?.contentView?.subviews.first { $0 is WindowTopEdge }?.toolTip = L10n.text(
            "拖动边缘调整大小；按住设置中的快捷键在终端内拖动可移动窗口（默认 ⌘⇧）",
            "Drag edges to resize; hold the shortcut set in Settings and drag inside the terminal to move (default ⌘⇧).")
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        terminal.acquireProgrammaticFocus()
    }

    func applyAppearance() {
        window?.level = module.alwaysOnTop ? .statusBar : .normal
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
    func windowDidBecomeKey(_ notification: Notification) { onActivate?() }

    @discardableResult
    func snapshotModule() -> Module {
        if let window { module.frame = NSStringFromRect(window.frame) }
        return module
    }

    private func saveFrame() {
        snapshotModule()
        onChange?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !processExited else { return true }
        let alert = NSAlert()
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        alert.messageText = L10n.text("关闭这个终端？", "Close this terminal?")
        alert.informativeText = L10n.text("此窗口中的 shell 和任务将结束。名称、位置、大小和置顶状态会保留，可从菜单重新打开。", "The shell and tasks will end. Name, position, size, and pin state are saved so you can reopen this widget from the menu.")
        alert.addButton(withTitle: L10n.text("关闭终端", "Close Terminal"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
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
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        alert.messageText = L10n.text("允许终端访问剪贴板？", "Allow terminal clipboard access?")
        alert.informativeText = L10n.text("终端请求受保护的复制或粘贴操作。仅在信任当前程序时允许。", "The terminal requests a protected copy or paste operation. Allow only if you trust the current program.")
        alert.addButton(withTitle: L10n.text("允许", "Allow"))
        alert.addButton(withTitle: L10n.text("拒绝", "Deny"))
        guard let window else { request.respond(allow: false); return }
        alert.beginSheetModal(for: window) { response in
            request.respond(allow: response == .alertFirstButtonReturn)
        }
    }
}

final class TerminalWindow: NSWindow {
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var resizeStart: (mouse: NSPoint, frame: NSRect, edges: ResizeEdges)?
    var dragModifiers: NSEvent.ModifierFlags = [.command, .shift]
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    struct ResizeEdges: OptionSet {
        let rawValue: Int
        static let left = Self(rawValue: 1)
        static let right = Self(rawValue: 2)
        static let bottom = Self(rawValue: 4)
        static let top = Self(rawValue: 8)
    }

    func resizeEdges(at point: NSPoint) -> ResizeEdges {
        guard let bounds = contentView?.bounds, bounds.contains(point) else { return [] }
        var edges: ResizeEdges = []
        if point.x < bounds.minX + 8 { edges.insert(.left) }
        if point.x >= bounds.maxX - 8 { edges.insert(.right) }
        if point.y < bounds.minY + 8 { edges.insert(.bottom) }
        if point.y >= bounds.maxY - 8 { edges.insert(.top) }
        return edges
    }

    func beginWindowResize(at point: NSPoint, edges: ResizeEdges) {
        dragStart = nil
        resizeStart = (point, frame, edges)
    }

    func updateWindowResize(to point: NSPoint) {
        guard let start = resizeStart else { return }
        var rect = start.frame
        let dx = point.x - start.mouse.x
        let dy = point.y - start.mouse.y
        if start.edges.contains(.left) {
            rect.size.width = max(minSize.width, start.frame.width - dx)
            rect.origin.x = start.frame.maxX - rect.width
        } else if start.edges.contains(.right) {
            rect.size.width = max(minSize.width, start.frame.width + dx)
        }
        if start.edges.contains(.bottom) {
            rect.size.height = max(minSize.height, start.frame.height - dy)
            rect.origin.y = start.frame.maxY - rect.height
        } else if start.edges.contains(.top) {
            rect.size.height = max(minSize.height, start.frame.height + dy)
        }
        setFrame(rect, display: true)
    }

    func isWindowDrag(_ event: NSEvent) -> Bool {
        !dragModifiers.isEmpty && event.type == .leftMouseDown && event.modifierFlags.intersection([.command, .option, .shift, .control]) == dragModifiers
    }

    func beginWindowDrag(at point: NSPoint) {
        resizeStart = nil
        dragStart = (point, frame.origin)
    }

    func updateWindowDrag(to point: NSPoint) {
        guard let start = dragStart else { return }
        setFrameOrigin(NSPoint(x: start.origin.x + point.x - start.mouse.x,
            y: start.origin.y + point.y - start.mouse.y))
    }

    override func sendEvent(_ event: NSEvent) {
        let edges = event.type == .leftMouseDown ? resizeEdges(at: event.locationInWindow) : []
        if event.type == .leftMouseDown && !edges.isEmpty {
            beginWindowResize(at: convertPoint(toScreen: event.locationInWindow), edges: edges)
        } else if resizeStart != nil && (event.type == .leftMouseDragged || event.type == .leftMouseUp) {
            updateWindowResize(to: convertPoint(toScreen: event.locationInWindow))
            if event.type == .leftMouseUp { resizeStart = nil }
        } else if isWindowDrag(event) {
            // Intercept before Ghostty sees mouseDown so no terminal selection or TUI click starts.
            beginWindowDrag(at: NSEvent.mouseLocation)
        } else if dragStart != nil && event.type == .leftMouseDragged {
            // Updating the origin directly avoids the native drag-to-tile session.
            updateWindowDrag(to: NSEvent.mouseLocation)
        } else if dragStart != nil && event.type == .leftMouseUp {
            updateWindowDrag(to: NSEvent.mouseLocation)
            dragStart = nil
        } else {
            super.sendEvent(event)
        }
    }
}

private final class WindowContentView: NSView {
    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: 8), cursor: .resizeUpDown)
        for x in [bounds.minX, bounds.maxX - 8] {
            addCursorRect(NSRect(x: x, y: 0, width: 8, height: bounds.height), cursor: .resizeLeftRight)
        }
    }
}

private final class WindowTopEdge: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds.insetBy(dx: 8, dy: 0), cursor: .resizeUpDown) }
}
