# atelier

一个「设计者 + 执行者 + 看板」的双 Agent 协作工坊。

| 角色 | 谁 | 职责 |
|------|----|----|
| 甲方 / 总编 | 你（人类） | 定优先级、起停工作、合并把关 |
| 架构师 / 评审 | **Claude** | 架构决策、规划、写规格、评审关键 PR |
| 工匠 / 执行 | **Codex** | 写代码、改 bug、补测试、机械重构 |
| 看板 | **GitHub** | 唯一事实来源（Issues / PR / Projects） |

核心原则：**两个 Agent 不直接对话，只通过 GitHub 读写状态。** Claude 稀缺昂贵，只做高杠杆思考；Codex 充裕，承担一切吃 token 的体力活。

## 📱 看板（手机直接打开）

> **首次使用需一次性配置**（约 1 分钟，之后永久有效）：
> 1. 进入仓库 **Settings → Pages**
> 2. Source 选 **Deploy from a branch**
> 3. Branch 选 `main`，目录选 `/docs`
> 4. 点 **Save**，等待约 1 分钟后 GitHub 完成构建

配置完成后，看板地址：

**https://steveng3.github.io/atelier/dashboard/**

60 秒自动刷新，无需登录，显示所有活跃 Issue / PR 状态、Claude-Codex 最近交互、以及高亮"待你合并"的 PR。

## 你只需要做两件事

设置完成后，Claude 定时任务自动处理所有中间步骤：

```
① 创建 Issue（手机 GitHub mobile）→ 加 claude:design 标签
              ↓
    Claude 自动：写规格 → 打 codex:go → Codex 自动实现
    Claude 自动：回复 Codex 问题、评审 PR
              ↓
② 合并 PR（手机 GitHub mobile 点 Merge）
```

## 完整工作流（全自动版）

```
你开 Issue（带验收标准 + project: <name>）→ 加 claude:design
  → [自动] Claude 写规格 → 打 codex:go + codex:implement
  → [自动] Codex 切分支实现
  → [自动] Codex 遇问题 → @claude + needs-response
  → [自动] Claude 回复决策 → Codex 继续
  → [自动] Codex 开 PR + claude:review
  → [自动] Claude 评审 → Approve
  → 【你】合并 PR → 闭环
```

## 手动控制（需要时）

```bash
./scripts/atelier.sh status       # 查看所有待处理项
./scripts/atelier.sh next         # 立即触发 Claude 处理最高优先级项
./scripts/atelier.sh go <N>       # 手动给 Issue #N 加 codex:go
./scripts/atelier.sh done <N>     # 停止 Codex（移除 codex:go）
```

或在 GitHub mobile → Actions → "手动触发 Claude" → Run workflow（备用继续键）。

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

