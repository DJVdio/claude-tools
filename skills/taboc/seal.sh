#!/usr/bin/env bash
# git-ops 收口流水线 —— 一次 Bash 跑完整条固定流水线，多仓并发。
#
# 本文件随 taboc 独立分发，不读取其他 skill 的脚本或状态。
#
#   用法:  seal.sh <清单文件>
#          seal.sh --dry-run <清单文件>     # 只预检不落地（不 commit/push）
#
#   清单每行一个仓，字段用 | 分隔（msg 里别用 |）：
#       <仓绝对路径> | <子模块名或 -> | <分支> | <白名单文件,逗号分隔> | <commit msg>
#   例：
#       /repo/web  | sub | main | src/auth.ts,src/login.ts | fix(web): 修登录鉴权
#       /repo/api  | -   | main | api/order.go            | fix(api): 修订单查询
#   `-` 表示该仓没有子模块，跳过刷指针。# 开头与空行忽略。
#
# 铁律（全部由脚本强制，不靠 LLM 自觉）：
#   白名单 add（清单外文件即停） / 空提交即停 / sha 一律 rev-parse 取值禁手写 /
#   push 前 fetch，远端前移则 rebase，冲突即 abort 停在安全点 / 禁 force push /
#   三步核验（刷指针 · 远端头==预期 sha · ahead=0 behind=0）/ 仓间失败隔离
#
# 注：所有变量引用一律 ${VAR}——变量后紧跟中文标点时，bash 会把多字节字符
#     吃进变量名，导致 unbound variable。这是手写 shell 的高发地雷。
set -uo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }
MANIFEST=${1:?用法: seal.sh [--dry-run] <清单文件>}
[ -f "${MANIFEST}" ] || { echo "❌ 清单不存在: ${MANIFEST}"; exit 2; }

LOGDIR=$(mktemp -d)

# ── 单仓流水线（在子 shell 里跑，仓间互不影响）──
seal_one() {
  local REPO=$1 SUB=$2 BR=$3 FILES_CSV=$4 MSG=$5
  local IFS=,; read -ra FILES <<< "${FILES_CSV}"; unset IFS

  die() { echo "❌ FAIL($1): $2"; echo "   → 已停在安全点，未 push；该仓需人工介入"; exit 1; }

  # 有子模块 → 先收子仓；无子模块 → 直接收本仓
  local WORK="${REPO}"
  [ "${SUB}" != "-" ] && WORK="${REPO}/${SUB}"
  cd "${WORK}" || die setup "进不去 ${WORK}"

  echo "── 白名单 add"
  git add -- "${FILES[@]}" || die add "白名单 add 失败"

  echo "── diff --cached 核对"
  local STAGED; STAGED=$(git diff --cached --name-only)
  local RESUME=0
  if [ -z "${STAGED}" ]; then
    # 暂存区空有两种可能：(a) 真没改动；(b) 上次收口已 commit 但在 rebase/push 阶段
    # 失败了 —— 改动都在本地未推的 commit 里。(b) 必须能续推，否则失败后重跑必挂。
    git fetch -q origin 2>/dev/null
    local AHEAD; AHEAD=$(git rev-list --count "origin/${BR}..HEAD" 2>/dev/null || echo 0)
    if [ "${AHEAD}" -gt 0 ]; then
      RESUME=1
      echo "     暂存区为空，但本地有 ${AHEAD} 个未推 commit —— 上次收口在 push 前失败，续推"
    else
      die empty "暂存区为空，无可提交内容（改动是否已被收口？）"
    fi
  else
    local f
    for f in ${STAGED}; do
      printf '%s\n' "${FILES[@]}" | grep -qxF "${f}" || die whitelist "暂存区混入清单外文件: ${f}"
    done
    echo "${STAGED}" | sed 's/^/     /'
  fi

  if [ "${DRY}" = 1 ]; then
    echo "── [dry-run] 到此为止，未 commit/push"
    [ "${RESUME}" = 0 ] && git reset -q
    exit 0
  fi

  local SHA
  if [ "${RESUME}" = 0 ]; then
    echo "── commit"
    git commit -qm "${MSG}" || die commit "commit 失败"
  fi
  SHA=$(git rev-parse HEAD) || die revparse "取 sha 失败"
  echo "     sha: ${SHA}"

  # push 前 fetch；远端前移则 rebase（禁 force）
  echo "── fetch + 必要时 rebase"
  git fetch -q origin || die fetch "fetch 失败（远端故障？本地提交已保住，成果未丢）"
  if [ -n "$(git rev-list "HEAD..origin/${BR}" 2>/dev/null)" ]; then
    echo "     远端已前移 → rebase"
    # rebase 要求工作区干净；别的 agent 的半成品先 stash 隔离，rebase 后恢复
    local STASHED=0
    if [ -n "$(git status --porcelain)" ]; then
      git stash push -qu -m "seal-tmp-$$" && STASHED=1 && echo "     其他改动已 stash 隔离"
    fi
    if ! git rebase -q "origin/${BR}"; then
      git rebase --abort
      [ "${STASHED}" = 1 ] && git stash pop -q
      die rebase "rebase 冲突，需人工介入（已 abort，工作区还原）"
    fi
    SHA=$(git rev-parse HEAD)
    if [ "${STASHED}" = 1 ]; then
      git stash pop -q || echo "     ⚠️ stash pop 冲突，半成品仍在 stash 里（git stash list），未丢失"
    fi
  fi

  echo "── push"
  git push -q origin "HEAD:${BR}" || die push "push 失败（远端故障？本地提交已保住）"

  echo "── 三步核验"
  git fetch -q origin
  local R; R=$(git rev-parse "origin/${BR}")
  [ "${R}" = "${SHA}" ] || die verify "远端头(${R}) != 预期(${SHA})"
  local A B; read -r A B <<<"$(git rev-list --left-right --count "HEAD...origin/${BR}" | tr '\t' ' ')"
  { [ "${A}" = 0 ] && [ "${B}" = 0 ]; } || die verify "ahead=${A} behind=${B}，非 0/0"
  echo "     ✅ 远端头==预期 sha，ahead=0 behind=0"

  # ── 无子模块：收工 ──
  if [ "${SUB}" = "-" ]; then
    echo "SEALED ${SHA}"; exit 0
  fi

  # ── 有子模块：回父仓刷指针 ──
  cd "${REPO}" || die setup "回不到父仓 ${REPO}"
  echo "── 父仓刷指针"
  git add -- "${SUB}" || die ptr "add 指针失败"
  local PTR; PTR=$(git diff --cached --name-only)
  [ "${PTR}" = "${SUB}" ] || die whitelist "父仓暂存区混入清单外: ${PTR}"
  local NEW; NEW=$(git ls-files -s "${SUB}" | awk '{print $2}')
  [ "${NEW}" = "${SHA}" ] || die ptr "指针(${NEW}) != 子仓新 sha(${SHA})"
  echo "     指针 → ${NEW}（rev-parse 取值，非手写）"

  git commit -qm "chore: 刷 ${SUB} 指针 → ${SHA:0:7}" || die commit "父仓 commit 失败"
  local PSHA; PSHA=$(git rev-parse HEAD)
  git fetch -q origin || die fetch "父仓 fetch 失败"
  if [ -n "$(git rev-list "HEAD..origin/${BR}" 2>/dev/null)" ]; then
    git rebase -q "origin/${BR}" || { git rebase --abort; die rebase "父仓 rebase 冲突"; }
    PSHA=$(git rev-parse HEAD)
  fi
  git push -q origin "HEAD:${BR}" || die push "父仓 push 失败"

  echo "── 父仓三步核验"
  git fetch -q origin
  R=$(git rev-parse "origin/${BR}")
  [ "${R}" = "${PSHA}" ] || die verify "父仓远端头(${R}) != 预期(${PSHA})"
  read -r A B <<<"$(git rev-list --left-right --count "HEAD...origin/${BR}" | tr '\t' ' ')"
  { [ "${A}" = 0 ] && [ "${B}" = 0 ]; } || die verify "父仓 ahead=${A} behind=${B}，非 0/0"
  echo "     ✅ 远端头==预期 sha，ahead=0 behind=0"
  echo "SEALED ${SHA} ${PSHA}"
}

