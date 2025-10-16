# Swap Staging Slot to Production (Deploy Deadlock Version to Production)
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json",

    [Parameter(Mandatory=$false)]
    [switch]$SkipConfirmation
)

Write-Host "Swapping Staging Slot to Production" -ForegroundColor Red
Write-Host "WARNING: This will deploy the deadlock version to production!" -ForegroundColor Yellow

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

# Confirm the swap
if (-not $SkipConfirmation) {
    Write-Host "`nWARNING: This will replace the healthy production version with the deadlock version!" -ForegroundColor Red
    $confirmation = Read-Host "Are you sure you want to proceed? (type 'yes' to continue)"
    if ($confirmation -ne "yes") {
        Write-Host "Operation cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

# Check current production health before swap
Write-Host "`nChecking current production health..." -ForegroundColor Cyan
try {
    $prodHealth = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
    Write-Host "Current Production Status: $($prodHealth.status)" -ForegroundColor Green
} catch {
    Write-Warning "Could not check production health: $($_.Exception.Message)"
}

# Check staging health before swap
Write-Host "`nChecking staging health..." -ForegroundColor Cyan
try {
    $stagingHealth = Invoke-RestMethod -Uri "$($config.StagingUrl)/health" -Method Get -TimeoutSec 10
    Write-Host "Current Staging Status: $($stagingHealth.status)" -ForegroundColor Yellow
} catch {
    Write-Warning "Could not check staging health: $($_.Exception.Message)"
}

# Perform the slot swap
Write-Host "`nPerforming slot swap..." -ForegroundColor Cyan
Write-Host "Swapping staging to production (deadlock version will be live)" -ForegroundColor Red

$swapResult = az webapp deployment slot swap --name $config.AppName --resource-group $config.ResourceGroupName --slot staging --target-slot production
if ($LASTEXITCODE -ne 0) {
    Write-Error "Slot swap failed"
    exit 1
}

Write-Host "Slot swap completed successfully" -ForegroundColor Green

# Wait for swap to complete
Write-Host "`nWaiting for swap to complete..." -ForegroundColor Cyan
Start-Sleep -Seconds 30

# Verify the swap worked
Write-Host "`nVerifying swap..." -ForegroundColor Cyan
$maxRetries = 20
$retryCount = 0

do {
    Start-Sleep -Seconds 10
    try {
        $newProdHealth = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
        Write-Host "New Production Status: $($newProdHealth.status)" -ForegroundColor White

        if ($newProdHealth.status -in @("Healthy", "Degraded")) {
            Write-Host "Production is responding after swap" -ForegroundColor Green
            break
        }
    } catch {
        Write-Host "Verification attempt $($retryCount + 1) failed, retrying..." -ForegroundColor Yellow
    }
    $retryCount++
} while ($retryCount -lt $maxRetries)

if ($retryCount -eq $maxRetries) {
    Write-Warning "Could not verify swap completion, but continuing..."
}

# Test that deadlock simulation is now active in production
Write-Host "`nTesting production endpoints (now with deadlock simulation)..." -ForegroundColor Cyan

$testEndpoints = @(
    @{Url="/api/products"; Name="Products"; Method="GET"},
    @{Url="/api/orders/process"; Method="POST"; Name="Order Processing"},
    @{Url="/api/inventory/update"; Method="POST"; Name="Inventory Update"}
)

foreach ($endpoint in $testEndpoints) {
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        if ($endpoint.Method -eq "POST") {
            $response = Invoke-RestMethod -Uri "$($config.AppServiceUrl)$($endpoint.Url)" -Method POST -Body "{}" -ContentType "application/json" -TimeoutSec 15
        } else {
            $response = Invoke-RestMethod -Uri "$($config.AppServiceUrl)$($endpoint.Url)" -Method Get -TimeoutSec 10
        }

        $stopwatch.Stop()
        $responseTime = $stopwatch.ElapsedMilliseconds

        $color = if ($responseTime -lt 500) { "Green" } elseif ($responseTime -lt 2000) { "Yellow" } else { "Red" }
        Write-Host "$($endpoint.Name): $($responseTime)ms" -ForegroundColor $color

        if ($endpoint.Url -like "*orders*" -or $endpoint.Url -like "*inventory*") {
            if ($responseTime -gt 1000) {
                Write-Host "  Deadlock simulation is active (slower response)" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Warning "$($endpoint.Name): Failed - $($_.Exception.Message)"
    }
}

# Update configuration
$config | Add-Member -NotePropertyName DeadlockDeployedToProduction -NotePropertyValue $true -Force
$config | Add-Member -NotePropertyName ProductionSwapTime -NotePropertyValue (Get-Date) -Force
$config | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigPath -Encoding UTF8

Write-Host "`nProduction Swap Complete!" -ForegroundColor Red
Write-Host "Production URL: $($config.AppServiceUrl)" -ForegroundColor White
Write-Host "Deadlock Simulation: ENABLED in Production" -ForegroundColor Red
Write-Host "Previous Healthy Version: Now in Staging Slot" -ForegroundColor Green

Write-Host "`nCurrent State:" -ForegroundColor Yellow
Write-Host "  Production: Deadlock version (will degrade under load)" -ForegroundColor Red
Write-Host "  Staging: Healthy version (available for rollback)" -ForegroundColor Green
Write-Host "  Alerts: Configured to detect performance degradation" -ForegroundColor White
Write-Host "  SRE Agent: Will automatically swap back when alerts fire" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Run: .\5-generate-load.ps1 (to trigger performance degradation)" -ForegroundColor White
Write-Host "2. Monitor Azure Portal for alerts and metrics" -ForegroundColor White

Write-Host "`nMonitor Production:" -ForegroundColor Cyan
Write-Host "  Health: $($config.AppServiceUrl)/health" -ForegroundColor Blue
Write-Host "  Orders Metrics: $($config.AppServiceUrl)/api/orders/metrics" -ForegroundColor Blue
Write-Host "  Inventory Metrics: $($config.AppServiceUrl)/api/inventory/metrics" -ForegroundColor Blue

Write-Host "`nExpected Timeline:" -ForegroundColor Cyan
Write-Host "  0-5 minutes: Application appears healthy" -ForegroundColor White
Write-Host "  5-10 minutes: Performance begins to degrade under load" -ForegroundColor Yellow
Write-Host "  10-15 minutes: Alerts fire, SRE Agent triggers remediation" -ForegroundColor Red
Write-Host "  15-20 minutes: Slot swap back to healthy version" -ForegroundColor Green
