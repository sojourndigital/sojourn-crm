<#
.SYNOPSIS
  Ask the CRM's SFTP host what it actually permits. Reads .env; never prints the password.

.DESCRIPTION
  The Kinsta panel settings - enabled/disabled, authentication methods, IP allowlist, password
  expiry - are host-side state and are not recorded anywhere on this machine. The only way to check
  them from here is to ask the server: whether the port answers tells you the allowlist lets this
  IP through, and the server's rejection message lists exactly which auth methods it accepts.

  This sends NO password. It asks with PreferredAuthentications=none purely to read the reply.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\Users\sojou\dev\sojourn-crm\check-sftp-permissions.ps1
#>
$ErrorActionPreference = 'Continue'

$envPath = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envPath)) { Write-Host "no .env at $envPath" -ForegroundColor Red; exit 1 }

$cfg = @{}
foreach ($line in Get-Content $envPath) {
  if ($line -match '^\s*#') { continue }
  if ($line -notmatch '=') { continue }
  $parts = $line -split '=', 2
  $cfg[$parts[0].Trim()] = $parts[1].Trim()
}

$h = $cfg['CRM_SFTP_HOST']; $p = $cfg['CRM_SFTP_PORT']; $u = $cfg['CRM_SFTP_USER']
if (-not $h -or -not $p -or -not $u) { Write-Host 'host, port or user is blank in .env' -ForegroundColor Red; exit 1 }
Write-Host ''
Write-Host "host $h  port $p  user $u" -ForegroundColor Cyan
Write-Host ("password in .env: {0}" -f $(if ($cfg['CRM_SFTP_PASSWORD']) { 'set (not shown, not sent)' } else { 'empty' }))
Write-Host ("key path in .env: {0}" -f $(if ($cfg['CRM_SFTP_KEY_PATH']) { $cfg['CRM_SFTP_KEY_PATH'] } else { 'empty - still on password auth' }))

Write-Host ''
Write-Host '=== 1. is the port reachable from this machine? (the IP allowlist) ===' -ForegroundColor Cyan
$tcp = Test-NetConnection -ComputerName $h -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue
if ($tcp) { Write-Host '  OK   port answers - this IP is getting through' -ForegroundColor Green }
else      { Write-Host '  !!   no answer - this IP is not allowed, the port is closed, or the user is disabled' -ForegroundColor Yellow }

