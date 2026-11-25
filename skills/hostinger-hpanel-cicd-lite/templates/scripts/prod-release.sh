#!/usr/bin/env bash
# Runs ON the server, from inside a freshly cloned release folder:
#   bash scripts/deploy/prod-release.sh <BASE> <RELEASE_NAME>
#
# BASE = ~/domains/<site>/prod   (contains releases/, shared/, current)
# Settings come from scripts/deploy/deploy.conf.
#
# Order: link shared files -> install -> boot check -> local smoke test -> DB backup -> migrate
#        -> optimize -> switch `current` -> public smoke test (rollback on failure) -> prune old releases.
set -euo pipefail

BASE="${1:?usage: prod-release.sh <BASE> <RELEASE_NAME>}"
NAME="${2:?usage: prod-release.sh <BASE> <RELEASE_NAME>}"
REL="$BASE/releases/$NAME"
DOMAIN_DIR="$(dirname "$BASE")"

cd "$REL"
# shellcheck disable=SC1091
. scripts/deploy/deploy.conf
export PHP_BIN

PREV="$(readlink "$BASE/current" 2>/dev/null || true)"
SWITCHED=0
SMOKE="scripts/deploy/smoke.sh"

log() { printf '==> %s\n' "$*"; }

on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$SWITCHED" -eq 0 ] && [ -n "$NAME" ] && [ -d "$REL" ]; then
    echo "Deploy failed before the switch: removing the unfinished release $NAME (live site untouched)."
    cd "$BASE" && rm -rf -- "releases/$NAME"
  fi
}
trap on_exit EXIT

# ---- shared files must exist ---------------------------------------------------------------------
for item in $SHARED_LINKS; do
  [ -e "$BASE/shared/$item" ] || { echo "ERROR: $BASE/shared/$item is missing (run server-scaffold.sh prepare)"; exit 1; }
done
if [ -f "$BASE/shared/.env" ] && grep -q CHANGE_ME "$BASE/shared/.env"; then
  echo "ERROR: $BASE/shared/.env still contains CHANGE_ME"; exit 1
