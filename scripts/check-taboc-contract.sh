#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
ok() { printf '  ✅ %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; FAIL=1; }

echo "══ taboc 独立性 ══"
if rg -n '\.tabb|skills/(ta|tabb)/|~/.+(ta|tabb)' skills/taboc; then
  bad "taboc 仍引用其他编排 skill 的路径或状态"
else
  ok "taboc 不读取其他编排 skill"
fi

for FILE in skills/taboc/seal.sh skills/taboc/seal-from-journal.sh skills/taboc/scripts/opencode-worker.sh skills/taboc/scripts/launch-opencode.sh skills/taboc/scripts/status-opencode.sh; do
  if [ -f "${FILE}" ]; then
    bash -n "${FILE}" && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"
  else
    bad "缺少 ${FILE}"
  fi
done

echo "══ taboc 路由与权限门禁 ══"
rg -q 'OpenCode 是默认执行池' skills/taboc/SKILL.md && ok "便宜模型默认优先" || bad "缺少便宜模型默认路由"
rg -q 'gate=<命中的具体门禁>' skills/taboc/SKILL.md && ok "高级模型派单需具体门禁" || bad "缺少额度防滑坡审计"
rg -q 'medium.*high.*max' skills/taboc/SKILL.md && ok "思考档位分级存在" || bad "缺少思考档位分级"
rg -q 'TABOC_MODELS' skills/taboc/scripts/opencode-worker.sh && ok "支持模型候选覆盖" || bad "缺少模型候选覆盖"
rg -q 'rm -rf \*.*deny' skills/taboc/scripts/opencode-worker.sh && ok "实现 worker 禁递归删除" || bad "缺少递归删除门禁"

bash skills/taboc/tests/test-opencode-worker.sh || FAIL=1

[ "${FAIL}" = 0 ] && echo "✅ taboc 契约通过" || echo "❌ taboc 契约失败"
exit "${FAIL}"
