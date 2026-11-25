# Contributing

Thanks for helping. This project is small and focused: a Claude Code skill plus the scripts and templates it generates. Good contributions are usually **reports from real servers**, small fixes, and support for more project types.

## Ground rules

1. **Never include secrets or personal data** in issues, PRs, tests or examples: no passwords, private keys, `.env` contents, real usernames, real domains or IPs. The server precheck masks the account name; keep it masked.
2. **Never make the scripts destructive on a user's server.** They move and back up, they do not delete (the single exception is the unfinished release folder of a failed deploy). Keep everything scoped to one site's folder.
3. **Be honest about what is proven.** If you add or change behaviour that only a real server can verify, say what you tested and what you did not.
4. Keep the three SSH keys separate (laptop, server deploy key, Actions key) and the deploy key read-only.

## Development setup

You need `bash`, `git`, `python3` (3.9+), and for the Laravel end-to-end test `php` 8.3+ and `composer`.

```bash
git clone https://github.com/mdirfanali-dev/hostinger-hpanel-cicd.git
cd hostinger-hpanel-cicd
pip install shellcheck-py yamllint     # linters used by CI
bash tests/lint.sh                      # shell, python, YAML and link checks
bash tests/lite-e2e.sh '^13.0'          # fresh Laravel project: render, simulate the server, two releases, cutover
```

`tests/lite-e2e.sh` renders the templates into a throwaway Laravel project and simulates the server folders locally (two releases and the cutover). Everything happens in a temp folder.

## What to change where

| You want to... | Edit |
|---|---|
| change the process Claude follows | `skills/hostinger-hpanel-cicd-lite/SKILL.md` and `references/` |
| change what is generated | `skills/hostinger-hpanel-cicd-lite/templates/` (render-time tokens look like `__NAME__`; run-time tokens `{{APP_KEY}}`, `__PORT__`, `__REL__` must be preserved) |
| add a setting | `scripts/instantiate.py` (defaults, validation) and the lite `SKILL.md` |

When you change a template, update `references/` and `CHANGELOG.md` in the same PR.

## Reporting what works on your server

Open an issue with the **masked** output of the failing step (the last 30 lines) and say which Hostinger plan and PHP version you use.

## Pull requests

- Keep PRs small and focused; describe the problem, the change, and how you tested it.
- CI must pass (lint + the end-to-end test on every Laravel version).
- Add or update a test in `tests/` when behaviour changes.
- Use clear commit messages ("Fix cutover when public_html has a dev folder"), not "update".
- By contributing you agree your contribution is licensed under the [MIT License](LICENSE).

## Code style

- Bash: `set -euo pipefail` where safe, quote variables, pass `shellcheck -S warning`.
- Python: standard library only, readable over clever.
- Docs: plain, concrete, with exact commands and expected output. Prefer tables for decisions and findings.

See also the [Code of Conduct](CODE_OF_CONDUCT.md).
