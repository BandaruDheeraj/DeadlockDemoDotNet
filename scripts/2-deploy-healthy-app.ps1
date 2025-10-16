# Deploy Healthy Application to Production
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json"
)

Write-Host "Deploying Healthy Application to Production" -ForegroundColor Green

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

# Ensure deadlock simulation is disabled
Write-Host "`nConfiguring application settings..." -ForegroundColor Cyan
az webapp config appsettings set --name $config.AppName --resource-group $config.ResourceGroupName --settings EnableDeadlockSimulation=false
Write-Host "Deadlock simulation disabled for production" -ForegroundColor Green

# Build and publish application
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

# Deploy to production slot
Write-Host "`nDeploying to production slot..." -ForegroundColor Cyan
az webapp deployment source config-zip --name $config.AppName --resource-group $config.ResourceGroupName --src "./publish.zip"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed"
    Set-Location "..\scripts"
    exit 1
}

Write-Host "Application deployed to production" -ForegroundColor Green

# Wait for deployment to be ready
Write-Host "`nWaiting for deployment to be ready..." -ForegroundColor Cyan
$maxRetries = 30
$retryCount = 0

do {
    Start-Sleep -Seconds 10
    try {
        $response = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
        if ($response.status -eq "Healthy") {
            Write-Host "Application is healthy and ready" -ForegroundColor Green
            break
        }
    } catch {
        Write-Host "Health check attempt $($retryCount + 1) failed, retrying..." -ForegroundColor Yellow
    }
    $retryCount++
} while ($retryCount -lt $maxRetries)

if ($retryCount -eq $maxRetries) {
    Write-Warning "Application may not be fully ready, but continuing..."
}

# Run performance baseline test
Write-Host "`nRunning performance baseline test..." -ForegroundColor Cyan
$endpoints = @("/api/products", "/api/products/1", "/api/products/search?query=test")
$responseTimes = @()
$totalRequests = 50

foreach ($endpoint in $endpoints) {
    Write-Host "Testing $endpoint..." -ForegroundColor White

    for ($i = 1; $i -le $totalRequests; $i++) {
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-RestMethod -Uri "$($config.AppServiceUrl)$endpoint" -Method Get -TimeoutSec 10
            $stopwatch.Stop()

            $responseTimes += $stopwatch.ElapsedMilliseconds

            if ($i % 10 -eq 0) {
                Write-Host "  Completed $i/$totalRequests requests" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Request $i failed: $($_.Exception.Message)"
        }
    }
}

# Calculate baseline metrics
if ($responseTimes.Count -gt 0) {
    $avgResponseTime = ($responseTimes | Measure-Object -Average).Average
    $p95ResponseTime = ($responseTimes | Sort-Object | Select-Object -Skip [Math]::Floor($responseTimes.Count * 0.95) | Select-Object -First 1)
    $maxResponseTime = ($responseTimes | Measure-Object -Maximum).Maximum

    Write-Host "`nPerformance Baseline Results:" -ForegroundColor Green
    Write-Host "  Average Response Time: $([Math]::Round($avgResponseTime, 2))ms" -ForegroundColor White
    Write-Host "  95th Percentile: $($p95ResponseTime)ms" -ForegroundColor White
    Write-Host "  Maximum Response Time: $($maxResponseTime)ms" -ForegroundColor White

    # Update config with baseline
    $config | Add-Member -NotePropertyName BaselineAverageResponseTime -NotePropertyValue ([Math]::Round($avgResponseTime, 2)) -Force
    $config | Add-Member -NotePropertyName BaselineP95ResponseTime -NotePropertyValue $p95ResponseTime -Force
    $config | Add-Member -NotePropertyName BaselineMaxResponseTime -NotePropertyValue $maxResponseTime -Force
    $config | ConvertTo-Json -Depth 3 | Out-File -FilePath "../scripts/$ConfigPath" -Encoding UTF8

    if ($avgResponseTime -gt 1000) {
        $roundedTime = [Math]::Round($avgResponseTime, 2)
        Write-Warning "Baseline response time is higher than expected: $roundedTime milliseconds"
    } else {
        Write-Host "Performance baseline established successfully" -ForegroundColor Green
    }
} else {
    Write-Error "No successful requests recorded for baseline"
}

# Cleanup
Remove-Item "./publish.zip" -Force -ErrorAction SilentlyContinue
Set-Location "..\scripts"

Write-Host "`nHealthy Application Deployment Complete!" -ForegroundColor Green
Write-Host "Production URL: $($config.AppServiceUrl)" -ForegroundColor White
Write-Host "Health Check: $($config.AppServiceUrl)/health" -ForegroundColor White
Write-Host "API Endpoints:" -ForegroundColor White
Write-Host "  Products: $($config.AppServiceUrl)/api/products" -ForegroundColor Gray
Write-Host "  Search: $($config.AppServiceUrl)/api/products/search?query=test" -ForegroundColor Gray

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Run: .\3-deploy-deadlock-to-staging.ps1" -ForegroundColor White
Write-Host "2. Verify staging deployment" -ForegroundColor White
Write-Host "3. Run: .\4-swap-to-production.ps1" -ForegroundColor White
