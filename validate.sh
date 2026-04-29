#!/usr/bin/env bash

set -euo pipefail

extract_components() {
  local msg="$1"
  local main_re='^Lab([0-9]{2}): ([a-z]+) (.+)$'
  [[ $msg =~ $main_re ]] || return 1

  local lab="${BASH_REMATCH[1]}"
  local verb="${BASH_REMATCH[2]}"
  local rest="${BASH_REMATCH[3]}"

  local metadata=""
  local meta_re=' \([^)]+\)$'
  if [[ $rest =~ $meta_re ]]; then
    metadata="${BASH_REMATCH[0]}"
    rest="${rest%${metadata}}"
    rest="${rest%% }"
  fi

  local scope_kw=""
  local filepath=""
  local scope_re='[[:space:]](in|to)[[:space:]](/?[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+)$'
  if [[ $rest =~ $scope_re ]]; then
    scope_kw="${BASH_REMATCH[1]}"
    filepath="${BASH_REMATCH[2]}"
    rest="${rest% ${scope_kw} ${filepath}}"
    rest="${rest%% }"
  fi

  echo "$lab"
  echo "$verb"
  echo "$rest"
  echo "$scope_kw"
  echo "$filepath"
  echo "$metadata"
}

check_format() {
  local msg="$1"
  [[ $msg =~ ^Lab[0-9]{2}:\ [a-z]+\ .+ ]]
}

check_verb() {
  local verb="$1"
  local allowed_verbs=(
    "add" "fix" "refactor" "migrate" "implement" "update"
    "remove" "delete" "merge" "revert" "optimize" "improve"
    "simplify" "restructure" "rename" "move" "copy" "create"
    "modify" "adjust" "enhance" "resolve" "correct" "document"
    "test" "setup" "configure" "initialize" "clean" "format"
    "insert" "split" "center" "scale" "set" "complete" "change"
    "answer" "introduce" "refine" "link" "suppress" "switch"
    "extend"
  )

  for verb_item in "${allowed_verbs[@]}"; do
    [[ "$verb" == "$verb_item" ]] && return 0
  done

  echo "  ✗ Invalid verb: '$verb' (must be infinitive form)"
  return 1
}

