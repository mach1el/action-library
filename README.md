# action-library

[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-reusable_workflows-2088FF?style=flat-square&logo=githubactions&logoColor=white)](https://docs.github.com/actions)
[![Ansible](https://img.shields.io/badge/Ansible-driven-1A1918?style=flat-square&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![License](https://img.shields.io/github/license/st-mich43l/action-library?style=flat-square)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/st-mich43l/action-library?style=flat-square)](https://github.com/st-mich43l/action-library/commits/master)
[![Repo Size](https://img.shields.io/github/repo-size/st-mich43l/action-library?style=flat-square)](https://github.com/st-mich43l/action-library)

Central deployment templates for `st-mich43l` services — the GitHub Actions
counterpart of a GitLab **pipeline-library**. Every service repo references the
same template instead of copy-pasting deploy YAML.

## What's inside

| Path | Type | Use |
|------|------|-----|
| [`.github/workflows/deploy-ansible.yml`](.github/workflows/deploy-ansible.yml) | Reusable workflow | **Preferred.** Runs the [`ansible-library`](https://github.com/st-mich43l/ansible-library) playbooks; all config centralized there, service repo needs only the vault-password secret. |
| [`.github/workflows/deploy-compose.yml`](.github/workflows/deploy-compose.yml) | Reusable workflow | Direct SSH+rsync deploy (no Ansible). Config passed as inputs/secrets per repo. |
| [`deploy-compose/action.yml`](deploy-compose/action.yml) | Composite action | The building block (SSH → rsync → `docker compose`). Use directly when you need custom steps around it. |
| [`init-env/init-env.sh`](init-env/init-env.sh) | Host script | One-time VPS bootstrap: create the deploy user, add it to `docker`, authorize the deploy key, create the deployment root. |

Deploy model: the runner SSHes into the VPS, `rsync`s the service's deploy
files to a target directory, then runs `docker compose` on the host. No image
registry required — images build on the host.

## Using it from a service repo

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [master]
  workflow_dispatch:

jobs:
  deploy:
    uses: st-mich43l/action-library/.github/workflows/deploy-compose.yml@master
    with:
      ssh-host: ${{ vars.DEPLOY_HOST }}
      ssh-user: ${{ vars.DEPLOY_USER }}
      target-path: /home/apexvoid/deployment/<service>
      source-path: deployment-template
      compose-files: "docker-compose.yml docker-compose.prod.yml"
      health-url: "http://127.0.0.1/_routing/health"
    secrets:
      ssh-key: ${{ secrets.DEPLOY_SSH_KEY }}
```

### Inputs (most used)

| Input | Default | Notes |
|-------|---------|-------|
| `ssh-host` / `ssh-user` | — | Non-secret → store as repo/org **Variables**. |
| `ssh-port` | `22` | |
| `target-path` | — | Absolute dir on the VPS. |
| `source-path` | `.` | Folder in the repo to ship, e.g. `deployment-template`. |
| `rsync-excludes` | `.git .github .env certbot` | Also protected from `--delete`, so server-only state (`.env`, TLS certs, data) survives. |
| `compose-files` | `docker-compose.yml` | Space-separated → `-f` args. |
| `compose-args` | `up -d --remove-orphans --force-recreate` | Forces containers to be recreated on each deploy. |
| `health-url` | — | Optional; curled on the host after deploy. |

### Secrets

| Secret | Required | Notes |
|--------|----------|-------|
| `ssh-key` | ✅ | Private SSH key of a deploy user on the VPS. **The only truly sensitive value.** |
| `env-file` | ❌ | Contents written to `<target>/.env` before compose. Use for services with app secrets (API keys, tokens). Routing does not need it. |

## VPS prerequisites (one-time)

Docker + compose v2 must be installed and inbound SSH reachable from
GitHub-hosted runners. Then provision the deploy user with
[`init-env/init-env.sh`](init-env/init-env.sh) — it creates the user, adds it to
the `docker` group, authorizes the deploy key, and creates the deployment root.
Idempotent, run as root on the host:

```bash
# generate a dedicated deploy keypair (do this once, locally)
ssh-keygen -t ed25519 -C "github-actions-deploy@<host>" -f deploy_key -N ""

# provision the host (script piped as stdin, public key passed as an argument)
ssh root@<host> "bash -s -- --user apexvoid --pubkey '$(cat deploy_key.pub)'" \
  < init-env/init-env.sh
```

Or copy the script over and run it locally on the host:

```bash
scp init-env/init-env.sh root@<host>:/tmp/
ssh root@<host> '/tmp/init-env.sh --user apexvoid --pubkey-file /tmp/deploy_key.pub'
```

Then put the **private** key (`deploy_key`) in the repo secret
`DEPLOY_SSH_KEY`. Default deploy root is `/home/<user>/deployment`; each service
lands under `/home/<user>/deployment/<project>`.

## Cross-repo referencing (private repos)

For private `st-mich43l/*` repos to reference this library:
**Settings → Actions → General → "Access"** on this repo → allow
*Accessible from repositories owned by the user*. Then pin to a tag
(`@v1`) once released instead of `@master`.
