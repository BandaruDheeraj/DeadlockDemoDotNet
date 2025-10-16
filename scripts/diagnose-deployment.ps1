# Diagnose Deployment Issues
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json"
)

Write-Host "Diagnosing Deployment Issues" -ForegroundColor Green

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

# Check App Service status
Write-Host "`nChecking App Service status..." -ForegroundColor Cyan
$appService = az webapp show --name $config.AppName --resource-group $config.ResourceGroupName --query "state" -o tsv
Write-Host "App Service State: $appService" -ForegroundColor White

# Check App Service settings
Write-Host "`nChecking App Service settings..." -ForegroundColor Cyan
$appSettings = az webapp config appsettings list --name $config.AppName --resource-group $config.ResourceGroupName --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" -o tsv
if ($appSettings) {
    Write-Host "Application Insights Connection String: Configured" -ForegroundColor Green
} else {
    Write-Host "Application Insights Connection String: NOT CONFIGURED" -ForegroundColor Red
}

# Check deployment status
Write-Host "`nChecking deployment status..." -ForegroundColor Cyan
try {
    $deployments = az webapp deployment list --name $config.AppName --resource-group $config.ResourceGroupName --query "[0].{Status:status,Time:start_time}" -o table
    Write-Host $deployments
} catch {
    Write-Host "Could not retrieve deployment status: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Check application logs
Write-Host "`nChecking recent application logs..." -ForegroundColor Cyan
try {
    # Get logs using the correct command syntax
    $logs = az webapp log download --name $config.AppName --resource-group $config.ResourceGroupName --log-file "logs.zip"
    if (Test-Path "logs.zip") {
        Write-Host "Logs downloaded successfully" -ForegroundColor Green
        # Extract and show recent logs
        Expand-Archive -Path "logs.zip" -DestinationPath "temp_logs" -Force
        $logFiles = Get-ChildItem -Path "temp_logs" -Recurse -Include "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
        foreach ($logFile in $logFiles) {
            Write-Host "`nRecent log from $($logFile.Name):" -ForegroundColor White
            Get-Content $logFile.FullName -Tail 20 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        }
        # Cleanup
        Remove-Item "logs.zip" -Force -ErrorAction SilentlyContinue
        Remove-Item "temp_logs" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "No logs available" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Could not retrieve logs: $($_.Exception.Message)" -ForegroundColor Red
}

# Test basic connectivity
Write-Host "`nTesting basic connectivity..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$($config.AppServiceUrl)" -Method Get -TimeoutSec 10
    Write-Host "Basic connectivity: SUCCESS (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "Basic connectivity: FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Test health endpoint
Write-Host "`nTesting health endpoint..." -ForegroundColor Cyan
try {
    $healthResponse = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
    Write-Host "Health check: SUCCESS" -ForegroundColor Green
    Write-Host "Health status: $($healthResponse.status)" -ForegroundColor White
} catch {
    Write-Host "Health check: FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Check .NET version
Write-Host "`nChecking .NET version..." -ForegroundColor Cyan
$netVersion = az webapp config show --name $config.AppName --resource-group $config.ResourceGroupName --query "netFrameworkVersion" -o tsv
Write-Host ".NET Framework Version: $netVersion" -ForegroundColor White

Write-Host "`nDiagnosis complete!" -ForegroundColor Green
