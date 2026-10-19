import AppKit
import SwiftUI

// Compare the same settings view retained in the resident process with a
// short-lived interface process. No event interception or login registration.
@main
struct MemoryBenchmark {
    static var window: NSWindow?
    static var interface: Process?
    static var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "SmoothScroll.memory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = Settings(defaults: defaults)
        settings.loginEnabled = true
        let mode = CommandLine.arguments[1]
        if mode == "interface" {
            let delegate = InterfaceDelegate(mode: "settings", failure: nil, parentPID: getppid(), settings: settings)
            app.delegate = delegate
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                defaults.removePersistentDomain(forName: suite)
                app.windows.first(where: { $0.isVisible })!.close()
            }
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        precondition(["retained", "isolated"].contains(mode))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "↕"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if mode == "retained" {
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 478), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                w.isReleasedWhenClosed = false
                w.contentView = NSHostingView(rootView: SettingsView(settings: settings))
                window = w
                w.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { w.close() }
            } else {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                process.arguments = ["interface"]
                try! process.run()
                interface = process
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            precondition(interface?.isRunning != true)
            print("ready: \(getpid())")
            fflush(stdout)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            defaults.removePersistentDomain(forName: suite)
            exit(0)
        }
        app.run()
    }
}
