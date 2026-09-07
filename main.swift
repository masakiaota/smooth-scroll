import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct Smoother {
    // Sixteen ticks at 120 Hz: about 133 ms. Delayed timer ticks can extend this.
    private var scheduled = Array(repeating: 0.0, count: 16)
    private let decay = 0.35
    var remaining: Double { scheduled.reduce(0, +) }

    mutating func add(_ delta: Int64) {
        guard delta != 0 else { return }
        // Normalize the decay curve so each input is fully emitted in sixteen ticks.
        let normalization = 1 - pow(1 - decay, Double(scheduled.count))
        var undistributed = Double(delta)
        for index in scheduled.indices {
            let step = index == scheduled.count - 1
                ? undistributed
                : Double(delta) * decay * pow(1 - decay, Double(index)) / normalization
            scheduled[index] += step
            undistributed -= step
        }
    }

    mutating func next() -> Double {
        let step = scheduled.removeFirst()
        scheduled.append(0)
        return step
    }
}

private let syntheticMarker: Int64 = 0x534D_4F4F_5448

final class AppState {
    let settings: Settings
    var tap: CFMachPort?
    private var targetPID: pid_t?
    init(settings: Settings) { self.settings = settings }
    var verticalSmoother = Smoother()
    var horizontalSmoother = Smoother()

    func reset() {
        verticalSmoother = Smoother()
        horizontalSmoother = Smoother()
        targetPID = nil
    }

    // Window bounds and CGEvent locations both use global display coordinates.
    func target(at point: CGPoint) -> NSRunningApplication? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? Int32 else { continue }
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }

    func accepts(_ app: NSRunningApplication?) -> Bool {
        guard let app, let id = app.bundleIdentifier else { return false }
        return app.processIdentifier != ProcessInfo.processInfo.processIdentifier && !settings.excluded.contains(id)
    }

    func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        // Never consume physical input if synthetic output is not permitted.
        guard CGPreflightPostEventAccess() && AXIsProcessTrusted() else {
            reset()
            return Unmanaged.passUnretained(event)
        }

        let app = target(at: event.location)
        if targetPID != app?.processIdentifier { reset() }
        guard accepts(app) else {
            reset()
            return Unmanaged.passUnretained(event)
        }

        let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pointX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        guard (pointY != 0 || pointX != 0), phase == 0, momentum == 0 else {
            reset()
            return Unmanaged.passUnretained(event)
        }

        targetPID = app?.processIdentifier
        verticalSmoother.add(pointY)
        horizontalSmoother.add(pointX)
        return nil
    }

    func emitNext() {
        guard let targetPID else { return }
        guard CGPreflightPostEventAccess() && AXIsProcessTrusted(),
              let pointer = CGEvent(source: nil) else { reset(); return }
        let app = target(at: pointer.location)
        guard app?.processIdentifier == targetPID, accepts(app) else { reset(); return }
        let verticalStep = verticalSmoother.next()
        let horizontalStep = horizontalSmoother.next()
        guard verticalStep != 0 || horizontalStep != 0,
              let event = CGEvent(
                  scrollWheelEvent2Source: nil,
                  units: .pixel,
                  wheelCount: 2,
                  wheel1: Int32(max(Double(Int32.min), min(Double(Int32.max), verticalStep.rounded(.towardZero)))),
                  wheel2: Int32(max(Double(Int32.min), min(Double(Int32.max), horizontalStep.rounded(.towardZero)))),
                  wheel3: 0
              ) else { return }
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: verticalStep)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontalStep)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: verticalStep)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontalStep)
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // Use the system routing that worked in the original MVP.
        event.post(tap: .cghidEventTap)
        if verticalSmoother.remaining == 0 && horizontalSmoother.remaining == 0 { reset() }
    }
}

