#!/usr/bin/env pwsh
<#
.SYNOPSIS
  One-step deploy to production: build, upload, extract, optimize, test
.PARAMETER SkipBuild
  Skip npm build (use existing public/build)
#>
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'

# Config
$SshHost = "40.233.76.229"
$SshPort = "34048"
$SshUser = "sojourncrm"
$SshKeyPath = "$env:USERPROFILE\.ssh\sojourn-crm_ed25519"
$RemotePath = "/www/sojourncrm_314/private"

Write-Host "=== Production Deploy ===" -ForegroundColor Cyan

# Step 1: Build frontend
if (-not $SkipBuild) {
    Write-Host "Step 1: Building frontend..." -ForegroundColor Cyan
    cd backend
    npm run build
    cd ..
} else {
    Write-Host "Step 1: Skipping build (using existing assets)" -ForegroundColor Gray
}

# Step 2: Create archive
Write-Host "Step 2: Creating deployment archive..." -ForegroundColor Cyan
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$CommitHash = git rev-parse --short HEAD
$ArchiveName = "deploy_${CommitHash}_${Timestamp}.tar.gz"

cd backend
tar --exclude=node_modules --exclude=.env --exclude=database/database.sqlite -czf "../$ArchiveName" .
cd ..

$ArchiveSize = (Get-Item $ArchiveName).Length / 1MB
Write-Host "  Archive: $ArchiveName ($([Math]::Round($ArchiveSize, 1)) MB)" -ForegroundColor Green

# Step 3: Upload
Write-Host "Step 3: Uploading to server..." -ForegroundColor Cyan
scp -i $SshKeyPath -P $SshPort $ArchiveName "${SshUser}@${SshHost}:${RemotePath}/"
Write-Host "  ✓ Uploaded" -ForegroundColor Green

# Step 4: Deploy (extract, migrate, optimize, test)
Write-Host "Step 4: Deploying on server..." -ForegroundColor Cyan

$DeployCmd = @"
set -e
cd $RemotePath

# Extract
ARCHIVE=`$(ls -t ${ArchiveName} 2>/dev/null | head -1 || ls -t deploy_*.tar.gz | head -1)
echo "Extracting: `$ARCHIVE"
tar -xzf `$ARCHIVE -C app/

# Migrate
cd app
php artisan migrate --force

# Optimize
php artisan optimize:clear
php artisan optimize

# Test (if phpunit available)
if [ -f vendor/bin/phpunit ]; then
  echo "Running tests..."
  ./vendor/bin/phpunit --no-coverage 2>&1 | tail -15
else
  echo "Tests skipped (phpunit not installed)"
fi

echo ""
echo "✓ Deployment complete"
"@

ssh -i $SshKeyPath -p $SshPort "${SshUser}@${SshHost}" $DeployCmd

Write-Host ""
Write-Host "✓ Deployment complete!" -ForegroundColor Green
Write-Host "  Live at: https://sojourncrm.kinsta.cloud" -ForegroundColor Green
Write-Host ""
Write-Host "Cleanup:"
Remove-Item $ArchiveName
Write-Host "  Removed: $ArchiveName"
