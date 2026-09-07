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
        settings.alert.layout()
        #expect(settings.skipTmux.state == .off)
        settings.skipTmux.performClick(nil)
        #expect(settings.skipTmux.state == .on)
        #expect(settings.skipTmux.isEnabled && !settings.skipTmux.isHidden)
        #expect(settings.alert.buttons.map(\.title) == ["保存", "取消"])
        #expect(settings.alert.buttons.allSatisfy { !$0.isHidden && $0.isEnabled })
        settings.alert.window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try capture(settings.alert.window, name: "settings")
        settings.alert.window.orderOut(nil)
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
    }
}
