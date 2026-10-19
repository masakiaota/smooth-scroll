import AppKit
import SwiftUI

// Only this short-lived process creates SwiftUI views. Exiting returns all UI
// caches to the OS, including allocations retained by the system frameworks.
enum InterfaceResult: Int32 {
    case closed = 0
    case ready = 10
    case restart = 11
    case quit = 12
}

final class InterfaceDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings: Settings
    private let mode: String
    private let failure: String?
    private let parentPID: pid_t
    private var parentMonitor: DispatchSourceProcess?
    private var showObserver: NSObjectProtocol?
    private var window: NSWindow?
    private static let showNotification = Notification.Name("com.masakiaota.smooth-scroll.showInterface")

    static func requestShow(processIdentifier: pid_t) {
        DistributedNotificationCenter.default().postNotificationName(showNotification, object: String(processIdentifier), userInfo: nil, deliverImmediately: true)
    }

    deinit {
        if let showObserver { DistributedNotificationCenter.default().removeObserver(showObserver) }
    }

    init(mode: String, failure: String?, parentPID: pid_t, settings: Settings = Settings(synchronizesAcrossProcesses: true)) {
        self.settings = settings
        self.mode = mode
        self.failure = failure
        self.parentPID = parentPID
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also close if the resident process is killed rather than quit normally.
        let monitor = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: .main)
        monitor.setEventHandler { Self.finish(.closed) }
        monitor.resume()
        parentMonitor = monitor
        if getppid() != parentPID { Self.finish(.closed) }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 478), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        showObserver = DistributedNotificationCenter.default().addObserver(forName: Self.showNotification, object: String(getpid()), queue: .main) { [weak self] _ in
            self?.showWindow()
        }
        if mode == "settings" {
            settings.refreshLogin()
            window.title = "SmoothScroll 設定"
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        } else {
            window.title = "SmoothScrollの準備"
            let view = NSHostingView(rootView: PermissionsView(
                failure: failure,
                start: { Self.finish(.ready) },
                restart: { Self.finish(.restart) },
                quit: { Self.finish(.quit) }
            ))
            window.contentView = view
            window.setContentSize(view.fittingSize)
        }
        window.center()
        showWindow()
    }

    private func showWindow() {
        window?.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { Self.finish(.closed) }

    private static func finish(_ result: InterfaceResult) {
        UserDefaults.standard.synchronize()
        exit(result.rawValue)
    }
}

func runInterface(mode: String, failure: String?, parentPID: pid_t) {
    let app = NSApplication.shared
    let delegate = InterfaceDelegate(mode: mode, failure: failure, parentPID: parentPID)
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
