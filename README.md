# claude-tools

个人自制的 Claude Code 扩展合集：skills + plugins。

## 目录结构

```
claude-tools/
├── plugins/
│   ├── ruler-engine/          Claude Code plugin，项目级规则注入引擎
│   └── karpathy-rules/        ruler-engine 的首个消费者，4 条 Karpathy 风格行为规则
├── scripts/
│   └── check-skill-sync.sh    校验 ta/tabb 各自独立可安装（改任一 seal.sh 后必跑）
└── skills/
    ├── archive-ops/           需求文档归档 + 过去经验教训读档
    ├── db-ops/                MySQL 安全操作（TEST 直连 / PROD 出 SQL）
    ├── large-file-write/      写超大文件（>1000 行）时防 socket 断开的分片策略
    ├── ta/                    多 agent 团队编排——主从星型（主 agent 集中调度 subagent）
    │   └── seal.sh            git 收口流水线：一条 Bash 跑完 add→commit→push→刷指针→三步核验，多仓并发
    ├── tabb/                  多 agent 团队编排——去中心化黑板（agent 靠共享黑板自助避让文件冲突）
    │   ├── seal.sh            同上（与 ta 的逐字一致；两套 skill 各自独立可装，谁都不依赖对方）
    │   └── seal-from-journal.sh  从 journal 的 [SEAL] 行零解析生成收口清单 → 调 seal.sh
    ├── taboc/                 异构多 agent 编排——OpenCode 免费模型优先，高风险任务升级高级模型
    │   ├── scripts/           launchd 后台启动、模型/档位探测、免费模型轮换、状态聚合
    │   ├── seal.sh            taboc 自带的独立 git 收口流水线
    │   └── seal-from-journal.sh  从独立 .taboc/journal.md 收口
    └── dev-workflow/          研发全流程三件套（产品 → 全栈 → 测试）
        ├── _shared/           跨 skill 共享 reference
        ├── product-designer/  写 PRD / 拆需求 / 可行性评估
        ├── fullstack-builder/ 读需求 → 实现 → self-review → 改动摘要
        └── test-runner/       生成测试用例 / 跑测试
```

---

## Plugins

### [ruler-engine](plugins/ruler-engine/) `v0.2.0`

可插拔的规则注入引擎：读项目下 `.claude-rules/ruler.yml`，通过 `UserPromptSubmit` / `PreToolUse` hook 自动把规则注入 Claude 的 prompt。零业务规则，作者在自己项目里写 rule。

**v0.2.0 新增**：插件级规则源（其他插件声明 `"ruler": true` 即可被本引擎发现）、`disable: [glob]` 过滤、`/tmp` 缓存、`ruler-engine-lint --file` / `ruler-engine-dry-run --sources`。向后兼容 0.1.0。

**依赖**：`yq` + `jq` + `python3`
**安装**：

```bash
/plugin marketplace add https://github.com/DJVdio/claude-tools
/plugin install ruler-engine
```

详情见 [plugins/ruler-engine/README.md](plugins/ruler-engine/README.md)。

### [karpathy-rules](plugins/karpathy-rules/) `v0.1.0`

4 条 Andrej Karpathy 风格的行为规则（think-before-coding / simplicity-first / surgical-changes / goal-driven-execution），改编自 [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)。作为 ruler-engine 的首个消费者插件，展示插件级规则源机制。

**依赖**：`ruler-engine >= 0.2.0`
**安装 + 启用**：

```bash
/plugin install karpathy-rules
# 然后在项目 .claude-rules/ruler.yml 顶层加：
#   load_plugin_sources: true
```

详情见 [plugins/karpathy-rules/README.md](plugins/karpathy-rules/README.md)。

---

## Skills

Skill 是 Claude Code 可发现的工具，**安装方式**：把 `skills/` 下目标目录软链到 `~/.claude/skills/<name>/`，Claude Code 启动时自动加载。

### [archive-ops](skills/archive-ops/)

本地归档完成的需求文档 + 读档查相关经验教训。含 Python 脚本（`archive_ops.py`）和倒排索引。

**用户数据（`data/archives/` + `data/index.json`）不会上传到本仓库**，首次运行时在本地生成。

```bash
ln -s "$PWD/skills/archive-ops" ~/.claude/skills/archive-ops
cd ~/.claude/skills/archive-ops && pip install -r requirements.txt
```