# ── 并发派活：仓间无依赖，wall-clock = 最慢那个仓 ──
declare -a PIDS=() NAMES=() REPOS=()
echo "══ 并发收口$([ "${DRY}" = 1 ] && printf '（dry-run 预检）') ══"
while IFS='|' read -r repo sub br files msg; do
  repo=$(echo "${repo}" | xargs); [ -z "${repo}" ] && continue
  case "${repo}" in \#*) continue;; esac
  sub=$(echo "${sub}" | xargs); br=$(echo "${br}" | xargs)
  files=$(echo "${files}" | xargs); msg=$(echo "${msg}" | sed 's/^ *//;s/ *$//')
  name=$(basename "${repo}")
  ( seal_one "${repo}" "${sub}" "${br}" "${files}" "${msg}" ) > "${LOGDIR}/${name}.log" 2>&1 &
  PIDS+=($!); NAMES+=("${name}"); REPOS+=("${repo}")
  echo "  ▸ ${name}  [${sub}]  ${msg}"
done < "${MANIFEST}"

[ ${#PIDS[@]} -eq 0 ] && { echo "❌ 清单为空"; exit 2; }

declare -a RC=()
for i in "${!PIDS[@]}"; do wait "${PIDS[$i]}"; RC+=($?); done

# ── 汇总 ──
# SEAL_RESULT_FILE 若设置，逐行写 OK|<仓路径> / FAIL|<仓路径>，供调用方按仓记账
: > "${SEAL_RESULT_FILE:-/dev/null}"
echo; echo "══ 汇总 ══"
FAIL=0
for i in "${!NAMES[@]}"; do
  n=${NAMES[$i]}; rc=${RC[$i]}
  [ "${rc}" = 0 ] && echo "OK|${REPOS[$i]}"   >> "${SEAL_RESULT_FILE:-/dev/null}" \
                  || echo "FAIL|${REPOS[$i]}" >> "${SEAL_RESULT_FILE:-/dev/null}"
  if [ "${rc}" = 0 ]; then
    line=$(grep '^SEALED' "${LOGDIR}/${n}.log" | head -1)
    if [ -n "${line}" ]; then
      set -- ${line}
      printf '  ✅ %-10s 收口完成  sha %s%s\n' "${n}" "${2:0:7}" "${3:+  父仓指针 ${3:0:7}}"
    else
      printf '  ✅ %-10s dry-run 预检通过（未落地）\n' "${n}"
    fi
  else
    FAIL=1
    printf '  ❌ %-10s %s\n' "${n}" "$(grep '^❌' "${LOGDIR}/${n}.log" | head -1)"
    echo '                └─ 已停在安全点未 push，其余仓不受影响'
  fi
done

echo
if [ "${FAIL}" = 0 ]; then
  [ "${DRY}" = 1 ] && echo "全部 ${#NAMES[@]} 个仓预检通过（未落地，去掉 --dry-run 即执行）" \
                    || echo "全部 ${#NAMES[@]} 个仓收口成功"
else
  echo "有仓失败：成功的仓已落地，失败的仓需人工介入（日志见下）"
fi
echo "日志: ${LOGDIR}"
exit "${FAIL}"
