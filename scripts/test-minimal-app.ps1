# Test with minimal application to isolate the issue
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json"
)

Write-Host "Testing with Minimal Application" -ForegroundColor Green

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

# Backup current Program.cs
Write-Host "`nBacking up current Program.cs..." -ForegroundColor Cyan
if (Test-Path "..\DeadlockApp\Program.cs") {
    Copy-Item "..\DeadlockApp\Program.cs" "..\DeadlockApp\Program.cs.backup" -Force
    Write-Host "Backup created: Program.cs.backup" -ForegroundColor Green
}

# Use minimal version
Write-Host "`nUsing minimal Program.cs..." -ForegroundColor Cyan
if (Test-Path "..\DeadlockApp\Program.Minimal.cs") {
    Copy-Item "..\DeadlockApp\Program.Minimal.cs" "..\DeadlockApp\Program.cs" -Force
    Write-Host "Minimal version deployed" -ForegroundColor Green
} else {
    Write-Host "Creating minimal Program.cs..." -ForegroundColor Yellow
    
    $minimalContent = @"
var builder = WebApplication.CreateBuilder(args);

// Add minimal services
builder.Services.AddControllers();

var app = builder.Build();

// Configure minimal pipeline
app.MapControllers();

// Simple health check endpoint
app.MapGet("/health", () => new { status = "Healthy", timestamp = DateTime.UtcNow });

// Simple test endpoint
app.MapGet("/", () => "Deadlock Demo API is running");

app.Run();
"@
    
    $minimalContent | Out-File -FilePath "..\DeadlockApp\Program.cs" -Encoding UTF8
    Write-Host "Minimal Program.cs created" -ForegroundColor Green
}

# Build and deploy minimal version
Write-Host "`nBuilding minimal application..." -ForegroundColor Cyan
Set-Location "..\DeadlockApp"

try {
    dotnet restore
    dotnet build --configuration Release
    dotnet publish --configuration Release --output ./publish
    
    # Create deployment package
    Compress-Archive -Path "./publish/*" -DestinationPath "./publish.zip" -Force
    
    # Deploy
    Write-Host "Deploying minimal version..." -ForegroundColor Cyan
    az webapp deployment source config-zip --name $config.AppName --resource-group $config.ResourceGroupName --src "./publish.zip"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Minimal version deployed successfully" -ForegroundColor Green
        
        # Wait and test
        Write-Host "`nWaiting for deployment..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30
        
        # Test basic connectivity
        try {
            $response = Invoke-WebRequest -Uri "$($config.AppServiceUrl)" -Method Get -TimeoutSec 10
            Write-Host "Basic connectivity: SUCCESS (Status: $($response.StatusCode))" -ForegroundColor Green
        } catch {
            Write-Host "Basic connectivity: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Test health endpoint
        try {
            $healthResponse = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
            Write-Host "Health check: SUCCESS - $($healthResponse.status)" -ForegroundColor Green
        } catch {
            Write-Host "Health check: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
        
    } else {
        Write-Host "Deployment failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Build/deploy failed: $_" -ForegroundColor Red
} finally {
    # Cleanup
    Remove-Item "./publish.zip" -Force -ErrorAction SilentlyContinue
    Set-Location "..\scripts"
}

Write-Host "`nMinimal test complete!" -ForegroundColor Green
Write-Host "If this works, the issue is with the complex health checks or Application Insights" -ForegroundColor Yellow
Write-Host "If this fails, the issue is with basic ASP.NET Core startup" -ForegroundColor Yellow
