# atelier

一个「设计者 + 执行者 + 看板」的双 Agent 协作工坊。

| 角色 | 谁 | 职责 |
|------|----|----|
| 甲方 / 总编 | 你（人类） | 定优先级、起停工作、合并把关 |
| 架构师 / 评审 | **Claude** | 架构决策、规划、写规格、评审关键 PR |
| 工匠 / 执行 | **Codex** | 写代码、改 bug、补测试、机械重构 |
| 看板 | **GitHub** | 唯一事实来源（Issues / PR / Projects） |

核心原则：**两个 Agent 不直接对话，只通过 GitHub 读写状态。** Claude 稀缺昂贵，只做高杠杆思考；Codex 充裕，承担一切吃 token 的体力活。

## 怎么开始

1. 读 [`docs/workflow.md`](docs/workflow.md) 了解看板列与标签路由。
2. Claude 的工作准则见 [`CLAUDE.md`](CLAUDE.md)，Codex 的见 [`AGENTS.md`](AGENTS.md)。
3. 架构决策记录在 [`docs/adr/`](docs/adr/)。
4. 用 `.github/labels.yml` 同步标签，用 Issue / PR 模板开卡。
5. `.github/workflows/` 里是触发 Agent 的 Action 骨架（需填入你的凭据，见文件内注释）。

## 一句话工作流

```
你开 Issue（带验收标准）
  → 打标签 codex:implement → Codex 在分支实现、开 PR
  → PR 打开触发 claude:review → Claude 评审
  → 需改则 Codex 自己迭代；通过则【你合并】→ 闭环
```

