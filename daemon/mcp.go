package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type mcpRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type mcpResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   *mcpError       `json:"error,omitempty"`
}

type mcpError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type mcpClient struct {
	baseURL string
	http    *http.Client
}

func newMCPClient() *mcpClient {
	port := 18787
	home, _ := os.UserHomeDir()
	for _, dir := range []string{".koklam-pr-bot", ".codex-pr-bot"} {
		if raw, err := os.ReadFile(filepath.Join(home, dir, "config.json")); err == nil {
			var cfg struct {
				Port int `json:"port"`
			}
			if json.Unmarshal(raw, &cfg) == nil && cfg.Port > 0 {
				port = cfg.Port
				break
			}
		}
	}
	return &mcpClient{
		baseURL: fmt.Sprintf("http://127.0.0.1:%d", port),
		http: &http.Client{
			Timeout:   30 * time.Second,
			Transport: &http.Transport{Proxy: nil},
		},
	}
}

func (c *mcpClient) ensureDaemon() {
	resp, err := c.http.Get(c.baseURL + "/")
	if err == nil {
		_ = resp.Body.Close()
		return
	}
	home, _ := os.UserHomeDir()
	plist := filepath.Join(home, "Library", "LaunchAgents", "com.wajipu.koklam-pr-bot.plist")
	uid := fmt.Sprintf("gui/%d", os.Getuid())
	if _, err := os.Stat(plist); err == nil {
		_ = exec.Command("/bin/launchctl", "bootstrap", uid, plist).Run()
		_ = exec.Command("/bin/launchctl", "kickstart", uid+"/com.wajipu.koklam-pr-bot").Run()
		time.Sleep(1200 * time.Millisecond)
	}
}

func (c *mcpClient) getStatus() (*Snapshot, error) {
	c.ensureDaemon()
	resp, err := c.http.Get(c.baseURL + "/api/status")
	if err != nil {
		return nil, fmt.Errorf("无法连接本地 KoKLam PR Bot 服务 (%s): %w", c.baseURL, err)
	}
	defer resp.Body.Close()
	var snap Snapshot
	if err := json.NewDecoder(resp.Body).Decode(&snap); err != nil {
		return nil, err
	}
	return &snap, nil
}

func (c *mcpClient) postJSON(path string, body any) (map[string]any, error) {
	c.ensureDaemon()
	raw, _ := json.Marshal(body)
	resp, err := c.http.Post(c.baseURL+path, "application/json", bytes.NewReader(raw))
	if err != nil {
		return nil, fmt.Errorf("调用本地 KoKLam PR Bot 失败 (%s): %w", path, err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	var out map[string]any
	_ = json.Unmarshal(b, &out)
	if resp.StatusCode >= 400 {
		msg := string(b)
		if m, ok := out["message"].(string); ok && m != "" {
			msg = m
		}
		return out, fmt.Errorf("HTTP %d: %s", resp.StatusCode, msg)
	}
	return out, nil
}

func mcpToolDefinitions() []map[string]any {
	return []map[string]any{
		{
			"name":        "review_pr",
			"description": "Trigger KoKLam PR Bot to review a GitHub Pull Request (posts live status & review comment as koklam-pr-bot[bot] on GitHub) and wait for the full structured review verdict and findings so the calling Agent can immediately fix any issues in a closed loop.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"repo": map[string]any{
						"type":        "string",
						"description": "GitHub repository in owner/name format, e.g. koklam-saas/kservice",
					},
					"number": map[string]any{
						"type":        "integer",
						"description": "Pull Request number",
					},
					"note": map[string]any{
						"type":        "string",
						"description": "Optional focus instructions for the reviewer",
					},
					"wait": map[string]any{
						"type":        "boolean",
						"description": "Whether to wait until the review completes and return the full review result (default: true)",
						"default":     true,
					},
					"timeout_seconds": map[string]any{
						"type":        "integer",
						"description": "Max seconds to wait when wait=true (default: 600)",
						"default":     600,
					},
				},
				"required": []string{"repo", "number"},
			},
		},
		{
			"name":        "get_pr_review_status",
			"description": "Get the latest KoKLam PR Bot review status, active progress, full review findings, and pending decisions for a specific GitHub PR.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"repo":   map[string]any{"type": "string", "description": "GitHub repository in owner/name format"},
					"number": map[string]any{"type": "integer", "description": "Pull Request number"},
				},
				"required": []string{"repo", "number"},
			},
		},
		{
			"name":        "list_open_prs",
			"description": "List all currently monitored Open Pull Requests and their KoKLam PR Bot review status.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"repo": map[string]any{"type": "string", "description": "Optional filter by repository name"},
				},
			},
		},
		{
			"name":        "merge_pr",
			"description": "Merge an approved GitHub Pull Request via KoKLam PR Bot (respects squash/merge-commit rules).",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"repo":   map[string]any{"type": "string", "description": "GitHub repository in owner/name format"},
					"number": map[string]any{"type": "integer", "description": "Pull Request number"},
				},
				"required": []string{"repo", "number"},
			},
		},
	}
}

