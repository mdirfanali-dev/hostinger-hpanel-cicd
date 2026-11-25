# Security Policy

## Supported versions

Only the latest release receives fixes. The project is pre-1.0.

## Reporting a vulnerability

Please **do not open a public issue** for a vulnerability.
Use GitHub's private reporting: **Security tab → "Report a vulnerability"** on this repository. If that is not available, open a public issue that says only *"I would like to report a security issue privately"* (no details) and a maintainer will arrange a private channel.

Include what the issue is, the affected file, steps to reproduce, and the impact. We aim to acknowledge reports within a week.

## What is in scope

This project generates and runs shell scripts and GitHub Actions workflows that act on a user's hosting account. Examples of in-scope issues:

- a script that could delete or overwrite data outside the intended folders, or touch another site on the account;
- a way for the precheck or generated files to leak secrets (keys, `.env` values, passwords) or personal data;
- unsafe handling of user-provided answers (command injection through the answers file or generated config);
- workflow templates that expose secrets (for example printing them to logs) or grant broader access than needed;
- weaknesses in the key model (the server deploy key must stay read-only and single-repo).

## Known, documented limitations (not vulnerabilities)

See the README, for example: the GitHub Actions key is a shell login for the whole hosting user; the SSH host key is not pinned by default; rollback does not undo database migrations.

## Good practice for users

Read the generated scripts before running them on your server, keep backups, use a deploy key per repository, and never paste secrets into chats or issues.
