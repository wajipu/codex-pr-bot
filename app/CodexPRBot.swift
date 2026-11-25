import SwiftUI
import AppKit

// MARK: - Models

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
    let live_lines: [String]
    let steps: [PipelineStep]?

    var displayRepo: String {
        short_repo ?? String(repo.split(separator: "/").last ?? Substring(repo))
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
        short_repo ?? String(repo.split(separator: "/").last ?? Substring(repo))
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
        short_repo ?? String(repo.split(separator: "/").last ?? Substring(repo))
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
        short_repo ?? String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct GitHubRelease: Codable, Sendable {
    let tag_name: String
    let html_url: String
}

enum PopoverTab: String, CaseIterable, Identifiable {
    case prs = "Open PR"
    case running = "链路"
    case history = "历史"
    case logs = "日志"

    var id: String { rawValue }
}

// MARK: - Store

@MainActor
final class BotStore: ObservableObject {
    static let githubRepo = "wajipu/codex-pr-bot"
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
    @Published var toastMessage: String?

    // Update checker state
    @Published var latestVersion: String?
    @Published var latestReleaseURL: URL?
    @Published var checkingUpdate = false

    private let baseURL = URL(string: "http://127.0.0.1:18787")!
    private let localSession: URLSession
    private var pollTask: Task<Void, Never>?

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:] // bypass proxy for localhost
        cfg.timeoutIntervalForRequest = 4
        self.localSession = URLSession(configuration: cfg)
        startPolling()
        checkForUpdates(silent: true)
    }

    func startPolling() {
        pollTask?.cancel()
        let session = self.localSession
        let statusURL = self.baseURL.appendingPathComponent("api/status")

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let decoded: BotSnapshot? = await Task.detached(priority: .utility) {
                    do {
                        let (data, resp) = try await session.data(from: statusURL)
                        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                        return try JSONDecoder().decode(BotSnapshot.self, from: data)
                    } catch {
                        return nil
                    }
                }.value

                guard let self else { return }
                if let d = decoded {
                    self.apply(d)
                } else if self.connected {
                    self.connected = false
                }

                let sleepNs: UInt64 = self.activeTasks.isEmpty ? 3_000_000_000 : 1_500_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
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
        if history != d.history { history = d.history }
        if logs != d.logs { logs = d.logs }
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
        guard connected, !activeTasks.isEmpty else { return "" }
        return "\(activeTasks.count)/\(concurrency)"
    }

    var menuBarSymbol: String {
        guard connected else { return "exclamationmark.triangle" }
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
    @State private var notePR: OpenPR?
    @State private var noteText = ""
    @State private var sessionText = ""

    @State private var fixTarget: HistoryItem?
    @State private var fixAgent = "codex"
    @State private var fixSessionID = ""
    @State private var fixNote = ""

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
            VStack(alignment: .leading, spacing: 12) {
                Text("发送 Review 建议给 Agent 修复")
                    .font(.system(size: 14, weight: .bold))
                Text("\(item.displayRepo)#\(item.number) — \(item.title)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Picker("目标 Agent", selection: $fixAgent) {
                    Text("Codex").tag("codex")
                    Text("Claude Code").tag("claude")
                    Text("Antigravity (agy)").tag("agy")
                    Text("Pi").tag("pi")
                    Text("OpenCode").tag("opencode")
                }
                .pickerStyle(.segmented)

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
            .frame(width: 400)
        }
    }

    private var topHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 16))
                .foregroundStyle(.cyan)
            Text("Codex PR Bot")
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
                Button("重试") { store.refreshNow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var prsListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
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

    private var runningListView: some View {
        let mergedCount = store.history.filter { $0.merged == true }.count
        let fixedCount = store.history.filter { $0.fix_dispatched == true }.count
        let activeSources = Set(store.activeTasks.compactMap(\.source_kind))
        let isReviewing = !store.activeTasks.isEmpty

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                // Summary Strip (like magpie's 路由 top line)
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReviewing ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text("累计 \(store.history.count) 次执行 · 已合并 \(mergedCount) · 自动派修 \(fixedCount)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
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

                        Text(t.live_lines.isEmpty ? t.stage : t.live_lines.suffix(5).joined(separator: "\n"))
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

                    ForEach(store.history.prefix(15)) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(outcomeColor(item))
                                    .frame(width: 7, height: 7)
                                if let u = URL(string: item.url) {
                                    Link("\(item.displayRepo)#\(item.number)", destination: u)
                                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                }
                                Text(sourceLabel(item.source_kind))
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                                    .foregroundStyle(.secondary)
                                Text(outcomeLabel(item))
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(outcomeColor(item).opacity(0.18), in: Capsule())
                                    .foregroundStyle(outcomeColor(item))
                                Spacer()
                                Text(String(item.finished_at.suffix(8)))
                                    .font(.system(size: 10.5, design: .monospaced))
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
                                Text("耗时 \(item.duration_sec)s")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
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
        ScrollView {
            LazyVStack(spacing: 6) {
                if store.history.isEmpty {
                    Text("暂无 Review 历史")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                } else {
                    ForEach(store.history) { item in
                        let isExp = expandedHistoryID == item.id
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                expandedHistoryID = isExp ? nil : item.id
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(item.ok ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text("\(item.displayRepo)#\(item.number)")
                                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                            if item.merged == true {
                                                Text("已合并")
                                                    .font(.system(size: 9.5, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.purple.opacity(0.22), in: Capsule())
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

                                HStack(spacing: 8) {
                                    Text(item.finished_at.replacingOccurrences(of: "T", with: " "))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let u = URL(string: item.url) {
                                        Link("GitHub", destination: u).font(.system(size: 11.5))
                                    }
                                    Button("复制") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.body, forType: .string)
                                        store.showToast("已复制")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)

                                    Button("发送给 Agent") {
                                        // Pre-fill bound agent/session if present on this open PR
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(12)
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

@main
struct CodexPRBotApp: App {
    @StateObject private var store = BotStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
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
    }
}
