import Foundation
import Testing
@testable import PinTerm

struct ModuleStoreTests {
    @Test func emptyCommandInheritsGhostty() {
        #expect(Module().launchCommand == nil)
    }

    @Test(.enabled(if: getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } == "/bin/zsh"))
    func zshCommandLoadsStartupEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "export PINTERM_PROFILE=loaded\n".write(to: directory.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
        try "export PATH=\"$ZDOTDIR/bin:$PATH\"\nalias widget_tool=fixture-tool\n".write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let tool = bin.appendingPathComponent("fixture-tool")
        try "#!/bin/sh\nprintf '%s:%s' \"$PINTERM_PROFILE\" \"$1\"\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        var module = Module()
        module.command = "widget_tool \"it's working\" | /usr/bin/tr a-z A-Z; printf '!done'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", try #require(module.launchCommand)]
        process.environment = ["HOME": directory.path, "ZDOTDIR": directory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "xterm-256color"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: data, as: UTF8.self) == "LOADED:IT'S WORKING!done")
    }

    @Test func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModuleStore(url: directory.appendingPathComponent("modules.json"))
        #expect(try store.load().isEmpty)
        var module = Module()
        module.command = "ssh example.test"
        module.frame = "{{100, 200}, {640, 400}}"
        module.alwaysOnTop = true
        module.fontSize = 18
        module.opacity = 0.75
        try store.save([module, Module()])
        #expect(try store.load().first == module)
        #expect(try store.load().count == 2)
        try store.save([])
        #expect(try store.load().isEmpty)
    }

    @Test func rejectsInvalidConfiguration() throws {
        var module = Module()
        module.opacity = 2
        #expect(throws: (any Error).self) { try module.validate() }
        module.opacity = 0.9
        module.fontSize = 0
        #expect(throws: (any Error).self) { try module.validate() }
        module.fontSize = 14
        module.workingDirectory = "relative/path"
        #expect(throws: (any Error).self) { try module.validate() }
    }

    @Test func corruptFileIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ModuleStore(url: directory.appendingPathComponent("modules.json"))
        let original = Data("not json".utf8)
        try original.write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.url) == original)
        let module = Module()
        try store.save([module, module])
        #expect(throws: (any Error).self) { try store.load() }
    }
}