Write-Host ''
Write-Host '=== 2. which authentication methods does the server accept? ===' -ForegroundColor Cyan
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  Write-Host '  ssh not on PATH - install the Windows OpenSSH Client feature, or read it off the panel' -ForegroundColor Yellow
} else {
  # Capture through a file rather than the pipeline. PowerShell 5.1 turns a native command's stderr
  # into ErrorRecord objects, and ssh says everything useful on stderr - which is how this section
  # printed nothing at all on the first run. A file cannot be swallowed.
  $tmp = Join-Path $env:TEMP 'crm-ssh-probe.txt'
  if (Test-Path $tmp) { Remove-Item $tmp -Force }
  $cmd = "ssh -o PreferredAuthentications=none -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $p $u@$h exit"
  Write-Host "  probing (no password sent)..." -ForegroundColor DarkGray
  & cmd /c "$cmd > ""$tmp"" 2>&1"
  Write-Host "  ssh exit code: $LASTEXITCODE"
  if (Test-Path $tmp) {
    $out = (Get-Content $tmp -Raw)
    if ([string]::IsNullOrWhiteSpace($out)) { Write-Host '  ssh said nothing at all - unusual; try adding -v' -ForegroundColor Yellow }
    else {
      Write-Host '  --- server reply, verbatim ---'
      $out.TrimEnd() -split "`n" | ForEach-Object { Write-Host "  $($_.TrimEnd())" }
      Write-Host '  --- end reply ---'
      if ($out -match 'Permission denied \(([^)]+)\)') {
        $methods = $Matches[1]
        Write-Host ''
        Write-Host "  ACCEPTED AUTH METHODS: $methods" -ForegroundColor Green
        if ($methods -match 'password') { Write-Host '  password auth is STILL ENABLED - this is what the key is meant to retire' -ForegroundColor Yellow }
        if ($methods -notmatch 'publickey') { Write-Host '  publickey is NOT offered - upload a key in the panel before switching to key-only' -ForegroundColor Yellow }
      }
    }
    Remove-Item $tmp -Force
  } else { Write-Host '  no output file - cmd could not run ssh' -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '=== 2b. is the private key usable without a passphrase? ===' -ForegroundColor Cyan
if (-not $cfg['CRM_SFTP_KEY_PATH']) {
  Write-Host '  no key path in .env yet' -ForegroundColor DarkGray
} elseif (-not (Test-Path $cfg['CRM_SFTP_KEY_PATH'])) {
  Write-Host "  key path does not exist: $($cfg['CRM_SFTP_KEY_PATH'])" -ForegroundColor Yellow
} else {
  # ssh-keygen -y re-derives the public half from the private one. With an empty -P it either
  # succeeds (no passphrase) or fails at once (there is one). It never prompts, so it cannot hang.
  $k3 = $cfg['CRM_SFTP_KEY_PATH']
  $t3 = Join-Path $env:TEMP 'crm-key-passphrase.txt'
  if (Test-Path $t3) { Remove-Item $t3 -Force }
  & cmd /c "ssh-keygen -y -f ""$k3"" -P """" > ""$t3"" 2>&1"
  $c3 = $LASTEXITCODE
  $o3 = if (Test-Path $t3) { (Get-Content $t3 -Raw) } else { '' }
  if ($c3 -eq 0 -and $o3 -match 'ssh-') {
    Write-Host '  OK   loads with no passphrase - correct for an unattended deploy key' -ForegroundColor Green
  } else {
    Write-Host "  !!   the key appears to HAVE a passphrase (exit $c3)" -ForegroundColor Yellow
    Write-Host '       Almost certainly the literal two quote characters, from a PowerShell' -ForegroundColor Yellow
    Write-Host '       quoting bug in the first version of setup-sftp-key.ps1.' -ForegroundColor Yellow
    Write-Host '       Fix, BEFORE pasting any key into the panel: delete both halves and re-run' -ForegroundColor Yellow
    Write-Host '       setup-sftp-key.ps1, which now generates through cmd.' -ForegroundColor Yellow
    Write-Host "         del $k3" -ForegroundColor Yellow
    Write-Host "         del $k3.pub" -ForegroundColor Yellow
    if ($o3) { $o3.TrimEnd() -split "`n" | ForEach-Object { Write-Host "       $($_.TrimEnd())" } }
  }
  if (Test-Path $t3) { Remove-Item $t3 -Force }
}

Write-Host ''
Write-Host '=== 3. does the key actually log in? ===' -ForegroundColor Cyan
if (-not $cfg['CRM_SFTP_KEY_PATH']) {
  Write-Host '  no key path in .env - run setup-sftp-key.ps1 first' -ForegroundColor DarkGray
} elseif (-not (Test-Path $cfg['CRM_SFTP_KEY_PATH'])) {
  Write-Host "  key path in .env does not exist: $($cfg['CRM_SFTP_KEY_PATH'])" -ForegroundColor Yellow
} else {
  $k = $cfg['CRM_SFTP_KEY_PATH']
  $t2 = Join-Path $env:TEMP 'crm-key-probe.txt'
  if (Test-Path $t2) { Remove-Item $t2 -Force }
  & cmd /c "ssh -i ""$k"" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $p $u@$h exit > ""$t2"" 2>&1"
  $code = $LASTEXITCODE
  $o2 = if (Test-Path $t2) { (Get-Content $t2 -Raw) } else { '' }
  if ($code -eq 0) {
    Write-Host '  OK   key login SUCCEEDED - safe to delete the password line and go key-only' -ForegroundColor Green
  } else {
    Write-Host "  !!   key login failed (exit $code) - do NOT set the panel to key-only yet" -ForegroundColor Yellow
    if ($o2) { $o2.TrimEnd() -split "`n" | ForEach-Object { Write-Host "       $($_.TrimEnd())" } }
  }
  if (Test-Path $t2) { Remove-Item $t2 -Force }
}

Write-Host ''
Write-Host 'Not checkable from here at all: password expiry, and whether the user is toggled' -ForegroundColor DarkGray
Write-Host 'Disabled. Those exist only in the MyKinsta panel.' -ForegroundColor DarkGray
Write-Host ''
