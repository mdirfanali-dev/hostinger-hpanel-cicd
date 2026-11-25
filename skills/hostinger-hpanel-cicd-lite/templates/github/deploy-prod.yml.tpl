name: Deploy PROD

# Push to __PROD_BRANCH__ -> tests -> release on the server (clone, install, backup DB, migrate, switch, smoke test).
# GitHub secrets needed: HOST, PORT, USERNAME, SSH_KEY

on:
  push:
    branches: [__PROD_BRANCH__]
  workflow_dispatch:

concurrency:
  group: deploy-prod
  cancel-in-progress: false

jobs:
  test:
    uses: ./.github/workflows/ci.yml

  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Release on the server
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.HOST }}
          port: ${{ secrets.PORT }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          envs: GITHUB_SHA
          script_stop: true
          script: |
            set -euo pipefail
            DOMAIN_DIR="$HOME/domains/__DOMAIN_DIR_NAME__"
            BASE="$DOMAIN_DIR/prod"
            NAME="$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$BASE/releases"
            echo "Cloning release $NAME at $GITHUB_SHA"
            git clone --quiet __GIT_REMOTE__ "$BASE/releases/$NAME"
            cd "$BASE/releases/$NAME"
            git checkout --quiet "$GITHUB_SHA"
            bash scripts/deploy/prod-release.sh "$BASE" "$NAME"
