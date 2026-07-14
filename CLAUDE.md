# CLAUDE.md

个人的 Claude Code 扩展合集（skills + plugins）。目录结构与安装方式见 [README](README.md)——这里只写**不看就会犯错**的东西。

## 改动 `skills/{ta,tabb}/` 之前，先读这三条

这两套是**平行且各自独立可安装**的多 agent 编排 skill。下面三条都是实战踩出来的，不是理论洁癖。

### 1. 跨 skill 引用对 agent 是悬空的

跑 `/tabb` 时**只有 `tabb/SKILL.md` 进上下文**，ta 的正文不会出现。所以「沿用 ta，不赘述」这种写法对人是有效引用，**对 agent 是空的**——它不会跑去读 ta，只会当那段内容不存在，然后自己现编一套。

（真实后果：tabb 的收口节写了「全部沿用 ta」，于是 agent 压根不知道 `seal.sh` 存在，连着三次收口都在逐条发 git 命令。）

同理，`tabb/SKILL.md` 里任何指向 `~/.claude/skills/ta/` 的路径，在只装了 tabb 的机器上都是死链。**每套 skill 要用的东西，自己目录里必须有一份。**

### 2. 两份 `seal.sh` 必须逐字一致

`skills/ta/seal.sh` 和 `skills/tabb/seal.sh` 是同一个文件的两份拷贝（因为两套 skill 谁都不能依赖对方存在）。**改了一份就同步另一份。**

### 3. 改完必须跑校验

```bash
bash scripts/check-skill-sync.sh
```

校验上面三条（两份一致 / 不引用对方路径 / 无悬空引用）外加 shell 语法与变量边界地雷。做过负向测试，不是恒绿的摆设。

## 写 shell 脚本时：变量后面紧跟中文标点会炸

```bash
echo "指针 → $NEW_PTR（rev-parse 取值）"   # ❌ unbound variable
echo "指针 → ${NEW_PTR}（rev-parse 取值）" # ✅
```

bash 会把全角括号、中文逗号的多字节字符吃进变量名。**所有变量引用一律 `${VAR}` 划清边界。** `check-skill-sync.sh` 会扫这个。

## 性能直觉：瓶颈永远是 LLM 工具往返，不是 I/O

这个仓库里的 skill 都是给 agent 用的，优化时别把力气花错地方。实测过的数量级：

| | 耗时 |
|---|---|
| 一次 `mkdir` 原子锁（含写 meta、放锁） | 161 µs |
| 一次 bash 进程启动 | ~4.5 ms |
| 一次 `python3` 冷启动 | ~16–28 ms |
| **一次 LLM 工具往返**（模型生成调用 → 执行 → 读回结果继续推理） | **2–5 秒** |

所以：

- **磁盘不是瓶颈。** `.tabb/` 那些几百字节的小文件读写全在内核 page cache 里（`mkdir`/`write` 都不 `fsync`），落盘是异步 writeback。"把黑板搬进内存"没有收益——OS 已经免费给了。详见 [`docs/superpowers/specs/2026-07-10-tabb-design.md`](docs/superpowers/specs/2026-07-10-tabb-design.md) 的「性能调研」节。
- **优化只有一个杠杆：减少工具往返次数。** 把固定流水线（git 收口这种中间没有模型决策分叉的）打包成一条 Bash，20–30 次往返 → 1 次。
- **别让 LLM 现编 shell。** 模型逐 token 吐一行带 `sed` 转义的命令要秒级，比执行它贵几十倍，还每次都可能写歪。固化成脚本。

## 让生产者吐结构化数据，别让消费者解析自由文本

tabb 的 `[SEAL]` 行就是这个原则的落地：干活 agent 完工时除了写给人看的长篇 `[DONE]`（那些根因分析有价值，别去限制它），**另写一行机器可读的 `[SEAL]`**——格式就是收口清单的一行。于是 git-ops 一条 `grep` 拿到白名单，零阅读理解。

反例是它的前身：让 git-ops 去翻几百 KB 的 journal、从几十行叙述性 `[DONE]` 里用眼睛把文件名抠出来再跟工作区对账。那是纯 LLM 阅读理解，**实测让一次收口卡 6 分钟**，把 `seal.sh` 省下的往返全赔了回去。

判据一句话：**谁最知道这个信息，就让谁直接写成机器可读的形式**——干活 agent 刚一个个 `mkdir` 锁过那些文件，它最清楚自己改了什么。

## git

- 直接提交推送 `main`（个人仓库，历史惯例如此）。
- push 撞 GitHub SSH 瞬时故障（`Connection closed by ... port 22`）是常事——**隔几秒重试即可**，commit 已经在本地，成果不会丢。
