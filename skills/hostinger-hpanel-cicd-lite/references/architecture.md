# Architecture (lite)

```
~/domains/<site>/
├─ public_html/          the only web-reachable folder
│  ├─ .htaccess          HTTPS rule, rewrite everything to site/
│  └─ site  -> ../prod/current/public
├─ prod/
│  ├─ releases/<timestamp>/   one full git clone per deploy
│  ├─ shared/  .env  storage/ survive every deploy
│  └─ current -> releases/<newest>
└─ backups/               DB dumps, public_html before the cutover
```

Three SSH keys, one job each, never reused:

| Key | From → to | Private half | Public half |
|---|---|---|---|
| A | your laptop → GitHub | laptop | your GitHub account |
| B | server → GitHub, read-only | server `~/.ssh/<slug>_key/<slug>` | repo Settings → Deploy keys |
| C | GitHub Actions → server | GitHub secret `SSH_KEY` | server `~/.ssh/authorized_keys` |

Only each release's `public/` folder is web-reachable. `.env` lives in `shared/`, outside every release and outside Git.
