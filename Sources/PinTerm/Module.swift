import Foundation

struct Module: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "Shell"
    var workingDirectory = NSHomeDirectory()
    var command: String?
    var configFile: String?
    var fontSize: Float?
    var opacity: Double?
    var alwaysOnTop = false
    var frame: String?

    /// Run compound user commands consistently, regardless of Ghostty's command parser.
    var launchCommand: String? {
        command.map { "/bin/sh -c '" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    }

    func validate() throws {
        guard fontSize.map({ (8...48).contains($0) }) ?? true,
              opacity.map({ (0.25...1).contains($0) }) ?? true,
              workingDirectory.hasPrefix("/") else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

struct ModuleStore {
    let url: URL

    static var standard: ModuleStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ModuleStore(url: directory.appendingPathComponent("PinTerm/modules.json"))
    }

    func load() throws -> [Module] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let modules = try JSONDecoder().decode([Module].self, from: Data(contentsOf: url))
        try modules.forEach { try $0.validate() }
        guard Set(modules.map(\.id)).count == modules.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return modules
    }

    func save(_ modules: [Module]) throws {
        try modules.forEach { try $0.validate() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(modules).write(to: url, options: .atomic)
    }
}
