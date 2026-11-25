#!/usr/bin/env bash
# End-to-end test of the lite edition on a fresh Laravel project.
#   bash tests/lite-e2e.sh [LARAVEL_VERSION_CONSTRAINT]      default ^13.0
# Renders the templates, checks the lite gates, simulates the server folders in a temp dir
# (scaffold prepare, two releases, cutover) and verifies the result. Nothing outside the temp dir is touched.
set -euo pipefail

LARAVEL_VERSION="${1:-^13.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skills/hostinger-hpanel-cicd-lite"
W="$(mktemp -d)"
KEEP="${E2E_KEEP:-0}"
if [ "$KEEP" = "1" ]; then echo "(keeping $W)"; else trap 'rm -rf "$W"' EXIT; fi
G=(git -c user.name=e2e -c user.email=e2e@example.invalid -c init.defaultBranch=main)
pass=0; fail=0
check() { if ( eval "$2" ); then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
annotate() { # title file
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  msg="$(tail -n 25 "$2" | python3 -c "import sys;t=sys.stdin.read();print(t.replace('%','%25').replace('\r','%0D').replace('\n','%0A'))")"
  echo "::error title=$1::${msg}"
}

echo "== creating a fresh Laravel project ($LARAVEL_VERSION)"
# Newer Composer blocks package versions with published advisories (common on old Laravel releases).
# This test checks the deploy files, not the packages, so security blocking is off for the test only.
export COMPOSER_NO_SECURITY_BLOCKING=1
if ! composer create-project "laravel/laravel:$LARAVEL_VERSION" "$W/project" --no-interaction --no-progress > "$W/create.log" 2>&1; then
  echo "composer create-project FAILED"; tail -n 40 "$W/create.log"; annotate "composer create-project failed" "$W/create.log"; exit 1
fi
cat > "$W/answers.env" <<'ANS'
PROJECT_SLUG=e2e-app
APP_TYPE=laravel
DOMAIN=e2e.example
GITHUB_OWNER=example
GITHUB_REPO=e2e-app
DB_TYPE=mysql
HAS_MAIL=yes
FORCE_HTTPS=yes
APP_NAME=E2E App
SMOKE_PAGES=/|200|<html;/e2e-missing/|404|
ANS
cd "$W/project"
"${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -q -m project

echo "== lite gates must refuse the full-edition features"
for extra in "HAS_DEV=yes" "WWW_POLICY=www"; do
  { cat "$W/answers.env"; echo "$extra"; } > "$W/gate.env"
  check "refused: $extra" "! python3 '$SKILL/scripts/instantiate.py' --answers '$W/gate.env' --repo . --dry-run >/dev/null 2>&1"
done
{ cat "$W/answers.env"; echo "APP_TYPE=static"; } > "$W/gate.env"
check "refused: APP_TYPE=static" "! python3 '$SKILL/scripts/instantiate.py' --answers '$W/gate.env' --repo . --dry-run >/dev/null 2>&1"

echo "== rendering templates"
python3 "$SKILL/scripts/instantiate.py" --answers "$W/answers.env" --repo .
check "no dev workflow was generated" "[ ! -e .github/workflows/deploy-dev.yml ] && [ ! -e scripts/deploy/dev-update.sh ]"
"${G[@]}" add -A && "${G[@]}" commit -q -m "add ci/cd"

echo "== simulated server"
D="$W/domains/e2e.example"
mkdir -p "$D/public_html"; echo "old live page" > "$D/public_html/index.html"
export DOMAIN_DIR="$D"
bash scripts/server-scaffold.sh prepare > "$W/prepare.log" 2>&1
check "prepare created the folders" "[ -d '$D/prod/releases' ] && [ -f '$D/prod/shared/.env' ]"
check "public_html untouched by prepare" "[ -f '$D/public_html/index.html' ]"
python3 - "$D/prod/shared/.env" "$D" <<'PYEOF'
import re, sys
p, d = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r'(?m)^DB_CONNECTION=.*$', 'DB_CONNECTION=sqlite', s)
s = re.sub(r'(?m)^DB_DATABASE=.*$', 'DB_DATABASE=%s/prod/shared/db.sqlite' % d, s)
s = re.sub(r'(?m)^DB_(HOST|PORT|USERNAME|PASSWORD)=.*\n', '', s)
s = re.sub(r'(?m)^MAIL_MAILER=.*$', 'MAIL_MAILER=log', s)
s = s.replace('CHANGE_ME', 'x').replace('SESSION_SECURE_COOKIE=true', 'SESSION_SECURE_COOKIE=false')
open(p, 'w').write(s)
PYEOF
touch "$D/prod/shared/db.sqlite"

release() { # name
  git clone -q "$W/project" "$D/prod/releases/$1" && ( cd "$D/prod/releases/$1" && git checkout -q "$("${G[@]}" -C "$W/project" rev-parse HEAD)" )
  ( cd "$D/prod/releases/$1" && SITE_URL="https://example.invalid" bash scripts/deploy/prod-release.sh "$D/prod" "$1" ) > "$W/$1.log" 2>&1
}
release 20260101_000001 && rc1=0 || rc1=$?
check "release 1 succeeded" "[ $rc1 -eq 0 ] && grep -q 'is live' '$W/20260101_000001.log'"
[ "$rc1" -eq 0 ] || annotate "release 1 log" "$W/20260101_000001.log"
release 20260101_000002 && rc2=0 || rc2=$?
check "release 2 succeeded" "[ $rc2 -eq 0 ] && grep -q 'is live' '$W/20260101_000002.log'"
[ "$rc2" -eq 0 ] || annotate "release 2 log" "$W/20260101_000002.log"
check "current points at release 2" "[ \"\$(readlink '$D/prod/current')\" = '$D/prod/releases/20260101_000002' ]"
check "smoke test ran against the new release" "grep -q '^ok ' '$W/20260101_000002.log'"
check "no test server left running" "! ps -eo args | grep -q '[p]hp.* -S 127.0.0.1:1[89]'"

bash scripts/server-scaffold.sh cutover > "$W/cutover.log" 2>&1 || true
check "cutover linked public_html/site" "[ \"\$(readlink '$D/public_html/site')\" = '../prod/current/public' ]"
check ".htaccess rewrites to site/" "grep -q 'RewriteRule ^(.*)\$ site/\$1' '$D/public_html/.htaccess'"
check "old public_html backed up, not deleted" "ls '$D'/backups/public_html-before-cutover-*/index.html >/dev/null 2>&1"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
