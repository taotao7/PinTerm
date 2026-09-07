import Foundation

struct AppSettings: Codable, Equatable {
    var defaultCommand = ""
    var defaultDirectory = NSHomeDirectory()
    /// Empty means inherit the user's Ghostty config files.
    var independentConfig = ""
    var restoreWindows = true

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
