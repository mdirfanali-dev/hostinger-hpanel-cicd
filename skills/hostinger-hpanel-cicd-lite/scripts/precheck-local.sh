#!/usr/bin/env bash
# LOCAL, read-only precheck of a project repository. Claude runs this first.
# Usage: bash precheck-local.sh [REPO_DIR]
# Prints facts only. Changes nothing.
REPO="${1:-.}"
cd "$REPO" 2>/dev/null || { echo "repo folder not found: $REPO"; exit 1; }
hr() { printf '\n== %s\n' "$*"; }

hr "Git"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "NOT a git repository"; exit 0; }
echo "branch: $(git branch --show-current)"
git remote -v | sed 's/^/remote: /'
echo "default branch (origin/HEAD): $(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo 'unknown')"
echo "local branches:  $(git branch --format='%(refname:short)' | tr '\n' ' ')"
echo "remote branches: $(git branch -r --format='%(refname:short)' | grep -v HEAD | tr '\n' ' ')"
echo "uncommitted changes: $(git status --porcelain | wc -l) file(s)"
if command -v gh >/dev/null 2>&1; then
  echo "--- gh repo view (visibility, default branch)"
  gh repo view --json nameWithOwner,visibility,defaultBranchRef 2>&1 | head -5
else
  echo "gh CLI not installed (ask the developer whether the repo is private)"
fi

hr "Existing automation"
ls .github/workflows 2>/dev/null | sed 's/^/workflow: /' || true
[ -d .github/workflows ] || echo "no .github/workflows yet"
ls scripts 2>/dev/null | sed 's/^/scripts\/: /' | head -20
[ -f scripts/deploy/deploy.conf ] && echo "FOUND scripts/deploy/deploy.conf (this skill was applied before: audit instead of generating)"

hr "Application type"
if [ -f composer.json ]; then
  echo "composer.json present"
  grep -E '"laravel/framework"|"symfony/framework-bundle"|"codeigniter4/framework"|"slim/slim"' composer.json | sed 's/^/  /'
  echo "  php requirement: $(grep -E '^\s*"php"\s*:' composer.json | head -1 | sed 's/^ *//')"
  grep -A2 '"platform"' composer.json | sed 's/^/  /'
fi
[ -f artisan ] && echo "artisan present -> Laravel"
[ -f public/index.php ] && echo "public/index.php present"
[ -f package.json ] && { echo "package.json present (JS build?):"; grep -E '"(build|dev)"' package.json | sed 's/^/  /'; }
[ -f index.html ] && echo "index.html at repo root (static site?)"
[ -f wp-config.php ] && echo "wp-config.php present -> WordPress (NOT covered by this skill's templates)"

hr "Tests and CI readiness"
[ -f phpunit.xml ] || [ -f phpunit.xml.dist ] && echo "phpunit config present"
for d in tests tests/Unit tests/Feature; do [ -d "$d" ] && echo "dir ok: $d" || echo "dir MISSING: $d"; done
if [ -f phpunit.xml ]; then
  grep -oE '<directory[^>]*>[^<]+</directory>' phpunit.xml | sed -E 's#<[^>]+>##g' | sed 's/^/  phpunit directory: /'
  echo "  (every directory above must be TRACKED by git: empty folders are not; add a .gitkeep)"
fi
[ -f .env.example ] && echo ".env.example present" || echo ".env.example MISSING (CI needs it for Laravel)"

hr "Secrets hygiene"
git ls-files | grep -E '(^|/)\.env$|id_rsa|id_ed25519|\.pem$|\.key$' | sed 's/^/TRACKED SECRET-LIKE FILE: /' || true
grep -qE '^\.env$|^/\.env$|^\.env' .gitignore 2>/dev/null && echo ".env is gitignored" || echo ".env NOT in .gitignore (fix before anything else)"
grep -qE '^/?vendor' .gitignore 2>/dev/null && echo "vendor/ is gitignored" || echo "vendor/ not in .gitignore"
git ls-files | grep -c '^vendor/' | sed 's/^/vendor files tracked: /'

hr "Local toolchain"
for t in php composer node python3 gh; do
  if command -v $t >/dev/null 2>&1; then echo "$t: $($t --version 2>&1 | head -1)"; else echo "$t: not found"; fi
done
echo "DONE"
