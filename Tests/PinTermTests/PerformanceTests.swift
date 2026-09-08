import AppKit
import Darwin
import Testing
@testable import PinTerm

/// Run alone with: PINTERM_PERF_TEST=1 swift test -c release --filter PerformanceTests
/// Measures the host process (including the test runner), not shell children or WindowServer.
@Suite(.serialized)
struct PerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PINTERM_PERF_TEST"] != nil))
    @MainActor func terminalResources() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        var windows: [ModuleWindow] = []
        defer { windows.forEach { $0.window?.close() } }
        func open(_ command: String, index: Int) throws {
            var module = Module()
            module.command = command
            let controller = try ModuleWindow(module: module,
                configuration: "font-size = 13\nbackground-opacity = 1\ncursor-style-blink = false")
            windows.append(controller)
            controller.present()
            controller.window?.setFrameOrigin(NSPoint(x: 60 + index * 150, y: 120 + index * 100))
        }
        func cpu() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        func sample(_ name: String) throws {
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            let start = Date()
            let before = cpu()
            RunLoop.current.run(until: Date().addingTimeInterval(10))
            let percent = (cpu() - before) / Date().timeIntervalSince(start) * 100
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "rss=", "-p", String(getpid())]
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let rss = Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            print(String(format: "PERF %@ CPU=%.2f%% RSS=%.1fMiB", name, percent, rss / 1024))
        }
        try sample("baseline")
        try open("exec /bin/zsh -f", index: 0)
        try sample("one-idle")
        for index in 1...3 { try open("exec /bin/zsh -f", index: index) }
        try sample("four-idle")
        windows.forEach { $0.window?.close() }
        windows.removeAll()
        for index in 0...3 {
            try open("while :; do printf '\\033[HCPU test: 20 redraws/sec\\n0123456789 abcdefghijklmnopqrstuvwxyz\\n'; sleep 0.05; done", index: index)
        }
        try sample("four-active-20Hz")
        windows.forEach { $0.window?.close() }
        windows.removeAll()
        try sample("after-close")
    }
}
