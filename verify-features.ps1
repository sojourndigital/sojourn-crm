#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Verify deployed features are working on live site
#>

$BaseUrl = "https://sojourncrm.kinsta.cloud"
$Features = @(
    @{Name = "Dashboard"; Path = "/"; Expected = "Good to see you" },
    @{Name = "Contacts"; Path = "/workspaces/northstar-property-care/people"; Expected = "Contacts\|69" },
    @{Name = "Companies"; Path = "/workspaces/northstar-property-care/organizations"; Expected = "Companies\|organizations" },
    @{Name = "Pipeline"; Path = "/workspaces/northstar-property-care/pipeline"; Expected = "Pipeline\|Active pipeline" },
    @{Name = "Tasks"; Path = "/workspaces/northstar-property-care/to-dos"; Expected = "to-dos\|tasks" },
    @{Name = "CSV Export (Contacts)"; Path = "/workspaces/northstar-property-care/people/export"; Expected = "attachment" },
    @{Name = "CSV Export (Pipeline)"; Path = "/workspaces/northstar-property-care/pipeline/export"; Expected = "attachment" },
)

Write-Host "=== Live Feature Verification ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl`n"

$Results = @()

foreach ($Feature in $Features) {
    $Url = $BaseUrl + $Feature.Path
    Write-Host "Testing: $($Feature.Name)... " -NoNewline

    try {
        $Response = Invoke-WebRequest -Uri $Url -MaximumRedirection 0 -ErrorAction SilentlyContinue

        if ($Response.StatusCode -eq 200 -or $Response.StatusCode -eq 302) {
            $Content = $Response.Content + $Response.RawContent

            if ($Content -match $Feature.Expected) {
                Write-Host "✓" -ForegroundColor Green
                $Results += @{Feature = $Feature.Name; Status = "PASS" }
            } else {
                Write-Host "✗ (missing expected content)" -ForegroundColor Yellow
                $Results += @{Feature = $Feature.Name; Status = "FAIL"; Reason = "Expected text not found" }
            }
        } else {
            Write-Host "✗ (HTTP $($Response.StatusCode))" -ForegroundColor Red
            $Results += @{Feature = $Feature.Name; Status = "FAIL"; Reason = "HTTP $($Response.StatusCode)" }
        }
    } catch {
        Write-Host "✗ (error)" -ForegroundColor Red
        $Results += @{Feature = $Feature.Name; Status = "FAIL"; Reason = $_.Exception.Message }
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$Passed = ($Results | Where-Object Status -eq "PASS").Count
$Failed = ($Results | Where-Object Status -eq "FAIL").Count
Write-Host "Passed: $Passed / Failed: $Failed`n"

if ($Failed -gt 0) {
    Write-Host "Failed tests:" -ForegroundColor Red
    $Results | Where-Object Status -eq "FAIL" | ForEach-Object {
        Write-Host "  - $($_.Feature): $($_.Reason)"
    }
}
