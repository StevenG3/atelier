# 规划会话交接（Planning Handoff）

> 本文件是 atelier 项目初始规划的浓缩记录，供任何新的 Claude / Codex 会话快速接上上下文。

## 协作模型

- **人类（仓库所有者）**：定优先级、起停工作、合并把关。唯一拥有合并权。
- **Claude（架构师/评审）**：架构决策、规划、写规格、评审关键 PR。稀缺资源，只做高杠杆思考。
- **Codex（执行者）**：写代码、改 bug、补测试、机械重构。承担一切吃 token 的体力活。
- **GitHub**：唯一事实来源。两个 Agent 不直接对话，只通过 Issues / PR / Projects 读写状态。

## 关键约束（决定了设计取舍）

- 两边都走**订阅授权（OAuth），不用 API key**：Claude Code 用 Pro 订阅，Codex 用 ChatGPT 订阅的 GitHub App。
- **Claude Pro 额度稀缺**：Claude.ai 聊天 / Claude Code / Cowork 共用同一额度池，按 5 小时滚动窗口 + 每周上限计。
- **Codex 充裕**：作为主力执行者，承担绝大部分实现工作量。
- 因此核心策略：**Claude 只思考，Codex 干活**。

## 工作闭环

```
人类开 Issue（带验收标准）
  → 复杂的先 claude:design 出规格
  → codex:implement + codex:go → Codex 切分支实现、自测到绿、开 PR
  → PR 触发 claude:review → Claude 评审 diff（不读全仓）
  → Request changes → Codex 迭代；Approve → 人类合并 → 闭环
```

## 省 Claude 额度的纪律

1. Claude 只评审 **PR 的 diff**，绝不把整个代码库读进去。
2. **批量**处理：攒一批再集中评审/规划，别零碎触发。
3. 用**测试 + CI** 让"完成"客观化，Codex 先自测到绿，机械错误不留给评审。
4. 上下文前置进 `CLAUDE.md` / `AGENTS.md` / ADR，绝不向 Claude 重复解释架构。
5. CI 里自动跑 Claude 会脱离订阅单独计费——预算敏感则保持手动评审。

## 仓库内的上下文地图

- `CLAUDE.md` — Claude 的工作准则（含禁区、评审清单、预算纪律）
- `AGENTS.md` — Codex 的工作准则（含自我验证清单）
- `docs/workflow.md` — 看板列与标签路由
- `docs/adr/` — 架构决策记录
- `.github/` — 标签定义、Issue/PR 模板、Action 骨架

## 待办

- 把 `CLAUDE.md` / `AGENTS.md` 里的 `TODO`（技术栈、构建/测试/lint 命令、禁区）按真实项目填实。
- 配置 Codex 侧的 GitHub App 触发。
- 决定 Claude 评审是手动还是接入 Action。

