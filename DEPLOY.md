# Deployment Guide

Quick reference for deploying Sojourn CRM to production.

## One-Command Deploy

```powershell
./deploy-prod.ps1
```

**What it does:**
1. Builds frontend (npm run build)
2. Creates timestamped .tar.gz archive
3. Uploads to Kinsta via SCP
4. Extracts and deploys on server
5. Runs migrations
6. Optimizes Laravel cache
7. Runs tests (if available)
8. Cleans up local archive

**Duration:** ~3-5 minutes

## Deploy Without Building

If you only changed backend code (no frontend changes):

```powershell
./deploy-prod.ps1 -SkipBuild
```

Reuses existing `public/build/` assets. Faster for backend-only changes.

## Verify Deployment

After deploying, verify the site is working:

```powershell
./verify-features.ps1    # Quick smoke test
./monitor-live.ps1       # Performance metrics
```

## Manual Deployment (if needed)

```powershell
# Step 1: Build
cd backend
npm run build
cd ..

# Step 2: Create archive
$CommitHash = git rev-parse --short HEAD
tar --exclude=node_modules --exclude=.env --exclude=database/database.sqlite `
  -czf "deploy_${CommitHash}_$(Get-Date -Format yyyyMMdd_HHmmss).tar.gz" backend/

# Step 3: Upload
scp -i ~/.ssh/sojourn-crm_ed25519 -P 34048 deploy_*.tar.gz `
  sojourncrm@40.233.76.229:/www/sojourncrm_314/private/

# Step 4: Deploy on server (SSH in and run):
cd /www/sojourncrm_314/private
tar -xzf deploy_*.tar.gz -C app/
cd app
php artisan migrate --force
php artisan optimize:clear && php artisan optimize
./vendor/bin/phpunit --no-coverage
```

## Rollback

See `backend/docs/RUNBOOK.md` → "Rollback" section

## Pre-Deployment Checklist

- [ ] Commit code locally
- [ ] Tests passing
- [ ] Update `backend/COORDINATION.md` if needed
- [ ] No uncommitted changes
- [ ] Build works locally (`npm run build`)

## Configuration

Credentials are baked into scripts:

**SSH Key:** `~/.ssh/sojourn-crm_ed25519` (configured in deploy script)
**Database:** `sojourncrm@localhost` with MariaDB
**Server:** `40.233.76.229:34048` (Kinsta environment)

All configured in `deploy-prod.ps1`. Update if credentials change.

## Monitoring

Live application status:

```powershell
./monitor-live.ps1
```

Checks:
- HTTP response times
- Database table counts
- Disk usage
- Error log entries

## Documentation

- **Performance:** `backend/docs/PERFORMANCE.md` — metrics, optimization, profiling
- **Operations:** `backend/docs/RUNBOOK.md` — troubleshooting, maintenance, SLA
- **Build Status:** `backend/COORDINATION.md` — feature tracking, decisions

## Live App

**URL:** https://sojourncrm.kinsta.cloud
**Login:** Temporary password auth (credentials given separately)
**Database:** MariaDB via phpMyAdmin at mysqleditor-sojourncrm.editdatabase.cloud

## Deployment History

Latest deployments tracked in git commit messages:
```bash
git log --oneline | head -10
```
