import Foundation
import Testing
@testable import PinTerm

struct ModuleStoreTests {
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
