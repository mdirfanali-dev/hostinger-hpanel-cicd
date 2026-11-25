#!/usr/bin/env python3
"""Render the hostinger-hpanel-cicd templates into a project repository.

Usage:
    python3 instantiate.py --answers answers.env --repo /path/to/project [--force] [--dry-run]

answers.env is a plain KEY=VALUE file (no secrets). See SKILL.md for every key.
Nothing is overwritten unless --force is given; existing files are reported instead.
Render-time tokens look like __NAME__. Run-time tokens ({{APP_KEY}}, __PORT__, __REL__) are left alone.
"""
import argparse
import os
import re
import shutil
import sys

# tools/build_lite.py rewrites this to "lite" when it builds the free edition from this same code.
EDITION = "lite"
LITE_NOTE = "That option is part of the full edition."

SKILL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = os.path.join(SKILL, "templates")
RUNTIME_TOKENS = {"__PORT__", "__REL__"}


def die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def read_answers(path):
    out = {}
    with open(path, encoding="utf8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            out[k.strip()] = v
    return out


def need(a, key):
    if not a.get(key):
        die("answers file is missing required key: " + key)
    return a[key]


def build(a):
    d = dict(a)
    slug = need(a, "PROJECT_SLUG")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug):
        die("PROJECT_SLUG must be lowercase letters, digits and dashes")
    app_type = need(a, "APP_TYPE")
    if app_type not in ("laravel", "php", "static"):
        die("APP_TYPE must be laravel | php | static")
    if EDITION == "lite" and app_type != "laravel":
        die("The lite edition supports Laravel only. " + LITE_NOTE)
    domain = need(a, "DOMAIN")
    owner, repo = need(a, "GITHUB_OWNER"), need(a, "GITHUB_REPO")

    d.setdefault("PROD_BRANCH", "main")
    d.setdefault("DEV_BRANCH", "dev")
    d.setdefault("HAS_DEV", "no" if EDITION == "lite" else "yes")
    d.setdefault("DEV_SUBDOMAIN", "dev")
    d.setdefault("KEEP_RELEASES", "5")
    d.setdefault("PHP_BIN", "php")
    d.setdefault("PHP_VERSIONS", "8.3,8.5")
    d.setdefault("DB_TYPE", "mysql")
    d.setdefault("HAS_MAIL", "no")
    d.setdefault("FORCE_HTTPS", "yes")
    d.setdefault("WWW_POLICY", "none")
    d.setdefault("APP_NAME", slug.upper())
    d.setdefault("MAIL_FROM", "hello@" + domain)
    if re.search(r'["$\\\n]', d["APP_NAME"]):
        die('APP_NAME must not contain double quotes, "$", backslashes or line breaks (it is written into .env files)')
    if not re.fullmatch(r"[A-Za-z0-9.-]+", domain):
        die("DOMAIN must contain only letters, digits, dots and dashes")
    d["DOMAIN_DIR_NAME"] = a.get("DOMAIN_DIR_NAME") or domain
    www = d["WWW_POLICY"]
    d["SITE_URL"] = a.get("SITE_URL") or ("https://www." + domain if www == "www" else "https://" + domain)
    alias = a.get("GIT_ALIAS") or "github.com-" + slug
    d["GIT_ALIAS"] = alias
    d["KEY_DIR"] = slug + "_key"          # ~/.ssh/<slug>_key/ holds the server deploy key
    d["GIT_REMOTE"] = "git@%s:%s/%s.git" % (alias, owner, repo)
    for k, allowed in (("HAS_DEV", ("yes", "no")), ("DB_TYPE", ("mysql", "none")), ("HAS_MAIL", ("yes", "no")),
                       ("FORCE_HTTPS", ("yes", "no")), ("WWW_POLICY", ("apex", "www", "none"))):
        if d[k] not in allowed:
            die("%s must be one of %s" % (k, "|".join(allowed)))

    if EDITION == "lite":
        if d["HAS_DEV"] == "yes":
            die("A dev environment is not available in the lite edition. " + LITE_NOTE)
        if d["WWW_POLICY"] != "none":
            die("www redirects are not available in the lite edition. " + LITE_NOTE)

    # ---- per application type defaults ------------------------------------------------------------
    php = d["PHP_BIN"]
    composer = "composer" if php == "php" else '"$PHP_BIN" "$(command -v composer)"'
    install = composer + " install --no-dev --optimize-autoloader --no-scripts --no-interaction --no-progress"
    if app_type == "laravel":
        t = {
            "PUBLIC_DIR": "public",
            "SHARED_LINKS": ".env storage",
            "SHARED_DIRS": "storage/app/public storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs",
            "EXTRA_DIRS": "bootstrap/cache",
            "WRITABLE_DIRS": "storage bootstrap/cache",
            "INSTALL_CMD": install,
            "POST_INSTALL_CMD": '"$PHP_BIN" artisan package:discover --ansi',
            "BOOT_CHECK_CMD": '"$PHP_BIN" artisan --version && "$PHP_BIN" artisan route:list --json > /dev/null',
            "MIGRATE_CMD": '"$PHP_BIN" artisan migrate --force' if d["DB_TYPE"] == "mysql" else "",
            "OPTIMIZE_CMD": '"$PHP_BIN" artisan optimize:clear && "$PHP_BIN" artisan optimize',
            "LOCAL_SERVE_CMD": 'cd public || exit 1; R="__REL__/vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php"; '
                               '[ -f "$R" ] || R="__REL__/server.php"; '
                               'exec setsid timeout 120 "$PHP_BIN" -d display_errors=0 -d log_errors=1 -S 127.0.0.1:__PORT__ "$R"',
        }
    elif app_type == "php":
        pub = a.get("PUBLIC_DIR", "public")
        t = {
            "PUBLIC_DIR": pub, "SHARED_LINKS": a.get("SHARED_LINKS", ""), "SHARED_DIRS": a.get("SHARED_DIRS", ""),
            "EXTRA_DIRS": "", "WRITABLE_DIRS": a.get("WRITABLE_DIRS", ""),
            "INSTALL_CMD": install if a.get("USES_COMPOSER", "yes") == "yes" else "",
            "POST_INSTALL_CMD": "", "BOOT_CHECK_CMD": "", "MIGRATE_CMD": a.get("MIGRATE_CMD", ""),
            "OPTIMIZE_CMD": "",
            "LOCAL_SERVE_CMD": 'cd %s && exec setsid timeout 120 "$PHP_BIN" -d display_errors=0 -d log_errors=1 -S 127.0.0.1:__PORT__' % pub,
        }
    else:  # static: the committed folder is served as is (build artefacts must be committed or built in a custom step)
        t = {
            "PUBLIC_DIR": a.get("PUBLIC_DIR", "public"), "SHARED_LINKS": "", "SHARED_DIRS": "", "EXTRA_DIRS": "",
            "WRITABLE_DIRS": "", "INSTALL_CMD": "", "POST_INSTALL_CMD": "", "BOOT_CHECK_CMD": "",
            "MIGRATE_CMD": "", "OPTIMIZE_CMD": "", "LOCAL_SERVE_CMD": "",
        }
    for k, v in t.items():
        d.setdefault(k, v)  # explicit answers win over defaults
    if d["PUBLIC_DIR"] in ("", ".", "/") or d["PUBLIC_DIR"].startswith(".."):
        die("PUBLIC_DIR must be a dedicated sub-folder (e.g. public). Never expose the repository root.")
    d["DB_BACKUP"] = "mysql-from-env" if d["DB_TYPE"] == "mysql" and app_type != "static" else "none"
    for k in ("INSTALL_CMD", "POST_INSTALL_CMD", "BOOT_CHECK_CMD", "MIGRATE_CMD", "OPTIMIZE_CMD", "LOCAL_SERVE_CMD"):
        if "'" in d[k]:
            die(k + " must not contain a single quote (it is stored in a single-quoted shell string)")

    # ---- generated blocks ---------------------------------------------------------------------------
    d["HTACCESS_DEV_BLOCK"] = (
        "# The dev subdomain has its own symlinked root (public_html/%s): leave it alone\n"
        "RewriteCond %%{HTTP_HOST} ^%s\\. [NC]\nRewriteRule ^ - [L]\n" % (d["DEV_SUBDOMAIN"], d["DEV_SUBDOMAIN"])
        if d["HAS_DEV"] == "yes" else "")
    d["HTACCESS_HTTPS_BLOCK"] = (
        "# Force HTTPS\nRewriteCond %{HTTPS} off\nRewriteCond %{HTTP:X-Forwarded-Proto} !https\n"
        "RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]\n" if d["FORCE_HTTPS"] == "yes" else "")
    if www == "apex":
        d["HTACCESS_WWW_BLOCK"] = "# www -> apex\nRewriteCond %{HTTP_HOST} ^www\\.(.+)$ [NC]\nRewriteRule ^ https://%1%{REQUEST_URI} [L,R=301]\n"
    elif www == "www":
        d["HTACCESS_WWW_BLOCK"] = "# apex -> www\nRewriteCond %{HTTP_HOST} !^www\\. [NC]\nRewriteRule ^ https://www.%{HTTP_HOST}%{REQUEST_URI} [L,R=301]\n"
    else:
        d["HTACCESS_WWW_BLOCK"] = ""

    if d["DB_TYPE"] == "mysql":
        blk = ("DB_CONNECTION=mysql\nDB_HOST=localhost\nDB_PORT=3306\nDB_DATABASE=CHANGE_ME\n"
               "DB_USERNAME=CHANGE_ME\nDB_PASSWORD=CHANGE_ME")
        d["DB_BLOCK_PROD"] = d["DB_BLOCK_DEV"] = blk
    else:
        d["DB_BLOCK_PROD"] = d["DB_BLOCK_DEV"] = "DB_CONNECTION=sqlite"
    d["MAIL_BLOCK_PROD"] = (
        "# Laravel 11+: MAIL_SCHEME (465 -> smtps, 587 -> smtp). Laravel 10 and older: MAIL_ENCRYPTION (465 -> ssl, 587 -> tls).\n"
        "MAIL_MAILER=smtp\nMAIL_SCHEME=smtps\nMAIL_ENCRYPTION=ssl\n"
        "MAIL_HOST=CHANGE_ME\nMAIL_PORT=465\nMAIL_USERNAME=%s\nMAIL_PASSWORD=CHANGE_ME\n"
        'MAIL_FROM_ADDRESS="%s"\nMAIL_FROM_NAME="%s"' % (d["MAIL_FROM"], d["MAIL_FROM"], d["APP_NAME"])
        if d["HAS_MAIL"] == "yes" else "MAIL_MAILER=log")

    pages = [p for p in a.get("SMOKE_PAGES", "/|200").split(";") if p.strip()]
    d["SMOKE_PAGES"] = "\n".join(p.strip() for p in pages)

    # ---- CI -----------------------------------------------------------------------------------------
    if app_type in ("laravel", "php"):
        versions = [v.strip() for v in d["PHP_VERSIONS"].split(",") if v.strip()]
        d["CI_STRATEGY"] = ("    strategy:\n      fail-fast: false\n      matrix:\n        php: [%s]"
                            % ", ".join("'%s'" % v for v in versions))
        steps = ("      - uses: shivammathur/setup-php@v2\n        with:\n          php-version: ${{ matrix.php }}\n"
                 "          extensions: mbstring, xml, ctype, fileinfo, pdo_sqlite, sqlite3, curl, zip, tokenizer, openssl%s\n"
                 "          coverage: none\n")
        steps = steps % (", " + a["CI_EXTENSIONS"] if a.get("CI_EXTENSIONS") else "")
        if a.get("USES_COMPOSER", "yes") == "yes":
            steps += "      - name: Install dependencies\n        run: composer install --no-interaction --prefer-dist --no-progress\n"
        if app_type == "laravel":
            steps += ("      - name: Prepare environment\n        run: |\n          cp .env.example .env\n"
                      "          php artisan key:generate\n")
        test_cmd = a.get("CI_TEST_CMD") or ("php artisan test" if app_type == "laravel" else "")
    else:
        d["CI_STRATEGY"] = ""
        steps = ""
        test_cmd = a.get("CI_TEST_CMD", "")
    steps += "      - name: Run tests\n        run: %s\n" % (test_cmd or 'echo "No automated tests configured yet"')
    d["CI_STEPS"] = steps.rstrip("\n")
    return d


