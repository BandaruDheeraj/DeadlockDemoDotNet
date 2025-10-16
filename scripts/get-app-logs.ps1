# Get Application Logs
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json"
)

Write-Host "Getting Application Logs" -ForegroundColor Green

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

# Get logs using correct Azure CLI commands
Write-Host "`nGetting application logs..." -ForegroundColor Cyan

# Method 1: Try to get recent logs
Write-Host "Trying to get recent logs..." -ForegroundColor White
try {
    # Enable logging first if not already enabled
    az webapp log config --name $config.AppName --resource-group $config.ResourceGroupName --application-logging filesystem --level information
    
    # Get logs using download command
    $logFile = "app-logs.zip"
    az webapp log download --name $config.AppName --resource-group $config.ResourceGroupName --log-file $logFile
    
    if (Test-Path $logFile) {
        Write-Host "Logs downloaded successfully" -ForegroundColor Green
        
        # Extract and show logs
        Expand-Archive -Path $logFile -DestinationPath "temp_logs" -Force -ErrorAction SilentlyContinue
        
        # Look for log files
        $logFiles = Get-ChildItem -Path "temp_logs" -Recurse -Include "*.log", "*.txt" -ErrorAction SilentlyContinue
        if ($logFiles) {
            foreach ($logFile in $logFiles) {
                Write-Host "`n=== Log File: $($logFile.Name) ===" -ForegroundColor Yellow
                $content = Get-Content $logFile.FullName -Tail 50 -ErrorAction SilentlyContinue
                if ($content) {
                    Write-Host $content -ForegroundColor Gray
                } else {
                    Write-Host "No content in log file" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "No log files found in download" -ForegroundColor Yellow
        }
        
        # Cleanup
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
        Remove-Item "temp_logs" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "Failed to download logs" -ForegroundColor Red
    }
} catch {
    Write-Host "Error getting logs: $($_.Exception.Message)" -ForegroundColor Red
}

# Method 2: Try to get stdout logs
Write-Host "`nTrying to get stdout logs..." -ForegroundColor White
try {
    $stdoutLogs = az webapp log tail --name $config.AppName --resource-group $config.ResourceGroupName
    if ($stdoutLogs) {
        Write-Host "Stdout logs:" -ForegroundColor Green
        Write-Host $stdoutLogs -ForegroundColor Gray
    } else {
        Write-Host "No stdout logs available" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error getting stdout logs: $($_.Exception.Message)" -ForegroundColor Red
}

# Method 3: Check App Service settings for any clues
Write-Host "`nChecking App Service configuration..." -ForegroundColor White
try {
    $appSettings = az webapp config appsettings list --name $config.AppName --resource-group $config.ResourceGroupName --query "[?contains(name, 'INSIGHTS') || contains(name, 'Deadlock') || contains(name, 'Performance')]" -o table
    Write-Host "Relevant App Settings:" -ForegroundColor Green
    Write-Host $appSettings
} catch {
    Write-Host "Error getting app settings: $($_.Exception.Message)" -ForegroundColor Red
}
