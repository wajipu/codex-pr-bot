# KoKLam PR Bot

轻量级、零外部依赖的 **本地 Codex CLI GitHub PR 自动审查机器人 + macOS 原生菜单栏桌面端**。

直接复用你本机登录好的 `codex` CLI 与 `gh` CLI，不需要公网服务器、不需要额外购买 OpenAI API Key，支持多并发并行 Review、GitHub App `[Bot]` 身份评论与 macOS 系统通知。

## 核心特性

- **双触发模式**：
  - **自动审查**：监听目标仓库的 Open PR，有新 PR 或推送新 Commit 时自动触发（按 `PR + commit SHA` 去重）。
  - **评论随时呼唤**：在任意 PR 评论区直接 **`@koklam-pr-bot`**（可附额外关注点，如 `@koklam-pr-bot 重点看并发和事务`，也兼容 `@codex review` / `/codex review` 及自定义 `trigger_mentions`），按评论 ID 去重。
- **原生 macOS 菜单栏下拉面板（SwiftUI）**：
  - 顶部菜单栏常驻，审查时实时显示并发进度（如 `⚡ 2/3`）。
  - 下拉毛玻璃面板查看 Open PR、正在并行 Review 的 Worker 实时输出、历史记录与运行日志。
  - 内置 GitHub Releases **自动检查更新**。
- **多并发 + 闭环自动派修 & 自动合并**：
  - 默认 3 并发并行执行 `codex exec -s read-only`。
  - **关联任意 Agent 会话自动修复**：支持 `claude`、`codex`、`agy`（Antigravity CLI）、`pi`、`opencode` 及自定义 `custom_agents`。PR 正文或评论含 `<!-- agent-session: <agent>:<id> -->`（或在面板里手动绑定）时，Review 不通过会在隔离的 `git worktree` 中直接 `resume` 原会话修复并推送（未写会话 ID 时自动降级新开会话，上限 2 轮防死循环）。
  - **通过自动合并 + 测试清单提醒**：Review 通过自动 `--squash --delete-branch` 合并（正文声明「勿 squash / 保留提交」时自动改 `--merge`），并弹出 macOS 系统通知 + 面板高亮展示 **🧪 待测试功能清单**。
- **macOS 原生通知**：审查通过（`✅`）、建议修改（`⚠️`）、发现高风险或执行失败（`❌`）自动弹出系统通知。

## 前置依赖

- macOS 13+（Apple Silicon）
- 已安装并登录 [GitHub CLI (`gh`)](https://cli.github.com/)：`gh auth login`
- 已安装并登录 [Codex CLI (`codex`)](https://github.com/openai/codex)

## 一键安装 / 更新

```bash
curl -fsSL https://raw.githubusercontent.com/wajipu/koklam-pr-bot/main/scripts/install.sh | bash
```

安装完成后编辑 `~/.koklam-pr-bot/config.json`，把 `repos` 改成你要监听的 GitHub 仓库（可选填 `local_repo_map` 让 Codex 读取本地仓库的 `AGENTS.md`）。

## 配置示例 (`~/.koklam-pr-bot/config.json`)

```json
{
  "repos": [
    "your-org/your-repo"
  ],
  "local_repo_map": {
    "your-org/your-repo": "~/code/your-repo"
  },
  "auto_review": true,
  "comment_trigger": true,
  "skip_draft": true,
  "reasoning_effort": "high",
  "timeout_seconds": 900,
  "port": 18787,
  "poll_interval_seconds": 120,
  "concurrency": 3
}
```

## 内置 MCP Server（Agent 闭环评审）

`koklam-pr-botd --mcp` 内置标准 stdio MCP Server，任何支持 MCP 的 Agent（Codex / Claude Code / Antigravity / Cursor / OpenCode）在提完 PR 或修完代码后，可直接调用 `review_pr(repo, number, wait=true)` 触发评审并同步拿到完整评审意见，带着原会话上下文直接修改再复审，形成完整闭环：

```json
{
  "mcpServers": {
    "koklam-pr-bot": {
      "command": "/Applications/KoKLam PR Bot.app/Contents/MacOS/koklam-pr-botd",
      "args": ["--mcp"]
    }
  }
}
```

## 自动打包与发布（GitHub Actions）

推送任意 `v*` 标签即可自动触发 `.github/workflows/release.yml` 在 `macos-15` runner 上编译打包 `.zip`、`.dmg` 与 `SHA256SUMS.txt` 并发布到 GitHub Releases：

```bash
git tag v1.0.1
git push origin v1.0.1
```

## License

[MIT](./LICENSE)
