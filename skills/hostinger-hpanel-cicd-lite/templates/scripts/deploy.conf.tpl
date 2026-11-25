# deploy.conf: the ONLY project-specific settings used by scripts/deploy/*.sh and scripts/server-scaffold.sh.
# Rendered by the hostinger-hpanel-cicd skill (scripts/instantiate.py). NO SECRETS in this file: it is committed.
# Values are single-quoted shell strings; commands are run with `eval` on the server.
# Variables that may be overridden from the environment use the ${VAR:-default} form.

PROJECT_SLUG='__PROJECT_SLUG__'
APP_TYPE='__APP_TYPE__'                          # laravel | php | static
DOMAIN='__DOMAIN__'
DOMAIN_DIR_NAME='__DOMAIN_DIR_NAME__'            # folder under ~/domains on the server
SITE_URL="${SITE_URL:-__SITE_URL__}"             # used by the public smoke test after the switch
GIT_REMOTE='__GIT_REMOTE__'                      # uses the SSH alias of the server's read-only deploy key
PROD_BRANCH='__PROD_BRANCH__'
DEV_BRANCH='__DEV_BRANCH__'
HAS_DEV='__HAS_DEV__'                            # yes | no
DEV_SUBDOMAIN='__DEV_SUBDOMAIN__'                # folder name under public_html that hPanel uses as the dev subdomain root

PUBLIC_DIR='__PUBLIC_DIR__'                      # the ONLY folder of a release that is web-reachable (never '.')
KEEP_RELEASES="${KEEP_RELEASES:-__KEEP_RELEASES__}"
PHP_BIN="${PHP_BIN:-__PHP_BIN__}"

# Files/folders linked from prod/shared/ into every release (top-level names only)
SHARED_LINKS='__SHARED_LINKS__'
# Folders created inside prod/shared/ by `server-scaffold.sh prepare` (chmod 775)
SHARED_DIRS='__SHARED_DIRS__'
# Folders that must exist and be writable inside a release / the dev clone
EXTRA_DIRS='__EXTRA_DIRS__'
WRITABLE_DIRS='__WRITABLE_DIRS__'

# Release steps (empty = skip)
INSTALL_CMD='__INSTALL_CMD__'
POST_INSTALL_CMD='__POST_INSTALL_CMD__'
BOOT_CHECK_CMD='__BOOT_CHECK_CMD__'
MIGRATE_CMD='__MIGRATE_CMD__'
OPTIMIZE_CMD='__OPTIMIZE_CMD__'

# Optional pre-switch test server. __PORT__ and __REL__ are replaced at run time. Empty = skip.
LOCAL_SERVE_CMD='__LOCAL_SERVE_CMD__'

# mysql-from-env = dump the DB described by DB_* in shared/.env before migrating | none
DB_BACKUP='__DB_BACKUP__'
