---
name: hostinger-hpanel-cicd-lite
description: Free lite edition. Generates a production-only GitHub Actions to Hostinger hPanel deploy pipeline for a Laravel project (release folders, atomic switch of a `current` symlink, instant rollback, database dump before migrate, smoke test). Use when the user wants auto-deploy or CI/CD for a Laravel project on Hostinger shared hosting. Production only: the dev environment, server precheck, local rehearsal and guided step-by-step handoff are in the full edition.
---

# Hostinger hPanel CI/CD: lite edition (Laravel, production only)

Generates the files for a release-folder deploy from GitHub to Hostinger shared hosting, then gives the developer the manual steps. This is the free edition: it covers one production environment for **Laravel 8 to 13**.

## What it builds

```
GitHub (your repo)                       Hostinger server  ~/domains/<site>/
  push to main ──► CI tests ──► SSH ──►    public_html/  .htaccess + site -> ../prod/current/public
                                           prod/  releases/<timestamp>/   shared/ (.env, storage)   current -> newest
                                           backups/  DB dumps + public_html as it was before cutover
```
Every deploy: new release folder, composer, boot check, smoke test of the new release, database dump, migrate, atomic switch of `current`, public smoke test, automatic rollback if that fails, old releases pruned.

## Rules

1. **No secrets in chat or git.** Never ask for passwords, private keys or `.env` contents.
2. **Claude never connects to the server.** The developer runs every server command and pastes back only output that has no secrets.
3. **Nothing is destroyed on the server.** The generated scripts move and back up; the only thing removed is an unfinished release that failed before going live. Work only inside the one domain folder the developer names.
4. **Commit locally, do not push or merge without the user's approval.**
5. Be honest: the generated templates are tested in CI against fresh Laravel installs, but nothing is proven on the developer's own server until they run it. Say so.

## Steps

1. **Look at the repo.** Run `bash <skill-dir>/scripts/precheck-local.sh <repo>` and read the output. Fix what blocks CI (an empty tracked `tests/Unit` folder needs a `.gitkeep`, a missing `.env.example`, secrets tracked in git).
2. **Ask the developer** (in chat, one short numbered list, wait for the answers): project slug (lowercase, dashes), domain, GitHub owner and repository name, production branch (default `main`), the PHP version(s) their Laravel supports for CI (e.g. `8.3`), database MySQL or none, whether the app sends mail.
3. **Write `answers.env`** (no secrets) and render the files:
   ```
   PROJECT_SLUG=my-shop
   APP_TYPE=laravel
   DOMAIN=example.com
   GITHUB_OWNER=my-org
   GITHUB_REPO=my-shop
   PROD_BRANCH=main
   PHP_VERSIONS=8.3
   DB_TYPE=mysql
   HAS_MAIL=no
   APP_NAME=My Shop
   SMOKE_PAGES=/|200|text on your home page
   ```
   ```
   python3 <skill-dir>/scripts/instantiate.py --answers answers.env --repo <repo>
   ```
   The renderer refuses unsafe values and never overwrites existing files unless `--force` is given.
4. **Review and commit locally.** Check `scripts/deploy/smoke-checks.txt` uses pages that really exist. On a Windows drive run the `git update-index --chmod=+x ...` command the renderer prints.
5. **Hand over the manual steps** from `references/quickstart.md` (keys, GitHub secrets, hPanel, server scaffold, first deploy, cutover). Give one block at a time and wait for the developer.

## Limits of this edition

Laravel only (8 to 13), one production environment, `www` redirects not generated, no server precheck, no local rehearsal script, no guided verification, no troubleshooting guide, no project manual. The full edition adds a dev site with its own database, a read-only server precheck that adapts to existing keys and sites, a local rehearsal of the whole deploy, plain PHP and static projects, HTTPS/www options, and a complete step-by-step handoff with expected output at every step.
