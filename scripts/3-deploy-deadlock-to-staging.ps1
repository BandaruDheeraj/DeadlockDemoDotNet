# Deploy Deadlock Version to Staging Slot
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json"
)

Write-Host "Deploying Deadlock Version to Staging Slot" -ForegroundColor Red

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

# Enable deadlock simulation for staging
Write-Host "`nConfiguring staging slot with deadlock simulation..." -ForegroundColor Cyan
az webapp config appsettings set --name $config.AppName --resource-group $config.ResourceGroupName --slot staging --settings EnableDeadlockSimulation=true
Write-Host "Deadlock simulation enabled for staging slot" -ForegroundColor Yellow

# Build and publish application (same build, different config)
Write-Host "`nBuilding .NET application..." -ForegroundColor Cyan
Set-Location "..\DeadlockApp"

try {
    dotnet restore
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed"
    }

    dotnet build --configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed"
    }

    dotnet publish --configuration Release --output ./publish
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed"
    }

    Write-Host "Application built successfully" -ForegroundColor Green
} catch {
    Write-Error "Build failed: $_"
    Set-Location "..\scripts"
    exit 1
}

# Create deployment package
Write-Host "`nCreating deployment package..." -ForegroundColor Cyan
Compress-Archive -Path "./publish/*" -DestinationPath "./publish.zip" -Force
Write-Host "Deployment package created" -ForegroundColor Green

# Deploy to staging slot
Write-Host "`nDeploying to staging slot..." -ForegroundColor Cyan
az webapp deployment source config-zip --name $config.AppName --resource-group $config.ResourceGroupName --slot staging --src "./publish.zip"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment to staging failed"
    Set-Location "..\scripts"
    exit 1
}

Write-Host "Application deployed to staging slot" -ForegroundColor Green

# Wait for staging deployment to be ready
Write-Host "`nWaiting for staging deployment to be ready..." -ForegroundColor Cyan
$maxRetries = 30
$retryCount = 0

do {
    Start-Sleep -Seconds 10
    try {
        $response = Invoke-RestMethod -Uri "$($config.StagingUrl)/health" -Method Get -TimeoutSec 10
        if ($response.status -eq "Healthy") {
            Write-Host "Staging application is healthy and ready" -ForegroundColor Green
            break
        } elseif ($response.status -eq "Degraded") {
            Write-Host "Staging application is degraded (expected with deadlock simulation)" -ForegroundColor Yellow
            break
        }
    } catch {
        Write-Host "Health check attempt $($retryCount + 1) failed, retrying..." -ForegroundColor Yellow
    }
    $retryCount++
} while ($retryCount -lt $maxRetries)

if ($retryCount -eq $maxRetries) {
    Write-Warning "Staging application may not be fully ready, but continuing..."
}

# Test staging endpoints to show they initially work
Write-Host "`nTesting staging endpoints..." -ForegroundColor Cyan
$testEndpoints = @(
    @{Url="/api/products"; Name="Products"},
    @{Url="/api/products/1"; Name="Single Product"},
    @{Url="/api/products/search?query=test"; Name="Search"}
)

foreach ($endpoint in $testEndpoints) {
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-RestMethod -Uri "$($config.StagingUrl)$($endpoint.Url)" -Method Get -TimeoutSec 10
        $stopwatch.Stop()

        $responseTime = $stopwatch.ElapsedMilliseconds
        $color = if ($responseTime -lt 500) { "Green" } elseif ($responseTime -lt 2000) { "Yellow" } else { "Red" }

        Write-Host "$($endpoint.Name): $($responseTime)ms" -ForegroundColor $color
    } catch {
        Write-Warning "$($endpoint.Name): Failed - $($_.Exception.Message)"
    }
}

# Test deadlock endpoints (these will be slower)
Write-Host "`nTesting deadlock-prone endpoints..." -ForegroundColor Cyan
Write-Host "Note: These endpoints may be slower due to deadlock simulation" -ForegroundColor Yellow

$deadlockEndpoints = @(
    @{Url="/api/orders/process"; Method="POST"; Name="Order Processing"},
    @{Url="/api/inventory/update"; Method="POST"; Name="Inventory Update"}
)

foreach ($endpoint in $deadlockEndpoints) {
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-RestMethod -Uri "$($config.StagingUrl)$($endpoint.Url)" -Method $endpoint.Method -Body "{}" -ContentType "application/json" -TimeoutSec 15
        $stopwatch.Stop()

        $responseTime = $stopwatch.ElapsedMilliseconds
        $color = if ($responseTime -lt 500) { "Green" } elseif ($responseTime -lt 2000) { "Yellow" } else { "Red" }

        Write-Host "$($endpoint.Name): $($responseTime)ms" -ForegroundColor $color
    } catch {
        Write-Warning "$($endpoint.Name): Failed - $($_.Exception.Message)"
    }
}

# Cleanup
Remove-Item "./publish.zip" -Force -ErrorAction SilentlyContinue
Set-Location "..\scripts"

Write-Host "`nDeadlock Version Deployed to Staging!" -ForegroundColor Red
Write-Host "Staging URL: $($config.StagingUrl)" -ForegroundColor White
Write-Host "Staging Health: $($config.StagingUrl)/health" -ForegroundColor White
Write-Host "Deadlock Simulation: ENABLED" -ForegroundColor Red

Write-Host "`nImportant Notes:" -ForegroundColor Yellow
Write-Host "  Staging slot has deadlock simulation ENABLED" -ForegroundColor White
Write-Host "  Production slot still has healthy version" -ForegroundColor White
Write-Host "  Deadlock will manifest under load" -ForegroundColor White
Write-Host "  This simulates a bad deployment" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Run: .\4-swap-to-production.ps1 (to deploy deadlock version to production)" -ForegroundColor White
Write-Host "2. Run: .\5-generate-load.ps1 (to trigger performance degradation)" -ForegroundColor White
Write-Host "3. Monitor Azure alerts for automatic remediation" -ForegroundColor White

Write-Host "`nMonitor Staging:" -ForegroundColor Cyan
Write-Host "  Health: $($config.StagingUrl)/health" -ForegroundColor Blue
Write-Host "  Orders Metrics: $($config.StagingUrl)/api/orders/metrics" -ForegroundColor Blue
Write-Host "  Inventory Metrics: $($config.StagingUrl)/api/inventory/metrics" -ForegroundColor Blue
