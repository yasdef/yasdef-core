#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_FILE="$ROOT/ai/user_review.md"

FILE="$DEFAULT_FILE"
MODE="changed"
BASE_REF="HEAD"

usage() {
  cat <<'USAGE'
Usage: ai/scripts/validate_user_review.sh [--file path] [--all|--changed-only] [--base-ref HEAD]

Validates UR hygiene in ai/user_review.md.

Checks:
- Required fields for new/updated UR entries: Trigger, Rule, How to verify, Example(s), References
- Duplicate UR IDs are rejected
- Overlap for normalized Trigger+Rule is rejected (update existing UR instead)

Modes:
- --changed-only (default): validate only new/updated UR entries vs base ref
- --all: validate all UR entries in the file
USAGE
}

require_option_arg() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 1
  fi
}

normalize_path_for_git() {
  local path="$1"
  if [[ "$path" == "$ROOT"/* ]]; then
    printf '%s' "${path#$ROOT/}"
    return 0
  fi
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      require_option_arg "--file" "${2:-}"
      FILE="$2"
      shift 2
      ;;
    --all)
      MODE="all"
      shift
      ;;
    --changed-only)
      MODE="changed"
      shift
      ;;
    --base-ref)
      require_option_arg "--base-ref" "${2:-}"
      BASE_REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$FILE" ]]; then
  echo "UR hygiene validation skipped: file not found: $FILE" >&2
  exit 0
fi

base_file="$(mktemp)"
trap 'rm -f "$base_file"' EXIT

if [[ "$MODE" == "changed" ]]; then
  rel_path="$(normalize_path_for_git "$FILE" || true)"
  if [[ -n "$rel_path" ]] && git -C "$ROOT" rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
    if git -C "$ROOT" cat-file -e "$BASE_REF:$rel_path" >/dev/null 2>&1; then
      git -C "$ROOT" show "$BASE_REF:$rel_path" >"$base_file"
    fi
  fi
fi

output="$(awk -v mode="$MODE" '
  function trim(s) {
    gsub(/^[[:space:]]+/, "", s)
    gsub(/[[:space:]]+$/, "", s)
    return s
  }

  function norm(s) {
    s = tolower(s)
    gsub(/[[:space:]]+/, " ", s)
    gsub(/^[[:space:]]+/, "", s)
    gsub(/[[:space:]]+$/, "", s)
    return s
  }

  function reset_entry() {
    entry_id = ""
    entry_block = ""
    entry_trigger = ""
    entry_rule = ""
    entry_has_trigger = 0
    entry_has_rule = 0
    entry_has_how = 0
    entry_has_examples = 0
    entry_has_refs = 0
  }

  function flush_entry(ds,    key, trigger_v, rule_v, overlap_v, block_v, seen_key, count_key) {
    if (entry_id == "") {
      return
    }

    key = ds SUBSEP entry_id
    count_key = ds SUBSEP "count" SUBSEP entry_id
    counts[count_key] = counts[count_key] + 1

    seen_key = ds SUBSEP "seen" SUBSEP entry_id
    if (!(seen_key in seen_ids)) {
      order_count[ds] = order_count[ds] + 1
      id_order[ds SUBSEP order_count[ds]] = entry_id
      seen_ids[seen_key] = 1
    }

    trigger_v = norm(entry_trigger)
    rule_v = norm(entry_rule)
    overlap_v = ""
    if (trigger_v != "" && rule_v != "") {
      overlap_v = trigger_v "|" rule_v
    }
    block_v = norm(entry_block)

    has_trigger[key] = entry_has_trigger
    has_rule[key] = entry_has_rule
    has_how[key] = entry_has_how
    has_examples[key] = entry_has_examples
    has_refs[key] = entry_has_refs
    overlap_key[key] = overlap_v
    block_norm[key] = block_v

    if (ds == "current" && overlap_v != "") {
      if (overlap_to_ids[overlap_v] == "") {
        overlap_to_ids[overlap_v] = entry_id
      } else {
        overlap_to_ids[overlap_v] = overlap_to_ids[overlap_v] "|" entry_id
      }
    }
  }

  function parse_line(line, ds,    id_line, v) {
    if (line ~ /^[[:space:]]*[-*]?[[:space:]]*\*\*ID\*\*:[[:space:]]*UR-[A-Za-z0-9_-]+/) {
      flush_entry(ds)
      reset_entry()
      id_line = line
      sub(/^[[:space:]]*[-*]?[[:space:]]*\*\*ID\*\*:[[:space:]]*/, "", id_line)
      entry_id = trim(id_line)
      entry_block = line
      return
    }

    if (entry_id == "") {
      return
    }

    entry_block = entry_block "\n" line

    if (line ~ /^[[:space:]]*[-*]?[[:space:]]*\*\*Trigger\*\*:[[:space:]]*/) {
      entry_has_trigger = 1
      if (entry_trigger == "") {
        v = line
        sub(/^[[:space:]]*[-*]?[[:space:]]*\*\*Trigger\*\*:[[:space:]]*/, "", v)
        entry_trigger = trim(v)
      }
    } else if (line ~ /^[[:space:]]*[-*]?[[:space:]]*\*\*Rule\*\*:[[:space:]]*/) {
      entry_has_rule = 1
      if (entry_rule == "") {
        v = line
        sub(/^[[:space:]]*[-*]?[[:space:]]*\*\*Rule\*\*:[[:space:]]*/, "", v)
        entry_rule = trim(v)
      }
    } else if (line ~ /^[[:space:]]*[-*]?[[:space:]]*\*\*How to verify\*\*:[[:space:]]*/) {
      entry_has_how = 1
    } else if (line ~ /^[[:space:]]*[-*]?[[:space:]]*\*\*Example\(s\)\*\*:[[:space:]]*/) {
      entry_has_examples = 1
    } else if (line ~ /^[[:space:]]*[-*]?[[:space:]]*\*\*References\*\*:[[:space:]]*/) {
      entry_has_refs = 1
    }
  }

  BEGIN {
    dataset = "base"
    reset_entry()
    failure = 0
  }

  FNR == 1 && NR != 1 {
    flush_entry(dataset)
    dataset = "current"
    reset_entry()
  }

  {
    parse_line($0, dataset)
  }

  END {
    flush_entry(dataset)

    if (order_count["current"] == 0) {
      print "UR hygiene validation passed: no UR entries found in user_review file."
      exit 0
    }

    changed_count = 0
    for (i = 1; i <= order_count["current"]; i++) {
      id = id_order["current" SUBSEP i]
      current_key = "current" SUBSEP id
      base_key = "base" SUBSEP id
      current_count_key = "current" SUBSEP "count" SUBSEP id
      base_count_key = "base" SUBSEP "count" SUBSEP id

      include = 0
      if (mode == "all" || order_count["base"] == 0) {
        include = 1
      } else if (!(base_key in block_norm)) {
        include = 1
      } else if (block_norm[current_key] != block_norm[base_key]) {
        include = 1
      } else if ((counts[current_count_key] + 0) != (counts[base_count_key] + 0)) {
        include = 1
      }

      if (include == 1) {
        changed_count = changed_count + 1
        changed_ids[changed_count] = id
      }
    }

    if (changed_count == 0) {
      print "UR hygiene validation passed: no new/updated UR entries detected."
      exit 0
    }

    print "UR hygiene validation failed for user review file:" > "/dev/stderr"

    for (i = 1; i <= changed_count; i++) {
      id = changed_ids[i]
      key = "current" SUBSEP id
      count_key = "current" SUBSEP "count" SUBSEP id

      missing = ""
      if ((has_trigger[key] + 0) != 1) {
        missing = missing "Trigger, "
      }
      if ((has_rule[key] + 0) != 1) {
        missing = missing "Rule, "
      }
      if ((has_how[key] + 0) != 1) {
        missing = missing "How to verify, "
      }
      if ((has_examples[key] + 0) != 1) {
        missing = missing "Example(s), "
      }
      if ((has_refs[key] + 0) != 1) {
        missing = missing "References, "
      }
      if (missing != "") {
        sub(/, $/, "", missing)
        print "- " id " missing required fields: " missing > "/dev/stderr"
        failure = 1
      }

      if ((counts[count_key] + 0) > 1) {
        print "- Duplicate UR ID detected: " id " appears " counts[count_key] " times." > "/dev/stderr"
        failure = 1
      }

      okey = overlap_key[key]
      if (okey != "") {
        split(overlap_to_ids[okey], ids, /\|/)
        for (j in ids) {
          other = ids[j]
          if (other == id) {
            continue
          }

          a = id
          b = other
          if (a > b) {
            tmp = a
            a = b
            b = tmp
          }
          pair = a "|" b
          if (pair in seen_overlap_pair) {
            continue
          }
          seen_overlap_pair[pair] = 1
          print "- Overlap detected between " a " and " b " (same normalized Trigger+Rule). Update existing UR entry instead of adding a duplicate." > "/dev/stderr"
          failure = 1
        }
      }
    }

    if (failure == 1) {
      exit 1
    }

    print "UR hygiene validation passed for user review file."
    exit 0
  }
' "$base_file" "$FILE")" && status=0 || status=$?

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

if [[ -n "$output" ]]; then
  echo "$output" >&2
fi
