# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-25

First release of the **lite** edition: a free, production-only pipeline for Laravel 8 to 13.

### Included
- Claude Code skill `hostinger-hpanel-cicd-lite`.
- Generated GitHub Actions (`ci`, `deploy-prod`), release script (release folders, atomic `current` switch, DB dump before migrate, smoke test, automatic rollback, pruning), server scaffold (`status`, `prepare`, `cutover`), `.htaccess` generator with HTTPS rule, Laravel production env template.
- `instantiate.py` renderer with input validation; `precheck-local.sh`.
- Quickstart and architecture notes.
- CI for this repository: shell and YAML lint, and an end-to-end test on a fresh install of every Laravel major from 8 to 13.
