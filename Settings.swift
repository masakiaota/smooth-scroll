import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct PermissionsView: View {
    let failure: String?
    let start: () -> Void
    @State private var listening = CGPreflightListenEventAccess()
    @State private var accessibility = AXIsProcessTrusted() && CGPreflightPostEventAccess()
    @State private var requestedPanes: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SmoothScrollを使い始める").font(.title2.bold())
            Text("ホイール入力を受け取り、滑らかなスクロールに置き換えるために、2つの許可が必要です。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            permissionRow("入力監視", detail: "ホイールの動きを受け取ります。", granted: listening, pane: "Privacy_ListenEvent")
            permissionRow("アクセシビリティ", detail: "滑らかなスクロールを送信します。", granted: accessibility, pane: "Privacy_Accessibility")
            Text("各「許可をリクエスト」を押し、macOSの案内に従ってSmoothScrollを許可してください。確認画面が出ない場合は、同じボタンからシステム設定を開けます。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let failure {
                Text(failure).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("終了") { NSApp.terminate(nil) }
                Spacer()
                Button("状態を再確認", action: refresh)
                Button("開始する", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!listening || !accessibility)
            }
            Text("開始するまで、元のスクロール動作を維持します。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        listening = CGPreflightListenEventAccess()
        accessibility = AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, pane: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.title2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted { Text("許可済み").foregroundStyle(.secondary) }
            else {
                Button(requestedPanes.contains(pane) ? "設定を開く" : "許可をリクエスト") {
                    if requestedPanes.insert(pane).inserted {
                        if pane == "Privacy_ListenEvent" {
                            _ = CGRequestListenEventAccess()
                        } else {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
                            if trusted && !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
                        }
                        refresh()
                    } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }.accessibilityLabel("\(title)：\(requestedPanes.contains(pane) ? "設定を開く" : "許可をリクエスト")")
            }
        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

final class Settings: ObservableObject {
    private let defaults: UserDefaults
    @Published var excluded: [String] {
        didSet { defaults.set(excluded, forKey: "excludedApps") }
    }
    @Published var loginEnabled = false
    @Published var loginMessage = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        excluded = defaults.stringArray(forKey: "excludedApps") ?? ["com.apple.Preview", "com.microsoft.Powerpoint"]
    }

    func initializeLogin() {
        if defaults.object(forKey: "loginInitialized") == nil {
            defaults.set(true, forKey: "loginInitialized")
            setLogin(true)
        } else {
            refreshLogin()
        }
    }

    func refreshLogin() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginMessage = status == .requiresApproval ? "macOSのログイン項目で許可が必要です。" : ""
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
        } catch {
            refreshLogin()
            loginMessage = "ログイン項目を変更できませんでした：\(error.localizedDescription)"
        }
    }

    func add(_ identifier: String) {
        guard !excluded.contains(identifier) else { return }
        excluded.append(identifier)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var selection: String?
    @State private var errorMessage: String?

    private func appURL(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    private func appName(_ id: String) -> String {
        if let url = appURL(id) { return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        return ["com.apple.Preview": "プレビュー", "com.microsoft.Powerpoint": "Microsoft PowerPoint"][id] ?? id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("平滑化しないアプリ").font(.title2.bold())
            Text("追加したアプリでは、元のスクロール動作を使います。")
                .foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(settings.excluded, id: \.self) { id in
                    HStack(spacing: 12) {
                        Image(nsImage: appURL(id).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(named: NSImage.applicationIconName)!)
                            .resizable().frame(width: 28, height: 28)
                        Text(appName(id)).lineLimit(1)
                        Spacer()
                    }.padding(.vertical, 5).tag(id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if settings.excluded.isEmpty {
                    Text("すべてのアプリで平滑化します")
                        .foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Button("アプリを追加…", action: selectApplication)
                Button("削除") {
                    if let selection { settings.excluded.removeAll { $0 == selection } }
                    selection = nil
                }.disabled(selection == nil)
                Spacer()
                Text("変更は自動保存されます").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("ログイン時に起動", isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLogin($0) }))
                .toggleStyle(.checkbox)
            if !settings.loginMessage.isEmpty {
                Text(settings.loginMessage).font(.callout).foregroundStyle(.secondary)
                Button("macOSのログイン項目を開く") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        .padding(24).frame(width: 480, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in settings.refreshLogin() }
        .alert("アプリを追加できません", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func selectApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "追加"
        panel.allowsMultipleSelection = true
        panel.begin { result in
            guard result == .OK else { return }
            for url in panel.urls {
                guard let id = Bundle(url: url)?.bundleIdentifier else {
                    errorMessage = "\(url.lastPathComponent)の識別情報を読み取れません。"
                    continue
                }
                settings.add(id)
                selection = id
            }
        }
    }
}