func runSelfTest() {
    var smoother = Smoother()
    smoother.add(13)
    var total = smoother.next()
    var parts = 1
    precondition(total > 4.55 && total < 4.57)
    while true {
        let step = smoother.next()
        if step == 0 { break }
        total += step
        parts += 1
        precondition(parts < 1000)
    }
    precondition(abs(total - 13) < 1e-9 && parts == 16)

    // Overlapping inputs, including reversal, preserve their signed total.
    total = 0
    var inputTotal = 0.0
    for delta: Int64 in [10000, 20000, -5000, 1, -13] {
        smoother.add(delta)
        inputTotal += Double(delta)
        total += smoother.next()
    }
    for _ in 0..<16 { total += smoother.next() }
    precondition(abs(total - inputTotal) < 1e-8 && smoother.remaining == 0)
    precondition(smoother.next() == 0)
    let suite = "SmoothScroll.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = Settings(defaults: defaults)
    precondition(settings.excluded.contains("com.apple.Preview"))
    settings.excluded = []
    precondition(Settings(defaults: defaults).excluded.isEmpty)
    settings.add("com.example.Test")
    settings.add("com.example.Test")
    precondition(settings.excluded == ["com.example.Test"])
    let state = AppState(settings: settings)
    state.verticalSmoother.add(13)
    state.horizontalSmoother.add(13)
    state.reset()
    precondition(state.verticalSmoother.next() == 0 && state.horizontalSmoother.next() == 0)
    print("self-test: ok")
}

let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<AppState>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        state.reset()
        if let tap = state.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }
    return state.handle(event)
}

final class SmoothScrollApplicationDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private lazy var state = AppState(settings: settings)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.masakiaota.smooth-scroll").count > 1 {
            NSApp.terminate(nil)
            return
        }
        installStatusMenu()
        beginIfPermitted()
    }

    private func beginIfPermitted() {
        let accessibility = AXIsProcessTrusted()
        let posting = CGPreflightPostEventAccess()
        NSLog("Permission check: accessibility=%d post=%d", accessibility ? 1 : 0, posting ? 1 : 0)
        // Accessibility grants both event listening and posting.
        guard accessibility else {
            showPermissions()
            return
        }
        // The AX prompt is asynchronous; request posting only after AX approval.
        guard posting || CGRequestPostEventAccess() else {
            showPermissions(failure: "アクセシビリティは許可済みですが、イベント送信をまだ利用できません。macOSの確認画面に従い、再度「開始する」を押してください。反映されない場合は、権限をオンのままアプリを終了して起動し直してください。")
            return
        }
        guard startSmoothing() else {
            showPermissions(failure: "入力処理を開始できませんでした。許可を確認し、必要ならSmoothScrollを起動し直してください。")
            return
        }
        NSLog("Scroll processing started")
        permissionsWindow?.close()
        permissionsWindow = nil
        settings.initializeLogin()
        if !settings.loginMessage.isEmpty { showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    private func startSmoothing() -> Bool {
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(state).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        self.tap = tap
        state.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [state] _ in
            state.emitNext()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(named: "MenuIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        item.button?.image = image
        item.button?.toolTip = "SmoothScroll"
        item.button?.setAccessibilityLabel("SmoothScroll")
        let menu = NSMenu()
        let settingsItem = menu.addItem(withTitle: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        if tap == nil { showPermissions(); return }
        settings.refreshLogin()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 478), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "SmoothScroll 設定"
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showPermissions(failure: String? = nil) {
        if permissionsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "SmoothScrollの準備"
            window.isReleasedWhenClosed = false
            window.center()
            permissionsWindow = window
        }
        let content = NSHostingView(rootView: PermissionsView(failure: failure, start: { [weak self] in self?.beginIfPermitted() }, restart: { [weak self] in self?.restartApplication() }))
        permissionsWindow?.contentView = content
        permissionsWindow?.setContentSize(content.fittingSize)
        NSApp.activate(ignoringOtherApps: true)
        permissionsWindow?.makeKeyAndOrderFront(nil)
    }

    private func restartApplication() {
        // Wait for this process to exit before Launch Services opens the same bundle.
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; exec /usr/bin/open \"$2\"", "SmoothScroll-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            showPermissions(failure: "再起動できませんでした。SmoothScrollを終了し、アプリケーションフォルダから開いてください。")
        }
    }
}

func runApplication() {
    let app = NSApplication.shared
    let delegate = SmoothScrollApplicationDelegate()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

if Array(CommandLine.arguments.dropFirst()) == ["--self-test"] {
    runSelfTest()
} else if CommandLine.arguments.count == 3 && ["--preview-settings", "--preview-permissions"].contains(CommandLine.arguments[1]) {
    // Render without event interception or login-item registration.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let suite = "SmoothScroll.preview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = Settings(defaults: defaults)
    settings.loginEnabled = true
    let preview = CommandLine.arguments[1] == "--preview-permissions"
        ? AnyView(PermissionsView(failure: nil, start: {}))
        : AnyView(SettingsView(settings: settings))
    let view = NSHostingView(rootView: preview)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 478), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.setContentSize(view.fittingSize)
    window.display()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    defaults.removePersistentDomain(forName: suite)
} else {
    runApplication()
}
