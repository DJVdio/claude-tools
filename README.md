# claude-tools

个人自制的 Claude Code 扩展合集：skills + plugins。

## 目录结构

```
claude-tools/
├── plugins/
│   └── ruler-engine/          Claude Code plugin，项目级规则注入引擎
└── skills/
    ├── archive-ops/           需求文档归档 + 过去经验教训读档
    ├── db-ops/                MySQL 安全操作（TEST 直连 / PROD 出 SQL）
    └── dev-workflow/          研发全流程三件套（产品 → 全栈 → 测试）
        ├── _shared/           跨 skill 共享 reference
        ├── product-designer/  写 PRD / 拆需求 / 可行性评估
        ├── fullstack-builder/ 读需求 → 实现 → self-review → 改动摘要
        └── test-runner/       生成测试用例 / 跑测试
```

---

## Plugins

### [ruler-engine](plugins/ruler-engine/)

可插拔的规则注入引擎：读项目下 `.claude-rules/ruler.yml`，通过 `UserPromptSubmit` / `PreToolUse` hook 自动把规则注入 Claude 的 prompt。零业务规则，作者在自己项目里写 rule。

**依赖**：`yq` + `jq` + `python3`
**安装**：

```bash
/plugin marketplace add https://github.com/DJVdio/claude-tools
/plugin install ruler-engine
```

详情见 [plugins/ruler-engine/README.md](plugins/ruler-engine/README.md)。

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

## License

MIT