### [db-ops](skills/db-ops/)

MySQL 数据库安全操作：TEST 库直连执行，PROD 库仅渲染 SQL 文本走 DBA 审批流。含 Python 脚本（`db_ops.py`）+ SQL 分类/风险判定单元测试。

**`config.yml` 和 `audit.log` 不会上传**。用 `config.example.yml` 作模板：

```bash
ln -s "$PWD/skills/db-ops" ~/.claude/skills/db-ops
cd ~/.claude/skills/db-ops
cp config.example.yml config.yml     # 填本地 DB 凭证（已被 .gitignore 忽略）
pip install -r requirements.txt
python3 -m pytest tests/ -v
```

### [large-file-write](skills/large-file-write/)

写超大文件（>1000 行）时，单次 Write 很容易触发 `socket connection was closed unexpectedly`。本 skill 把过程拆成"骨架 + 哨兵 + 分片 Edit"，单次 tool call 控制在 300 行以内，规避 socket 断开。

**安装**（纯 SKILL.md，零依赖）：

```bash
cd /path/to/claude-tools   # 先进入本仓库根目录（$PWD 才会指对）
ln -s "$PWD/skills/large-file-write" ~/.claude/skills/large-file-write
# 或直接写死绝对路径:
#   ln -s /Users/<you>/claude-tools/skills/large-file-write ~/.claude/skills/large-file-write
```

触发方式：Claude 遇到写大文件场景或收到 socket 错误时自动命中；也可直接说"用分片写 xxx.html"。

### 多 agent 团队编排：[ta](skills/ta/) 与 [tabb](skills/tabb/)

两套**平行且各自独立可安装**的编排 skill——单装任一套都完整可用，谁都不依赖对方。都只通过 `/ta` / `/tabb` 手动触发，不自动命中。

|  | [ta](skills/ta/)（主从星型） | [tabb](skills/tabb/)（去中心化黑板） |
|---|---|---|
| 协调方式 | 主 agent 集中裁决，所有协调过它 | agent 通过共享黑板文件（`.tabb/`）自助协调 |
| 硬内核 | 干净的全局台账、简单可控 | **并行改同一仓时的文件争用避让**（`mkdir` 原子锁，零主 agent 介入） |
| 什么时候用 | 交互式持续派单，任务间文件冲突不频繁 | **多 agent 高频并行改同一仓、公共文件反复被撞** |

**选型第一判据是文件冲突协调的频度，不是任务数量。** 黑板不是免费的（轮询延迟、需清道夫兜死锁），只有"主 agent 成了文件协调瓶颈"这个痛点真实且高频时才值得上 tabb，否则 ta 更省心。

两者都把 subagent 当执行体（侦察 / 实现 / 验证 / git 收口全部派出去），主 agent 不自己写代码。含角色编制、派单 prompt 要素、里程碑进度条、决策上抛、定期回报循环、异常处理手册。

#### git 收口走 `seal.sh`，不逐条发命令

两套 skill 各自带一份 **`seal.sh`**（内容逐字一致）：白名单 add → `diff --cached` 核对 → commit → fetch → 必要时 rebase（工作区脏则先 stash 隔离半成品）→ push → 刷 submodule 指针 → **三步核验**（远端头 == 预期 sha、ahead=0 behind=0），**一条 Bash 跑完，多仓并发，仓间失败隔离**。

这条流水线里没有需要模型决策的分叉，逐条发 git 命令等于把它拆成 20–30 次秒级 LLM 往返（一次收口拖几分钟，多端串行十几分钟）；打包成一条 Bash 只要 1 次。LLM 只保留两个真决策：**白名单点哪些文件、commit message 写什么**。

tabb 额外带 **`seal-from-journal.sh`**：干活 agent 完工时除了写给人看的长篇 `[DONE]`，还必须 append 一行机器可读的 `[SEAL]`（格式就是收口清单的一行）。于是 git-ops 一条命令收口，**零 LLM 阅读理解**——否则它得翻几百 KB 的 journal 从叙述里抠文件名，把 `seal.sh` 省下的往返又赔回去。

```bash
# tabb 的 git-ops 收口（先预检，再落地；失败后直接重跑，成功的仓自动跳过）
bash ~/.claude/skills/tabb/seal-from-journal.sh --dry-run
bash ~/.claude/skills/tabb/seal-from-journal.sh
```

