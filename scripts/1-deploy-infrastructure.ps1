# Deploy Azure Infrastructure for Deadlock Demo
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory=$false)]
    [string]$AppName = "deadlock-demo-app",
    
    [Parameter(Mandatory=$false)]
    [string]$AppServicePlanSku = "S1"
)

Write-Host "🚀 Deploying Azure Infrastructure for Deadlock Demo" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow
Write-Host "App Name: $AppName" -ForegroundColor Yellow

# Ensure Azure CLI is logged in
Write-Host "`n📋 Checking Azure CLI login status..." -ForegroundColor Cyan
$account = az account show --output json | ConvertFrom-Json
if (-not $account) {
    Write-Error "❌ Not logged into Azure CLI. Please run 'az login' first."
    exit 1
}
Write-Host "✅ Logged in as: $($account.user.name)" -ForegroundColor Green

# Create resource group if it doesn't exist
Write-Host "`n🏗️  Creating resource group..." -ForegroundColor Cyan
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "false") {
    az group create --name $ResourceGroupName --location $Location --output json | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Failed to create resource group"
        exit 1
    }
    Write-Host "✅ Resource group created" -ForegroundColor Green
} else {
    Write-Host "✅ Resource group already exists" -ForegroundColor Green
}

# Deploy Bicep template
Write-Host "`n📦 Deploying Bicep template..." -ForegroundColor Cyan
$deploymentName = "deadlock-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$deploymentResult = az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file "../infrastructure/main.bicep" `
    --parameters appServiceName=$AppName appServicePlanSku=$AppServicePlanSku location=$Location `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Bicep deployment failed"
    exit 1
}

Write-Host "✅ Bicep deployment completed" -ForegroundColor Green

# Extract outputs
$appServiceName = $deploymentResult.properties.outputs.appServiceName.value
$appServiceUrl = $deploymentResult.properties.outputs.appServiceUrl.value
$stagingUrl = $deploymentResult.properties.outputs.stagingUrl.value
$appInsightsConnectionString = $deploymentResult.properties.outputs.applicationInsightsConnectionString.value
$workspaceName = $deploymentResult.properties.outputs.workspaceName.value
$actionGroupName = $deploymentResult.properties.outputs.actionGroupName.value

# Save configuration for other scripts
$config = @{
    ResourceGroupName = $ResourceGroupName
    AppName = $appServiceName
    AppServiceUrl = $appServiceUrl
    StagingUrl = $stagingUrl
    AppInsightsConnectionString = $appInsightsConnectionString
    WorkspaceName = $workspaceName
    ActionGroupName = $actionGroupName
    DeploymentDate = Get-Date
}

$configPath = ".\demo-config.json"
$config | ConvertTo-Json -Depth 3 | Out-File -FilePath $configPath -Encoding UTF8
Write-Host "✅ Configuration saved to $configPath" -ForegroundColor Green

# Display results
Write-Host "`n🎉 Infrastructure Deployment Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "App Service Name: $appServiceName" -ForegroundColor White
Write-Host "Production URL: $appServiceUrl" -ForegroundColor White
Write-Host "Staging URL: $stagingUrl" -ForegroundColor White
Write-Host "Log Analytics Workspace: $workspaceName" -ForegroundColor White
Write-Host "Action Group: $actionGroupName" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow

Write-Host "`n🔗 Quick Links:" -ForegroundColor Cyan
Write-Host "• Azure Portal: https://portal.azure.com/#@/resource/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName" -ForegroundColor Blue
Write-Host "• App Service: https://portal.azure.com/#@/resource/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$appServiceName" -ForegroundColor Blue
Write-Host "• Application Insights: https://portal.azure.com/#@/resource/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/components/$appServiceName-ai" -ForegroundColor Blue

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Run: .\2-deploy-healthy-app.ps1" -ForegroundColor White
Write-Host "2. Run: .\3-deploy-deadlock-to-staging.ps1" -ForegroundColor White
Write-Host "3. Run: .\4-swap-to-production.ps1" -ForegroundColor White
Write-Host "4. Run: .\5-generate-load.ps1" -ForegroundColor White

Write-Host "`n⚠️  Note: Update the webhook URL in the Action Group for SRE Agent integration" -ForegroundColor Yellow
