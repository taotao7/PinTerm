import Foundation

struct Module: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "Shell"
    var workingDirectory = NSHomeDirectory()
    var command: String?
    var configFile: String?
    var fontSize: Float?
    var opacity: Double?
    var alwaysOnTop = true
    var frame: String?
    /// Nil in older files means the widget was open.
    var isClosed: Bool?

    /// Match a normal terminal's startup files, PATH, aliases, and shell syntax.
    var launchCommand: String? {
        guard let command else { return nil }
        let shell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        return "'" + shell.replacingOccurrences(of: "'", with: "'\\''")
            + "' -lic '" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
