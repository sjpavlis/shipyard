# 🚢 Shipyard

> One-command deployment toolkit for Docker containers on any VPS with Caddy auto-HTTPS.

Deploy Spring Boot (or any Docker) apps to a fresh VPS in minutes. No Kubernetes, no Terraform, no complexity.

---

## What It Does

- **Provisions a fresh VPS** — installs Docker, Caddy, optional MySQL
- **Deploys your app** — pulls image, starts container, configures reverse proxy
- **Handles HTTPS automatically** — Caddy + Let's Encrypt, zero config
- **Supports subdomains** — route multiple subdomains to one app with path rewriting
- **Works with GitHub Actions** — fetch scripts at CI time, deploy on push

---

## Stack

| Component | Role |
|-----------|------|
| Docker | Container runtime |
| Caddy | Reverse proxy + auto HTTPS |
| ghcr.io | Container registry (GitHub) |
| GitHub Actions | CI/CD pipeline |
| MySQL | Optional database |

---

## Quick Start

### 1. Provision a new droplet (one-time)

```bash
ssh root@YOUR_IP "bash <(curl -s https://raw.githubusercontent.com/sjpavlis/shipyard/main/scripts/setup-droplet.sh)" \
  --domain yourdomain.com \
  --subdomains "www,app,api" \
  --mysql false
```

### 2. Integrate into your project

Add a workflow file to your project that fetches Shipyard's deploy script:

```yaml
# .github/workflows/deploy.yml
- name: Get Shipyard
  run: git clone --depth 1 https://github.com/sjpavlis/shipyard.git .shipyard

- name: Deploy
  run: .shipyard/scripts/deploy-app.sh
  env:
    APP_NAME: myapp
    IMAGE: ghcr.io/youruser/yourapp:latest
    DROPLET_HOST: ${{ secrets.DROPLET_HOST }}
    DROPLET_SSH_KEY: ${{ secrets.DROPLET_SSH_KEY }}
    REGISTRY_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    REGISTRY_USER: ${{ github.actor }}
    ENV_VARS: "GITHUB_TOKEN=${{ secrets.APP_TOKEN }}"
```

That's it. Push to main → app deploys.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-droplet.sh` | Install Docker + Caddy on a fresh VPS |
| `scripts/setup-mysql.sh` | Install MySQL + create database/user |
| `scripts/setup-caddy.sh` | Generate and install Caddyfile from parameters |
| `scripts/deploy-app.sh` | Pull image, stop old container, start new one |
| `scripts/setup-backup.sh` | Configure daily MySQL backup to GitHub |

---

## Full Example: Spring Boot App

See [examples/spring-boot-workflow.yml](examples/spring-boot-workflow.yml) for a complete GitHub Actions pipeline that builds, pushes, and deploys a Spring Boot app.

---

## Configuration

All configuration is passed via environment variables or CLI flags. No config files to manage.

### Deploy Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `APP_NAME` | Yes | Container name |
| `IMAGE` | Yes | Full image path (e.g. `ghcr.io/user/app:latest`) |
| `DROPLET_HOST` | Yes | VPS IP address |
| `DROPLET_SSH_KEY` | Yes | SSH private key for VPS access |
| `REGISTRY_TOKEN` | Yes | Token to pull from container registry |
| `REGISTRY_USER` | Yes | Registry username |
| `APP_PORT` | No | App port (default: 8080) |
| `NETWORK_MODE` | No | Docker network mode (default: bridge) |
| `ENV_VARS` | No | Env vars to pass to container (newline-separated) |
| `KEEP_IMAGES` | No | Number of old images to keep (default: 3) |

### Setup Variables

| Variable/Flag | Required | Description |
|---------------|----------|-------------|
| `--domain` | Yes | Primary domain |
| `--subdomains` | No | Comma-separated subdomains |
| `--mysql` | No | Install MySQL (true/false, default: false) |
| `--db-name` | No | Database name (if mysql=true) |
| `--db-user` | No | Database user (if mysql=true) |
| `--db-password` | No | Database password (if mysql=true) |

---

## DNS Setup

After provisioning, point your domain to the VPS:

| Type | Name | Value |
|------|------|-------|
| A | `@` | VPS IP |
| A | `www` | VPS IP |
| A | each subdomain | VPS IP |

Caddy handles SSL certificates automatically once DNS resolves.

---

## License

MIT
