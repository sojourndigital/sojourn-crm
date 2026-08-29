<#
.SYNOPSIS
  Create the CRM deploy key, lock its file permissions down, and print the public half to paste
  into the MyKinsta panel. Writes nothing to the server and touches no password.

.DESCRIPTION
  Order matters here. The key is generated and REGISTERED IN .env first; the panel is only switched
  to key-only after a real key login has been proven. Flipping the panel first, with no working key,
  locks you out of your own host - and the probe already told us publickey is accepted, so there is
  no reason to gamble.

  The private key goes in $env:USERPROFILE\.ssh\, not in the repo. A private key inside a project
  folder gets copied with the project, and .gitignore does not stop a copy.

  No passphrase, deliberately: this key is used by unattended deploy scripts, so a passphrase would
  either block them or end up stored beside the key. That makes the FILE PERMISSIONS the only
  protection, which is why the icacls step is not optional - and it is also why Windows OpenSSH
  refuses a key whose ACL is too broad.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\Users\sojou\dev\sojourn-crm\setup-sftp-key.ps1
#>
$ErrorActionPreference = 'Stop'

$sshDir = Join-Path $env:USERPROFILE '.ssh'
$key    = Join-Path $sshDir 'sojourn-crm_ed25519'
$pub    = "$key.pub"
$envPath = Join-Path $PSScriptRoot '.env'

if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
  Write-Host 'ssh-keygen not on PATH - install the Windows OpenSSH Client feature first' -ForegroundColor Red; exit 1
}
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }

if (Test-Path $key) {
  Write-Host "key already exists: $key" -ForegroundColor Yellow
  Write-Host 'not overwriting - delete it yourself if you want a fresh pair' -ForegroundColor Yellow
} else {
  Write-Host "generating ed25519 keypair at $key" -ForegroundColor Cyan
  # Through cmd, not PowerShell: PS 5.1 drops or mangles an empty string argument to a native
  # command, so -N '""' can reach ssh-keygen as a literal two-character passphrase instead of
  # none. Done exactly that once already (2026-08-27). cmd passes -N "" through correctly.
  & cmd /c "ssh-keygen -t ed25519 -f ""$key"" -N """" -C ""sojourn-crm deploy key"" -q"
  if (-not (Test-Path $key)) { Write-Host 'keygen did not produce a key' -ForegroundColor Red; exit 1 }
  Write-Host '  OK   keypair created' -ForegroundColor Green
}

# Windows OpenSSH refuses a private key that other principals can read.
Write-Host ''
Write-Host 'locking down the private key ACL' -ForegroundColor Cyan
& icacls $key /inheritance:r  | Out-Null
& icacls $key /grant:r "$($env:USERNAME):(R)" | Out-Null
& icacls $key /remove 'Users' 'Authenticated Users' 'Everyone' 2>$null | Out-Null
Write-Host '  OK   readable by you only' -ForegroundColor Green

# Register the path, leaving the password line alone until the key is proven.
$lines = Get-Content $envPath
$new = $lines | ForEach-Object {
  if ($_ -match '^CRM_SFTP_KEY_PATH=') { "CRM_SFTP_KEY_PATH=$key" } else { $_ }
}
Set-Content -Path $envPath -Value $new -Encoding UTF8
Write-Host "  OK   CRM_SFTP_KEY_PATH written to .env (password line left in place for now)" -ForegroundColor Green

Write-Host ''
Write-Host '=== paste THIS into MyKinsta > SFTP/SSH > SSH keys ===' -ForegroundColor Cyan
Write-Host ''
Get-Content $pub
Write-Host ''
Write-Host '=== then, in order ===' -ForegroundColor Cyan
Write-Host '  1. re-run check-sftp-permissions.ps1 - it will now TEST the key and say if it works'
Write-Host '  2. only once it reports the key login succeeded: delete the CRM_SFTP_PASSWORD line'
Write-Host '  3. then set the panel to key-only and allowlist your IP'
Write-Host ''
Write-Host 'The public half above is safe to paste anywhere. The private half never leaves this' -ForegroundColor DarkGray
Write-Host 'machine, and is not in the repo folder.' -ForegroundColor DarkGray
Write-Host ''
