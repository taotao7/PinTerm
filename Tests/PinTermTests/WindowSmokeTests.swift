import AppKit
import GhosttyTerminal
import Testing
@testable import PinTerm

@Suite(.serialized)
struct WindowSmokeTests {
    /// Routes through WindowServer, unlike direct sendEvent tests. Moves the system pointer.
    @MainActor private func systemMouseResize() throws {
        try #require(CGPreflightPostEventAccess(), "Requires permission to post system mouse events")
        let app = NSApplication.shared
        var module = Module()
        module.command = "printf 'Mouse resize test\\n'; exec /bin/cat"
        let controller = try ModuleWindow(module: module, configuration: "background-opacity = 1")
        let window = try #require(controller.window)
        let screen = try #require(NSScreen.main)
        let rect = NSRect(x: (screen.visibleFrame.midX - 320).rounded(),
            y: (screen.visibleFrame.midY - 180).rounded(), width: 640, height: 360)
        // Catch any click-through in our own window, not a user's terminal or desktop.
        let backdrop = NSWindow(contentRect: rect.insetBy(dx: -100, dy: -100),
            styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.backgroundColor = .darkGray
        // Keep the test above previously created widgets, which now default to pinned.
        backdrop.level = window.level
        backdrop.orderFrontRegardless()
        window.setFrame(rect, display: true)
        controller.present()
        defer { window.close(); backdrop.close() }
        let displayHeight = try #require(NSScreen.screens.first).frame.height
        let originalMouse = NSEvent.mouseLocation
        defer { CGWarpMouseCursorPosition(CGPoint(x: originalMouse.x, y: displayHeight - originalMouse.y)) }
        func pump(for duration: TimeInterval) {
            let deadline = Date().addingTimeInterval(duration)
            while Date() < deadline {
                if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) {
                    app.sendEvent(event)
                }
                app.updateWindows()
            }
        }
        pump(for: 1)
        let tty = controller.terminal.ttyName
        for (local, delta) in [(NSPoint(x: 636, y: 160), NSPoint(x: 60, y: 0)),
                               (NSPoint(x: 4, y: 160), NSPoint(x: -60, y: 0)),
                               (NSPoint(x: 320, y: 4), NSPoint(x: 0, y: -40)),
                               (NSPoint(x: 4, y: 4), NSPoint(x: -60, y: -40)),
                               (NSPoint(x: 4, y: 356), NSPoint(x: -60, y: 40)),
                               (NSPoint(x: 636, y: 356), NSPoint(x: 60, y: 40)),
                               (NSPoint(x: 636, y: 4), NSPoint(x: 60, y: -40)),
                               (NSPoint(x: 320, y: 356), NSPoint(x: 0, y: 40)),
                               (NSPoint(x: 320, y: 356), NSPoint(x: 0, y: -40)),
                               (NSPoint(x: 636, y: 356), NSPoint(x: -400, y: -240))] {
            window.setFrame(rect, display: true)
            pump(for: 0.2)
            let start = CGPoint(x: rect.minX + local.x, y: displayHeight - rect.minY - local.y)
            let end = CGPoint(x: start.x + delta.x, y: start.y - delta.y)
            DispatchQueue.global().async {
                for (type, point): (CGEventType, CGPoint) in [(.mouseMoved, start), (.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.15)
                }
            }
            pump(for: 1.5)
            #expect(window.frame.width == rect.width + (local.x < 8 ? -delta.x : delta.x))
            #expect(window.frame.height == rect.height + (local.y < 8 ? -delta.y : delta.y))
            #expect(window.frame.minX == rect.minX + (local.x < 8 ? delta.x : 0))
            #expect(window.frame.minY == rect.minY + (local.y < 8 ? delta.y : 0))
            #expect(NSRectFromString(try #require(controller.module.frame)) == window.frame)
            #expect(controller.terminal.ttyName == tty)
        }
        try capture(window, name: "system-mouse-resized")
    }

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

        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }
        NSApp.appearance = NSAppearance(named: .aqua)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        #expect(controller.terminal.controller?.effectiveColorScheme == .light)
        #expect(controller.terminal.controller?.renderedConfig.contains("background = #f5f0e8") == true)
        #expect(controller.terminal.ttyName == tty)
        try capture(window, name: "system-theme-light")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        #expect(controller.terminal.controller?.effectiveColorScheme == .dark)
        #expect(controller.terminal.controller?.renderedConfig.contains("background = #1a1d21") == true)
        #expect(controller.terminal.ttyName == tty)
        try capture(window, name: "system-theme-dark")
        controller.module.cornerRadius = 32
        controller.applyAppearance()
        #expect(window.contentView?.layer?.cornerRadius == 32)
        #expect(window.contentView?.layer?.masksToBounds == true)
        #expect(controller.terminal.ttyName == tty)
        try capture(window, name: "rounded-widget")

        var independentModule = module
        independentModule.id = UUID()
        let independent = try ModuleWindow(module: independentModule,
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
        #expect(settings.alert.buttons.map(\.title) == [L10n.text("保存", "Save"), L10n.text("取消", "Cancel")])
        #expect(settings.alert.buttons.allSatisfy { !$0.isHidden && $0.isEnabled })
        settings.alert.window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try capture(settings.alert.window, name: "settings")
        settings.alert.window.orderOut(nil)

        let oldLanguage = UserDefaults.standard.object(forKey: "interfaceLanguage")
        defer { UserDefaults.standard.set(oldLanguage, forKey: "interfaceLanguage") }
        let delegate = PinTermApp()
        for language in [AppLanguage.chinese, .english] {
            L10n.language = language
            #expect(UserDefaults.standard.string(forKey: "interfaceLanguage") == language.rawValue)
            delegate.rebuildMenus()
            let menu = try #require(NSApp.mainMenu?.items.first?.submenu)
            #expect(menu.items.first?.title == (language == .chinese ? "自定义模块…" : "Custom Widget…"))
            #expect(menu.items.first?.keyEquivalent == "n")
            let presets = try #require(menu.items.compactMap(\.submenu).first)
            #expect(presets.items.first?.representedObject as? String == "btop")
            #expect(presets.items.first?.title == (language == .chinese ? "系统监控" : "System Monitor"))
            controller.updateLocalizedText()
            #expect(handle.toolTip?.hasPrefix(language == .chinese ? "拖动" : "Drag") == true)
            #expect(controller.terminal.ttyName == tty)
            let localized = SettingsDialog(AppSettings())
            #expect(localized.alert.messageText == (language == .chinese ? "PinTerm 设置" : "PinTerm Settings"))
            #expect(localized.languagePicker.indexOfSelectedItem == AppLanguage.allCases.firstIndex(of: language))
            localized.alert.window.appearance = NSAppearance(named: .aqua)
            localized.alert.layout()
            localized.alert.window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            try capture(localized.alert.window, name: "settings-\(language.rawValue)")
            localized.alert.window.orderOut(nil)
            // Changing the picker is only a pending choice until settings are saved.
            let pending = SettingsDialog(AppSettings())
            pending.languagePicker.selectItem(at: 0)
            pending.alert.buttons[0].perform(#selector(NSButton.performClick(_:)), with: nil,
                afterDelay: 0.3, inModes: [.modalPanel, .default])
            let selection = try #require(pending.run())
            #expect(selection.language == .system)
            #expect(L10n.language == language)

            var captureError: (any Error)?
            let timer = Timer(timeInterval: 0.3, repeats: false) { _ in
                MainActor.assumeIsolated {
                    do { try capture(try #require(NSApp.modalWindow), name: "custom-\(language.rawValue)") }
                    catch { captureError = error }
                    NSApp.abortModal()
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            #expect(NSApp.sendAction(NSSelectorFromString("customModule"), to: delegate, from: nil))
            if let captureError { throw captureError }
        }

        let otherFrame = try #require(independent.window?.frame)
        #expect(terminalWindow.resizeEdges(at: NSPoint(x: 100, y: 100)).isEmpty)
        #expect(terminalWindow.resizeEdges(at: NSPoint(x: 100, y: window.frame.height - 4)) == .top)
        let baseline = window.frame
        // Exercise real window event dispatch for sides and all four corners.
        for (point, delta, expected): (NSPoint, NSPoint, NSRect) in [
            (NSPoint(x: 4, y: 100), NSPoint(x: -40, y: 0), NSRect(x: baseline.minX - 40, y: baseline.minY, width: 720, height: 380)),
            (NSPoint(x: 676, y: 100), NSPoint(x: 40, y: 0), NSRect(x: baseline.minX, y: baseline.minY, width: 720, height: 380)),
            (NSPoint(x: 100, y: 4), NSPoint(x: 0, y: -30), NSRect(x: baseline.minX, y: baseline.minY - 30, width: 680, height: 410)),
            (NSPoint(x: 100, y: 376), NSPoint(x: 0, y: 30), NSRect(x: baseline.minX, y: baseline.minY, width: 680, height: 410)),
            (NSPoint(x: 100, y: 376), NSPoint(x: 0, y: -30), NSRect(x: baseline.minX, y: baseline.minY, width: 680, height: 350)),
            (NSPoint(x: 100, y: 376), NSPoint(x: 0, y: -1000), NSRect(x: baseline.minX, y: baseline.minY, width: 680, height: 48)),
            (NSPoint(x: 4, y: 4), NSPoint(x: -40, y: -30), NSRect(x: baseline.minX - 40, y: baseline.minY - 30, width: 720, height: 410)),
            (NSPoint(x: 676, y: 4), NSPoint(x: 40, y: -30), NSRect(x: baseline.minX, y: baseline.minY - 30, width: 720, height: 410)),
            (NSPoint(x: 4, y: 376), NSPoint(x: -40, y: 30), NSRect(x: baseline.minX - 40, y: baseline.minY, width: 720, height: 410)),
            (NSPoint(x: 676, y: 376), NSPoint(x: 40, y: 30), NSRect(x: baseline.minX, y: baseline.minY, width: 720, height: 410)),
            (NSPoint(x: 4, y: 4), NSPoint(x: 1000, y: 1000), NSRect(x: baseline.maxX - 80, y: baseline.maxY - 48, width: 80, height: 48)),
        ] {
            window.setFrame(baseline, display: true)
            let start = window.convertPoint(toScreen: point)
            let end = NSPoint(x: start.x + delta.x, y: start.y + delta.y)
            for (type, screenPoint): (NSEvent.EventType, NSPoint) in [(.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
                window.sendEvent(try #require(NSEvent.mouseEvent(with: type,
                    location: window.convertPoint(fromScreen: screenPoint), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
            }
            #expect(window.frame == expected)
            #expect(NSRectFromString(try #require(controller.module.frame)) == expected)
            #expect(controller.terminal.ttyName == tty)
            #expect(independent.window?.frame == otherFrame)
            terminalWindow.updateWindowResize(to: NSPoint(x: 0, y: 0))
            #expect(window.frame == expected, "Mouse-up must end resizing")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModuleStore(url: directory.appendingPathComponent("modules.json"))
        try store.save([controller.module, independent.module])
        let saved = try store.load()
        #expect(saved == [controller.module, independent.module])
        for (module, expected) in zip(saved, [window.frame, otherFrame]) {
            let restored = try ModuleWindow(module: module, configuration: "")
            #expect(restored.window?.frame == expected)
            restored.present()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            #expect(restored.window?.frame == expected)
            restored.window?.close()
        }
        controller.present()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try capture(window, name: "mouse-resized")
        try widgetSelectionAndRestoration()
        if ProcessInfo.processInfo.environment["PINTERM_MOUSE_TEST"] != nil {
            try systemMouseResize()
        }
    }

    @MainActor private func widgetSelectionAndRestoration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config")
        try "background-opacity = 1".write(to: config, atomically: true, encoding: .utf8)
        let store = ModuleStore(url: directory.appendingPathComponent("modules.json"))
        let emptyApp = PinTermApp(store: store)
        try emptyApp.restoreModules(using: AppSettings())
        #expect(emptyApp.windows.isEmpty)
        #expect(try store.load().isEmpty)
        var first = Module()
        first.alwaysOnTop = false
        first.title = "Calendar"
        first.command = "printf 'Calendar widget\\n'; exec /bin/cat"
        first.configFile = config.path
        var second = first
        second.id = UUID()
        second.title = "Monitor"
        try store.save([first, second])
        var noRestore = AppSettings()
        noRestore.restoreWindows = false
        try emptyApp.restoreModules(using: noRestore)
        #expect(emptyApp.windows.isEmpty)
        #expect(try store.load().map(\.id) == [first.id, second.id])
        #expect(try store.load().allSatisfy { $0.isClosed == true })
        try store.save([first, second])
        let delegate = PinTermApp(store: store)
        try delegate.restoreModules(using: AppSettings())
        let controllers = delegate.windows
        defer { controllers.forEach { $0.onClose = nil; $0.onChange = nil; $0.window?.close() } }
        let calendar = try #require(controllers.first)
        let window = try #require(calendar.window)
        let original = window.frame
        let expected = NSRect(x: original.minX + 30, y: original.minY - 25, width: 510, height: 290)
        window.setFrame(expected, display: true)
        #expect(NSRectFromString(try #require(store.load().first?.frame)) == expected)
        let menu = try #require(NSApp.mainMenu?.items.first?.submenu)
        let choice = try #require(menu.items.first { $0.representedObject as? UUID == first.id })
        #expect(choice.title == "Calendar")
        menu.performActionForItem(at: menu.index(of: choice))
        #expect(delegate.windows.count == 2, "Selecting a widget must not create one")
        #expect(delegate.current === calendar)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let tty = try #require(calendar.terminal.ttyName)
        // A different window takes focus before the menu action.
        let other = NSWindow(contentRect: expected, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.title = "Other Window"
        other.level = .floating
        other.makeKeyAndOrderFront(nil)
        defer { other.close() }
        #expect(!window.isKeyWindow)
        #expect(delegate.current === calendar)
        delegate.menuWillOpen(menu)
        let pin = try #require(menu.items.first { $0.action == NSSelectorFromString("togglePin:") })
        #expect(pin.title.hasSuffix(": Calendar"))
        controllers[1].present()
        #expect(delegate.current === controllers[1])
        menu.performActionForItem(at: menu.index(of: pin))
        menu.update()
        #expect(pin.state == .on)
        #expect(calendar.module.alwaysOnTop)
        #expect(!controllers[1].module.alwaysOnTop)
        #expect(window.level.rawValue > other.level.rawValue)
        other.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let order = try #require(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])
        let ids = order.compactMap { $0[kCGWindowNumber as String] as? Int }
        let pinnedIndex = try #require(ids.firstIndex(of: window.windowNumber))
        let otherIndex = try #require(ids.firstIndex(of: other.windowNumber))
        #expect(pinnedIndex < otherIndex)
        #expect(calendar.terminal.ttyName == tty)
        #expect(try store.load().first?.alwaysOnTop == true)
        menu.performActionForItem(at: menu.index(of: pin))
        menu.update()
        #expect(pin.state == .off)
        #expect(window.level == .normal)
        #expect(try store.load().first?.alwaysOnTop == false)
        menu.performActionForItem(at: menu.index(of: pin))
        calendar.present()

        let pinAll = try #require(menu.items.first { $0.action == NSSelectorFromString("pinAll") })
        menu.performActionForItem(at: menu.index(of: pinAll))
        #expect(controllers.allSatisfy { $0.module.alwaysOnTop && $0.window?.level == .statusBar })
        #expect(try store.load().allSatisfy(\.alwaysOnTop))

        var renameError: (any Error)?
        let renameTimer = Timer(timeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated {
                do {
                    let modal = try #require(NSApp.modalWindow)
                    @MainActor func fields(_ view: NSView) -> [NSTextField] {
                        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
                    }
                    let content = try #require(modal.contentView)
                    let field = try #require(fields(content).first { $0.isEditable })
                    field.stringValue = "My Calendar"
                    try capture(modal, name: "rename-widget")
                    NSApp.stopModal(withCode: .alertFirstButtonReturn)
                } catch { renameError = error; NSApp.abortModal() }
            }
        }
        RunLoop.main.add(renameTimer, forMode: .modalPanel)
        #expect(NSApp.sendAction(NSSelectorFromString("renameCurrent"), to: delegate, from: nil))
        if let renameError { throw renameError }
        #expect(calendar.module.title == "My Calendar")
        #expect(calendar.module.command == first.command)
        #expect(calendar.terminal.ttyName == tty)
        let updated = try #require(NSApp.mainMenu?.items.first?.submenu)
        #expect(updated.items.first { $0.representedObject as? UUID == first.id }?.title == "My Calendar")

        // Run the real quit-save path, then restore through the real application path.
        let quitTimer = Timer(timeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
        }
        RunLoop.main.add(quitTimer, forMode: .modalPanel)
        #expect(delegate.applicationShouldTerminate(NSApp) == .terminateNow)
        controllers.forEach { $0.window?.close() }
        let restored = PinTermApp(store: store)
        try restored.restoreModules(using: AppSettings())
        defer { restored.windows.forEach { $0.onClose = nil; $0.onChange = nil; $0.window?.close() } }
        let restoredCalendar = try #require(restored.windows.first)
        #expect(restoredCalendar.window?.frame == expected)
        #expect(restoredCalendar.module.title == "My Calendar")
        #expect(restoredCalendar.module.alwaysOnTop)
        #expect(restoredCalendar.window?.level == .statusBar)
        #expect(restored.windows.count == 2)
        let small = NSRect(x: expected.minX, y: expected.minY, width: 240, height: 120)
        restoredCalendar.window?.setFrame(small, display: true)
        let closeTimer = Timer(timeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
        }
        RunLoop.main.add(closeTimer, forMode: .modalPanel)
        restoredCalendar.requestClose()
        #expect(restored.windows.count == 1)
        let closed = try #require(store.load().first { $0.id == first.id })
        #expect(closed.isClosed == true)
        #expect(NSRectFromString(try #require(closed.frame)) == small)
        // Closed records survive an application restart without opening themselves.
        restored.windows.forEach { $0.onClose = nil; $0.onChange = nil; $0.window?.close() }
        let relaunched = PinTermApp(store: store)
        try relaunched.restoreModules(using: AppSettings())
        defer { relaunched.windows.forEach { $0.onClose = nil; $0.onChange = nil; $0.window?.close() } }
        #expect(relaunched.windows.count == 1)
        let reopenedMenu = try #require(NSApp.mainMenu?.items.first?.submenu)
        let reopen = try #require(reopenedMenu.items.compactMap(\.submenu).first { menu in
            menu.items.contains { $0.action == NSSelectorFromString("reopenWidget:") }
        })
        let reopenItem = try #require(reopen.items.first { $0.representedObject as? UUID == first.id })
        #expect(reopenItem.title == "My Calendar")
        reopen.performActionForItem(at: reopen.index(of: reopenItem))
        let reopened = try #require(relaunched.windows.first { $0.module.id == first.id })
        #expect(reopened.window?.frame == small)
        #expect(reopened.module.alwaysOnTop)
        #expect(reopened.module.isClosed != true)
        #expect(try store.load().count == 2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        try capture(try #require(reopened.window), name: "small-reopened-widget")
        var offscreen = first
        offscreen.frame = "{{-99999, -99999}, {510, 290}}"
        let recovered = try ModuleWindow(module: offscreen, configuration: "")
        #expect(recovered.window?.frame.size == expected.size)
        recovered.window?.close()
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