func (c *mcpClient) handleToolCall(name string, rawArgs json.RawMessage) (string, bool) {
	switch name {
	case "list_open_prs":
		var args struct {
			Repo string `json:"repo"`
		}
		_ = json.Unmarshal(rawArgs, &args)
		snap, err := c.getStatus()
		if err != nil {
			return err.Error(), true
		}
		var lines []string
		for _, pr := range snap.OpenPRs {
			if args.Repo != "" && !strings.EqualFold(pr.Repo, args.Repo) && !strings.EqualFold(pr.ShortRepo, args.Repo) {
				continue
			}
			rev := "未审"
			if pr.Reviewed {
				rev = "已审"
			}
			lines = append(lines, fmt.Sprintf("- %s#%d [%s] %s (%s -> %s, %s) %s",
				pr.Repo, pr.Number, rev, pr.Title, pr.Head, pr.Base, pr.Sha8, pr.URL))
		}
		if len(lines) == 0 {
			return "当前没有监听中的 Open PR。", false
		}
		return fmt.Sprintf("当前 Open PR (%d 个):\n%s", len(lines), strings.Join(lines, "\n")), false

	case "get_pr_review_status":
		var args struct {
			Repo   string `json:"repo"`
			Number int    `json:"number"`
		}
		if err := json.Unmarshal(rawArgs, &args); err != nil || args.Repo == "" || args.Number <= 0 {
			return "参数错误：需要 repo 和 number", true
		}
		snap, err := c.getStatus()
		if err != nil {
			return err.Error(), true
		}
		for _, t := range snap.ActiveTasks {
			if strings.EqualFold(t.Repo, args.Repo) && t.Number == args.Number {
				return fmt.Sprintf("⏳ 正在执行中：%s#%d\n当前阶段：%s（已耗时 %ds）\n最新输出：\n%s",
					t.Repo, t.Number, t.Stage, t.ElapsedSec, strings.Join(t.LiveLines, "\n")), false
			}
		}
		for _, h := range snap.History {
			if strings.EqualFold(h.Repo, args.Repo) && h.Number == args.Number {
				return formatHistoryForMCP(h), false
			}
		}
		return fmt.Sprintf("暂未找到 %s#%d 的评审记录，可调用 review_pr 触发评审。", args.Repo, args.Number), false

	case "review_pr":
		var args struct {
			Repo           string `json:"repo"`
			Number         int    `json:"number"`
			Note           string `json:"note"`
			Wait           *bool  `json:"wait"`
			TimeoutSeconds int    `json:"timeout_seconds"`
		}
		if err := json.Unmarshal(rawArgs, &args); err != nil || strings.TrimSpace(args.Repo) == "" || args.Number <= 0 {
			return "参数错误：需要 repo (owner/name) 和 number (PR 号)", true
		}
		repo := strings.TrimSpace(args.Repo)
		wait := true
		if args.Wait != nil {
			wait = *args.Wait
		}
		timeoutSec := args.TimeoutSeconds
		if timeoutSec <= 0 {
			timeoutSec = 600
		}

		// Capture previous latest history ID for this PR so we know when the new review lands
		prevID := ""
		if snap, err := c.getStatus(); err == nil {
			for _, h := range snap.History {
				if strings.EqualFold(h.Repo, repo) && h.Number == args.Number {
					prevID = h.ID
					break
				}
			}
		}

		note := strings.TrimSpace(args.Note)
		if note == "" {
			note = "MCP 闭环评审触发"
		}
		res, err := c.postJSON("/api/review", map[string]any{
			"repo":   repo,
			"number": args.Number,
			"note":   note,
		})
		if err != nil {
			return fmt.Sprintf("触发评审失败：%v", err), true
		}
		if !wait {
			msg, _ := res["message"].(string)
			return fmt.Sprintf("已触发 %s#%d 评审（异步模式）：%s", repo, args.Number, msg), false
		}

		deadline := time.Now().Add(time.Duration(timeoutSec) * time.Second)
		for time.Now().Before(deadline) {
			time.Sleep(2500 * time.Millisecond)
			snap, err := c.getStatus()
			if err != nil {
				continue
			}
			for _, h := range snap.History {
				if strings.EqualFold(h.Repo, repo) && h.Number == args.Number {
					if h.ID != prevID {
						return formatHistoryForMCP(h), !h.OK
					}
					break
				}
			}
		}
		return fmt.Sprintf("等待 %s#%d 评审结果超时（>%ds），评审可能仍在后台执行，可稍后调用 get_pr_review_status 查看。", repo, args.Number, timeoutSec), true

	case "merge_pr":
		var args struct {
			Repo   string `json:"repo"`
			Number int    `json:"number"`
		}
		if err := json.Unmarshal(rawArgs, &args); err != nil || args.Repo == "" || args.Number <= 0 {
			return "参数错误：需要 repo 和 number", true
		}
		res, err := c.postJSON("/api/merge", map[string]any{
			"repo":   strings.TrimSpace(args.Repo),
			"number": args.Number,
		})
		if err != nil {
			return fmt.Sprintf("合并失败：%v", err), true
		}
		msg, _ := res["message"].(string)
		return fmt.Sprintf("✅ 合并结果（%s#%d）：%s", args.Repo, args.Number, msg), false

	default:
		return fmt.Sprintf("未知工具: %s", name), true
	}
}

