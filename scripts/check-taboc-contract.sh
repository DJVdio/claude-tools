#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${0}")/.."

SKILL="skills/taboc/SKILL.md"
FAIL=0
ok()  { printf '  ✅ %s\n' "${1}"; }
bad() { printf '  ❌ %s\n' "${1}"; FAIL=1; }
need() {
  grep -Fq "${1}" "${SKILL}" && ok "${2}" || bad "${2}"
}

echo "══ taboc 独立性与核心契约 ══"
BYTES="$(wc -c < "${SKILL}" | tr -d ' ')"
LINES="$(wc -l < "${SKILL}" | tr -d ' ')"
[ "${BYTES}" -le 10000 ] && ok "SKILL.md ${BYTES} bytes ≤ 10000" || bad "SKILL.md 过大：${BYTES} bytes"
[ "${LINES}" -le 140 ] && ok "SKILL.md ${LINES} lines ≤ 140" || bad "SKILL.md 过长：${LINES} lines"

need '仅在用户显式调用 `/taboc`' "只手动触发"
need '不读取其他 skill' "独立运行"
need 'OpenCode **只执行纯只读任务**' "OpenCode 只读边界"
need '路由只认下表五档' "固定五档路由"
need '文件多、耗时长、测试慢只是拆单信号' "规模不触发 Sol"
need '选 Sol 必须' "Sol 升档有理由"
need '额度期 Luna `low`' "额度期 Luna-low"
need '目标模型等于当前主模型' "支持父模型继承"
need '禁止换模型' "禁止静默替换"
need '【taboc premium 协议】' "premium worker 协议自包含"
need 'seal-from-journal.sh --dry-run' "收口预检"
need '[references/failures.md](references/failures.md)' "异常手册按需加载"

if rg -q '\.tabb|skills/(ta|tabb)/|~/.+(ta|tabb)' skills/taboc; then
  bad "taboc 仍引用其他编排 skill"
else
  ok "taboc 无其他编排 skill 依赖"
fi
if grep -REq -- '--profile|profile=simple|simple_protocol|TABOC_MAX_ATTEMPTS' skills/taboc/scripts; then
  bad "OpenCode 运行时仍含已删除的写入 profile/重试分支"
else
  ok "OpenCode 运行时仅保留只读路径"
fi
grep -Fq '"*":"deny"' skills/taboc/scripts/opencode-worker.sh \
  && grep -Fq '".taboc/journal.md":"allow"' skills/taboc/scripts/opencode-worker.sh \
  && ok "OpenCode 权限默认拒绝，仅放行读与 journal" || bad "OpenCode 只读权限不完整"
grep -q 'launchctl bootstrap' skills/taboc/scripts/launch-opencode.sh && ok "launchd 一次性托管" || bad "缺 launchd 启动"
grep -q 'model-query.lock' skills/taboc/scripts/opencode-worker.sh && ok "模型查询有并发锁" || bad "模型查询无并发锁"
grep -q -- '--idle-timeout' skills/taboc/scripts/opencode-worker.sh \
  && grep -q -- '--hard-timeout' skills/taboc/scripts/opencode-worker.sh \
  && ok "同时有 idle/hard timeout" || bad "超时门禁不完整"
grep -q '\[POOL_QUOTA\].*no free-model fallback' skills/taboc/scripts/opencode-worker.sh \
  && ok "限额后不试其他免费模型" || bad "限额可能继续回退"

for FILE in skills/taboc/*.sh skills/taboc/scripts/*.sh; do
  [ -f "${FILE}" ] && { bash -n "${FILE}" && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"; }
done
for FILE in skills/taboc/scripts/*.py; do
  python3 -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "${FILE}" \
    && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"
done
bash skills/taboc/tests/test-opencode-worker.sh || FAIL=1

[ "${FAIL}" = 0 ] && echo "✅ taboc 契约通过" || echo "❌ taboc 契约失败"
exit "${FAIL}"
