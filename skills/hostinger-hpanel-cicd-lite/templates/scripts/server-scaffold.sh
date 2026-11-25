#!/usr/bin/env bash
# Server scaffold (run ON the Hostinger server, over SSH). Settings come from scripts/deploy/deploy.conf.
#
#   bash server-scaffold.sh status     show what exists (changes nothing)
#   bash server-scaffold.sh prepare    create folders, shared files and .env files (does NOT touch public_html)
#   bash server-scaffold.sh cutover    point the website at the deployed app (run AFTER the first deploy worked)
#
# Safe to run more than once. It never deletes: anything it replaces is moved into backups/.
# Options (environment variables):
#   DOMAIN_DIR=/some/path           override ~/domains/<DOMAIN_DIR_NAME> (tests only)
#   PREPARE_ENV_FROM=/path/.env     copy an existing production .env instead of the template
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/deploy/deploy.conf"

DOMAIN_DIR="${DOMAIN_DIR:-$HOME/domains/$DOMAIN_DIR_NAME}"
PROD="$DOMAIN_DIR/prod"
SHARED="$PROD/shared"
DEV="$DOMAIN_DIR/dev"
BACKUPS="$DOMAIN_DIR/backups"
WEB="$DOMAIN_DIR/public_html"
STAMP="$(date +%Y%m%d_%H%M%S)"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  [ok]   %s\n' "$*"; }
made() { printf '  [new]  %s\n' "$*"; }
warn() { printf '  [warn] %s\n' "$*"; }
die()  { printf '  [STOP] %s\n' "$*" >&2; exit 1; }

sanity() {
  [ -d "$DOMAIN_DIR" ] || die "$DOMAIN_DIR does not exist."
  [ -d "$WEB" ]        || die "$WEB does not exist."
  case "$PUBLIC_DIR" in ''|.|/|..*) die "PUBLIC_DIR must be a dedicated sub-folder, never the repository root." ;; esac
}

make_dir() { if [ -d "$1" ]; then ok "$1"; else mkdir -p "$1"; made "$1"; fi; }

new_key() { php -r 'echo "base64:".base64_encode(random_bytes(32));'; }

render_env() { # template-file kind
  local tpl="$1" out
  [ -f "$tpl" ] || { echo ""; return 0; }
  out="$(cat "$tpl")"
  if [ "$APP_TYPE" = "laravel" ] && grep -q '{{APP_KEY}}' "$tpl"; then
    out="${out//\{\{APP_KEY\}\}/$(new_key)}"
  fi
  printf '%s\n' "$out"
}

write_env_if_missing() { # path kind(prod|dev)
  local path="$1" kind="$2" tpl="$HERE/deploy/env/$2.env.template"
  if [ -f "$path" ]; then ok "$path (kept, not overwritten)"; return; fi
  if [ "$kind" = prod ] && [ -n "${PREPARE_ENV_FROM:-}" ] && [ -f "$PREPARE_ENV_FROM" ]; then
    cp "$PREPARE_ENV_FROM" "$path"; made "$path (copied from $PREPARE_ENV_FROM)"
  elif [ -f "$tpl" ]; then
    render_env "$tpl" > "$path"; made "$path (template: replace every CHANGE_ME)"
  else
    warn "no env template for $kind: skipped $path"; return
  fi
  chmod 600 "$path"
}

cmd_status() {
  sanity
  say "Location: $DOMAIN_DIR"
  for p in "$PROD/releases" "$SHARED" "$SHARED/.env" "$PROD/current" "$DEV" "$DEV/.env" "$BACKUPS" "$WEB/.htaccess" "$WEB/site" "$WEB/$DEV_SUBDOMAIN"; do
    if [ -L "$p" ]; then printf '  link   %s -> %s\n' "$p" "$(readlink "$p")";
    elif [ -e "$p" ]; then printf '  exists %s\n' "$p";
    else printf '  MISSING %s\n' "$p"; fi
  done
  for f in "$SHARED/.env" "$DEV/.env"; do
    [ -f "$f" ] && printf '  CHANGE_ME left in %s: %s\n' "$f" "$(grep -c CHANGE_ME "$f" || true)"
  done
  "$PHP_BIN" -v | head -1 | sed 's/^/  php: /'
  composer --version 2>/dev/null | head -1 | sed 's/^/  /' || warn "composer not found"
}

