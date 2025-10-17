# Deploy Fixed Application
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json"
)

Write-Host "Deploying Fixed Application" -ForegroundColor Green

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

# Build and publish application
Write-Host "`nBuilding .NET application..." -ForegroundColor Cyan
Set-Location "..\DeadlockApp"

try {
    Write-Host "Cleaning previous build..." -ForegroundColor White
    dotnet clean
    
    Write-Host "Restoring packages..." -ForegroundColor White
    dotnet restore
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed"
    }

    Write-Host "Building application..." -ForegroundColor White
    dotnet build --configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed"
    }

    Write-Host "Publishing application..." -ForegroundColor White
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

Write-Host "Application deployed successfully" -ForegroundColor Green

# Wait for deployment to be ready
Write-Host "`nWaiting for deployment to be ready..." -ForegroundColor Cyan
$maxRetries = 30
$retryCount = 0

do {
    Start-Sleep -Seconds 10
    try {
        $response = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
        if ($response.status -eq "Healthy") {
            Write-Host "Application is healthy and ready!" -ForegroundColor Green
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

# Test basic endpoints
Write-Host "`nTesting basic endpoints..." -ForegroundColor Cyan

# Test root endpoint
try {
    $response = Invoke-WebRequest -Uri "$($config.AppServiceUrl)" -Method Get -TimeoutSec 10
    Write-Host "Root endpoint: SUCCESS (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "Root endpoint: FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Test health endpoint
try {
    $healthResponse = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
    Write-Host "Health endpoint: SUCCESS - Status: $($healthResponse.status)" -ForegroundColor Green
} catch {
    Write-Host "Health endpoint: FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Test API endpoints
$apiEndpoints = @("/api/products", "/api/products/1")
foreach ($endpoint in $apiEndpoints) {
    try {
        $response = Invoke-WebRequest -Uri "$($config.AppServiceUrl)$endpoint" -Method Get -TimeoutSec 10
        Write-Host "API $endpoint: SUCCESS (Status: $($response.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "API $endpoint: FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Cleanup
Remove-Item "./publish.zip" -Force -ErrorAction SilentlyContinue
Set-Location "..\scripts"

Write-Host "`nFixed Application Deployment Complete!" -ForegroundColor Green
Write-Host "Production URL: $($config.AppServiceUrl)" -ForegroundColor White
Write-Host "Health Check: $($config.AppServiceUrl)/health" -ForegroundColor White

Write-Host "`nKey Changes Made:" -ForegroundColor Cyan
Write-Host "✓ Removed TelemetryClient dependency from all custom classes" -ForegroundColor Green
Write-Host "✓ Added proper error handling for Application Insights configuration" -ForegroundColor Green
Write-Host "✓ Replaced telemetry calls with structured logging" -ForegroundColor Green
Write-Host "✓ Downgraded to .NET 8.0 for better stability" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Run: .\3-deploy-deadlock-to-staging.ps1" -ForegroundColor White
Write-Host "2. Verify staging deployment" -ForegroundColor White
Write-Host "3. Run: .\4-swap-to-production.ps1" -ForegroundColor White

