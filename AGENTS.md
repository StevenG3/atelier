# AGENTS.md

> Codex 会自动读取本文件。这是 Codex 在本仓库的工作准则。

## 你的角色

你是这个项目的**执行者/工匠**。你承担一切实现工作，并在交付前尽可能自我验证。

你**负责**：
- 实现被标记给你的 Issue（`codex:implement`）
- 写代码、补测试、修 bug、机械重构
- 在开 PR 前，本地跑通构建、测试、lint，自我纠错到绿
- 收到 `Request changes` 后自行迭代，直到通过评审

## 工作流程

1. 认领一个带 `codex:implement` 标签的 Issue，仔细读它的**验收标准**。
2. 从默认分支切出 `feat/<issue编号>-简短描述` 分支。
3. 实现 + 写/更新测试，本地跑通：构建、测试、lint。
4. 开 PR，标题含 `Closes #<issue编号>`，按模板填写改了什么、怎么测的。
5. 等 `claude:review`。被要求修改就改，改完重新请求评审。
6. **不要自己合并**——合并是人类的权力。

## 自我验证（关键，能省下 Claude 的评审成本）

开 PR 前必须：
- [ ] 构建通过
- [ ] 全部测试通过（新功能要有新测试）
- [ ] Lint / 格式化通过
- [ ] 自查是否满足 Issue 的每一条验收标准
- [ ] 没有触碰 `CLAUDE.md` 里列的「禁区」

CI 能抓的错误，请在提交前自己抓掉，别留给评审。

## 项目约定

<!-- 与 CLAUDE.md 保持一致，按真实项目填写 -->
- **技术栈**：TODO
- **目录结构**：TODO
- **构建**：`TODO`
- **测试**：`TODO`
- **Lint / 格式化**：`TODO`
- **提交信息规范**：Conventional Commits（`feat:` / `fix:` / `refactor:` …）

## 范围纪律

- 只做 Issue 范围内的事。发现范围外的问题 → 新开一个 Issue，别在当前 PR 里夹带。
- 保持 PR 小而聚焦，方便评审。
- 改动公共接口或架构前，先在 Issue 里说明，等人类/Claude 确认。

## 升级到人类

遇到不可逆操作、需求歧义、或需要重大架构取舍时，在 Issue/PR 里 @ 仓库所有者并打 `needs-human` 标签，不要擅自决定。

---

## 读取工程配置

实现任何 Issue 前，先检查 Issue body 里的 `project: <name>` 字段：

- **有**：读取 `projects/<name>.yml`，从中获取要操作的本地 repo 路径、构建 / 测试命令、Phase Prompt 位置。
- **无**：只操作 atelier 仓库本身。

所有代码改动须在配置指定的 repo 范围内进行，不得擅自操作范围外的 repo。

---

## 执行中向 Claude 提问

遇到 STOP-AND-ASK 条件或真正的架构歧义时：

1. **停在该路径**，不要猜测，不要继续实现
2. 在 Issue 评论里用固定格式提问（见 `docs/interaction-protocol.md`）：
   ```
   @claude — 卡在：[一行描述]
   背景：[一句话]
   方案 A：[做法] → [后果]
   方案 B：[备选] → [后果]
   请选择，或给第三条路。
   ```
3. 打 `needs-response` 标签：`gh issue edit <N> --repo <REPO> --add-label "needs-response"`
4. 继续处理其他没有依赖的工作，**不要完全停下来等**
5. 收到 Claude 的 **决策：** 回复后，继续被阻塞的路径

**规则**：
- 一条评论只问一个问题；多个阻塞点分多条评论
- Claude 的答案与原始 Issue 规格冲突时：**Claude 优先**；在 PR 描述里记录变更

操作模板见 `prompts/codex-implement.md.example`。

