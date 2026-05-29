# 提示词模板库

此目录包含触发 Claude 和 Codex 的标准提示词模板。

## 使用方式

1. 选择对应场景的 `.md.example` 文件
2. 将 `{{变量}}` 替换为实际值
3. 将替换后的内容粘贴到 Claude Code 或 Codex CLI 会话里

## 模板索引

| 文件 | 场景 | 触发者 |
|---|---|---|
| `claude-design.md.example` | Claude 为 Issue 写功能规格 | 你（Issue 打了 `claude:design`） |
| `codex-implement.md.example` | Codex 实现一个 Issue | 你（Issue 打了 `codex:go`）或 Codex App |
| `claude-respond.md.example` | Claude 回复 Codex 的 @claude 提问 | Claude 定时任务（`needs-response` 标签） |
| `claude-review.md.example` | Claude 评审 Codex 提交的 PR | Claude 定时任务（`claude:review` 标签） |
| `claude-next-phase.md.example` | **hermes-aegis 专用**：生成 Phase N+1 完整规格并创建 Atelier Issue | `atelier design hermes-aegis Phase <N>` |

## 变量说明

| 变量 | 含义 |
|---|---|
| `{{ISSUE_NUMBER}}` | GitHub Issue 编号，如 `5` |
| `{{PR_NUMBER}}` | GitHub PR 编号，如 `12` |
| `{{PROJECT_NAME}}` | `projects/` 下的配置文件名（不含 `.yml`），如 `my-project` |
| `{{SHORT_DESC}}` | 分支名用的简短描述，如 `add-reconcile-endpoint` |
| `{{REPO}}` | 完整仓库名，如 `StevenG3/atelier` |
| `{{CURRENT_PHASE}}` | 刚完成的 Phase 编号（hermes-aegis 专用） |
| `{{NEXT_PHASE}}` | 即将生成的 Phase 编号（hermes-aegis 专用） |

## 与协议的关系

问答格式（提问 / 决策）的完整规范见 `docs/interaction-protocol.md`。  
模板里的步骤是协议的操作化版本。
