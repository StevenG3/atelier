# 工作流与看板

## 看板列（GitHub Projects）

按从左到右流动，列顶到底就是优先级：

| 列 | 含义 | 负责人 |
|----|------|--------|
| `Backlog` | 待规划的想法 | 你 |
| `Designing` | Claude 正在出规格 | Claude |
| `Ready` | 规格就绪，可实现 | — |
| `In Progress` | Codex 实现中 | Codex |
| `In Review` | Claude 评审 PR 中 | Claude |
| `Done` | 已合并 | 你（合并） |

## 标签路由

| 标签 | 作用 |
|------|------|
| `claude:design` | 需要 Claude 出规格/拆解 |
| `codex:implement` | 规格就绪，Codex 开工 |
| `codex:go` | 起停开关——有此标签才允许 Codex 动手 |
| `claude:review` | 需要 Claude 评审（通常 PR 自动带） |
| `needs-human` | 卡住了，等你介入 |
| `on-hold` / `blocked` | 暂停，任何 Agent 都不动 |

## 闭环

```
你开 Issue（用 design-spec 或 feature 模板，写清验收标准）
   │
   ├─ 复杂/需设计 → 打 claude:design → Claude 在 Issue 里产出规格 → 转 Ready
   │
   ▼
打 codex:implement + codex:go
   │
   ▼
Codex 切分支实现 → 自测到绿 → 开 PR（Closes #N）
   │
   ▼
PR 触发 claude:review → Claude 评审
   │
   ├─ Request changes → Codex 迭代（回到上一步）
   │
   ▼
Approve → 【你】合并 → 看板自动进 Done
```

## 你的控制点（起停）

- **起**：给 Issue 加 `codex:go`。
- **停**：去掉 `codex:go`，或加 `on-hold`，或把 PR 转成 Draft。
- **急停**：在仓库 Settings → Actions 里禁用对应 workflow。
- **终极门禁**：开启 main 分支保护，要求你 approve 才能合并。