cmd_prepare() {
  sanity
  say "Preparing $DOMAIN_DIR  (public_html is NOT touched)"
  make_dir "$PROD/releases"
  make_dir "$SHARED"
  for d in $SHARED_DIRS; do make_dir "$SHARED/$d"; done
  [ -n "$SHARED_DIRS" ] && chmod -R 775 "$SHARED"/* 2>/dev/null || true
  make_dir "$BACKUPS"; chmod 700 "$BACKUPS"
  write_env_if_missing "$SHARED/.env" prod
  if [ "$HAS_DEV" = "yes" ]; then
    make_dir "$DEV"
    write_env_if_missing "$DEV/.env" dev
  fi
  say ""
  say "Next:"
  say "  1. Replace every CHANGE_ME:  nano $SHARED/.env$([ "$HAS_DEV" = yes ] && echo "   and   nano $DEV/.env")"
  say "  2. Run the first deploy (GitHub Actions), then:  bash $0 cutover"
}

cmd_cutover() {
  sanity
  [ -L "$PROD/current" ] || die "$PROD/current does not exist yet. Do the first deploy before cutover."
  [ -d "$PROD/current/$PUBLIC_DIR" ] || die "$PROD/current/$PUBLIC_DIR not found: the release looks incomplete."
  for f in $SHARED_LINKS; do [ -e "$SHARED/$f" ] || die "$SHARED/$f missing. Run 'prepare' first."; done
  if [ -f "$SHARED/.env" ] && grep -q CHANGE_ME "$SHARED/.env"; then die "$SHARED/.env still contains CHANGE_ME."; fi
  [ -f "$HERE/deploy/htaccess.template" ] || die "$HERE/deploy/htaccess.template missing."

  local bk="$BACKUPS/public_html-before-cutover-$STAMP"
  mkdir -p "$bk"
  say "Backing up current public_html contents to $bk (moved, nothing deleted)"
  shopt -s dotglob nullglob
  for item in "$WEB"/*; do
    name="$(basename "$item")"
    case "$name" in site|"$DEV_SUBDOMAIN") continue ;; esac
    mv "$item" "$bk/"
  done
  for name in site "$DEV_SUBDOMAIN"; do
    if [ -e "$WEB/$name" ] || [ -L "$WEB/$name" ]; then mv "$WEB/$name" "$bk/$name"; fi
  done
  shopt -u dotglob nullglob

  ln -s "../prod/current/$PUBLIC_DIR" "$WEB/site"
  made "$WEB/site -> ../prod/current/$PUBLIC_DIR"

  if [ "$HAS_DEV" = "yes" ]; then
    if [ -d "$DEV/$PUBLIC_DIR" ]; then
      ln -s "../dev/$PUBLIC_DIR" "$WEB/$DEV_SUBDOMAIN"
      made "$WEB/$DEV_SUBDOMAIN -> ../dev/$PUBLIC_DIR   (dev subdomain document root)"
    else
      mkdir -p "$WEB/$DEV_SUBDOMAIN"
      warn "$DEV/$PUBLIC_DIR not found (dev not deployed yet): left an empty $WEB/$DEV_SUBDOMAIN. Run cutover again after the first dev deploy."
    fi
  fi

  cp "$HERE/deploy/htaccess.template" "$WEB/.htaccess"
  made "$WEB/.htaccess"

  say ""
  say "Cutover done. Open $SITE_URL/ now."
  say "To roll back:  rm $WEB/site $WEB/.htaccess ; [ -L $WEB/$DEV_SUBDOMAIN ] && rm $WEB/$DEV_SUBDOMAIN ; mv $bk/* $bk/.[!.]* $WEB/ 2>/dev/null"
}

case "${1:-}" in
  status)   cmd_status ;;
  prepare)  cmd_prepare ;;
  cutover)  cmd_cutover ;;
  *) say "Usage: bash $0 {status|prepare|cutover}"; exit 2 ;;
esac
