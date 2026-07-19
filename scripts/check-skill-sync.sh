#!/usr/bin/env bash
# 校验 ta / tabb 两套 skill 的「独立可安装」契约。
#
# 背景：ta 和 tabb 是两套可独立安装的 skill。单装任一套都必须完整可用——
#       因为跑 /tabb 时只有 tabb/SKILL.md 进上下文，ta 的正文不会出现。
#       跨 skill 的「沿用 ta，不赘述」是**悬空引用**：对人有效，对 agent 无效。
#       （实战教训：tabb 收口节写「沿用 ta」，agent 压根不知道 seal.sh 存在，
#         于是三次收口全在逐条发 git 命令。）
#
# 用法: bash scripts/check-skill-sync.sh
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
ok()   { printf '  ✅ %s\n' "$1"; }
bad()  { printf '  ❌ %s\n' "$1"; FAIL=1; }

echo "══ 1. 两份 seal.sh 必须逐字一致 ══"
if diff -q skills/ta/seal.sh skills/tabb/seal.sh >/dev/null 2>&1; then
  ok "skills/{ta,tabb}/seal.sh 一致 ($(shasum -a 256 skills/ta/seal.sh | cut -c1-12))"
else
  bad "两份 seal.sh 已漂移！改了一份要同步另一份："
  diff skills/ta/seal.sh skills/tabb/seal.sh | head -20
fi

echo "══ 2. 每套 skill 都得自带 seal.sh ══"
for s in ta tabb; do
  if [ -f "skills/${s}/seal.sh" ]; then ok "skills/${s}/seal.sh 存在"
  else bad "skills/${s}/seal.sh 缺失——单装 ${s} 时收口会失败"; fi
done

echo "══ 2b. tabb 专属脚本（ta 无 journal，不需要它）══"
if [ -f "skills/tabb/seal-from-journal.sh" ]; then
  ok "skills/tabb/seal-from-journal.sh 存在（从 [SEAL] 行零解析生成收口清单）"
  bash -n skills/tabb/seal-from-journal.sh 2>/dev/null \
    && ok "seal-from-journal.sh 语法通过" || bad "seal-from-journal.sh 语法错误"
else
  bad "skills/tabb/seal-from-journal.sh 缺失——git-ops 会退回用眼睛抠白名单（收口卡 6 分钟）"
fi
for f in skills/tabb/scripts/register-assignment.sh skills/tabb/scripts/task-panel.sh; do
  if [ -f "${f}" ]; then
    bash -n "${f}" 2>/dev/null && ok "${f} 存在且语法通过" || bad "${f} 语法错误"
  else
    bad "缺少 ${f}——tabb 模型登记或任务面板不可用"
  fi
done
if diff -q skills/tabb/scripts/check-model-ceiling.py skills/taboc/scripts/check-model-ceiling.py >/dev/null 2>&1; then
  ok "tabb/taboc 模型上限门禁一致且各自独立携带"
else
  bad "tabb/taboc 的同系列模型上限门禁已漂移"
fi

echo "══ 3. 不得引用对方 skill 的文件路径（跨 skill 依赖 = 单装即坏）══"
if grep -n 'skills/tabb/' skills/ta/SKILL.md 2>/dev/null; then
  bad "ta/SKILL.md 引用了 tabb 的文件——单装 ta 时会指向不存在的路径"
else ok "ta/SKILL.md 不依赖 tabb 的文件"; fi
if grep -n 'skills/ta/' skills/tabb/SKILL.md 2>/dev/null; then
  bad "tabb/SKILL.md 引用了 ta 的文件——单装 tabb 时会指向不存在的路径"
else ok "tabb/SKILL.md 不依赖 ta 的文件"; fi

echo "══ 4. 不得留「沿用/不赘述」式悬空引用（对 agent 无效）══"
HITS=$(grep -nE '(沿用|复用|同) \[\[ta\]\]|不赘述|沿用 ta' skills/tabb/SKILL.md 2>/dev/null)
if [ -n "${HITS}" ]; then
  bad "tabb/SKILL.md 有悬空引用——agent 读不到 ta 的正文，必须就地展开："
  echo "${HITS}" | sed 's/^/     /'
else ok "tabb/SKILL.md 无悬空引用（提及 ta 仅用于选型对比）"; fi

echo "══ 5. seal.sh 语法 + 变量边界地雷（变量后紧跟中文标点会被吃进变量名）══"
for s in ta tabb; do
  f="skills/${s}/seal.sh"
  bash -n "${f}" 2>/dev/null && ok "${f} 语法通过" || bad "${f} 语法错误"
  if grep -qP '\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F{]' "${f}" 2>/dev/null; then
    bad "${f} 有变量边界地雷（用 \${VAR} 划清边界）："
    grep -nP '\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F{]' "${f}" | sed 's/^/     /'
  else ok "${f} 无变量边界地雷"; fi
done

echo
[ "${FAIL}" = 0 ] && echo "✅ 全部通过：ta / tabb 各自独立可安装" \
                  || echo "❌ 有检查未通过，见上方"
exit "${FAIL}"
