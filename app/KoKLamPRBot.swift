import SwiftUI
import AppKit
import UserNotifications

// MARK: - Native macOS Notification Center Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func send(title: String, subtitle: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if ok {
                let content = UNMutableNotificationContent()
                content.title = title
                content.subtitle = subtitle
                content.body = body
                content.sound = .default
                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(req) { err in
                    if err != nil {
                        self?.sendViaOsascript(title: title, subtitle: subtitle, body: body)
                    }
                }
            } else {
                if settings.authorizationStatus == .notDetermined {
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
                self?.sendViaOsascript(title: title, subtitle: subtitle, body: body)
            }
        }
    }

    private func sendViaOsascript(title: String, subtitle: String, body: String) {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
             .replacingOccurrences(of: "\n", with: " ")
        }
        var script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
        if !subtitle.isEmpty {
            script += " subtitle \"\(esc(subtitle))\""
        }
        script += " sound name \"Glass\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

// MARK: - Models

struct TokenUsage: Codable, Equatable, Sendable {
    let input_tokens: Int64
    let cached_tokens: Int64
    let output_tokens: Int64
    let total_tokens: Int64

    var netTokens: Int64 {
        let uncached = max(0, input_tokens - cached_tokens)
        return uncached + output_tokens
    }
}

struct DecisionItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let created_at: String
    let repo: String
    let short_repo: String?
    let number: Int
    let title: String
    let url: String
    let sha8: String
    let reason: String
    let question: String
    let context: String
    let agent_session: String?

    var displayRepo: String {
        if let s = short_repo, !s.isEmpty { return s }
        return String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct ResolvedDecision: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let resolved_at: String
    let repo: String
    let short_repo: String?
    let number: Int
    let title: String
    let url: String
    let question: String
    let reply_text: String
    let action: String
    let result_note: String

    var displayRepo: String {
        if let s = short_repo, !s.isEmpty { return s }
        return String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct ChatMessageItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let role: String
    let at: String
    let text: String
    let badge: String?
}

struct BotSnapshot: Codable, Equatable, Sendable {
    let status: String
    let paused: Bool
    let concurrency: Int
    let last_scan_at: String?
    let next_scan_in_sec: Int?
    let repos: [String]
    let active_tasks: [ActiveTask]
    let pending_queue: [QueuedTask]
    let open_prs: [OpenPR]
    let history: [HistoryItem]
    let logs: [String]
    let today_usage: TokenUsage?
    let total_usage: TokenUsage?
    let pending_decisions: [DecisionItem]?
    let resolved_decisions: [ResolvedDecision]?
    let chat_messages: [ChatMessageItem]?
}

struct PipelineStep: Codable, Equatable, Sendable {
    let name: String
    let status: String // done | running | failed | skipped
    let detail: String
    let duration_sec: Int
    let at: String
}

struct ActiveTask: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let worker_id: Int
    let repo: String
    let short_repo: String?
    let number: Int
    let title: String
    let url: String
    let sha8: String
    let source_kind: String?
    let trigger_info: String
    let stage: String
    let elapsed_sec: Int
    let live_lines: [String]?
    let steps: [PipelineStep]?

    var safeLiveLines: [String] { live_lines ?? [] }
    var displayRepo: String {
        if let s = short_repo, !s.isEmpty { return s }
        return String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct QueuedTask: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let repo: String
    let short_repo: String?
    let number: Int
    let title: String
    let url: String
    let sha8: String
    let trigger_info: String

    var displayRepo: String {
        if let s = short_repo, !s.isEmpty { return s }
        return String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct OpenPR: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let repo: String
    let short_repo: String?
    let number: Int
    let title: String
    let url: String
    let head: String
    let base: String
    let sha8: String
    let is_draft: Bool
    let reviewed: Bool
    let agent_session: String?

    var displayRepo: String {
        if let s = short_repo, !s.isEmpty { return s }
        return String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let finished_at: String
    let duration_sec: Int
    let ok: Bool
    let verdict: String?
    let outcome: String?
    let source_kind: String?
    let fixer_agent: String?
    let merged: Bool?
    let merge_note: String?
    let fix_dispatched: Bool?
    let fix_note: String?
    let test_checklist: [String]?
    let steps: [PipelineStep]?
    let usage: TokenUsage?
    let repo: String
    let short_repo: String?
    let number: Int
    let title: String
    let url: String
    let sha8: String
    let trigger_info: String
    let summary: String
    let body: String

    var displayRepo: String {
        if let s = short_repo, !s.isEmpty { return s }
        return String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct GitHubRelease: Codable, Sendable {
    let tag_name: String
    let html_url: String
}

struct BotConfigPayload: Codable, Equatable, Sendable {
    var repos: [String]
    var local_repo_map: [String: String]?
    var allowed_commenters: [String]?
    var auto_review: Bool
    var comment_trigger: Bool
    var auto_fix: Bool
    var auto_merge: Bool
    var fallback_new_session: Bool
    var live_status_comment: Bool?
    var skip_draft: Bool
    var github_app_id: String?
    var github_app_private_key: String?
    var fallback_fixer: String
    var max_fix_rounds: Int
    var review_agent: String?
    var review_model: String?
    var discovered_models: [String: [String]]?
    var reasoning_effort: String
    var poll_interval_seconds: Int
    var concurrency: Int
    var config_path: String?
}

enum PopoverTab: String, CaseIterable, Identifiable {
    case prs = "Open PR"
    case decisions = "待拍板"
    case running = "链路"
    case history = "历史"
    case logs = "日志"

    var id: String { rawValue }
}

// MARK: - Store

@MainActor
final class BotStore: ObservableObject {
    static let githubRepo = "wajipu/koklam-pr-bot"
    static let currentVersion: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"

    @Published var connected = false
    @Published var status = "idle"
    @Published var paused = false
    @Published var concurrency = 3
    @Published var nextScanInSec: Int? = nil
    @Published var activeTasks: [ActiveTask] = []
    @Published var pendingQueue: [QueuedTask] = []
    @Published var openPRs: [OpenPR] = []
    @Published var history: [HistoryItem] = []
    @Published var logs: [String] = []
    @Published var todayUsage: TokenUsage?
    @Published var totalUsage: TokenUsage?
    @Published var pendingDecisions: [DecisionItem] = []
    @Published var resolvedDecisions: [ResolvedDecision] = []
    @Published var chatMessages: [ChatMessageItem] = []
    @Published var toastMessage: String?
    @Published var lastError: String?

    // Update checker state
    @Published var latestVersion: String?
    @Published var latestReleaseURL: URL?
    @Published var checkingUpdate = false

    private let baseURL = URL(string: "http://127.0.0.1:18787")!
    private let localSession: URLSession
    private var pollTask: Task<Void, Never>?
    private var lastNotifiedHistoryID: String?
    private var initializedHistory = false
    private var consecutiveFailures = 0
    private var lastDaemonStartAttempt: Date = .distantPast
    @Published var startingDaemon = false

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        // Explicitly disable all system/Clash proxies for 127.0.0.1 IPC
        cfg.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0,
            "ProxyAutoDiscoveryEnable": 0
        ]
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 10
        cfg.waitsForConnectivity = false
        self.localSession = URLSession(configuration: cfg)
        NotificationDelegate.shared.setup()
        startPolling()
        checkForUpdates(silent: true)
    }

    func startPolling() {
        pollTask?.cancel()
        let session = self.localSession
        let statusURL = self.baseURL.appendingPathComponent("api/status")

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let result: Result<BotSnapshot, Error> = await Task.detached(priority: .utility) {
                    do {
                        let (data, resp) = try await session.data(from: statusURL)
                        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                            return .failure(NSError(domain: "HTTP", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"]))
                        }
                        return .success(try JSONDecoder().decode(BotSnapshot.self, from: data))
                    } catch {
                        return .failure(error)
                    }
                }.value

                guard let self else { return }
                switch result {
                case .success(let d):
                    self.consecutiveFailures = 0
                    self.lastError = nil
                    self.apply(d)
                case .failure(let err):
                    self.consecutiveFailures += 1
                    self.lastError = err.localizedDescription
                    if self.consecutiveFailures >= 3 && self.connected {
                        self.connected = false
                    }
                    if !self.connected && (self.consecutiveFailures == 1 || self.consecutiveFailures % 5 == 0) {
                        self.ensureDaemonRunning(force: false)
                    }
                }

                let sleepNs: UInt64 = self.activeTasks.isEmpty ? 3_000_000_000 : 1_500_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    func ensureDaemonRunning(force: Bool = false) {
        let now = Date()
        if !force && now.timeIntervalSince(lastDaemonStartAttempt) < 15 {
            return
        }
        lastDaemonStartAttempt = now
        startingDaemon = true

        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let uid = getuid()
            let plistPath = "\(home)/Library/LaunchAgents/com.wajipu.koklam-pr-bot.plist"

            var startedViaLaunchd = false
            if FileManager.default.fileExists(atPath: plistPath) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                p.arguments = ["bootstrap", "gui/\(uid)", plistPath]
                p.standardOutput = Pipe()
                p.standardError = Pipe()
                try? p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 {
                    startedViaLaunchd = true
                } else {
                    // Already bootstrapped — try kickstart
                    let k = Process()
                    k.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    k.arguments = ["kickstart", "gui/\(uid)/com.wajipu.koklam-pr-bot"]
                    k.standardOutput = Pipe()
                    k.standardError = Pipe()
                    try? k.run()
                    k.waitUntilExit()
                    startedViaLaunchd = (k.terminationStatus == 0)
                }
            }

            if !startedViaLaunchd {
                if let execURL = Bundle.main.executableURL {
                    let daemonURL = execURL.deletingLastPathComponent().appendingPathComponent("koklam-pr-botd")
                    if FileManager.default.isExecutableFile(atPath: daemonURL.path) {
                        let dataDir = "\(home)/.koklam-pr-bot"
                        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
                        let logPath = "\(dataDir)/bot.log"
                        if !FileManager.default.fileExists(atPath: logPath) {
                            FileManager.default.createFile(atPath: logPath, contents: nil)
                        }
                        let proc = Process()
                        proc.executableURL = daemonURL
                        var env = ProcessInfo.processInfo.environment
                        let extraPath = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                        env["PATH"] = extraPath + ":" + (env["PATH"] ?? "")
                        env["HOME"] = home
                        proc.environment = env
                        if let fh = FileHandle(forWritingAtPath: logPath) {
                            fh.seekToEndOfFile()
                            proc.standardOutput = fh
                            proc.standardError = fh
                        }
                        try? proc.run()
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { [weak self] in
                self?.startingDaemon = false
                self?.refreshNow()
            }
        }
    }

    private func apply(_ d: BotSnapshot) {
        if !connected { connected = true }
        if status != d.status { status = d.status }
        if paused != d.paused { paused = d.paused }
        if concurrency != d.concurrency { concurrency = d.concurrency }
        if nextScanInSec != d.next_scan_in_sec { nextScanInSec = d.next_scan_in_sec }
        if activeTasks != d.active_tasks { activeTasks = d.active_tasks }
        if pendingQueue != d.pending_queue { pendingQueue = d.pending_queue }
        if openPRs != d.open_prs { openPRs = d.open_prs }
        if history != d.history {
            if initializedHistory, let newest = d.history.first, newest.id != lastNotifiedHistoryID {
                notifyForHistory(newest)
            }
            lastNotifiedHistoryID = d.history.first?.id
            initializedHistory = true
            history = d.history
        } else if !initializedHistory {
            lastNotifiedHistoryID = d.history.first?.id
            initializedHistory = true
        }
        if logs != d.logs { logs = d.logs }
        if todayUsage != d.today_usage { todayUsage = d.today_usage }
        if totalUsage != d.total_usage { totalUsage = d.total_usage }
        let decs = d.pending_decisions ?? []
        if pendingDecisions != decs {
            if initializedHistory, let first = decs.first, !pendingDecisions.contains(where: { $0.id == first.id }) {
                NotificationDelegate.shared.send(
                    title: "🙋 需要你拍板 · \(first.displayRepo)#\(first.number)",
                    subtitle: first.title,
                    body: first.question
                )
            }
            pendingDecisions = decs
        }
        let resDecs = d.resolved_decisions ?? []
        if resolvedDecisions != resDecs { resolvedDecisions = resDecs }
        let chats = d.chat_messages ?? []
        if chatMessages != chats { chatMessages = chats }
    }

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            _ = await post(path: "api/chat", body: ["text": trimmed])
            refreshNow()
        }
    }

    private func notifyForHistory(_ item: HistoryItem) {
        let sub = "\(item.displayRepo)#\(item.number) (\(item.sha8)) · \(item.duration_sec)s"
        if !item.ok {
            NotificationDelegate.shared.send(title: "❌ Codex Review 失败", subtitle: sub, body: item.summary)
        } else if item.merged == true {
            let preview = (item.test_checklist?.prefix(2).joined(separator: "；")) ?? "无额外真机测试项"
            NotificationDelegate.shared.send(title: "🎉 PR 已通过并自动合并 · 请测试", subtitle: sub, body: "待测：\(preview)")
        } else if item.fix_dispatched == true {
            NotificationDelegate.shared.send(title: "🔧 已自动派回 Agent 修复", subtitle: sub, body: item.fix_note ?? item.summary)
        } else if item.verdict == "PASS" {
            NotificationDelegate.shared.send(title: "✅ Codex Review 通过", subtitle: sub, body: item.summary)
        } else {
            NotificationDelegate.shared.send(title: "⚠️ PR 建议修改后再合并", subtitle: sub, body: item.summary)
        }
    }

    func sendTestNotification() {
        NotificationDelegate.shared.send(
            title: "✅ KoKLam PR Bot 通知正常",
            subtitle: "原生 macOS 通知已启用",
            body: "PR 审查通过、自动派修或合并后都会在这里弹窗提醒"
        )
        showToast("已发送测试通知（如未弹出请在系统设置→通知开启 KoKLam PR Bot）")
    }

    func refreshNow() {
        let session = self.localSession
        let statusURL = self.baseURL.appendingPathComponent("api/status")
        Task {
            let decoded: BotSnapshot? = await Task.detached(priority: .userInitiated) {
                guard let (data, resp) = try? await session.data(from: statusURL),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return try? JSONDecoder().decode(BotSnapshot.self, from: data)
            }.value
            if let d = decoded { apply(d) }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        guard !checkingUpdate else { return }
        checkingUpdate = true
        let repo = Self.githubRepo
        let curVer = Self.currentVersion

        Task {
            let release: GitHubRelease? = await Task.detached(priority: .utility) {
                guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
                var req = URLRequest(url: url)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 8
                guard let (data, resp) = try? await URLSession.shared.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return try? JSONDecoder().decode(GitHubRelease.self, from: data)
            }.value

            self.checkingUpdate = false
            guard let rel = release else {
                if !silent { showToast("检查更新失败或暂无发布版本") }
                return
            }
            let cleanTag = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if cleanTag.compare(curVer, options: .numeric) == .orderedDescending {
                self.latestVersion = rel.tag_name
                self.latestReleaseURL = URL(string: rel.html_url)
                if !silent { showToast("发现新版本 \(rel.tag_name)") }
            } else {
                self.latestVersion = nil
                self.latestReleaseURL = URL(string: rel.html_url)
                if !silent { showToast("当前已是最新版 v\(curVer)") }
            }
        }
    }

    func openUpdateOrCheck() {
        if let url = latestReleaseURL, latestVersion != nil {
            NSWorkspace.shared.open(url)
        } else {
            checkForUpdates(silent: false)
        }
    }

    func triggerScan() {
        Task {
            await post(path: "api/scan", body: [:])
            showToast("已触发扫描")
            refreshNow()
        }
    }

    func togglePause() {
        Task {
            await post(path: "api/toggle-pause", body: [:])
            refreshNow()
        }
    }

    func triggerManualReview(repo: String, number: Int, note: String = "", agentSession: String = "") {
        Task {
            let ok = await post(path: "api/review", body: [
                "repo": repo,
                "number": number,
                "note": note,
                "agent_session": agentSession
            ])
            showToast(ok ? "已加入队列：\(repo.split(separator: "/").last ?? "")#\(number)" : "触发失败")
            refreshNow()
        }
    }

    func sendToAgentFix(repo: String, number: Int, reviewBody: String, agent: String, sessionID: String, note: String) {
        Task {
            let ok = await post(path: "api/fix", body: [
                "repo": repo,
                "number": number,
                "review_body": reviewBody,
                "agent": agent,
                "session_id": sessionID,
                "note": note
            ])
            showToast(ok ? "已发送给 \(agent) 修复：\(repo.split(separator: "/").last ?? "")#\(number)" : "发送修复失败")
            refreshNow()
        }
    }

    func mergePR(repo: String, number: Int) {
        Task {
            let ok = await post(path: "api/merge", body: [
                "repo": repo,
                "number": number
            ])
            showToast(ok ? "🎉 已合并 \(repo.split(separator: "/").last ?? "")#\(number)" : "合并失败，请检查日志/冲突")
            refreshNow()
        }
    }

    func syncStuckDecisions() {
        Task {
            let ok = await post(path: "api/decision/sync", body: [:])
            showToast(ok ? "已同步卡住的待拍板 PR" : "同步失败")
            refreshNow()
        }
    }

    func replyDecision(id: String, action: String, replyText: String = "") {
        Task {
            let ok = await post(path: "api/decision/reply", body: [
                "id": id,
                "action": action,
                "reply_text": replyText
            ])
            if action == "dismiss" {
                showToast(ok ? "已忽略该拍板项" : "操作失败")
            } else {
                showToast(ok ? "已授权并续接 Agent 执行" : "派发失败，请检查日志")
            }
            refreshNow()
        }
    }

    func fetchConfig() async -> BotConfigPayload? {
        let session = self.localSession
        let url = self.baseURL.appendingPathComponent("api/config")
        return await Task.detached(priority: .userInitiated) {
            guard let (data, resp) = try? await session.data(from: url),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try? JSONDecoder().decode(BotConfigPayload.self, from: data)
        }.value
    }

    func saveConfig(_ cfg: BotConfigPayload) async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/config"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(cfg)
        do {
            let (_, resp) = try await localSession.data(for: req)
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            if ok {
                showToast("设置已保存并生效")
                refreshNow()
            } else {
                showToast("保存设置失败")
            }
            return ok
        } catch {
            showToast("保存设置失败")
            return false
        }
    }

    @discardableResult
    private func post(path: String, body: [String: Any]) async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await localSession.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func showToast(_ msg: String) {
        toastMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toastMessage == msg { toastMessage = nil }
        }
    }

    var menuBarText: String {
        guard connected else { return "" }
        if !pendingDecisions.isEmpty { return "待批 \(pendingDecisions.count)" }
        if !activeTasks.isEmpty { return "\(activeTasks.count)/\(concurrency)" }
        return ""
    }

    var menuBarSymbol: String {
        guard connected else { return "exclamationmark.triangle" }
        if !pendingDecisions.isEmpty { return "questionmark.bubble.fill" }
        if !activeTasks.isEmpty { return "bolt.circle.fill" }
        if paused { return "pause.circle" }
        return "checkmark.bubble.fill"
    }
}

// MARK: - Popover UI

struct PopoverView: View {
    @ObservedObject var store: BotStore
    @State private var tab: PopoverTab = .prs
    @State private var expandedHistoryID: String?
    @State private var expandedTraceID: String?
    @State private var notePR: OpenPR?
    @State private var noteText = ""
    @State private var sessionText = ""

    @State private var fixTarget: HistoryItem?
    @State private var fixAgent = "codex"
    @State private var fixSessionID = ""
    @State private var fixNote = ""
    @State private var showClosedHistory = false
    @State private var showSettings = false
    @State private var decisionReplies: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            topHeader
            segmentedTabs
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.25)

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.25)
            footerBar
        }
        .frame(width: 440, height: 580)
        .overlay(alignment: .bottom) {
            if let msg = store.toastMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
                    .padding(.bottom, 46)
            }
        }
        .sheet(item: $notePR) { pr in
            VStack(alignment: .leading, spacing: 12) {
                Text("立即 Review \(pr.displayRepo)#\(pr.number)")
                    .font(.system(size: 14, weight: .bold))
                Text(pr.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                TextField("可选：重点关注项（留空直接审）", text: $noteText)
                    .textFieldStyle(.roundedBorder)
                TextField("可选：关联会话（claude / codex / agy / pi / opencode:<id>）", text: $sessionText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("取消") { notePR = nil; noteText = ""; sessionText = "" }
                    Button("开始 Review") {
                        store.triggerManualReview(repo: pr.repo, number: pr.number, note: noteText, agentSession: sessionText)
                        notePR = nil
                        noteText = ""
                        sessionText = ""
                        tab = .running
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 380)
        }
        .sheet(item: $fixTarget) { item in
            let agents: [(id: String, label: String)] = [
                ("codex", "Codex"),
                ("claude", "Claude"),
                ("agy", "agy"),
                ("pi", "Pi"),
                ("opencode", "OpenCode"),
            ]
            VStack(alignment: .leading, spacing: 12) {
                Text("发送 Review 建议给 Agent 修复")
                    .font(.system(size: 14, weight: .bold))
                Text("\(item.displayRepo)#\(item.number) — \(item.title)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("选择目标 Agent")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        ForEach(agents, id: \.id) { ag in
                            let sel = fixAgent == ag.id
                            Button {
                                fixAgent = ag.id
                            } label: {
                                Text(ag.label)
                                    .font(.system(size: 11.5, weight: sel ? .semibold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(sel ? Color.accentColor : Color.primary.opacity(0.08))
                                    )
                                    .foregroundStyle(sel ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("可选：会话 ID（留空则新开会话修复）", text: $fixSessionID)
                    .textFieldStyle(.roundedBorder)
                TextField("可选：附加指令（如：只修 P1 问题）", text: $fixNote)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("取消") { fixTarget = nil }
                    Button("发送给 \(fixAgent)") {
                        store.sendToAgentFix(
                            repo: item.repo,
                            number: item.number,
                            reviewBody: item.body,
                            agent: fixAgent,
                            sessionID: fixSessionID,
                            note: fixNote
                        )
                        fixTarget = nil
                        tab = .running
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 396)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(store: store) {
                showSettings = false
            }
        }
    }

    private var topHeader: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("KoKLam PR Bot")
                .font(.system(size: 14.5, weight: .bold))

            statusPill

            Spacer()

            Button {
                store.openUpdateOrCheck()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(store.latestVersion ?? "更新")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (store.latestVersion != nil ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.08)),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .help(store.latestVersion != nil ? "打开 GitHub 下载新版本" : "检查 GitHub Releases 更新")

            Button { store.sendTestNotification() } label: {
                Image(systemName: "bell")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("发送测试通知")

            Button { store.triggerScan() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("立即扫描 PR")
            .disabled(!store.connected)

            Button { store.togglePause() } label: {
                Image(systemName: store.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(store.paused ? "恢复轮询" : "暂停轮询")
            .disabled(!store.connected)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("设置")
            .disabled(!store.connected)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var statusPill: some View {
        let (color, label): (Color, String) = {
            guard store.connected else { return (.red, "未连接") }
            if !store.activeTasks.isEmpty { return (.orange, "审中 \(store.activeTasks.count)/\(store.concurrency)") }
            if store.status == "scanning" { return (.blue, "扫描中") }
            if store.paused { return (.gray, "已暂停") }
            return (.green, "监控中")
        }()

        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6.5, height: 6.5)
            Text(label).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }

    private var segmentedTabs: some View {
        HStack(spacing: 4) {
            ForEach(PopoverTab.allCases) { t in
                let isSel = tab == t
                let count = tabCount(t)
                Button {
                    tab = t
                } label: {
                    HStack(spacing: 4) {
                        Text(t.rawValue)
                            .font(.system(size: 12.5, weight: isSel ? .semibold : .regular))
                        if let count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(t == .running ? .orange : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSel ? Color.white.opacity(0.14) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tabCount(_ t: PopoverTab) -> Int? {
        guard store.connected else { return nil }
        switch t {
        case .prs: return store.openPRs.count
        case .decisions: return store.pendingDecisions.count
        case .running: return store.activeTasks.count + store.pendingQueue.count
        case .history: return store.history.count
        case .logs: return nil
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if store.connected {
            switch tab {
            case .prs: prsListView
            case .decisions: decisionsTabView
            case .running: runningListView
            case .history: historyListView
            case .logs: logsListView
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "bolt.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("正在连接本地后台服务...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if let err = store.lastError {
                    Text(err)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                HStack(spacing: 8) {
                    Button(store.startingDaemon ? "正在启动..." : "启动后台服务") {
                        store.ensureDaemonRunning(force: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.startingDaemon)

                    Button("重试") { store.refreshNow() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var prsListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if !store.pendingDecisions.isEmpty {
                    decisionsBannerSection
                }
                if !store.activeTasks.isEmpty {
                    Button { tab = .running } label: {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在并行 Review \(store.activeTasks.count) 个 PR，点击查看")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }

                if store.openPRs.isEmpty {
                    Text("当前没有 Open PR")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(store.openPRs) { pr in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(pr.is_draft ? Color.gray : (pr.reviewed ? Color.green : Color.orange))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("\(pr.displayRepo)#\(pr.number)")
                                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                    Text(pr.sha8)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    if let sess = pr.agent_session {
                                        Text(sess.split(separator: ":").first.map(String.init) ?? "agent")
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.cyan.opacity(0.18), in: Capsule())
                                            .foregroundStyle(.cyan)
                                    }
                                }
                                Text(pr.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 6)

                            if let u = URL(string: pr.url) {
                                Link(destination: u) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11.5))
                                        .padding(6)
                                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }

                            Button("审") {
                                noteText = ""
                                sessionText = pr.agent_session ?? ""
                                notePR = pr
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(12)
        }
    }

    private var decisionsTabView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("待拍板 \(store.pendingDecisions.count) · 已处理 \(store.resolvedDecisions.count)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("拉取卡住 PR") {
                        store.syncStuckDecisions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if store.pendingDecisions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 26))
                            .foregroundStyle(.green.opacity(0.85))
                        Text("当前没有待你拍板的 PR 提问")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("当 PR 涉及跨范围/接口授权、达到修复上限或原会话不可恢复时，会自动在这里发起提问；你也可以点右上角「拉取卡住 PR」。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    decisionsBannerSection
                }

                if !store.resolvedDecisions.isEmpty {
                    Text("已处理决策记录")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(store.resolvedDecisions) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                if let u = URL(string: r.url) {
                                    Link("\(r.displayRepo)#\(r.number)", destination: u)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                }
                                Spacer()
                                Text(String(r.resolved_at.suffix(8)))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(r.question)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            if !r.reply_text.isEmpty {
                                HStack {
                                    Spacer()
                                    Text(r.reply_text)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                            }

                            Text("⚡ \(r.result_note)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(r.action == "merge" ? .purple : .cyan)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(12)
        }
    }

    private var decisionsBannerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.yellow)
                Text("需要你拍板授权 (\(store.pendingDecisions.count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)
                Spacer()
            }

            ForEach(store.pendingDecisions) { dec in
                let replyBinding = Binding<String>(
                    get: { decisionReplies[dec.id] ?? "" },
                    set: { decisionReplies[dec.id] = $0 }
                )
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        if let u = URL(string: dec.url) {
                            Link("\(dec.displayRepo)#\(dec.number)", destination: u)
                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        }
                        if let sess = dec.agent_session {
                            Text(sess.split(separator: ":").first.map(String.init) ?? "agent")
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.cyan.opacity(0.18), in: Capsule())
                                .foregroundStyle(.cyan)
                        }
                        Spacer()
                        Text(String(dec.created_at.suffix(8)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text(dec.question)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    TextField("输入授权/修改决定（如：授权增加内部选店回执）", text: replyBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))

                    HStack(spacing: 6) {
                        Button("授权并续接修复") {
                            let txt = decisionReplies[dec.id] ?? ""
                            store.replyDecision(id: dec.id, action: "authorize_fix", replyText: txt)
                            decisionReplies.removeValue(forKey: dec.id)
                            tab = .running
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)

                        Button("直接合并") {
                            store.mergePR(repo: dec.repo, number: dec.number)
                            store.replyDecision(id: dec.id, action: "dismiss")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Spacer()

                        Button("忽略") {
                            store.replyDecision(id: dec.id, action: "dismiss")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.yellow.opacity(0.4), lineWidth: 0.9))
            }
        }
        .padding(.bottom, 6)
    }

    private var runningListView: some View {
        let mergedCount = store.history.filter { $0.merged == true }.count
        let fixedCount = store.history.filter { $0.fix_dispatched == true }.count
        let activeSources = Set(store.activeTasks.compactMap(\.source_kind))
        let isReviewing = !store.activeTasks.isEmpty

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                // Summary Strip (like magpie's 路由 top line with token stats)
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReviewing ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text("今日 \(formatTokens(store.todayUsage?.netTokens ?? 0)) token · 累计 \(formatTokens(store.totalUsage?.netTokens ?? 0))")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("合并 \(mergedCount) · 派修 \(fixedCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)

                // Visual Topology Diagram (Source -> Bot -> Review / Fix / Merge)
                PipelineTopologyCard(
                    isReviewing: isReviewing,
                    activeCount: store.activeTasks.count,
                    activeSources: activeSources,
                    hasMerged: mergedCount > 0,
                    hasFixed: fixedCount > 0
                )

                // Live Active Pipelines
                ForEach(store.activeTasks) { t in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text("Worker #\(t.worker_id)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                            if let u = URL(string: t.url) {
                                Link("\(t.displayRepo)#\(t.number)", destination: u)
                                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            }
                            Text(sourceLabel(t.source_kind))
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                                .foregroundStyle(.secondary)
                            Spacer()
                            ProgressView().controlSize(.small)
                            Text("\(t.elapsed_sec)s")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let steps = t.steps, !steps.isEmpty {
                            stepChainRow(steps)
                        }

                        Text(t.safeLiveLines.isEmpty ? t.stage : t.safeLiveLines.suffix(5).joined(separator: "\n"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(5)
                            .padding(8)
                            .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(11)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.orange.opacity(0.45), lineWidth: 0.9))
                }

                if !store.pendingQueue.isEmpty {
                    Text("等待队列 (\(store.pendingQueue.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(store.pendingQueue) { q in
                        HStack {
                            Text("\(q.displayRepo)#\(q.number)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text(q.title).font(.system(size: 11.5)).lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            Text(q.sha8).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Recent Execution Trace Cards (magpie 路由 list style)
                if !store.history.isEmpty {
                    Text("最近链路轨迹")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    let openKeysTrace = Set(store.openPRs.map { "\($0.repo)#\($0.number)" })
                    ForEach(store.history.prefix(15)) { item in
                        let isExp = expandedTraceID == item.id
                        let isStillOpen = item.merged != true && openKeysTrace.contains("\(item.repo)#\(item.number)")
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                expandedTraceID = isExp ? nil : item.id
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(isStillOpen ? outcomeColor(item) : Color.purple)
                                            .frame(width: 7, height: 7)
                                        Text("\(item.displayRepo)#\(item.number)")
                                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.blue)
                                        Text(sourceLabel(item.source_kind))
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.primary.opacity(0.08), in: Capsule())
                                            .foregroundStyle(.secondary)
                                        Text(isStillOpen ? outcomeLabel(item) : "已合并/关闭")
                                            .font(.system(size: 10, weight: .semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background((isStillOpen ? outcomeColor(item) : Color.purple).opacity(0.18), in: Capsule())
                                            .foregroundStyle(isStillOpen ? outcomeColor(item) : Color.purple)
                                        Spacer()
                                        Text(String(item.finished_at.suffix(8)))
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Image(systemName: isExp ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let steps = item.steps, !steps.isEmpty {
                                        stepChainRow(steps)
                                    } else {
                                        Text("→ \(sourceLabel(item.source_kind)) → Codex Review → \(outcomeLabel(item))")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack {
                                        Text(item.title)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        if let u = item.usage, u.netTokens > 0 {
                                            Text("\(formatTokens(u.netTokens)) token ·")
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(.cyan.opacity(0.9))
                                        }
                                        Text("\(item.duration_sec)s")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isExp {
                                Divider().opacity(0.25)
                                if let steps = item.steps, !steps.isEmpty {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(Array(steps.enumerated()), id: \.offset) { _, st in
                                            let c: Color = st.status == "done" ? .green : (st.status == "running" ? .orange : .red)
                                            HStack(alignment: .top, spacing: 6) {
                                                Circle().fill(c).frame(width: 6, height: 6).padding(.top, 4)
                                                Text(st.name)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .frame(width: 62, alignment: .leading)
                                                Text(st.detail)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                if st.duration_sec > 0 {
                                                    Text("\(st.duration_sec)s")
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                                }

                                if let note = item.fix_note, !note.isEmpty {
                                    Text("🔧 \(note)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.blue)
                                }

                                ScrollView {
                                    Text(item.body)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 140)
                                .padding(8)
                                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

                                HStack(spacing: 6) {
                                    Text(item.sha8)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let u = URL(string: item.url) {
                                        Link("GitHub", destination: u)
                                            .font(.system(size: 11))
                                    }
                                    Button("复制指令") {
                                        let prompt = "请按以下 Codex PR Review 建议修复 PR \(item.repo)#\(item.number)（\(item.title)），修复后运行必要测试并 push 到该 PR 分支：\n\n\(item.body)"
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(prompt, forType: .string)
                                        store.showToast("已复制修复指令")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)

                                    if isStillOpen {
                                        Button("继续修复") {
                                            if let open = store.openPRs.first(where: { $0.repo == item.repo && $0.number == item.number }),
                                               let sess = open.agent_session,
                                               sess.contains(":") {
                                                let parts = sess.split(separator: ":", maxSplits: 1)
                                                fixAgent = String(parts[0])
                                                fixSessionID = String(parts[1])
                                            } else {
                                                fixAgent = item.fixer_agent ?? "codex"
                                                fixSessionID = ""
                                            }
                                            fixNote = ""
                                            fixTarget = item
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)

                                        Button("直接合并") {
                                            store.mergePR(repo: item.repo, number: item.number)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(12)
        }
    }

    private func stepChainRow(_ steps: [PipelineStep]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, st in
                    if idx > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    let c: Color = st.status == "done" ? .green : (st.status == "running" ? .orange : .red)
                    HStack(spacing: 3) {
                        Circle().fill(c).frame(width: 5, height: 5)
                        Text(st.name)
                            .font(.system(size: 10.5, weight: .medium))
                        if st.duration_sec > 0 {
                            Text("\(st.duration_sec)s")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(c.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func formatTokens(_ n: Int64) -> String {
        if n >= 10_000 {
            return String(format: "%.1f 万", Double(n) / 10_000.0)
        }
        if n >= 1_000 {
            return String(format: "%.1fk", Double(n) / 1_000.0)
        }
        return "\(n)"
    }

    private func sourceLabel(_ kind: String?) -> String {
        switch kind {
        case "comment": return "@评论"
        case "manual": return "手动"
        default: return "新PR"
        }
    }

    private func outcomeLabel(_ item: HistoryItem) -> String {
        if item.merged == true { return "已合并" }
        if item.fix_dispatched == true {
            return item.fixer_agent.map { "\($0) 派修" } ?? "已派修"
        }
        if !item.ok { return "失败" }
        if item.verdict == "PASS" { return "通过" }
        return "需修改"
    }

    private func outcomeColor(_ item: HistoryItem) -> Color {
        if item.merged == true { return .purple }
        if item.fix_dispatched == true { return .blue }
        if !item.ok { return .red }
        if item.verdict == "PASS" { return .green }
        return .orange
    }

    private var historyListView: some View {
        let openKeys = Set(store.openPRs.map { "\($0.repo)#\($0.number)" })
        let isOpenPR: (HistoryItem) -> Bool = { item in
            item.merged != true && openKeys.contains("\(item.repo)#\(item.number)")
        }
        let sortedAll = store.history.sorted { a, b in
            let oa = isOpenPR(a), ob = isOpenPR(b)
            if oa != ob { return oa }
            return a.finished_at > b.finished_at
        }
        // In "未合并" mode, deduplicate by PR (keep only the latest run per open PR)
        var seenPRs = Set<String>()
        var roundCounts: [String: Int] = [:]
        for h in sortedAll where isOpenPR(h) {
            let k = "\(h.repo)#\(h.number)"
            roundCounts[k, default: 0] += 1
        }
        let openLatest: [HistoryItem] = sortedAll.filter { h in
            guard isOpenPR(h) else { return false }
            let k = "\(h.repo)#\(h.number)"
            if seenPRs.contains(k) { return false }
            seenPRs.insert(k)
            return true
        }
        let visibleItems = showClosedHistory ? sortedAll : openLatest
        let hiddenCount = sortedAll.count - openLatest.count

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button("未合并 (\(openLatest.count))") {
                    showClosedHistory = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: !showClosedHistory ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(!showClosedHistory ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06), in: Capsule())

                Button("全部记录 (\(sortedAll.count))") {
                    showClosedHistory = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: showClosedHistory ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(showClosedHistory ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06), in: Capsule())

                Spacer()
                if hiddenCount > 0 && !showClosedHistory {
                    Text("已折叠 \(hiddenCount) 条旧轮次/已合并")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if visibleItems.isEmpty {
                        Text(showClosedHistory ? "暂无 Review 历史" : "当前没有未合并的 PR 审查记录（可切到「全部」查看已合并历史）")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 50)
                            .padding(.horizontal, 20)
                    } else {
                        ForEach(visibleItems) { item in
                            let openNow = isOpenPR(item)
                            let isExp = expandedHistoryID == item.id
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    expandedHistoryID = isExp ? nil : item.id
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(!openNow ? Color.gray : (item.ok ? Color.green : Color.red))
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text("\(item.displayRepo)#\(item.number)")
                                                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                                if !showClosedHistory, let rc = roundCounts["\(item.repo)#\(item.number)"], rc > 1 {
                                                    Text("×\(rc)")
                                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.primary.opacity(0.09), in: Capsule())
                                                        .foregroundStyle(.secondary)
                                                }
                                                if item.merged == true || !openNow {
                                                    Text(item.merged == true ? "已合并" : "已关闭/合并")
                                                        .font(.system(size: 9.5, weight: .semibold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(Color.purple.opacity(0.20), in: Capsule())
                                                        .foregroundStyle(.purple)
                                                } else if item.fix_dispatched == true {
                                                    Text("已派修")
                                                        .font(.system(size: 9.5, weight: .bold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(Color.blue.opacity(0.22), in: Capsule())
                                                        .foregroundStyle(.blue)
                                                }
                                                Text("\(item.duration_sec)s")
                                                    .font(.system(size: 10.5, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                if let u = item.usage, u.netTokens > 0 {
                                                    Text("\(formatTokens(u.netTokens)) tok")
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundStyle(.cyan.opacity(0.9))
                                                }
                                            }
                                            Text(item.summary)
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: isExp ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if isExp {
                                    Divider().opacity(0.25)
                                    if let tests = item.test_checklist, !tests.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("🧪 待测试功能清单")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.green)
                                                Spacer()
                                                Button("复制清单") {
                                                    let txt = tests.map { "- [ ] \($0)" }.joined(separator: "\n")
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(txt, forType: .string)
                                                    store.showToast("已复制待测试清单")
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.mini)
                                            }
                                            ForEach(Array(tests.enumerated()), id: \.offset) { _, t in
                                                Text("• \(t)")
                                                    .font(.system(size: 11))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    if let u = item.usage, u.total_tokens > 0 {
                                        let net = max(0, u.input_tokens - u.cached_tokens) + u.output_tokens
                                        Text("实际消耗：\(formatTokens(net))（新增输入 \(formatTokens(max(0, u.input_tokens - u.cached_tokens))) · 输出 \(formatTokens(u.output_tokens)) · 缓存命中 \(formatTokens(u.cached_tokens))）")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(.cyan.opacity(0.9))
                                    }
                                    if let note = item.fix_note, !note.isEmpty {
                                        Text("🔧 \(note)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.blue)
                                    }
                                    ScrollView {
                                        Text(item.body)
                                            .font(.system(size: 11, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .frame(maxHeight: 170)
                                    .padding(8)
                                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

                                    HStack(spacing: 6) {
                                        Text(String(item.finished_at.suffix(8)))
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if let u = URL(string: item.url) {
                                            Link("GitHub", destination: u).font(.system(size: 11))
                                        }
                                        Button("复制修复指令") {
                                            let prompt = "请按以下 Codex PR Review 建议修复 PR \(item.repo)#\(item.number)（\(item.title)），修复后运行必要测试并 push 到该 PR 分支：\n\n\(item.body)"
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(prompt, forType: .string)
                                            store.showToast("已复制修复指令，可直接粘贴给原 Agent 会话")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)

                                        if openNow {
                                            Button("发给 Agent") {
                                                if let open = store.openPRs.first(where: { $0.repo == item.repo && $0.number == item.number }),
                                                   let sess = open.agent_session,
                                                   sess.contains(":") {
                                                    let parts = sess.split(separator: ":", maxSplits: 1)
                                                    fixAgent = String(parts[0])
                                                    fixSessionID = String(parts[1])
                                                } else {
                                                    fixAgent = item.fixer_agent ?? "codex"
                                                    fixSessionID = ""
                                                }
                                                fixNote = ""
                                                fixTarget = item
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.mini)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .opacity(openNow ? 1.0 : 0.65)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var logsListView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("最近 \(store.logs.count) 条日志")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制全部") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.logs.joined(separator: "\n"), forType: .string)
                    store.showToast("已复制日志")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(store.logs.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private var footerBar: some View {
        HStack {
            if store.connected {
                let next = store.paused ? "轮询已暂停" : "下次扫描 \(store.nextScanInSec ?? 0)s"
                Text("v\(BotStore.currentVersion) · \(next) · 并发 \(store.concurrency)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                Text("v\(BotStore.currentVersion) · 后台未连接")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Settings Sheet (live edit config.json without touching code)

struct SettingsSheetView: View {
    @ObservedObject var store: BotStore
    let onClose: () -> Void

    @State private var cfg: BotConfigPayload?
    @State private var newRepo = ""
    @State private var newRepoPath = ""
    @State private var allowText = ""
    @State private var appIDText = ""
    @State private var appKeyPathText = ""
    @State private var reviewAgentText = "codex"
    @State private var reviewModelText = ""
    @State private var discoveredModels: [String: [String]] = [:]
    @State private var liveCommentOn = true
    @State private var saving = false

    private let efforts = ["low", "medium", "high", "max"]
    private let fixers = ["codex", "claude", "agy", "pi", "opencode"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("设置", systemImage: "gearshape.fill")
                    .font(.system(size: 14.5, weight: .bold))
                Spacer()
                if let p = cfg?.config_path {
                    Button("打开配置文件") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: p))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.25)

            if let c = Binding($cfg) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Toggles
                        VStack(alignment: .leading, spacing: 8) {
                            Text("自动化开关")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Toggle("新 PR / 新提交自动审查", isOn: c.auto_review)
                            Toggle("PR 评论 @koklam-pr-bot / @codex review 触发", isOn: c.comment_trigger)
                            Toggle("审查不通过时自动派回原会话修复", isOn: c.auto_fix)
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle("找不到原会话时自动新开会话修复", isOn: c.fallback_new_session)
                                Text("关闭时不会擅自新开会话，会发通知并在「待拍板」等你选择")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Toggle("审查通过自动合并 PR", isOn: c.auto_merge)
                            Toggle("开审先发 Working 占位评论并原地更新", isOn: $liveCommentOn)
                            Toggle("跳过草稿 PR (Draft)", isOn: c.skip_draft)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 12.5))

                        Divider().opacity(0.25)

                        // Parameters
                        VStack(alignment: .leading, spacing: 10) {
                            Text("执行参数")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("Review 引擎").font(.system(size: 12))
                                Spacer()
                                HStack(spacing: 4) {
                                    ForEach(fixers, id: \.self) { ag in
                                        let sel = reviewAgentText == ag
                                        Button(ag) {
                                            if reviewAgentText != ag {
                                                reviewAgentText = ag
                                                let avail = discoveredModels[ag] ?? []
                                                if !reviewModelText.isEmpty && !avail.contains(reviewModelText) {
                                                    reviewModelText = ""
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: sel ? .semibold : .regular))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(sel ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(sel ? .white : .primary)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                let modelsForAgent = discoveredModels[reviewAgentText] ?? []
                                HStack {
                                    Text("Review 模型（已自动读取 \(reviewAgentText) 配置 · \(modelsForAgent.count) 个）")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                Picker("", selection: Binding(
                                    get: {
                                        let cur = reviewModelText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if cur.isEmpty || modelsForAgent.contains(cur) { return cur }
                                        return "__custom__"
                                    },
                                    set: { val in
                                        if val != "__custom__" {
                                            reviewModelText = val
                                        }
                                    }
                                )) {
                                    Text("默认（跟随 \(reviewAgentText) CLI 配置）").tag("")
                                    ForEach(modelsForAgent, id: \.self) { m in
                                        Text(m).tag(m)
                                    }
                                    if !reviewModelText.isEmpty && !modelsForAgent.contains(reviewModelText) {
                                        Text("自定义: \(reviewModelText)").tag("__custom__")
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                TextField("留空使用 CLI 默认模型，或手动输入模型名", text: $reviewModelText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }

                            HStack {
                                Text("推理深度").font(.system(size: 12))
                                Spacer()
                                HStack(spacing: 4) {
                                    ForEach(efforts, id: \.self) { ef in
                                        let sel = (c.reasoning_effort.wrappedValue.isEmpty ? "high" : c.reasoning_effort.wrappedValue) == ef
                                        Button(ef) { c.reasoning_effort.wrappedValue = ef }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 11, weight: sel ? .semibold : .regular))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(sel ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                            .foregroundStyle(sel ? .white : .primary)
                                    }
                                }
                            }

                            HStack {
                                Text("新开会话修复 Agent").font(.system(size: 12))
                                Spacer()
                                HStack(spacing: 4) {
                                    ForEach(fixers, id: \.self) { ag in
                                        let sel = (c.fallback_fixer.wrappedValue.isEmpty ? "codex" : c.fallback_fixer.wrappedValue) == ag
                                        Button(ag) { c.fallback_fixer.wrappedValue = ag }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 11, weight: sel ? .semibold : .regular))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(sel ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                            .foregroundStyle(sel ? .white : .primary)
                                    }
                                }
                            }

                            HStack {
                                Text("最大自动修复轮数").font(.system(size: 12))
                                Spacer()
                                Stepper("\(c.max_fix_rounds.wrappedValue) 轮", value: c.max_fix_rounds, in: 1...10)
                                    .font(.system(size: 12, design: .monospaced))
                            }

                            HStack {
                                Text("轮询间隔").font(.system(size: 12))
                                Spacer()
                                Stepper("\(c.poll_interval_seconds.wrappedValue) 秒", value: c.poll_interval_seconds, in: 30...600, step: 30)
                                    .font(.system(size: 12, design: .monospaced))
                            }

                            HStack {
                                Text("并发上限（重启生效）").font(.system(size: 12))
                                Spacer()
                                Stepper("\(c.concurrency.wrappedValue) 个", value: c.concurrency, in: 1...5)
                                    .font(.system(size: 12, design: .monospaced))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("评论触发白名单（GitHub 用户名，逗号分隔，留空不限）")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                TextField("例如：wajipu", text: $allowText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("GitHub App [Bot] 身份（可选，填了就显示专属 Bot 头像和标签）")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    TextField("App ID", text: $appIDText)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .frame(width: 100)
                                    TextField("私钥路径（如 ~/.koklam-pr-bot/app.pem）", text: $appKeyPathText)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11.5, design: .monospaced))
                                }
                            }
                        }

                        Divider().opacity(0.25)

                        // Repos
                        VStack(alignment: .leading, spacing: 8) {
                            Text("监听仓库 (\(c.repos.wrappedValue.count))")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(c.repos.wrappedValue, id: \.self) { r in
                                HStack {
                                    Text(r)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        c.repos.wrappedValue.removeAll { $0 == r }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                            }

                            HStack(spacing: 6) {
                                TextField("owner/repo", text: $newRepo)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5))
                                TextField("可选：本地路径", text: $newRepoPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5))
                                Button("添加") {
                                    let r = newRepo.trimmingCharacters(in: .whitespaces)
                                    guard !r.isEmpty, r.contains("/") else { return }
                                    if !c.repos.wrappedValue.contains(r) {
                                        c.repos.wrappedValue.append(r)
                                    }
                                    let p = newRepoPath.trimmingCharacters(in: .whitespaces)
                                    if !p.isEmpty {
                                        var map = c.local_repo_map.wrappedValue ?? [:]
                                        map[r] = p
                                        c.local_repo_map.wrappedValue = map
                                    }
                                    newRepo = ""
                                    newRepoPath = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                ProgressView("加载配置中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider().opacity(0.25)

            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button(saving ? "保存中..." : "保存设置") {
                    guard var current = cfg else { return }
                    let parsed = allowText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    current.allowed_commenters = parsed
                    current.review_agent = reviewAgentText
                    current.review_model = reviewModelText.trimmingCharacters(in: .whitespacesAndNewlines)
                    current.discovered_models = nil
                    current.live_status_comment = liveCommentOn
                    current.github_app_id = appIDText.trimmingCharacters(in: .whitespacesAndNewlines)
                    current.github_app_private_key = appKeyPathText.trimmingCharacters(in: .whitespacesAndNewlines)
                    saving = true
                    Task {
                        _ = await store.saveConfig(current)
                        saving = false
                        onClose()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(cfg == nil || saving)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 400, height: 540)
        .task {
            let loaded = await store.fetchConfig()
            cfg = loaded
            allowText = (loaded?.allowed_commenters ?? []).joined(separator: ", ")
            reviewAgentText = (loaded?.review_agent?.isEmpty == false ? loaded?.review_agent : nil) ?? "codex"
            reviewModelText = loaded?.review_model ?? ""
            discoveredModels = loaded?.discovered_models ?? [:]
            liveCommentOn = loaded?.live_status_comment ?? true
            appIDText = loaded?.github_app_id ?? ""
            appKeyPathText = loaded?.github_app_private_key ?? ""
        }
    }
}

// MARK: - Visual Flow Topology Card (magpie-style Bezier diagram)

struct PipelineTopologyCard: View {
    let isReviewing: Bool
    let activeCount: Int
    let activeSources: Set<String>
    let hasMerged: Bool
    let hasFixed: Bool

    var body: some View {
        ZStack {
            // Smooth Bezier connectors
            Canvas { ctx, size in
                let midX = size.width * 0.48
                let midY = size.height * 0.5
                let leftX = size.width * 0.30
                let rightX = size.width * 0.66
                let ys: [CGFloat] = [size.height * 0.23, size.height * 0.50, size.height * 0.77]

                let leftActive = [
                    activeSources.contains("auto"),
                    activeSources.contains("comment"),
                    activeSources.contains("manual")
                ]
                let rightActive = [isReviewing, hasFixed, hasMerged]
                let rightColors: [Color] = [.orange, .blue, .purple]

                for (i, y) in ys.enumerated() {
                    var lp = Path()
                    lp.move(to: CGPoint(x: leftX, y: y))
                    lp.addCurve(
                        to: CGPoint(x: midX - 20, y: midY),
                        control1: CGPoint(x: (leftX + midX) * 0.5, y: y),
                        control2: CGPoint(x: (leftX + midX) * 0.5, y: midY)
                    )
                    ctx.stroke(lp, with: .color(leftActive[i] ? .cyan.opacity(0.85) : .white.opacity(0.14)), lineWidth: leftActive[i] ? 1.8 : 1.1)

                    var rp = Path()
                    rp.move(to: CGPoint(x: midX + 20, y: midY))
                    rp.addCurve(
                        to: CGPoint(x: rightX, y: y),
                        control1: CGPoint(x: (midX + rightX) * 0.5, y: midY),
                        control2: CGPoint(x: (midX + rightX) * 0.5, y: y)
                    )
                    ctx.stroke(rp, with: .color(rightActive[i] ? rightColors[i].opacity(0.8) : .white.opacity(0.14)), lineWidth: rightActive[i] ? 1.8 : 1.1)
                }
            }

            HStack(spacing: 0) {
                // Left: Sources
                VStack(alignment: .trailing, spacing: 8) {
                    nodePill(icon: "arrow.triangle.pull", text: "GitHub PR", color: .cyan, lit: activeSources.contains("auto"))
                    nodePill(icon: "text.bubble", text: "@codex 评论", color: .cyan, lit: activeSources.contains("comment"))
                    nodePill(icon: "hand.tap", text: "手动触发", color: .cyan, lit: activeSources.contains("manual"))
                }
                .frame(width: 118, alignment: .trailing)

                Spacer()

                // Center Hub
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.32))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().strokeBorder(
                                (isReviewing ? Color.orange : Color.white.opacity(0.22)),
                                lineWidth: isReviewing ? 1.8 : 1
                            )
                        )
                    VStack(spacing: 1) {
                        Image(systemName: isReviewing ? "bolt.fill" : "cpu")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isReviewing ? .orange : .cyan)
                        if isReviewing {
                            Text("\(activeCount)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                // Right: Execution & Outcomes
                VStack(alignment: .leading, spacing: 8) {
                    nodePill(icon: "magnifyingglass", text: "Codex 审查", color: .orange, lit: isReviewing)
                    nodePill(icon: "wrench.and.screwdriver", text: "Agent 派修", color: .blue, lit: hasFixed)
                    nodePill(icon: "arrow.triangle.merge", text: "自动合并", color: .purple, lit: hasMerged)
                }
                .frame(width: 132, alignment: .leading)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 112)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
    }

    private func nodePill(icon: String, text: String, color: Color, lit: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(lit ? color : Color.secondary.opacity(0.45)).frame(width: 5.5, height: 5.5)
            Image(systemName: icon).font(.system(size: 9.5)).foregroundStyle(lit ? color : .secondary)
            Text(text).font(.system(size: 10.5, weight: lit ? .semibold : .regular))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(lit ? 0.11 : 0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(lit ? color.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 0.7))
    }
}

// MARK: - Orca-Style Unified Stream Desktop Window

struct MainStreamWindowView: View {
    @ObservedObject var store: BotStore
    var isPopover: Bool = true
    var onPopOut: (() -> Void)? = nil
    @State private var inputText = ""
    @State private var expandedIDs: Set<String> = []
    @State private var showOpenPRsSheet = false
    @State private var showLogsSheet = false
    @State private var showSettings = false

    private let bgColor = Color(red: 0.082, green: 0.090, blue: 0.110)
    private let cardColor = Color(red: 0.118, green: 0.129, blue: 0.157)
    private let bubbleColor = Color(red: 0.153, green: 0.165, blue: 0.196)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(Color.white.opacity(0.07))

                if store.connected {
                    streamBody
                    Divider().overlay(Color.white.opacity(0.07))
                    bottomComposer
                } else {
                    disconnectedView
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(
            minWidth: isPopover ? 560 : 680,
            idealWidth: isPopover ? 580 : 860,
            minHeight: isPopover ? 620 : 520,
            idealHeight: isPopover ? 660 : 680
        )
        .overlay(alignment: .top) {
            if let msg = store.toastMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.16, green: 0.18, blue: 0.22), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .padding(.top, 56)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(store: store) { showSettings = false }
        }
        .sheet(isPresented: $showOpenPRsSheet) {
            openPRsSheetView
        }
        .sheet(isPresented: $showLogsSheet) {
            logsSheetView
        }
    }

    // MARK: - Top Bar (Orca centered pill + clean controls)

    private var topBar: some View {
        HStack(spacing: 8) {
            // Left: Logo + title + live status dot
            HStack(spacing: 7) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 19, height: 19)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("PR 评审")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .fixedSize()
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6.5, height: 6.5)
                Text(statusShortText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: Capsule())

            Button {
                showOpenPRsSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.pull")
                        .font(.system(size: 10))
                    Text("Open PR (\(store.openPRs.count))")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            // Right: concise primary controls + overflow menu
            if let latest = store.latestVersion {
                Button {
                    store.openUpdateOrCheck()
                } label: {
                    Text("↑ \(latest)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            iconBtn("arrow.clockwise", help: "立即扫描") { store.triggerScan() }
            iconBtn(store.paused ? "play.fill" : "pause.fill", help: store.paused ? "恢复轮询" : "暂停轮询") {
                store.togglePause()
            }
            iconBtn("gearshape", help: "设置") { showSettings = true }

            Menu {
                Button { showLogsSheet = true } label: {
                    Label("查看运行日志", systemImage: "terminal")
                }
                Button { store.sendTestNotification() } label: {
                    Label("发送测试通知", systemImage: "bell")
                }
                if let popOut = onPopOut {
                    Button { popOut() } label: {
                        Label("弹出独立大窗口", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                Divider()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label("退出 KoKLam PR Bot", systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26, height: 26)
            .help("更多")
        }
        .padding(.horizontal, isPopover ? 14 : 18)
        .frame(height: 46)
    }

    private func iconBtn(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var statusDotColor: Color {
        if !store.connected { return .red }
        if store.paused { return .yellow }
        if !store.activeTasks.isEmpty { return .orange }
        return .green
    }

    private var statusShortText: String {
        if !store.connected { return "未连接" }
        if store.paused { return "已暂停" }
        if !store.activeTasks.isEmpty { return "评审中 \(store.activeTasks.count)/\(store.concurrency)" }
        if let s = store.nextScanInSec { return "待命 · \(s)s" }
        return "待命"
    }

    // MARK: - Unified Orca Stream Body

    private var streamBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Empty state welcome
                if store.chatMessages.isEmpty && store.activeTasks.isEmpty && store.pendingDecisions.isEmpty && store.history.isEmpty {
                    VStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .opacity(0.85)
                        Text("KoKLam PR 评审已就绪")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("当前监听 \(store.openPRs.count) 个 Open PR。你可以在下方直接说「open 都看下吧」，或在 GitHub PR 评论区 @koklam-pr-bot。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 64)
                }

                // 2. Chat conversation bubbles (oldest -> newest)
                if !store.chatMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.chatMessages.suffix(20)) { msg in
                            if msg.role == "user" {
                                HStack {
                                    Spacer(minLength: 100)
                                    Text(msg.text)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
                                }
                            } else {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(nsImage: NSApp.applicationIconImage)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let badge = msg.badge, !badge.isEmpty {
                                            taskPill(badge, dotColor: .cyan)
                                        }
                                        Text(msg.text)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.84))
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // 3. Active & Queued Work Block (exact Orca style!)
                if !store.activeTasks.isEmpty || !store.pendingQueue.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(nsImage: NSApp.applicationIconImage)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            let maxElapsed = store.activeTasks.map(\.elapsed_sec).max() ?? 0
                            Text("工作中 · \(store.activeTasks.count) 个任务 · \(formatDuration(maxElapsed))")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                            Spacer()
                        }

                        Divider().overlay(Color.white.opacity(0.08))

                        ForEach(store.activeTasks) { t in
                            activeTaskRow(t)
                        }

                        ForEach(store.pendingQueue) { q in
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.4))
                                Text("Queued")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                Text("PR 评审")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                                Text("\(q.displayRepo)#\(q.number) · \(q.title)")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // 4. Inline Pending Decisions (Orca style — right in the stream!)
                if !store.pendingDecisions.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.pendingDecisions) { dec in
                            inlineDecisionCard(dec)
                        }
                    }
                }

                // 5. Completed History Stream (compact expandable Orca rows)
                if !store.history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(nsImage: NSApp.applicationIconImage)
                                .resizable()
                                .frame(width: 18, height: 18)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Text("评审与执行记录（\(store.history.count)）")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                        Divider().overlay(Color.white.opacity(0.07))

                        ForEach(store.history.prefix(25)) { item in
                            historyStreamRow(item)
                        }
                    }
                }

                // 6. Resolved Decisions (compact Orca reply records)
                if !store.resolvedDecisions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.resolvedDecisions.prefix(6)) { r in
                            HStack {
                                Spacer(minLength: 120)
                                VStack(alignment: .trailing, spacing: 4) {
                                    taskPill("\(r.displayRepo)#\(r.number) · \(r.title)", dotColor: .yellow)
                                    Text(r.reply_text)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, isPopover ? 16 : 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Stream Row Components

    private func activeTaskRow(_ t: ActiveTask) -> some View {
        let isExp = expandedIDs.contains("act-\(t.id)")
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                toggleExpand("act-\(t.id)")
            } label: {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                    Text("Started")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("PR 评审")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("\(t.displayRepo)#\(t.number) · \(t.stage) (\(formatDuration(t.elapsed_sec)))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Image(systemName: isExp ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExp {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                    if let steps = t.steps, !steps.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { _, st in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(st.status == "done" ? Color.green : (st.status == "running" ? Color.orange : Color.red))
                                        .frame(width: 5.5, height: 5.5)
                                    Text(st.name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.05), in: Capsule())
                            }
                        }
                    }
                    if let lines = t.live_lines, !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(lines.suffix(12).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(2)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7))
                .padding(.leading, 20)
            }
        }
    }

    private func inlineDecisionCard(_ dec: DecisionItem) -> some View {
        let isExp = expandedIDs.contains("dec-\(dec.id)")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
                Text("就")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.55))
                taskPill("\(dec.displayRepo)#\(dec.number) · \(dec.title)", dotColor: .orange)
                Text("向你提问")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }

            Text(dec.question)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .textSelection(.enabled)

            if !dec.context.isEmpty {
                Button {
                    toggleExpand("dec-\(dec.id)")
                } label: {
                    HStack(spacing: 4) {
                        Text(isExp ? "收起详细评审上下文" : "查看详细评审上下文")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                        Image(systemName: isExp ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)

                if isExp {
                    Text(dec.context)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: 8) {
                Button("授权新开会话修复") {
                    store.replyDecision(id: dec.id, action: "authorize_fix", replyText: "授权新开会话修复")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("合并 PR") {
                    store.replyDecision(id: dec.id, action: "merge", replyText: "直接合并 PR")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("忽略") {
                    store.replyDecision(id: dec.id, action: "dismiss", replyText: "忽略")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if let u = URL(string: dec.url) {
                    Button("打开 GitHub") { NSWorkspace.shared.open(u) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.cyan.opacity(0.85))
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.9))
    }

    private func historyStreamRow(_ item: HistoryItem) -> some View {
        let isExp = expandedIDs.contains("his-\(item.id)")
        let badge = historyVerdictLabel(item)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                toggleExpand("his-\(item.id)")
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(badge.color)
                        .frame(width: 6.5, height: 6.5)
                    Text("PR 评审")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("\(item.displayRepo)#\(item.number) \(badge.text)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    if let u = item.usage, u.netTokens > 0 {
                        Text("· \(formatTokens(u.netTokens))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Image(systemName: isExp ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                    Spacer()
                    Text("\(item.duration_sec)s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExp {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(item.body.isEmpty ? item.summary : item.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.78))
                        .textSelection(.enabled)
                        .lineSpacing(3)

                    if let tests = item.test_checklist, !tests.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("🧪 待测试功能清单")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.orange)
                            ForEach(tests, id: \.self) { t in
                                Text("• \(t)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(spacing: 8) {
                        if let u = URL(string: item.url) {
                            Button("打开 PR") { NSWorkspace.shared.open(u) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Button("重新 Review") {
                            store.triggerManualReview(repo: item.repo, number: item.number, note: "", agentSession: "")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if item.merged != true {
                            Button("立即派修") {
                                store.sendToAgentFix(repo: item.repo, number: item.number, reviewBody: item.body, agent: "", sessionID: "", note: "")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("合并 PR") {
                                store.mergePR(repo: item.repo, number: item.number)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                }
                .padding(14)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
                .padding(.leading, 16)
            }
        }
    }

    private func taskPill(_ text: String, dotColor: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func historyVerdictLabel(_ item: HistoryItem) -> (text: String, color: Color) {
        if !item.ok { return ("执行失败", .red) }
        if item.merged == true { return ("评审通过，已自动合并", .purple) }
        if item.fix_dispatched == true { return ("建议修改，已派回修复", .blue) }
        let v = item.verdict ?? ""
        if v.contains("通过") { return ("评审通过", .green) }
        if v.contains("阻塞") || v.contains("风险") { return ("建议暂缓合并", .red) }
        return ("评审完成，建议修改", .orange)
    }

    private func toggleExpand(_ id: String) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    // MARK: - Bottom Chat / Command Bar

    private var bottomComposer: some View {
        VStack(spacing: 8) {
            // Quick prompt chips + today token usage
            HStack(spacing: 8) {
                quickChip("open 都看下吧")
                quickChip("扫描新 PR")
                if let firstDec = store.pendingDecisions.first {
                    quickChip("授权新开会话修复 #\(firstDec.number)")
                }
                Spacer()
                if let today = store.todayUsage, today.netTokens > 0 {
                    Text("今日 \(formatTokens(today.netTokens))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: 780)

            HStack(spacing: 10) {
                TextField(
                    store.pendingDecisions.isEmpty
                        ? "输入指令，例如：open 都看下吧 / 审 #63 / 修 #42..."
                        : "直接回复待拍板问题，或输入指令（如 open 都看下吧）...",
                    text: $inputText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .onSubmit { submitInput() }

                Button {
                    submitInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.22) : .white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8))
            .frame(maxWidth: 780)
        }
        .padding(.horizontal, isPopover ? 14 : 28)
        .padding(.vertical, 10)
        .background(bgColor)
    }

    private func quickChip(_ text: String) -> some View {
        Button(text) {
            store.sendChat(text)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5))
        .foregroundStyle(.white.opacity(0.68))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6))
    }

    private func submitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        store.sendChat(trimmed)
    }

    // MARK: - Disconnected State

    private var disconnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.4))
            Text("正在连接本地后台服务...")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.85))
            }
            HStack(spacing: 10) {
                Button(store.startingDaemon ? "正在启动..." : "启动后台服务") {
                    store.ensureDaemonRunning(force: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.startingDaemon)

                Button("重试") { store.refreshNow() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auxiliary Sheets (Open PRs & Logs)

    private var openPRsSheetView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Open PR 列表 (\(store.openPRs.count))")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("全部评审") {
                    showOpenPRsSheet = false
                    store.sendChat("open 都看下吧")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("关闭") { showOpenPRsSheet = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(14)
            Divider().opacity(0.2)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.openPRs) { pr in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("\(pr.displayRepo)#\(pr.number)")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.cyan)
                                    Text(pr.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                }
                                Text("\(pr.head) → \(pr.base) · \(pr.sha8)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("评审") {
                                store.triggerManualReview(repo: pr.repo, number: pr.number, note: "", agentSession: "")
                                showOpenPRsSheet = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            if let u = URL(string: pr.url) {
                                Button("打开") { NSWorkspace.shared.open(u) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 560, height: 460)
    }

    private var logsSheetView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("后台运行日志")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("关闭") { showLogsSheet = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(14)
            Divider().opacity(0.2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(store.logs.suffix(120).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 620, height: 460)
    }

    private func formatDuration(_ sec: Int) -> String {
        if sec < 60 { return "\(sec)s" }
        return "\(sec / 60)m \(sec % 60)s"
    }

    private func formatTokens(_ n: Int64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

@main
struct KoKLamPRBotApp: App {
    @StateObject private var store = BotStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MainStreamWindowView(store: store, isPopover: true) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.menuBarSymbol)
                if !store.menuBarText.isEmpty {
                    Text(store.menuBarText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("KoKLam PR Bot", id: "main") {
            MainStreamWindowView(store: store, isPopover: false)
        }
        .defaultSize(width: 860, height: 680)
    }
}
