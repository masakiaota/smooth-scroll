import AppKit

// Deterministically insert another process's edit between reading a snapshot
// and applying it to Settings, without relying on scheduler timing.
final class ReloadRaceDefaults: UserDefaults {
    var afterRead: (() -> Void)?
    var writes = 0

    override func stringArray(forKey key: String) -> [String]? {
        let snapshot = super.stringArray(forKey: key)
        if key == "excludedApps", let afterRead {
            self.afterRead = nil
            afterRead()
        }
        return snapshot
    }

    override func set(_ value: Any?, forKey key: String) {
        if key == "excludedApps" { writes += 1 }
        super.set(value, forKey: key)
    }
}

@main
struct InterfaceTests {
    static func spin(until condition: () -> Bool, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        precondition(condition(), "Timed out", file: file, line: line)
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
        if args.first == "show" {
            InterfaceDelegate.requestShow(processIdentifier: Int32(args[1])!)
            return
        }
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
                let window = app.windows.first(where: { $0.isVisible })!
                if args[1] == "settings" {
                    window.miniaturize(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        precondition(window.isMiniaturized)
                        let requester = child(["show", String(getpid())])
                        let deadline = Date(timeIntervalSinceNow: 3)
                        // Return to the main queue so the notification can run.
                        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                            precondition(Date() < deadline, "Window was not restored")
                            guard !window.isMiniaturized, window.isVisible, !requester.isRunning else { return }
                            precondition(requester.terminationStatus == 0)
                            timer.invalidate()
                            defaults.removePersistentDomain(forName: suite)
                            window.close()
                        }
                    }
                    return
                }
                defaults.removePersistentDomain(forName: suite)
                window.close()
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

        let raceSuite = "SmoothScroll.interface-tests.\(UUID().uuidString)"
        let racingDefaults = ReloadRaceDefaults(suiteName: raceSuite)!
        defer { racingDefaults.removePersistentDomain(forName: raceSuite) }
        let receiver = Settings(defaults: racingDefaults)
        racingDefaults.set(["com.example.Snapshot"], forKey: "excludedApps")
        let writesBefore = racingDefaults.writes
        racingDefaults.afterRead = { [unowned racingDefaults] in
            racingDefaults.set(["com.example.NewerEdit"], forKey: "excludedApps")
        }
        receiver.reloadExcluded()
        precondition(receiver.excluded == ["com.example.Snapshot"])
        precondition(racingDefaults.stringArray(forKey: "excludedApps") == ["com.example.NewerEdit"])
        precondition(racingDefaults.writes == writesBefore + 1, "Reload must not write back")
        receiver.reloadExcluded()
        precondition(receiver.excluded == ["com.example.NewerEdit"])
        receiver.add("com.example.LocalEdit")
        precondition(racingDefaults.writes == writesBefore + 2, "Local edits must still persist")

        // Test the real executable's entry point, not only InterfaceDelegate.
        let executable = URL(fileURLWithPath: args.first ?? ".build/SmoothScroll-test-release")
        for arguments in [["--interface"], ["--interface", "invalid", "1"], ["--interface", "settings", "1"], ["--interface", "permissions", "not-a-pid"]] {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let errors = Pipe()
            process.standardError = errors
            try! process.run()
            spin(until: { !process.isRunning })
            precondition(process.terminationStatus == InterfaceResult.closed.rawValue)
            precondition(errors.fileHandleForReading.readDataToEndOfFile().isEmpty, "Invalid helper started resident initialization")
        }

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
        print("interface-tests: ok (settings sync/race, minimize/restore, close/reopen, helper entry, parent exit)")
    }
}
