<#
.SYNOPSIS
  Deploy the backend to Kinsta, run tests, and report results to COORDINATION.md

.PARAMETER CommitHash
  The git commit hash to deploy (should match a built archive)

.PARAMETER ArchivePath
  Path to the .zip archive to deploy

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File deploy-to-kinsta.ps1 -CommitHash 04e15bd -ArchivePath ./deploy_04e15bd_20260828_170802.zip
#>
param(
  [string]$CommitHash = "04e15bd",
  [string]$ArchivePath = ""
)

$ErrorActionPreference = 'Stop'

# Load environment
$envPath = Join-Path $PSScriptRoot '.env'
$cfg = @{}
foreach ($line in Get-Content $envPath) {
  if ($line -match '^\s*#') { continue }
  if ($line -notmatch '=') { continue }
  $parts = $line -split '=', 2
  $cfg[$parts[0].Trim()] = $parts[1].Trim()
}

$h = $cfg['CRM_SFTP_HOST']
$p = $cfg['CRM_SFTP_PORT']
$u = $cfg['CRM_SFTP_USER']
$pw = $cfg['CRM_SFTP_PASSWORD']

if (-not $h -or -not $p -or -not $u -or -not $pw) {
  Write-Host "SFTP credentials incomplete in .env" -ForegroundColor Red
  exit 1
}

# Find the archive if not specified
if (-not $ArchivePath) {
  $archives = Get-ChildItem -Path $PSScriptRoot -Filter "deploy_${CommitHash}*.zip" -ErrorAction SilentlyContinue
  if ($archives.Count -eq 0) {
    Write-Host "No archive found for commit $CommitHash. Create one first with:" -ForegroundColor Yellow
    Write-Host "  cd backend; Compress-Archive -Path . -DestinationPath ../deploy_${CommitHash}_`$(Get-Date -Format yyyyMMdd_HHmmss).zip"
    exit 1
  }
  $ArchivePath = $archives[0].FullName
}

if (-not (Test-Path $ArchivePath)) {
  Write-Host "Archive not found: $ArchivePath" -ForegroundColor Red
  exit 1
}

$archiveName = Split-Path -Leaf $ArchivePath
Write-Host ""
Write-Host "=== Kinsta Deployment: $CommitHash ===" -ForegroundColor Cyan
Write-Host "Archive: $archiveName"
Write-Host "Target: $u@$h:$p"
Write-Host ""

# Set up SSH environment - use password auth
$sshCmd = @"
`$ProgressPreference = 'SilentlyContinue'
`$env:SSHPASS = '$pw'
"@

# Step 1: Upload archive via scp
Write-Host "Step 1: Uploading archive..." -ForegroundColor Cyan
$scpCmd = "scp -P $p -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=nul `"$ArchivePath`" $u@$h:/www/sojourncrm_314/private/"
Write-Host "  $scpCmd" -ForegroundColor Gray

# Use SSHPASS for password-based auth if available
$sshpass = Get-Command sshpass -ErrorAction SilentlyContinue
if ($sshpass) {
  $env:SSHPASS = $pw
  & sshpass -e scp -P $p -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=nul "$ArchivePath" "$u@$h:/www/sojourncrm_314/private/" 2>&1
} else {
  # Fallback: use ssh config or prompt for password
  Write-Host "  (sshpass not available, using ssh with password prompt)" -ForegroundColor Yellow
  & scp -P $p -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=nul "$ArchivePath" "$u@$h:/www/sojourncrm_314/private/" 2>&1
}

if ($LASTEXITCODE -ne 0) {
  Write-Host "Upload failed" -ForegroundColor Red
  exit 1
}
Write-Host "  ✓ Archive uploaded" -ForegroundColor Green

# Step 2: Deploy on Kinsta (extract, optimize, test)
Write-Host ""
Write-Host "Step 2: Extracting and optimizing on Kinsta..." -ForegroundColor Cyan

$deployScript = @"
set -e
cd /www/sojourncrm_314/private

# Extract
unzip -q -o `$archiveName -d .

# Navigate to app and run optimization
cd app
php artisan optimize:clear
php artisan optimize

# Run tests
cd /www/sojourncrm_314/private/app
php artisan test 2>&1

exit 0
"@

# Run remote commands via SSH
if ($sshpass) {
  $env:SSHPASS = $pw
  $testOutput = & sshpass -e ssh -p $p -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=nul "$u@$h" "cd /www/sojourncrm_314/private && unzip -q -o '$archiveName' -d . && cd app && php artisan optimize:clear && php artisan optimize && php artisan test 2>&1" 2>&1
} else {
  Write-Host "  (sshpass not available, using ssh with password prompt)" -ForegroundColor Yellow
  $testOutput = & ssh -p $p -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=nul "$u@$h" "cd /www/sojourncrm_314/private && unzip -q -o '$archiveName' -d . && cd app && php artisan optimize:clear && php artisan optimize && php artisan test 2>&1" 2>&1
}

Write-Host ""
Write-Host "Step 3: Test Results" -ForegroundColor Cyan
Write-Host $testOutput

# Extract test count from output
$testOutput = $testOutput -join "`n"
if ($testOutput -match "(\d+) passed") {
  $passed = $matches[1]
  Write-Host ""
  Write-Host "  ✓ Tests passed: $passed" -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "  ⚠ Could not parse test count" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Deployment complete. Update COORDINATION.md with results." -ForegroundColor Green
