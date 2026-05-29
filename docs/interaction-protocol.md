# 问答协议 — Claude × Codex 执行中交互规范

> 本文件定义 Claude（架构师）和 Codex（执行者）在执行过程中如何通过 GitHub 相互沟通。
> 与具体工程无关；所有接入 atelier 的工程均遵守此协议。

---

## 全自动协作闭环

```
你创建 Issue（写验收标准）
  → 打 claude:design 标签
    → Claude 检测到 → 在 Issue 写规格 → 打 claude:spec-ready 标签
      → 你打 codex:go 标签
        → Codex App 触发 → 切分支实现
          → 遇到 STOP-AND-ASK
            → Codex 在 Issue 评论 @claude 提问 → 打 needs-response 标签
              → Claude 检测到 → 用决策格式回复 → 移除 needs-response 标签
                → Codex 读到决策 → 继续实现 → 开 PR → 打 claude:review 标签
                  → Claude 检测到 → 评审 PR → Approve / Request changes
                    → 【你】合并
```

**你只需要做两件事**：打 `codex:go` 标签 + 最终合并 PR。

---

## Codex → Claude 提问格式

在 Issue 评论里使用以下固定格式，**不要随意发挥**：

```
@claude — 卡在：[一行描述，说明具体阻塞点]

背景：[一句话，说明当前实现状态]

方案 A：[Codex 打算怎么做] → [预期后果或风险]
方案 B：[备选做法] → [预期后果或风险]

请选择其中一个，或给出第三条路。
```

**规则**：
- 一条评论只问一个问题。多个阻塞点分多条评论逐一发出。
- 等回复时继续处理其他没有依赖的工作，不要完全停下来等。
- 发完评论后打 `needs-response` 标签，让 Claude 定时任务能检测到。

---

## Claude → Codex 决策格式

Claude 回复时使用以下固定格式，**不给菜单，只给决策**：

```
**决策：** [一个清晰答案，不含"两者皆可"或"取决于"]
**理由：** [一句话]
**行动：** 继续 | 等人类 | 停止
```

**规则**：
- 一个问题一个决策，不拆成多个回复。
- 如果决策导致规格变更，Claude 须同时用 `gh issue edit` 更新 Issue body（不只是评论）。
- 回复后移除 `needs-response` 标签。
- 如果真的无法决策，打 `needs-human` 标签并说明缺少哪些信息。

---

## 何时 Codex 必须提问

以下情况**强制提问**，不得猜测：

- Phase N Prompt 里明确列出的 STOP-AND-ASK 条件
- 需要操作 ALLOWED FILES 列表以外的文件
- 规格有歧义且不同解读会导致不兼容的实现
- 不可逆操作（删数据、改 schema、改公共 API）

---

## 何时 Codex 不需要提问

以下情况**自行判断**，不要浪费 Claude 的额度：

- 实现细节（数据结构选择、函数拆分方式）
- 测试结构（测试文件命名、fixture 组织方式）
- 变量命名、注释风格、代码格式

---

## 冲突处理

如果 Claude 的回答与 Phase N Prompt 或原始 Issue 规格冲突：

- **Claude 的实时回答优先**（Claude 是架构师，有权更新规格）
- Codex 须在 PR 描述里记录：`Claude 决策覆盖了原始规格 §X：[说明]`
- Claude 须同步更新 Issue body，保持文档一致

---

## 交互日志惯例

每次完成一轮 Q&A，Claude 或 Codex 在置顶的「交互日志」Issue 里追加一条记录：

```
### 交互 #N — YYYY-MM-DD HH:MM UTC

| 字段 | 内容 |
|---|---|
| **关联 Issue/PR** | #[N] — [标题] |
| **提问方** | Codex |
| **问题摘要** | [一行] |
| **Claude 决策** | [一行] |
| **行动** | 继续 / 等人类 / 停止 |
| **规格是否变更** | 是（Issue #N 已更新）/ 否 |
```
