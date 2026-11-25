# Quickstart: the manual steps (lite edition)

Fill the placeholders from your project's `scripts/deploy/deploy.conf` (and `docs/cicd-answers.env`).
`<SLUG>` project slug · `<ALIAS>` `github.com-<SLUG>` · `<DIR>` the domain folder name · `<GIT_REMOTE>` from `deploy.conf`.
Connect to the server first: `ssh -p <PORT> <USER>@<HOST>` (hPanel → Advanced → SSH Access).
Never paste passwords, private keys or `.env` contents anywhere.

## 1. Push the production branch
Claude committed everything locally. Push it: `git push -u origin main`. A red deploy run is expected until step 4.

## 2. Server key B: server → GitHub (read-only)
```
mkdir -p ~/.ssh/<SLUG>_key && chmod 700 ~/.ssh ~/.ssh/<SLUG>_key
ssh-keygen -t ed25519 -C "<SLUG>-server-deploy" -f ~/.ssh/<SLUG>_key/<SLUG> -N ""
cat >> ~/.ssh/config <<'EOF2'

Host <ALIAS>
    HostName github.com
    User git
    IdentityFile ~/.ssh/<SLUG>_key/<SLUG>
    IdentitiesOnly yes
EOF2
chmod 600 ~/.ssh/config
cat ~/.ssh/<SLUG>_key/<SLUG>.pub
```
GitHub → repo → **Settings → Deploy keys → Add deploy key**, paste the line, leave **write access off**. Test: `ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts && ssh -T git@<ALIAS>`.

## 3. Server key C: GitHub Actions → server
```
ssh-keygen -t ed25519 -C "<SLUG>-github-actions" -f ~/.ssh/<SLUG>_key/actions -N ""
cat ~/.ssh/<SLUG>_key/actions.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
cat ~/.ssh/<SLUG>_key/actions
```
Copy the printed private key into the GitHub secret `SSH_KEY`, then `rm ~/.ssh/<SLUG>_key/actions`.

## 4. GitHub secrets
Repo → Settings → Secrets and variables → Actions: `HOST` (server IP), `PORT` (SSH port, often 65002), `USERNAME` (server user), `SSH_KEY` (step 3).

## 5. hPanel
Create the production MySQL database and user. Set the PHP version your Laravel needs.

## 6. Scaffold the server folders
```
git clone --depth 1 -b main <GIT_REMOTE> ~/<SLUG>-tmp
bash ~/<SLUG>-tmp/scripts/server-scaffold.sh prepare
rm -rf ~/<SLUG>-tmp
nano ~/domains/<DIR>/prod/shared/.env        # replace every CHANGE_ME
```
`prepare` never touches `public_html`.

## 7. First deploy
GitHub → Actions → re-run the failed run (or push an empty commit). It ends with `Release ... is live`. Your live site is still the old one.

## 8. Cutover
```
bash ~/domains/<DIR>/prod/current/scripts/server-scaffold.sh cutover
```
It moves your current `public_html` into `backups/` (nothing is deleted), links the new release and prints the rollback command. Save that line. Open the site and check it.

## Rollback
```
cd ~/domains/<DIR>/prod && ls releases
ln -sfn "$PWD/releases/OLDER" current.tmp && mv -Tf current.tmp current
```
Database migrations are not undone. Dumps are in `~/domains/<DIR>/backups/`.
