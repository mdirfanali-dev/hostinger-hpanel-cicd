# Smoke checks for __PROJECT_SLUG__ (edit freely; keep them cheap and stable).
#   /path|expected_status|text that must appear in the page   (text optional)
#   private|/path                                             (must answer 403 or 404)
__SMOKE_PAGES__

# Private files must never be reachable
private|/.env
private|/.git/config
private|/composer.json
private|/scripts/deploy/deploy.conf
private|/storage/logs/laravel.log
