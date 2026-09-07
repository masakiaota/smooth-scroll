import AppKit
import CoreGraphics
import Foundation

struct Smoother {
    private(set) var remaining = 0.0
    private let decay = 0.18
    private let maxStep = 48.0
    private let maxBacklog = 540.0
    private let stopThreshold = 0.01

    mutating func add(_ delta: Int64) {
        guard delta != 0 else { return }
        let bounded = min(max(Double(delta), -maxBacklog), maxBacklog)
        if remaining != 0 && (remaining > 0) != (bounded > 0) {
            remaining = bounded
        } else {
            // ponytail: Bound the tail; raise maxBacklog if fast scrolling feels too short.
            remaining = min(max(remaining + bounded, -maxBacklog), maxBacklog)
        }
    }

    mutating func next() -> Double {
        guard abs(remaining) >= stopThreshold else {
            remaining = 0
            return 0
        }
        let magnitude = min(maxStep, abs(remaining) * decay)
        let step = remaining > 0 ? magnitude : -magnitude
        remaining -= step
        return step
    }
}

private let syntheticMarker: Int64 = 0x534D_4F4F_5448

final class AppState {
    var verticalSmoother = Smoother()
    var horizontalSmoother = Smoother()

    func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pointX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        guard (pointY != 0 || pointX != 0), phase == 0, momentum == 0 else {
            return Unmanaged.passUnretained(event)
        }

        verticalSmoother.add(pointY)
        horizontalSmoother.add(pointX)
        return nil
    }

    func emitNext() {
        let verticalStep = verticalSmoother.next()
        let horizontalStep = horizontalSmoother.next()
        guard verticalStep != 0 || horizontalStep != 0,
              let event = CGEvent(
                  scrollWheelEvent2Source: nil,
                  units: .pixel,
                  wheelCount: 2,
                  wheel1: Int32(verticalStep.rounded(.towardZero)),
                  wheel2: Int32(horizontalStep.rounded(.towardZero)),
                  wheel3: 0
              ) else { return }
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: verticalStep)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontalStep)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: verticalStep)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontalStep)
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }
}

func runSelfTest() {
    var smoother = Smoother()
    smoother.add(13)
    var total = smoother.next()
    var parts = 1
    precondition(total > 2 && total < 3)
    while true {
        let step = smoother.next()
        if step == 0 { break }
        total += step
        parts += 1
        precondition(parts < 1000)
    }
    precondition(abs(total - 13) < 0.01 && parts > 1)

    smoother.add(100)
    precondition(smoother.next() > 0)
    smoother.add(-13)
    precondition(smoother.next() < 0)
    print("self-test: ok")
}

let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<AppState>.fromOpaque(userInfo).takeUnretainedValue()
    return state.handle(event)
}

final class SmoothScrollApplicationDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        guard requestPermissions(), startSmoothing() else {
            showFailure()
            NSApp.terminate(nil)
            return
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    private func requestPermissions() -> Bool {
        let canListen = CGPreflightListenEventAccess() || CGRequestListenEventAccess()
        let canPost = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        return canListen && canPost
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

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "SmoothScrollを終了",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func showFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SmoothScrollを開始できない"
        alert.informativeText = "システム設定の「プライバシーとセキュリティ」で、入力監視とアクセシビリティを許可してから、アプリを起動し直してください。"
        alert.runModal()
    }
}

func runApplication() {
    let app = NSApplication.shared
    let delegate = SmoothScrollApplicationDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}

if Array(CommandLine.arguments.dropFirst()) == ["--self-test"] {
    runSelfTest()
} else {
    runApplication()
}
