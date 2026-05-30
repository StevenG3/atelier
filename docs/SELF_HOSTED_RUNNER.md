# Self-hosted Runner 注册(事件驱动拉起 codex)

打 `codex:go` 标签 → GitHub 瞬间触发 `.github/workflows/codex-implement.yml`
→ 你机器上的 self-hosted runner 跑 orchestrator 一个 tick。无需常驻 daemon。

## 一次性注册(你在终端做)

GitHub 会给一段带 token 的安装命令(token 只能从网页/API 拿,我无法代取)。

### 方式 A:网页(最简单)

1. 打开 `https://github.com/StevenG3/atelier/settings/actions/runners/new`
2. 选 **Linux x64**,照页面给的命令在服务器跑(下载 + `./config.sh`,含一次性 token)
3. 注册时建议:
   - Runner group:Default
   - Labels:保留默认 `self-hosted`(workflow 用 `runs-on: self-hosted`)
   - Work folder:默认

### 方式 B:命令行拿 token

```bash
# 拿注册 token(有 repo admin 权限)
TOKEN=$(gh api -X POST repos/StevenG3/atelier/actions/runners/registration-token --jq .token)

mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o runner.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz
# 或到 https://github.com/actions/runner/releases 取对应版本
tar xzf runner.tar.gz
./config.sh --url https://github.com/StevenG3/atelier --token "$TOKEN" --unattended --labels self-hosted
```

## 装成常驻服务(开机自启 + 崩溃重拉)

```bash
cd ~/actions-runner
sudo ./svc.sh install gggqqy     # 以 gggqqy 用户运行,能访问 ~/.codex ~/.claude ~/.config/gh
sudo ./svc.sh start
sudo ./svc.sh status
```

> 必须以 **gggqqy** 用户运行,否则 runner 找不到 codex/claude/gh 的 OAuth 凭据。

## 验证

```bash
# runner 在线?
gh api repos/StevenG3/atelier/actions/runners --jq '.runners[]|{name,status}'

# 手动触发一个 tick 测试
gh workflow run orchestrator --repo StevenG3/atelier
gh run list --repo StevenG3/atelier --workflow orchestrator --limit 3
```

## 触发方式一览

| 触发 | 时机 | 安全 |
|---|---|---|
| `issues labeled codex:go` | 你/Claude 打标签即时触发 | ✓ 打标签需写权限,外部无法触发 |
| `schedule` 每 10 分钟 | 兜底推进 CI修复/评审/合并/规划 | ✓ 内部定时 |
| `workflow_dispatch` | 手动 `gh workflow run orchestrator` | ✓ 需权限 |

**绝不用 `pull_request` 触发**——public repo 下 fork PR 会在本机跑任意代码。

## 安全提醒

- atelier/aegis 当前是 **public**。self-hosted runner + public repo 的唯一风险是
  fork PR 触发;本 workflow 已规避(不监听 pull_request)。
- 如需最彻底隔离:把 repo 设为 private(`gh repo edit StevenG3/atelier --visibility private`)。

## 停止

```bash
touch /home/gggqqy/archives/atelier/.atelier-stop   # 暂停循环(runner 仍在,但 tick 立即退出)
sudo ~/actions-runner/svc.sh stop                    # 停 runner
```
