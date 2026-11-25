#!/usr/bin/env bash
# Static checks used by CI: shell, python, YAML, markdown links, executable bits and a secrets hygiene scan.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
S=skills/hostinger-hpanel-cicd-lite

echo "== shellcheck"
shellcheck -S warning "$S"/scripts/*.sh "$S"/templates/scripts/*.sh tests/*.sh

echo "== python"
python3 -m py_compile "$S/scripts/instantiate.py" tests/check_links.py
rm -rf "$S/scripts/__pycache__" tests/__pycache__

echo "== yaml (workflows and issue forms)"
yamllint -c tests/yamllint.yml .github

echo "== markdown links"
python3 tests/check_links.py

echo "== hygiene: no keys, tokens or private data"
if grep -rnIE "BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|ssh-ed25519 AAAA|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}" . --exclude-dir=.git --exclude=lint.sh; then
  echo "FOUND something that looks like a secret"; exit 1
fi

echo "== every script is committed as executable (checks what Git recorded)"
if git rev-parse --git-dir >/dev/null 2>&1; then
  bad="$(git ls-files -s -- '*.sh' '*.py' | awk '$1 != "100755" {print $4}')"
  if [ -n "$bad" ]; then echo "recorded as NON-executable in git (fix: git update-index --chmod=+x <file>):"; echo "$bad"; exit 1; fi
fi

echo "lint OK"