def render(text, d):
    def sub(m):
        key = m.group(1)
        if m.group(0) in RUNTIME_TOKENS:
            return m.group(0)
        if key not in d:
            return m.group(0)
        return str(d[key])
    return re.sub(r"__([A-Z][A-Z0-9_]*)__", sub, text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--answers", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    a = read_answers(args.answers)
    d = build(a)
    repo = os.path.abspath(args.repo)
    if not os.path.isdir(repo):
        die("repo folder not found: " + repo)

    plan = [
        ("github/ci.yml.tpl", ".github/workflows/ci.yml", False),
        ("github/deploy-prod.yml.tpl", ".github/workflows/deploy-prod.yml", False),
        ("github/deploy-dev.yml.tpl", ".github/workflows/deploy-dev.yml", True),
        ("scripts/deploy.conf.tpl", "scripts/deploy/deploy.conf", False),
        ("scripts/prod-release.sh", "scripts/deploy/prod-release.sh", False),
        ("scripts/dev-update.sh", "scripts/deploy/dev-update.sh", True),
        ("scripts/smoke.sh", "scripts/deploy/smoke.sh", False),
        ("scripts/smoke-checks.txt.tpl", "scripts/deploy/smoke-checks.txt", False),
        ("scripts/htaccess.template", "scripts/deploy/htaccess.template", False),
        ("scripts/server-scaffold.sh", "scripts/server-scaffold.sh", False),
        ("env/laravel-prod.env.tpl", "scripts/deploy/env/prod.env.template", None),
        ("env/laravel-dev.env.tpl", "scripts/deploy/env/dev.env.template", "dev-laravel"),
        ("docs/CICD.md.tpl", "docs/CICD.md", False),
    ]
    written, skipped = [], []
    for src, dst, cond in plan:
        if cond is True and d["HAS_DEV"] != "yes":
            continue
        if cond is None or cond == "dev-laravel":
            if d["APP_TYPE"] != "laravel":
                continue
            if cond == "dev-laravel" and d["HAS_DEV"] != "yes":
                continue
        sp = os.path.join(TPL, src)
        if not os.path.exists(sp):
            if EDITION != "lite":
                print("  (template missing, skipped: %s)" % src)
            continue
        out = render(open(sp, encoding="utf8").read(), d)
        left = sorted(set(re.findall(r"__[A-Z][A-Z0-9_]*__", out)) - RUNTIME_TOKENS)
        if left:
            die("%s still contains unfilled placeholders: %s (add them to the answers file)" % (src, ", ".join(left)))
        target = os.path.join(repo, dst)
        if os.path.exists(target) and not args.force:
            if open(target, encoding="utf8").read() != out:
                skipped.append(dst)
            continue
        written.append(dst)
        if args.dry_run:
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf8", newline="\n") as fh:
            fh.write(out)
        if dst.endswith(".sh"):
            os.chmod(target, 0o755)

    # Shell scripts must keep LF line endings or they break on the Linux server (Windows checkouts may use CRLF).
    ga = os.path.join(repo, ".gitattributes")
    rules = ["*.sh text eol=lf", "scripts/deploy/* text eol=lf", "scripts/server-scaffold.sh text eol=lf",
             "*.yml text eol=lf"]
    existing = open(ga, encoding="utf8").read() if os.path.exists(ga) else ""
    missing = [r for r in rules if r not in existing]
    if missing:
        written.append(".gitattributes (+%d line ending rule(s))" % len(missing))
        if not args.dry_run:
            with open(ga, "a", encoding="utf8", newline="\n") as fh:
                if existing and not existing.endswith("\n"):
                    fh.write("\n")
                fh.write("\n".join(missing) + "\n")

    if not args.dry_run:
        os.makedirs(os.path.join(repo, "docs"), exist_ok=True)
        shutil.copyfile(args.answers, os.path.join(repo, "docs", "cicd-answers.env"))
    print(("DRY RUN: would write" if args.dry_run else "Wrote") + " %d file(s):" % len(written))
    for w in written:
        print("  + " + w)
    try:
        import subprocess
        mode = subprocess.run(["git", "-C", repo, "config", "core.fileMode"], capture_output=True, text=True).stdout.strip()
    except Exception:
        mode = ""
    if mode == "false" and not args.dry_run:
        print("NOTE: this git repository ignores file modes (typical on Windows drives). After `git add`, run:\n"
              "  git update-index --chmod=+x scripts/server-scaffold.sh scripts/deploy/*.sh\n"
              "so the scripts are executable after a clone on the server.")
    if skipped:
        print("Skipped (already exist and differ; use --force to overwrite): ")
        for s in skipped:
            print("  ! " + s)


if __name__ == "__main__":
    main()
