# hostinger-hpanel-cicd (lite)

**Free, production-only GitHub → Hostinger hPanel deploys for Laravel, as a [Claude Code](https://claude.com/claude-code) skill.**
Release folders, instant rollback, database dump before every migration, smoke test, and tests before deploy. Claude generates the files; you follow a short quickstart for the server.

[![CI](https://github.com/mdirfanali-dev/hostinger-hpanel-cicd/actions/workflows/ci.yml/badge.svg)](https://github.com/mdirfanali-dev/hostinger-hpanel-cicd/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Edition](https://img.shields.io/badge/edition-lite-6f42c1)

## What you get (lite)

Hostinger shared hosting has no real deployment story: the built-in Git integration copies files into `public_html`, which does not fit Laravel, and there are no releases, rollbacks or tests. This skill generates a proper pipeline for **one production environment**:

- **Tests before every deploy.** A push to `main` runs your tests first.
- **A new release folder per deploy** and an **atomic switch** of a `current` symlink. Rollback means repointing one link.
- **Database dump before every migration** (last 10 kept).
- **Smoke test** of the new release, then of the live site; **automatic rollback** if the live check fails.
- **Secrets stay on the server** (`shared/.env`), never in Git.
- A **read-only deploy key** for the server and a separate key for GitHub Actions.

```
GitHub (your repo)                       Hostinger server  ~/domains/<site>/
  push to main ──► CI tests ──► SSH ──►    public_html/  .htaccess + site -> ../prod/current/public
                                           prod/  releases/<timestamp>/   shared/ (.env, storage)   current -> newest
                                           backups/  DB dumps + public_html as it was before cutover
```

## Lite vs full

| | **Lite (this repo, free)** | **Full edition** |
|---|---|---|
| Laravel 8 to 13, production pipeline | ✅ | ✅ |
| Release folders, atomic switch, rollback, DB dump, smoke test | ✅ | ✅ |
| Dev / staging site with its own database, noindex, optional password | ❌ | ✅ |
| Read-only **server precheck** that adapts to your existing keys, sites and `.htaccess` | ❌ | ✅ |
| **Local rehearsal** of the whole deploy before you touch the server | ❌ | ✅ |
| Plain PHP and static projects | ❌ | ✅ |
| HTTPS and `www` options, mail options, decision question bank | basic | ✅ |
| Guided step-by-step handoff with expected output at every step | short quickstart | ✅ |
| Troubleshooting guide and a manual generated for your project | ❌ | ✅ |

The **full edition** is sold on the Agensi marketplace (search for *Hostinger hPanel CI/CD*). The lite edition is a complete, working pipeline on its own.

## Quick start

**1. Install the skill** (per project):
```bash
git clone --depth 1 https://github.com/mdirfanali-dev/hostinger-hpanel-cicd.git /tmp/hostinger-hpanel-cicd
mkdir -p .claude/skills
cp -r /tmp/hostinger-hpanel-cicd/skills/hostinger-hpanel-cicd-lite .claude/skills/
```
Or copy the folder to `~/.claude/skills/` to have it in every project. On Windows PowerShell:
```powershell
git clone --depth 1 https://github.com/mdirfanali-dev/hostinger-hpanel-cicd.git $env:TEMP\hostinger-hpanel-cicd
New-Item -ItemType Directory -Force .claude\skills | Out-Null
Copy-Item -Recurse $env:TEMP\hostinger-hpanel-cicd\skills\hostinger-hpanel-cicd-lite .claude\skills\
```
Start a new Claude Code session.

**2. Ask for it:** *"Set up CI/CD for this Laravel project to my Hostinger hosting."*

**3. Follow the quickstart** Claude gives you ([`references/quickstart.md`](skills/hostinger-hpanel-cicd-lite/references/quickstart.md)): keys, GitHub secrets, hPanel, server scaffold, first deploy, cutover.

## Requirements

Hostinger **shared/Business hosting** with hPanel and **SSH enabled** · a GitHub repository you administer · a Laravel project (8 to 13) · `git`, `composer` on the server (standard on Hostinger) · Claude Code.

## Verified in CI

Every push runs an end-to-end test on a **fresh install of Laravel 8, 9, 10, 11, 12 and 13**: it renders the files, simulates the server folders, runs two releases and performs the cutover. Shell and YAML lint also run. Nothing is proven on *your* server until you run it, and Hostinger plans differ.

## Safety

- **Claude never connects to your server.** You run the commands and paste back output without secrets.
- The generated scripts **never delete** anything on your server except an unfinished release that failed before going live; your old `public_html` is moved into `backups/`.
- Everything is scoped to the one domain folder you choose.
- Read the generated scripts before running them. Rollback does not undo database migrations.

Not affiliated with Hostinger or Anthropic. Their names belong to their owners.

## Contributing and license

Bug reports and improvements to the lite edition are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). [MIT](LICENSE), provided as is, without warranty.
