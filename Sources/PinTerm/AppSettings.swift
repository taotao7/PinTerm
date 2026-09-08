import AppKit

struct AppSettings: Codable, Equatable {
    var defaultCommand = ""
    var defaultDirectory = NSHomeDirectory()
    /// Empty means inherit the user's Ghostty config files.
    var independentConfig = ""
    var restoreWindows = true
    var skipTmux = true
    var dragModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue

    init() {}

    private enum CodingKeys: String, CodingKey {
        case defaultCommand, defaultDirectory, independentConfig, restoreWindows, skipTmux, dragModifiers
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultCommand = try values.decodeIfPresent(String.self, forKey: .defaultCommand) ?? ""
        defaultDirectory = try values.decodeIfPresent(String.self, forKey: .defaultDirectory) ?? NSHomeDirectory()
        independentConfig = try values.decodeIfPresent(String.self, forKey: .independentConfig) ?? ""
        restoreWindows = try values.decodeIfPresent(Bool.self, forKey: .restoreWindows) ?? true
        skipTmux = try values.decodeIfPresent(Bool.self, forKey: .skipTmux) ?? true
        dragModifiers = try values.decodeIfPresent(UInt.self, forKey: .dragModifiers)
            ?? NSEvent.ModifierFlags([.command, .shift]).rawValue
    }

    static var url: URL { ModuleStore.standard.url.deletingLastPathComponent().appendingPathComponent("settings.json") }

    static func load() throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
    }

    func newModule() -> Module {
        var module = Module()
        module.workingDirectory = defaultDirectory
        module.command = defaultCommand.isEmpty ? nil : defaultCommand
        return module
    }
}
