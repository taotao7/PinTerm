import AppKit
import GhosttyTerminal
import Testing
@testable import PinTerm

@Suite(.serialized)
struct WindowSmokeTests {
    /// Opt-in: requires a logged-in desktop and Metal.
    /// Does not touch saved modules, settings, login items or the user's running shells.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PINTERM_UI_TEST"] != nil))
    @MainActor func borderlessTerminalAndSettings() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        var module = Module()
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        module.command = "printf '\\033[2J\\033[HPinTerm / native Ghostty config\\nNo title bar. Real PTY.\\n'; touch '\(marker.path)'; exec /bin/cat"
        let inherited = try GhosttyConfiguration().load(independentFile: nil)
        let controller = try ModuleWindow(module: module, configuration: inherited)
        defer { controller.window?.close() }
        controller.present()
        let window = try #require(controller.window)
        #expect(!window.styleMask.contains(.titled))
        #expect(window.standardWindowButton(.closeButton) == nil)
        #expect(window.canBecomeKey && window.canBecomeMain)
        window.contentView?.layoutSubtreeIfNeeded()
        let container = try #require(window.contentView)
        let handle = try #require(container.subviews.first { $0.toolTip != nil })
        #expect(handle.frame.height == 8)
        #expect(handle.acceptsFirstMouse(for: nil))
        #expect(container.hitTest(NSPoint(x: 100, y: container.bounds.maxY - 4)) === handle)
        #expect(!handle.frame.intersects(controller.terminal.frame))
        let terminalWindow = try #require(window as? TerminalWindow)
        for flags: NSEvent.ModifierFlags in [[], .command, .option, [.command, .shift], [.command, .option], [.command, .option, .shift]] {
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
                location: NSPoint(x: 150, y: 100), modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            #expect(terminalWindow.isWindowDrag(event) == (flags == [.command, .shift]))
            terminalWindow.dragModifiers = [.command, .option]
            #expect(terminalWindow.isWindowDrag(event) == (flags == [.command, .option]))
            terminalWindow.dragModifiers = [.command, .shift]
        }
        let originalFrame = window.frame
        terminalWindow.beginWindowDrag(at: NSPoint(x: 100, y: 100))
        terminalWindow.updateWindowDrag(to: NSPoint(x: 150, y: 120))
        #expect(window.frame.origin == NSPoint(x: originalFrame.minX + 50, y: originalFrame.minY + 20))
        #expect(window.frame.size == originalFrame.size)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        try #require(FileManager.default.fileExists(atPath: marker.path), "Explicit module command must override inherited command before any keyboard input")
        #expect(controller.terminal.ttyName != nil)
        #expect(controller.terminal.sendKey(.a))
        #expect(controller.terminal.sendKey(.enter))
        let tty = controller.terminal.ttyName
        window.setContentSize(NSSize(width: 680, height: 380))
        module.fontSize = 20
        controller.module.fontSize = 20
        controller.module.opacity = 0.75
        controller.applyAppearance()
        #expect(controller.terminal.ttyName == tty)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try capture(window, name: "borderless-inherited")

        let independent = try ModuleWindow(module: module,
            configuration: "font-size = 18\nbackground = 18232d\nforeground = b7dfca\nbackground-opacity = 1")
        defer { independent.window?.close() }
        independent.present()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try capture(try #require(independent.window), name: "borderless-independent")

        let settings = SettingsDialog(AppSettings())
        settings.alert.window.appearance = NSAppearance(named: .aqua)
        settings.alert.layout()
        #expect(settings.skipTmux.state == .on)
        settings.skipTmux.performClick(nil)
        #expect(settings.skipTmux.state == .off)
        settings.skipTmux.performClick(nil)
        #expect(settings.selectedDragModifiers == AppSettings().dragModifiers)
        settings.modifierButtons.forEach { $0.1.state = .off }
        #expect(settings.selectedDragModifiers == 0)
        settings.modifierButtons[3].1.performClick(nil)
        #expect(settings.selectedDragModifiers == NSEvent.ModifierFlags.control.rawValue)
        #expect(settings.skipTmux.isEnabled && !settings.skipTmux.isHidden)
        #expect(settings.alert.buttons.map(\.title) == ["保存", "取消"])
        #expect(settings.alert.buttons.allSatisfy { !$0.isHidden && $0.isEnabled })
        settings.alert.window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try capture(settings.alert.window, name: "settings")
        settings.alert.window.orderOut(nil)

        let sizeDialog = PanelSizeDialog(size: window.frame.size, maximum: NSSize(width: 1440, height: 900))
        sizeDialog.alert.window.appearance = NSAppearance(named: .aqua)
        sizeDialog.width.stringValue = "800"
        sizeDialog.height.stringValue = "450"
        #expect(try sizeDialog.selectedSize() == NSSize(width: 800, height: 450))
        window.setContentSize(try sizeDialog.selectedSize())
        #expect(window.frame.size == NSSize(width: 800, height: 450))
        #expect(controller.terminal.ttyName == tty)
        #expect(NSRectFromString(try #require(controller.module.frame)).size == window.frame.size)
        sizeDialog.alert.layout()
        #expect(sizeDialog.alert.buttons.map(\.title) == ["应用", "取消"])
        sizeDialog.alert.window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try capture(sizeDialog.alert.window, name: "panel-size")
        sizeDialog.alert.window.orderOut(nil)
        for value in ["0", "NaN", "abc", "1500"] {
            sizeDialog.width.stringValue = value
            #expect(throws: (any Error).self) { try sizeDialog.selectedSize() }
        }
    }

    @MainActor private func capture(_ window: NSWindow, name: String) throws {
        try #require(window.isVisible)
        try #require(window.windowNumber > 0)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/verification")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let view = try #require(window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        if ProcessInfo.processInfo.environment["PINTERM_SCREEN_CAPTURE"] != nil {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), directory.appendingPathComponent("\(name)-screen.png").path]
            try capture.run()
            capture.waitUntilExit()
            #expect(capture.terminationStatus == 0)
        }
    }
}