func formatHistoryForMCP(h HistoryItem) string {
	var sb strings.Builder
	verdict := h.Verdict
	if verdict == "" {
		if h.OK {
			verdict = "评审完成"
		} else {
			verdict = "执行失败"
		}
	}
	sb.WriteString(fmt.Sprintf("## KoKLam PR Bot 评审结果：%s#%d\n", h.Repo, h.Number))
	sb.WriteString(fmt.Sprintf("- **结论**：%s\n", verdict))
	sb.WriteString(fmt.Sprintf("- **Commit**：`%s` · 耗时 `%ds`\n", h.Sha8, h.DurationSec))
	sb.WriteString(fmt.Sprintf("- **PR 链接**：%s\n", h.URL))
	if h.Merged {
		sb.WriteString("- **合并状态**：已自动合并\n")
	}
	if len(h.TestChecklist) > 0 {
		sb.WriteString("\n### 🧪 待测试功能清单\n")
		for _, t := range h.TestChecklist {
			sb.WriteString("- " + t + "\n")
		}
	}
	sb.WriteString("\n### 详细评审意见\n")
	if strings.TrimSpace(h.Body) != "" {
		sb.WriteString(h.Body)
	} else {
		sb.WriteString(h.Summary)
	}
	return sb.String()
}

func runMCPServer() {
	client := newMCPClient()
	reader := bufio.NewReaderSize(os.Stdin, 1024*1024)
	enc := json.NewEncoder(os.Stdout)

	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err == io.EOF {
				return
			}
			return
		}
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		var req mcpRequest
		if err := json.Unmarshal(line, &req); err != nil {
			continue
		}

		// Notifications have no ID and require no response
		if len(req.ID) == 0 || string(req.ID) == "null" {
			continue
		}

		resp := mcpResponse{JSONRPC: "2.0", ID: req.ID}
		switch req.Method {
		case "initialize":
			resp.Result = map[string]any{
				"protocolVersion": "2024-11-05",
				"capabilities": map[string]any{
					"tools": map[string]any{},
				},
				"serverInfo": map[string]any{
					"name":    "koklam-pr-bot",
					"version": "3.7.0",
				},
			}
		case "ping":
			resp.Result = map[string]any{}
		case "tools/list":
			resp.Result = map[string]any{
				"tools": mcpToolDefinitions(),
			}
		case "tools/call":
			var p struct {
				Name      string          `json:"name"`
				Arguments json.RawMessage `json:"arguments"`
			}
			if err := json.Unmarshal(req.Params, &p); err != nil {
				resp.Error = &mcpError{Code: -32602, Message: "invalid params"}
			} else {
				text, isErr := client.handleToolCall(p.Name, p.Arguments)
				resp.Result = map[string]any{
					"content": []map[string]any{
						{"type": "text", "text": text},
					},
					"isError": isErr,
				}
			}
		default:
			resp.Error = &mcpError{Code: -32601, Message: "method not found: " + req.Method}
		}

		_ = enc.Encode(resp)
	}
}
