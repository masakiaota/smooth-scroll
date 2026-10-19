import AppKit

@main
struct InterfaceTests {
    static func spin(until condition: () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        precondition(condition(), "Timed out")
    }

    static func child(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = arguments
        try! process.run()
        return process
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "write" {
            let settings = Settings(defaults: UserDefaults(suiteName: args[1])!, synchronizesAcrossProcesses: true)
            settings.excluded = ["com.example.Changed"]
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
            return
        }
        if args.first == "window" {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let suite = "SmoothScroll.interface-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let delegate = InterfaceDelegate(mode: args[1], failure: nil, parentPID: getppid(), settings: Settings(defaults: defaults))
            app.delegate = delegate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                precondition(app.windows.contains { $0.isVisible }, "Interface did not open")
                defaults.removePersistentDomain(forName: suite)
                app.windows.first(where: { $0.isVisible })!.close()
            }
            withExtendedLifetime(delegate) { app.run() }
            fatalError("Closing the interface must exit")
        }
        if args.first == "orphan-parent" {
            let process = child(["orphan-window"])
            try! String(process.processIdentifier).write(toFile: args[1], atomically: true, encoding: .utf8)
            // Give the child time to install its parent monitor before exiting.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
            return
        }
        if args.first == "orphan-window" {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = InterfaceDelegate(mode: "permissions", failure: nil, parentPID: getppid())
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }

        let suite = "SmoothScroll.interface-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, synchronizesAcrossProcesses: true)
        let writer = child(["write", suite])
        spin(until: { settings.excluded == ["com.example.Changed"] })
        precondition(writer.isRunning, "Settings must propagate before the UI exits")
        spin(until: { !writer.isRunning })
        precondition(writer.terminationStatus == 0)
        defaults.set([], forKey: "excludedApps")
        settings.reloadExcluded()
        precondition(settings.excluded.isEmpty)

        for mode in ["settings", "permissions"] {
            for _ in 0..<3 {
                let process = child(["window", mode])
                spin(until: { !process.isRunning })
                precondition(process.terminationStatus == InterfaceResult.closed.rawValue)
            }
        }
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        let parent = child(["orphan-parent", pidFile])
        spin(until: { !parent.isRunning })
        precondition(parent.terminationStatus == 0)
        let orphanPID = Int32(try! String(contentsOfFile: pidFile, encoding: .utf8))!
        spin(until: { kill(orphanPID, 0) != 0 })
        print("interface-tests: ok (cross-process settings, close/reopen, parent exit)")
    }
}
