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

---

## 执行中来回协作

Codex 实现过程中遇到阻塞时，通过 GitHub Issue 评论与 Claude 来回沟通：

```
Codex 遇到 STOP-AND-ASK
  → Issue 评论（@claude 提问格式） + 打 needs-response 标签
    → Claude 检测到 needs-response
      → 读评论历史 → 用决策格式回复 → 移除 needs-response 标签
        → Codex 读到「决策：」→ 继续被阻塞的路径
```

**提问格式**（Codex 发）：
```
@claude — 卡在：[一行描述]
背景：[一句话]
方案 A：[做法] → [后果]
方案 B：[备选] → [后果]
请选择，或给第三条路。
```

**决策格式**（Claude 回）：
```
**决策：** [一个清晰答案]
**理由：** [一句话]
**行动：** 继续 | 等人类 | 停止
```

完整协议见 `docs/interaction-protocol.md`，操作命令见 `prompts/` 目录。

## 接入新工程

1. 复制 `projects/example.yml`，重命名为 `projects/<your-project>.yml`
2. 填写 repo 列表、Phase Prompt 路径、测试命令
3. 新建 Issue 时在 body 第一行加 `project: <your-project>`
4. Claude 和 Codex 会自动读取配置，知道操作哪些 repo

## 看板配置（GitHub Projects）

推荐在 GitHub Projects 里创建 Table view，添加以下自定义字段：

| 字段名 | 类型 | 用途 |
|---|---|---|
| `工程` | Text | 对应 `projects/<name>.yml` 里的 project_tag |
| `Phase` | Text | 当前 Phase 编号 |
| `当前执行方` | Single select | Claude · Codex · 等待人类 |
| `状态` | Single select | 设计中 · 实现中 · 提问中 · PR评审 · 完成 |
| `最新决策` | Text | Claude 最近一条决策摘要 |