**安装**（纯 SKILL.md + shell 脚本，零依赖；两套独立，可只装其一）：

```bash
cd /path/to/claude-tools   # 先进入本仓库根目录（$PWD 才会指对）
ln -s "$PWD/skills/ta"   ~/.claude/skills/ta
ln -s "$PWD/skills/tabb" ~/.claude/skills/tabb
```

### 异构模型编排：[taboc](skills/taboc/)

`taboc` 是一套完全独立的编排 skill：用自己的 `.taboc/` 黑板和锁，把只读、调研、机械性及低风险实现默认并发派给本机 OpenCode 免费模型；认证、支付、生产数据、架构语义等高风险任务留给 Codex/Claude。DeepSeek V4 会按任务使用 `medium/high/max`，额度或服务失败时自动轮换其他实时可见的免费模型。

OpenCode worker 不占 Codex/Claude subagent 槽，可同时使用两边的并发能力。消耗高级额度的 Codex/Claude 子 agent 必须继承主模型且不得提高 effort；免费 OpenCode 可以强于主 agent，但仍按任务复杂度使用 `medium/high/max`，避免浪费限额和时间。`taboc` 使用一次性 LaunchAgent，自带权限隔离、结构化错误判定、模型/努力程度任务面板、状态聚合与收口脚本，不读取 `ta` 或 `tabb` 的文件。

```bash
cd /path/to/claude-tools
ln -s "$PWD/skills/taboc" ~/.claude/skills/taboc
# Codex 安装则链接到 ~/.codex/skills/taboc
```

仅通过 `/taboc` 手动触发。开发校验：

```bash
bash scripts/check-taboc-contract.sh
```

### [dev-workflow](skills/dev-workflow/)

**研发全流程三件套**：`product-designer` → `fullstack-builder` → `test-runner`，把一个子需求的 PRD / 可行性 / 实现 / self-review / 改动总结 / 测试用例 / 测试报告全部产出到同一目录。

详见 [skills/dev-workflow/README.md](skills/dev-workflow/README.md)。

**硬依赖** `superpowers` plugin：

```bash
/plugin marketplace add https://github.com/obra/superpowers
/plugin install superpowers
```

**安装三个主 skill + shared**（必须同时装，内部相对路径引用 `_shared/`）：

```bash
cd ~/projects/claude-tools/skills/dev-workflow
ln -s "$PWD/_shared"            ~/.claude/skills/_shared
ln -s "$PWD/product-designer"   ~/.claude/skills/product-designer
ln -s "$PWD/fullstack-builder"  ~/.claude/skills/fullstack-builder
ln -s "$PWD/test-runner"        ~/.claude/skills/test-runner
```

可选：`cp config.example.yml config.yml` 固化项目适配（默认自动探测）。

---

## 开发

每个 skill / plugin 在自己子目录里独立维护。`plugins/ruler-engine/` 以 git subtree 形式嵌入，可用 `git subtree pull/push --prefix=plugins/ruler-engine <remote> main` 同步独立 repo。

**改了 `skills/{ta,tabb}/` 之后必须跑一次**：

```bash
bash scripts/check-skill-sync.sh
bash scripts/check-tabb-contract.sh  # 改 tabb 时额外跑：体积预算 + 核心能力回归
bash scripts/check-taboc-contract.sh # 改 taboc 时额外跑：独立性 + 路由 + 权限 + 模型回退
```

`check-skill-sync.sh` 校验 ta / tabb 的「各自独立可安装」契约：两份 `seal.sh` 逐字一致、各自带齐脚本、**不引用对方 skill 的文件路径**、没有「沿用 ta，不赘述」式的悬空引用、shell 语法与变量边界地雷。`check-tabb-contract.sh` 限制 tabb prompt 体积，并守住原子锁、交接、决策上抛、idle 防重派、分层测试和收口门禁。

为什么要这个校验：跑 `/tabb` 时**只有 `tabb/SKILL.md` 进上下文**，ta 的正文不会出现。所以跨 skill 的「沿用 ta，不赘述」对人是有效引用，**对 agent 是悬空的**——它会直接当那段内容不存在，然后自己现编一套。同理，任何指向 `~/.claude/skills/<对方>/` 的路径在单装场景下都是死链。这两类问题都实战踩过，所以固化成了可执行检查。

## License

MIT
