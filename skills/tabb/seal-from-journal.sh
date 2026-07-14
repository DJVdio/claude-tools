#!/usr/bin/env bash
# 从 .tabb/journal.md 的 [SEAL] 行生成收口清单并跑 seal.sh —— 零 LLM 阅读理解。
#
#   用法:  seal-from-journal.sh [--dry-run] [<.tabb 目录，默认 ./.tabb>]
#
# 为什么存在：journal 的 [DONE] 是给人看的长篇分析（几十行 markdown、口径判据、
# 对照表），让 git-ops 用眼睛从里面抠文件名 = 把 seal.sh 省下的往返又赔回去。
# 所以干活 agent 完工时**额外 append 一行机器可读的 [SEAL]**，格式就是 seal
# 清单的一行——生产者最知道自己改了哪些文件（它刚一个个 mkdir 锁过），
# 由它直接吐出结构化行，消费者一条 grep 就拿到清单。
#
#   [SEAL] <仓绝对路径> | <子模块名或 -> | <分支> | <文件,逗号分隔> | <commit msg>
#
# 本脚本负责：抽行 → 去掉已收口的 → 同仓多 agent 聚合（文件合并去重、msg 拼接）
#            → 调 seal.sh → 成功后记账（防下次重复收口）
set -uo pipefail

DRY=""
[ "${1:-}" = "--dry-run" ] && { DRY="--dry-run"; shift; }
TABB=${1:-.tabb}
J="${TABB}/journal.md"
SEALED="${TABB}/sealed.log"

[ -f "${J}" ] || { echo "❌ 找不到 ${J}"; exit 2; }
touch "${SEALED}"

# ── 1. 抽 [SEAL] 行 ──
RAW=$(grep '^\[SEAL\]' "${J}" 2>/dev/null | sed 's/^\[SEAL\][[:space:]]*//')
if [ -z "${RAW}" ]; then
  echo "❌ journal 里没有任何 [SEAL] 行。"
  echo "   干活 agent 完工时必须 append 一行："
  echo "   [SEAL] <仓绝对路径> | <子模块或 -> | <分支> | <文件,逗号分隔> | <commit msg>"
  echo "   （派单协议块里有这条；缺了就得靠 LLM 从长篇 [DONE] 里抠文件名，慢且易错）"
  exit 2
fi

# ── 2. 去掉已收口的（防重复收口）──
NEW=$(printf '%s\n' "${RAW}" | grep -vxFf "${SEALED}" 2>/dev/null || true)
if [ -z "${NEW}" ]; then
  echo "✅ 无待收口内容：journal 里 $(printf '%s\n' "${RAW}" | grep -c .) 条 [SEAL] 全部已收口。"
  exit 0
fi

# ── 3. 同仓多 agent 聚合：文件合并去重、msg 拼接 ──
MANIFEST=$(mktemp)
printf '%s\n' "${NEW}" | awk -F'|' '
function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
{
  repo=trim($1); sub_=trim($2); br=trim($3); fs=trim($4); msg=trim($5)
  if (repo=="" || fs=="") next
  key=repo"|"sub_"|"br
  if (!(key in seen)) { seen[key]=1; order[++n]=key }
  # 文件合并 + 去重
  m=split(fs, arr, ",")
  for (i=1;i<=m;i++) {
    f=trim(arr[i]); if (f=="") continue
    if (!((key SUBSEP f) in hasfile)) { hasfile[key SUBSEP f]=1; files[key]=files[key](files[key]?",":"")f }
  }
  if (msg!="") msgs[key]=msgs[key](msgs[key]?"; ":"")msg
}
END{ for(i=1;i<=n;i++){ k=order[i]; print k" | "files[k]" | "msgs[k] } }
' > "${MANIFEST}"

echo "══ 从 journal 的 [SEAL] 行生成的收口清单（零 LLM 解析）══"
sed 's/^/  /' "${MANIFEST}"
echo

# ── 4. 跑 seal.sh ──
RESULT=$(mktemp)
SEAL_RESULT_FILE="${RESULT}" bash "$(dirname "$0")/seal.sh" ${DRY} "${MANIFEST}"
RC=$?

# ── 5. 按仓记账（只记成功落地的仓；失败的仓留着，重跑时只收它）──
if [ -z "${DRY}" ]; then
  OKN=0
  while IFS='|' read -r st repo; do
    [ "${st}" = "OK" ] || continue
    # 该仓的所有 [SEAL] 原始行（可能来自多个 agent）记账
    while IFS= read -r line; do
      [ -z "${line}" ] && continue
      r=$(printf '%s' "${line}" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')
      [ "${r}" = "${repo}" ] && { printf '%s\n' "${line}" >> "${SEALED}"; OKN=$((OKN+1)); }
    done <<< "${NEW}"
  done < "${RESULT}"
  [ "${OKN}" -gt 0 ] && echo "已记账 ${OKN} 条 [SEAL]（仅成功落地的仓）到 ${SEALED}——下次不再重复收。"
  if [ "${RC}" != 0 ]; then
    echo "⚠️ 失败的仓未记账：解决它的问题后**直接重跑本脚本**——已成功的仓已记账、会被自动跳过，只收失败的那个。"
  fi
fi
exit "${RC}"
