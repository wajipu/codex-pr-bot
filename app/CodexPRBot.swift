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

struct ActiveTask: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let worker_id: Int
    let repo: String
    let short_repo: String?
    let number: Int
    let title: String
    let url: String
    let sha8: String
    let trigger_info: String
    let stage: String
    let elapsed_sec: Int
    let live_lines: [String]

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

    var displayRepo: String {
        short_repo ?? String(repo.split(separator: "/").last ?? Substring(repo))
    }
}

struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let finished_at: String
    let duration_sec: Int
    let ok: Bool
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
    case running = "进行中"
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

    func triggerManualReview(repo: String, number: Int, note: String = "") {
        Task {
            let ok = await post(path: "api/review", body: [
                "repo": repo,
                "number": number,
                "note": note
            ])
            showToast(ok ? "已加入队列：\(repo.split(separator: "/").last ?? "")#\(number)" : "触发失败")
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
                HStack {
                    Spacer()
                    Button("取消") { notePR = nil; noteText = "" }
                    Button("开始 Review") {
                        store.triggerManualReview(repo: pr.repo, number: pr.number, note: noteText)
                        notePR = nil
                        noteText = ""
                        tab = .running
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 360)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.activeTasks.isEmpty && store.pendingQueue.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 30))
                            .foregroundStyle(.green.opacity(0.85))
                        Text("当前空闲，等待新 PR 或 @codex review")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
                } else {
                    ForEach(store.activeTasks) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Worker #\(t.worker_id)")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.orange)
                                if let u = URL(string: t.url) {
                                    Link("\(t.displayRepo)#\(t.number)", destination: u)
                                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                }
                                Spacer()
                                ProgressView().controlSize(.small)
                                Text("\(t.elapsed_sec)s")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(t.title).font(.system(size: 12)).lineLimit(1)
                            Text("\(t.stage) · \(t.sha8)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)

                            Text(t.live_lines.isEmpty ? "Codex CLI 分析中..." : t.live_lines.suffix(8).joined(separator: "\n"))
                                .font(.system(size: 10.5, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(8)
                                .padding(8)
                                .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(11)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.8))
                    }

                    if !store.pendingQueue.isEmpty {
                        Text("等待队列 (\(store.pendingQueue.count))")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(store.pendingQueue) { q in
                            HStack {
                                Text("\(q.displayRepo)#\(q.number)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text(q.title).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text(q.sha8).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .padding(9)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(12)
        }
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
                                ScrollView {
                                    Text(item.body)
                                        .font(.system(size: 11, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 170)
                                .padding(8)
                                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

                                HStack {
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
