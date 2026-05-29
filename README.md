# atelier

一个「设计者 + 执行者 + 看板」的双 Agent 协作工坊。

| 角色 | 谁 | 职责 |
|------|----|----|
| 甲方 / 总编 | 你（人类） | 定优先级、起停工作、合并把关 |
| 架构师 / 评审 | **Claude** | 架构决策、规划、写规格、评审关键 PR |
| 工匠 / 执行 | **Codex** | 写代码、改 bug、补测试、机械重构 |
| 看板 | **GitHub** | 唯一事实来源（Issues / PR / Projects） |

核心原则：**两个 Agent 不直接对话，只通过 GitHub 读写状态。** Claude 稀缺昂贵，只做高杠杆思考；Codex 充裕，承担一切吃 token 的体力活。

## 日常使用（三步）

```bash
# 1. 看谁在等你
./scripts/atelier.sh status

# 2. 拿到已填好的 Claude 提示词（自动找最高优先级）
./scripts/atelier.sh next
# 或指定：
./scripts/atelier.sh prompt respond 5   # 回复 Codex 问题
./scripts/atelier.sh prompt review 12   # 评审 PR
./scripts/atelier.sh prompt design 8    # 写功能规格

# 3. 把输出粘贴到 Claude Code
#    或在 Claude Code 里直接说：atelier next（见 CLAUDE.md 触发短语）

# 启动 Codex（规格就绪后）
./scripts/atelier.sh go 5
```

## 完整工作流

```
你开 Issue（带验收标准 + project: <name>）
  → 打 claude:design → Claude 写规格 → 打 claude:spec-ready
  → 你打 codex:go（或 ./scripts/atelier.sh go <N>）→ Codex 实现
  → Codex 遇到问题 → @claude 评论 + needs-response 标签
  → Claude 回复决策 → Codex 继续
  → Codex 开 PR + claude:review → Claude 评审
  → 【你合并】→ 闭环
```

## 接入新工程

复制 `projects/example.yml` → `projects/<your-project>.yml`，填写 repo 列表和测试命令。  
新建 Issue 时在 body 第一行写 `project: <your-project>`。

## 文档索引

| 文件 | 内容 |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Claude 角色、触发短语、问答协议 |
| [`AGENTS.md`](AGENTS.md) | Codex 角色、工作流、提问规范 |
| [`docs/workflow.md`](docs/workflow.md) | 看板列、标签路由、控制点 |
| [`docs/interaction-protocol.md`](docs/interaction-protocol.md) | 问答格式规范 |
| [`prompts/`](prompts/) | 四种操作的提示词模板 |
| [`projects/`](projects/) | 工程接入配置文件 |
| [`scripts/atelier.sh`](scripts/atelier.sh) | 用户侧 CLI 工具 |

