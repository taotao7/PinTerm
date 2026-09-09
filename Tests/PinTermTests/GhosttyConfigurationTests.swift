import AppKit
import Testing
@testable import PinTerm

struct GhosttyConfigurationTests {
    @Test func skipTmuxCommandsAndPersistSetting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("config")
        let original = "font-size = 19\ncommand = /bin/zsh\nconfig-file = child"
        try original.write(to: root, atomically: true, encoding: .utf8)
        try "command = /opt/homebrew/bin/tmux new-session -A\ninitial-command = /bin/sh -c 'exec tmux'".write(to: directory.appendingPathComponent("child"), atomically: true, encoding: .utf8)
        let loader = GhosttyConfiguration()
        #expect(try loader.load(independentFile: root.path).contains("exec tmux"))
        let filtered = try loader.load(independentFile: root.path, skipTmux: true)
        #expect(filtered == "font-size = 19\ncommand = /bin/zsh\ncommand =\ninitial-command =")
        #expect(try String(contentsOf: root, encoding: .utf8) == original)
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.skipTmux)
        #expect(settings.dragModifiers == AppSettings().dragModifiers)
        settings.skipTmux = false
        settings.dragModifiers = NSEvent.ModifierFlags.control.rawValue
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test func inheritanceOrderAndIndependentFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let loader = GhosttyConfiguration(home: home, xdg: nil, themeDirectories: [])
        for (index, url) in loader.defaultFiles.enumerated() {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "font-size = \(10 + index)".write(to: url, atomically: true, encoding: .utf8)
        }
        #expect(try loader.load(independentFile: nil) == "font-size = 10\nfont-size = 11\nfont-size = 12\nfont-size = 13")
        #expect(try loader.load(independentFile: loader.defaultFiles[0].path) == "font-size = 10")
    }

    @Test func includesThemesAndRelativeResources() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let loader = GhosttyConfiguration(home: home, xdg: nil, themeDirectories: [])
        let root = loader.defaultFiles[0]
        let directory = root.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("themes"), withIntermediateDirectories: true)
        try "background = 112233".write(to: directory.appendingPathComponent("themes/Test"), atomically: true, encoding: .utf8)
        try "font-size = 21".write(to: directory.appendingPathComponent("child"), atomically: true, encoding: .utf8)
        try "config-file = child\nfont-size = 12\nconfig-file = ?missing\ntheme = light:Test,dark:Test\ncustom-shader = shader.glsl".write(to: root, atomically: true, encoding: .utf8)
        let result = try loader.load(independentFile: root.path)
        #expect(result.hasSuffix("font-size = 21"))
        #expect(!result.contains("config-file"))
        #expect(result.contains("theme = light:\(directory.path)/themes/Test,dark:\(directory.path)/themes/Test"))
        #expect(result.contains("custom-shader = \(directory.path)/shader.glsl"))
        try "config-file = config".write(to: directory.appendingPathComponent("child"), atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try loader.load(independentFile: root.path) }
        try "config-file = missing\nconfig-file =\nconfig-file = \"child\"".write(to: root, atomically: true, encoding: .utf8)
        try "font-size = 22".write(to: directory.appendingPathComponent("child"), atomically: true, encoding: .utf8)
        #expect(try loader.load(independentFile: root.path) == "font-size = 22")
    }

    @Test func defaultsAndOldModules() throws {
        var settings = AppSettings()
        #expect(Module().alwaysOnTop)
        #expect(settings.newModule().command == nil)
        #expect(settings.newModule().fontSize == nil)
        #expect(settings.newModule().opacity == nil)
        #expect(settings.cornerRadius == 0)
        settings.defaultCommand = "btop"
        settings.defaultDirectory = "/tmp"
        settings.cornerRadius = 32
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.newModule().command == "btop")
        #expect(decoded.newModule().workingDirectory == "/tmp")
        let old = Data("""
        {"id":"8EE58FE1-307C-4620-B515-F6FDF5037327","title":"Shell","workingDirectory":"/tmp","fontSize":18,"opacity":0.9,"alwaysOnTop":false}
        """.utf8)
        let module = try JSONDecoder().decode(Module.self, from: old)
        #expect(module.fontSize == 18)
        #expect(module.configFile == nil)
    }

    @Test func selectsThemeForSystemAppearance() throws {
        let configuration = "font-size = 14\ntheme = dark:/themes/night, light:/themes/day\ncursor-style = block"
        #expect(try GhosttyConfiguration.selectingTheme(in: configuration, dark: false)
            == "font-size = 14\ntheme = /themes/day\ncursor-style = block")
        #expect(try GhosttyConfiguration.selectingTheme(in: configuration, dark: true)
            == "font-size = 14\ntheme = /themes/night\ncursor-style = block")
        #expect(try GhosttyConfiguration.selectingTheme(in: "theme = Custom", dark: true) == "theme = Custom")
    }
}