fi
env_get() { grep -E "^$1=" "$BASE/shared/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

log "Linking shared files: ${SHARED_LINKS:-none}"
for item in $SHARED_LINKS; do
  rm -rf -- "$item"
  ln -s "../../shared/$item" "$item"
done
for d in $EXTRA_DIRS; do mkdir -p "$d"; done

# ---- install / boot check ------------------------------------------------------------------------
if [ -n "$INSTALL_CMD" ]; then log "Installing dependencies"; eval "$INSTALL_CMD"; fi
if [ -n "$POST_INSTALL_CMD" ]; then eval "$POST_INSTALL_CMD"; fi
if [ -n "$BOOT_CHECK_CMD" ]; then log "Boot check"; eval "$BOOT_CHECK_CMD"; fi

# ---- local smoke test of the new release (before it goes live) -----------------------------------
if [ -n "$LOCAL_SERVE_CMD" ] && [ -f "$SMOKE" ]; then
  log "Local smoke test of the new release (before it goes live)"
  PORT=$((18000 + RANDOM % 1000))
  PIDFILE="$(mktemp)"
  SRVLOG="$(mktemp)"
  CMD="${LOCAL_SERVE_CMD//__PORT__/$PORT}"
  CMD="${CMD//__REL__/$REL}"
  # detached from the SSH session (stdin/stdout/stderr) so it can never keep the deploy hanging
  ( eval "$CMD" </dev/null >"$SRVLOG" 2>&1 ) &
  echo $! > "$PIDFILE"
  stop_test_server() {
    pkill -f -- "-S 127.0.0.1:$PORT" 2>/dev/null || true
    kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null || true
  }
  UP=0
  for _ in $(seq 1 20); do
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/"; then UP=1; break; fi
    sleep 0.5
  done
  if [ "$UP" -eq 1 ]; then
    if ! bash "$SMOKE" "http://127.0.0.1:$PORT"; then
      stop_test_server
      echo "--- test server output (PHP errors), to help find the cause:"
      tail -n 25 "$SRVLOG" 2>/dev/null | cut -c1-400
      echo "--- last application log lines (shared storage), to help find the cause:"
      for lf in "$BASE"/shared/storage/logs/*.log; do
        [ -f "$lf" ] && { echo "[$lf]"; tail -n 25 "$lf" | cut -c1-400; }
      done 2>/dev/null
      echo "ERROR: smoke test of the new release failed. Not switching."
      exit 1
    fi
  else
    echo "WARNING: could not start a local test server on this host; skipping the pre-switch smoke test."
  fi
  stop_test_server
  rm -f "$PIDFILE" "$SRVLOG"
fi

# ---- database backup -----------------------------------------------------------------------------
if [ "$DB_BACKUP" = "mysql-from-env" ] && [ "$(env_get DB_CONNECTION)" = "mysql" ] && command -v mysqldump >/dev/null 2>&1; then
  log "Backing up the database"
  mkdir -p "$DOMAIN_DIR/backups"
  MYSQL_PWD="$(env_get DB_PASSWORD)" mysqldump --no-tablespaces --single-transaction \
    -h "$(env_get DB_HOST)" -P "$(env_get DB_PORT)" -u "$(env_get DB_USERNAME)" "$(env_get DB_DATABASE)" \
    | gzip > "$DOMAIN_DIR/backups/db-$NAME.sql.gz"
  ls -1t "$DOMAIN_DIR"/backups/db-*.sql.gz 2>/dev/null | tail -n +11 | xargs -r rm -f   # keep the 10 newest
else
  echo "NOTE: skipping database backup (disabled, not mysql, or mysqldump not available)."
fi

if [ -n "$MIGRATE_CMD" ]; then log "Migrating"; eval "$MIGRATE_CMD"; fi
if [ -n "$OPTIMIZE_CMD" ]; then log "Optimizing"; eval "$OPTIMIZE_CMD"; fi

# ---- atomic switch -------------------------------------------------------------------------------
[ -d "$REL/$PUBLIC_DIR" ] || { echo "ERROR: web root folder '$PUBLIC_DIR' is missing in this release"; exit 1; }
log "Switching current -> $NAME"
ln -sfn "$REL" "$BASE/current.tmp"
mv -Tf "$BASE/current.tmp" "$BASE/current"
SWITCHED=1

rollback() {
  echo "ERROR: $1"
  if [ -n "$PREV" ] && [ -d "$PREV" ]; then
    echo "Rolling back to $PREV"
    ln -sfn "$PREV" "$BASE/current.tmp"
    mv -Tf "$BASE/current.tmp" "$BASE/current"
    echo "Rolled back. NOTE: database migrations that ran are NOT undone."
  else
    echo "No previous release to roll back to."
  fi
  exit 1
}

# ---- public smoke test (only once public_html points at current) ---------------------------------
if [ -L "$DOMAIN_DIR/public_html/site" ] && [ -f "$SMOKE" ]; then
  log "Public smoke test: $SITE_URL"
  ok=0
  for _ in 1 2 3; do
    if bash "$SMOKE" "$SITE_URL"; then ok=1; break; fi
    sleep 3
  done
  [ "$ok" -eq 1 ] || rollback "public smoke test failed"
else
  echo "NOTE: public_html is not switched over yet (run server-scaffold.sh cutover); skipping the public smoke test."
fi

# ---- prune ---------------------------------------------------------------------------------------
log "Pruning old releases (keeping $KEEP_RELEASES, plus current and previous)"
CUR="$(readlink "$BASE/current")"
ls -1d "$BASE"/releases/*/ 2>/dev/null | sort -r | tail -n +"$((KEEP_RELEASES + 1))" | while read -r dir; do
  dir="${dir%/}"
  [ "$dir" = "$CUR" ] && continue
  [ "$dir" = "$PREV" ] && continue
  rm -rf -- "$dir"
done

log "Release $NAME is live."
