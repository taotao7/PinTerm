import Foundation

/// Resolve file references before the wrapper moves the configuration to a temporary file.
/// Ghostty itself still parses and validates the resulting terminal configuration.
struct GhosttyConfiguration {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
    var themeDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/Resources/ghostty/themes"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ghostty.app/Contents/Resources/ghostty/themes"),
    ]

    var defaultFiles: [URL] {
        let xdgRoot = xdg.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        return [xdgRoot.appendingPathComponent("ghostty"),
            home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")]
            .flatMap { directory in ["config", "config.ghostty"].map { directory.appendingPathComponent($0) } }
    }

    func load(independentFile: String?, skipTmux: Bool = false) throws -> String {
        let roots = independentFile.map { [URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)] }
            ?? defaultFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        var output: [String] = []
        var queue = roots.map { ($0.standardizedFileURL, [URL]()) }
        var index = 0
        while index < queue.count {
            let (file, ancestors) = queue[index]
            index += 1
            guard !ancestors.contains(file), index <= 256 else {
                throw ConfigurationError(L10n.text("config-file 循环引用或引用过多：", "Circular or excessive config-file references: ") + file.path)
            }
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { output.append(line); continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let rawValue = parts[1].trimmingCharacters(in: .whitespaces)
                let value = rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"") && rawValue.count >= 2
                    ? String(rawValue.dropFirst().dropLast()) : rawValue
                if skipTmux, ["command", "initial-command"].contains(key),
                   value.range(of: #"(?<![A-Za-z0-9_.-])tmux(?![A-Za-z0-9_.-])"#, options: .regularExpression) != nil {
                    output.append("\(key) =")
                } else if key == "config-file" {
                    if value.isEmpty {
                        queue.removeSubrange(max(index, roots.count)..<queue.count)
                        continue
                    }
                    let optional = value.hasPrefix("?")
                    let path = optional ? String(value.dropFirst()) : value
                    let included = resolve(path, relativeTo: file.deletingLastPathComponent())
                    if !optional || FileManager.default.fileExists(atPath: included.path) {
                        queue.append((included, ancestors + [file]))
                    }
                } else if key == "theme", !value.isEmpty {
                    let variants = value.split(separator: ",").map(String.init)
                    let resolved = variants.map { variant -> String in
                        for prefix in ["light:", "dark:"] where variant.hasPrefix(prefix) {
                            return prefix + themePath(String(variant.dropFirst(prefix.count)), relativeTo: file.deletingLastPathComponent())
                        }
                        return themePath(variant, relativeTo: file.deletingLastPathComponent())
                    }
                    output.append("theme = " + resolved.joined(separator: ","))
                } else if ["custom-shader", "background-image"].contains(key), !value.isEmpty {
                    output.append("\(key) = \(resolve(value, relativeTo: file.deletingLastPathComponent()).path)")
                } else {
                    output.append(line)
                }
            }
        }
        return output.joined(separator: "\n")
    }

    static func selectingTheme(in configuration: String, dark: Bool) throws -> String {
        let prefix = dark ? "dark:" : "light:"
        return try configuration.components(separatedBy: .newlines).map { line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "theme",
                  let variant = parts[1].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
                    .first(where: { $0.hasPrefix(prefix) }) else { return line }
            let selected = String(variant.dropFirst(prefix.count))
            if FileManager.default.fileExists(atPath: selected) {
                return try String(contentsOfFile: selected, encoding: .utf8)
            }
            return "theme = " + selected
        }.joined(separator: "\n")
    }

    private func resolve(_ path: String, relativeTo directory: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : directory.appendingPathComponent(expanded)).standardizedFileURL
    }

    private func themePath(_ name: String, relativeTo directory: URL) -> String {
        if name.hasPrefix("/") || name.hasPrefix(".") || name.hasPrefix("~") {
            return resolve(name, relativeTo: directory).path
        }
        let userThemes = defaultFiles[0].deletingLastPathComponent().appendingPathComponent("themes")
        return ([userThemes] + themeDirectories).map { $0.appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0.path) }?.path ?? name
    }
}

struct ConfigurationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