check_description() {
  local desc="$1"

  [[ $desc =~ ^[a-zA-Z0-9] ]] || { echo "  ✗ Description must start with alphanumeric character"; return 1; }
  [[ $desc =~ [a-zA-Z0-9]$ ]] || { echo "  ✗ Description must end with alphanumeric character"; return 1; }

  local desc_re='^[a-zA-Z0-9 ,.-]+$'
  [[ $desc =~ $desc_re ]] || {
    if [[ $desc =~ [a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+ ]]; then
      echo "  ✗ Description should not contain file paths. Use scope instead: 'verb description [in|to] filepath' (e.g., 'create skeleton in lab05/README')"
    else
      echo "  ✗ Description contains invalid special characters (only letters, numbers, spaces, commas, periods, hyphens allowed)"
    fi
    return 1
  }

  return 0
}

check_rq_format() {
  local desc="$1"
  local temp_desc="$desc"

  if [[ $desc =~ RQ[0-9]+-[0-9]+ ]]; then
    echo "  ✗ Invalid RQ range format: use RQX-RQY instead of RQX-Y"
    return 1
  fi

  if [[ $desc =~ RQ[0-9]+[[:space:]]+-[[:space:]]*RQ[0-9]+ ]] || [[ $desc =~ RQ[0-9]+[[:space:]]*-[[:space:]]+RQ[0-9]+ ]]; then
    echo "  ✗ Invalid RQ range format: spaces around the hyphen are not allowed (use RQX-RQY)"
    return 1
  fi

  while [[ $temp_desc =~ RQ([0-9]+) ]]; do
    local rq_num="${BASH_REMATCH[1]}"
    if [[ $rq_num =~ ^0[0-9] ]]; then
      echo "  ✗ Invalid RQ format: RQ${rq_num} (no leading zeros, use RQ${rq_num#0} instead)"
      return 1
    fi
    temp_desc="${temp_desc#*RQ${rq_num}}"
  done

  return 0
}

check_scope_path() {
  local filepath="$1"
  [[ -z "$filepath" ]] && return 0

  if [[ $filepath =~ [a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+/.+ ]]; then
    echo "  ✗ Invalid file path: $filepath (use single-level paths like utils/helpers.py or lab02/README)"
    return 1
  fi

  if [[ $filepath =~ /README ]]; then
    if [[ ! $filepath =~ ^lab[0-9][0-9]/README$ ]]; then
      echo "  ✗ Invalid README path: $filepath (must be lab##/README format, e.g., lab05/README)"
      return 1
    fi
  else
    if [[ ! $filepath =~ \.[a-zA-Z0-9]+$ ]]; then
      echo "  ✗ Invalid file path: $filepath (must have an extension like .py, .json)"
      return 1
    fi
  fi

  return 0
}

check_optional_metadata() {
  local metadata="$1"
  [[ -z "$metadata" ]] && return 0

  [[ $metadata =~ ^\ \( ]] || { echo "  ✗ Metadata must be preceded by exactly one space"; return 1; }

  local content="${metadata# (}"
  content="${content%)}"

  local valid_patterns=(
    '^fix #[0-9]+$'
    '^fixes #[0-9]+$'
    '^task #[0-9]+$'
    '^pull request #[0-9]+$'
    '^fix #[0-9]+ for task #[0-9]+$'
    '^fixes #[0-9]+ for task #[0-9]+$'
    '^tasks #[0-9]+, #[0-9]+$'
    '^tasks #[0-9]+, #[0-9]+, #[0-9]+$'
  )

  for pattern in "${valid_patterns[@]}"; do
    [[ $content =~ $pattern ]] && return 0
  done

  echo "  ✗ Invalid optional metadata: ($content)"
  return 1
}

check_spelling() {
  local msg="$1"
  if [[ -n "${CSPELL_CONFIG_PATH:-}" && -f "${CSPELL_CONFIG_PATH}" ]]; then
    printf '%s\n' "$msg" | cspell --config "${CSPELL_CONFIG_PATH}" --no-progress --no-summary stdin 2>&1
  else
    printf '%s\n' "$msg" | cspell --no-progress --no-summary stdin 2>&1
  fi
}

md_cell() { printf '%s' "${1//|/\\|}"; }

record_fail() {
  local step="$1" reason="$2" msg="$3"
  printf '::error title=%s::%s\n' "$step" "${msg} — ${reason}"
  FAILED=1
}

ZERO_SHA="0000000000000000000000000000000000000000"
if [[ "${BEFORE_SHA}" == "${ZERO_SHA}" ]]; then
  mapfile -t MSGS < <(git log --format=%s origin/main.."${AFTER_SHA}")
elif git merge-base --is-ancestor "${BEFORE_SHA}" "${AFTER_SHA}" 2>/dev/null; then
  mapfile -t MSGS < <(git log --format=%s "${BEFORE_SHA}".."${AFTER_SHA}" ^origin/main)
else
  mapfile -t MSGS < <(git log --format=%s origin/main.."${AFTER_SHA}")
fi

[[ "${#MSGS[@]}" -eq 0 ]] && {
  echo "No new commits to check."
  echo "## ✅ No new commits to check" >> "$GITHUB_STEP_SUMMARY"
  exit 0
}

FAILED=0
declare -a SUM_MSGS=()
declare -a SUM_STATUS=()
declare -a SUM_ERRORS=()

for MSG in "${MSGS[@]}"; do
  [[ -z "$MSG" ]] && continue
  echo "════════════════════════════════════════"
  echo "Commit: $MSG"
  echo ""

  if ! check_format "$MSG"; then
    record_fail "Step 1 — format" "Invalid format (Required: Lab<2digits>: <verb> <description> [in/to <filepath>] [(metadata)])" "$MSG"
    SUM_MSGS+=("$MSG"); SUM_STATUS+=("fail"); SUM_ERRORS+=("Step 1 — format")
    continue
  fi

  mapfile -t components < <(extract_components "$MSG")
  verb="${components[1]}"
  description="${components[2]}"
  filepath="${components[4]}"
  metadata="${components[5]}"

  if ! verb_err=$(check_verb "$verb"); then
    echo "$verb_err"
    record_fail "Step 2 — verb" "${verb_err#*✗ }" "$MSG"
    SUM_MSGS+=("$MSG"); SUM_STATUS+=("fail"); SUM_ERRORS+=("Step 2 — verb")
    continue
  fi

  if ! desc_err=$(check_description "$description"); then
    echo "$desc_err"
    record_fail "Step 3 — description" "${desc_err#*✗ }" "$MSG"
    SUM_MSGS+=("$MSG"); SUM_STATUS+=("fail"); SUM_ERRORS+=("Step 3 — description")
    continue
  fi

  if ! rq_err=$(check_rq_format "$description"); then
    echo "$rq_err"
    record_fail "Step 4 — RQ format" "${rq_err#*✗ }" "$MSG"
    SUM_MSGS+=("$MSG"); SUM_STATUS+=("fail"); SUM_ERRORS+=("Step 4 — RQ format")
    continue
  fi

  if ! scope_err=$(check_scope_path "$filepath"); then
    echo "$scope_err"
    record_fail "Step 5 — scope" "${scope_err#*✗ }" "$MSG"
    SUM_MSGS+=("$MSG"); SUM_STATUS+=("fail"); SUM_ERRORS+=("Step 5 — scope")
    continue
  fi

  if ! meta_err=$(check_optional_metadata "$metadata"); then
    echo "$meta_err"
    record_fail "Step 6 — metadata" "${meta_err#*✗ }" "$MSG"
    SUM_MSGS+=("$MSG"); SUM_STATUS+=("fail"); SUM_ERRORS+=("Step 6 — metadata")
    continue
  fi

  if ! check_spelling "$MSG"; then
    record_fail "Step 7 — spelling" "Spelling error detected" "$MSG"
    SUM_MSGS+=("$MSG"); SUM_STATUS+=("fail"); SUM_ERRORS+=("Step 7 — spelling")
    continue
  fi

  SUM_MSGS+=("$MSG"); SUM_STATUS+=("pass"); SUM_ERRORS+=("")
done

{
  if [[ $FAILED -eq 0 ]]; then
    echo "## ✅ All commit messages passed validation"
  else
    echo "## ❌ Commit message validation failed"
  fi
  echo ""
  if [[ $FAILED -ne 0 ]]; then
    echo "### ✗ Failed"
    echo ""
    echo "| Commit message | Failure |"
    echo "|---|---|"
    for i in "${!SUM_MSGS[@]}"; do
      [[ "${SUM_STATUS[$i]}" != "fail" ]] && continue
      echo "| \`$(md_cell "${SUM_MSGS[$i]}")\` | ${SUM_ERRORS[$i]} |"
    done
  fi
} >> "$GITHUB_STEP_SUMMARY"

if [[ $FAILED -eq 0 ]]; then
  echo "✓ All commit messages passed validation!"
else
  echo "✗ One or more commit messages failed validation."
  exit 1
fi
