#!/usr/bin/env bash
# Smoke test. Usage: bash scripts/deploy/smoke.sh BASE_URL [CHECKS_FILE]
# Exit code 1 if any check fails. Checks come from scripts/deploy/smoke-checks.txt:
#   /path|expected_status|text that must appear in the page   (text optional)
#   private|/path                                             (must answer 403 or 404)
set -u
BASE="${1:?usage: smoke.sh BASE_URL [CHECKS_FILE]}"
BASE="${BASE%/}"
FILE="${2:-$(dirname "$0")/smoke-checks.txt}"
[ -f "$FILE" ] || { echo "smoke: checks file not found: $FILE"; exit 1; }
fail=0

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  IFS='|' read -r a b c <<< "$line"
  if [ "$a" = "private" ]; then
    code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$BASE$b")
    case "$code" in
      403|404) echo "ok   $b -> $code (private)" ;;
      *) echo "FAIL $b -> $code (should be 403/404)"; fail=1 ;;
    esac
  else
    out=$(curl -s -m 15 -w '\n%{http_code}' "$BASE$a")
    code="${out##*$'\n'}"
    if [ "$code" != "$b" ]; then echo "FAIL $a -> $code (wanted $b)"; fail=1; continue; fi
    if [ -n "${c:-}" ] && ! grep -qF -- "$c" <<<"$out"; then echo "FAIL $a missing text: $c"; fail=1; continue; fi
    echo "ok   $a -> $code"
  fi
done < "$FILE"

exit $fail
