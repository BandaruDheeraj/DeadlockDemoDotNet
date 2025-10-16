# Full Deadlock Demo Sequence
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory=$false)]
    [string]$AppName = "deadlock-demo-app",
    
    [Parameter(Mandatory=$false)]
    [int]$LoadTestDurationMinutes = 10,
    
    [Parameter(Mandatory=$false)]
    [int]$MonitorDurationMinutes = 10
)

Write-Host "🎭 Azure SRE Agent Deadlock Demo - Full Sequence" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "This demo will:" -ForegroundColor White
Write-Host "1. Deploy Azure infrastructure" -ForegroundColor White
Write-Host "2. Deploy healthy application to production" -ForegroundColor White
Write-Host "3. Deploy deadlock version to staging" -ForegroundColor White
Write-Host "4. Swap deadlock version to production" -ForegroundColor White
Write-Host "5. Generate load to trigger performance degradation" -ForegroundColor White
Write-Host "6. Monitor SRE Agent automatic remediation" -ForegroundColor White
Write-Host "7. Create GitHub issue and PR for fix" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow

Write-Host "`n📋 Demo Configuration:" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "Location: $Location" -ForegroundColor White
Write-Host "App Name: $AppName" -ForegroundColor White
Write-Host "Load Test Duration: $LoadTestDurationMinutes minutes" -ForegroundColor White
Write-Host "Monitor Duration: $MonitorDurationMinutes minutes" -ForegroundColor White

$confirmation = Read-Host "`nReady to start the demo? (Press Enter to continue or 'q' to quit)"
if ($confirmation -eq "q") {
    Write-Host "❌ Demo cancelled by user" -ForegroundColor Yellow
    exit 0
}

# Step 1: Deploy Infrastructure
Write-Host "`n🏗️  STEP 1: Deploy Azure Infrastructure" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Deploying App Service, slots, Application Insights, and alerts..." -ForegroundColor White

try {
    & ".\1-deploy-infrastructure.ps1" -ResourceGroupName $ResourceGroupName -Location $Location -AppName $AppName
    if ($LASTEXITCODE -ne 0) {
        throw "Infrastructure deployment failed"
    }
    Write-Host "✅ Infrastructure deployed successfully" -ForegroundColor Green
} catch {
    Write-Error "❌ Step 1 failed: $_"
    exit 1
}

$continue = Read-Host "`nPress Enter to continue to Step 2..."
if ($continue -eq "q") { exit 0 }

# Step 2: Deploy Healthy App
Write-Host "`n🏥 STEP 2: Deploy Healthy Application to Production" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Deploying application with deadlock simulation disabled..." -ForegroundColor White

try {
    & ".\2-deploy-healthy-app.ps1"
    if ($LASTEXITCODE -ne 0) {
        throw "Healthy app deployment failed"
    }
    Write-Host "✅ Healthy application deployed successfully" -ForegroundColor Green
} catch {
    Write-Error "❌ Step 2 failed: $_"
    exit 1
}

$continue = Read-Host "`nPress Enter to continue to Step 3..."
if ($continue -eq "q") { exit 0 }

# Step 3: Deploy Deadlock to Staging
Write-Host "`n🔒 STEP 3: Deploy Deadlock Version to Staging" -ForegroundColor Red
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Deploying application with deadlock simulation enabled to staging..." -ForegroundColor White

try {
    & ".\3-deploy-deadlock-to-staging.ps1"
    if ($LASTEXITCODE -ne 0) {
        throw "Deadlock deployment failed"
    }
    Write-Host "✅ Deadlock version deployed to staging successfully" -ForegroundColor Green
} catch {
    Write-Error "❌ Step 3 failed: $_"
    exit 1
}

$continue = Read-Host "`nPress Enter to continue to Step 4..."
if ($continue -eq "q") { exit 0 }

# Step 4: Swap to Production
Write-Host "`n🔄 STEP 4: Swap Staging to Production" -ForegroundColor Red
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "⚠️  This will deploy the deadlock version to production!" -ForegroundColor Red

try {
    & ".\4-swap-to-production.ps1"
    if ($LASTEXITCODE -ne 0) {
        throw "Slot swap failed"
    }
    Write-Host "✅ Deadlock version now in production" -ForegroundColor Green
} catch {
    Write-Error "❌ Step 4 failed: $_"
    exit 1
}

$continue = Read-Host "`nPress Enter to continue to Step 5..."
if ($continue -eq "q") { exit 0 }

# Step 5: Generate Load
Write-Host "`n🔥 STEP 5: Generate Load to Trigger Performance Degradation" -ForegroundColor Red
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Generating load for $LoadTestDurationMinutes minutes to trigger deadlock..." -ForegroundColor White

try {
    & ".\5-generate-load.ps1" -DurationMinutes $LoadTestDurationMinutes
    if ($LASTEXITCODE -ne 0) {
        throw "Load generation failed"
    }
    Write-Host "✅ Load generation completed" -ForegroundColor Green
} catch {
    Write-Error "❌ Step 5 failed: $_"
    exit 1
}

$continue = Read-Host "`nPress Enter to continue to Step 6..."
if ($continue -eq "q") { exit 0 }

# Step 6: Monitor SRE Agent
Write-Host "`n🤖 STEP 6: Monitor SRE Agent Automatic Remediation" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Monitoring for automatic remediation for $MonitorDurationMinutes minutes..." -ForegroundColor White

try {
    & ".\6-monitor-sre-agent.ps1" -MonitorMinutes $MonitorDurationMinutes
    if ($LASTEXITCODE -ne 0) {
        throw "SRE Agent monitoring failed"
    }
    Write-Host "✅ SRE Agent monitoring completed" -ForegroundColor Green
} catch {
    Write-Error "❌ Step 6 failed: $_"
    exit 1
}

$continue = Read-Host "`nPress Enter to continue to Step 7..."
if ($continue -eq "q") { exit 0 }

# Step 7: Create Issue and PR
Write-Host "`n🐙 STEP 7: Create GitHub Issue and PR" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Creating GitHub issue and PR for deadlock fix..." -ForegroundColor White

$githubToken = Read-Host "Enter GitHub Personal Access Token (required for API access)"
$repositoryUrl = Read-Host "Enter GitHub Repository URL (e.g., https://github.com/owner/repo)"

if (-not $githubToken -or -not $repositoryUrl) {
    Write-Warning "⚠️  Skipping GitHub issue/PR creation - missing token or repository URL"
    Write-Host "You can run .\7-create-issue-and-pr.ps1 manually later" -ForegroundColor Yellow
} else {
    try {
        & ".\7-create-issue-and-pr.ps1" -GitHubToken $githubToken -RepositoryUrl $repositoryUrl
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub issue/PR creation failed"
        }
        Write-Host "✅ GitHub issue and PR created successfully" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  GitHub issue/PR creation failed: $_"
        Write-Host "You can run .\7-create-issue-and-pr.ps1 manually later" -ForegroundColor Yellow
    }
}

# Demo Complete
Write-Host "`n🎉 DEADLOCK DEMO COMPLETE!" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "All demo steps completed successfully!" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow

# Load final configuration and display summary
if (Test-Path ".\demo-config.json") {
    $config = Get-Content ".\demo-config.json" | ConvertFrom-Json
    
    Write-Host "`n📊 Demo Summary:" -ForegroundColor Cyan
    Write-Host "App Service: $($config.AppName)" -ForegroundColor White
    Write-Host "Production URL: $($config.AppServiceUrl)" -ForegroundColor White
    Write-Host "Staging URL: $($config.StagingUrl)" -ForegroundColor White
    
    if ($config.BaselineAverageResponseTime) {
        Write-Host "Baseline Response Time: $($config.BaselineAverageResponseTime)ms" -ForegroundColor White
    }
    
    if ($config.LoadTestResults) {
        Write-Host "Load Test Results:" -ForegroundColor White
        Write-Host "  Average Response Time: $($config.LoadTestResults.AverageResponseTime)ms" -ForegroundColor White
        Write-Host "  Timeout Rate: $($config.LoadTestResults.TimeoutRate)%" -ForegroundColor White
        Write-Host "  Total Requests: $($config.LoadTestResults.TotalRequests)" -ForegroundColor White
    }
    
    if ($config.SREAgentMonitoring) {
        Write-Host "SRE Agent Results:" -ForegroundColor White
        Write-Host "  Alert Fired: $(if ($config.SREAgentMonitoring.AlertFired) { 'Yes' } else { 'No' })" -ForegroundColor White
        Write-Host "  Remediation Successful: $(if ($config.SREAgentMonitoring.RemediationSuccessful) { 'Yes' } else { 'No' })" -ForegroundColor White
    }
    
    if ($config.GitHubIssue) {
        Write-Host "GitHub Issue: #$($config.GitHubIssue.Number)" -ForegroundColor White
        Write-Host "Issue URL: $($config.GitHubIssue.Url)" -ForegroundColor Blue
    }
}

Write-Host "`n🔗 Monitoring and Review:" -ForegroundColor Cyan
Write-Host "• Azure Portal: https://portal.azure.com/#@/resource/subscriptions/*/resourceGroups/$ResourceGroupName" -ForegroundColor Blue
Write-Host "• Application Insights Live Metrics" -ForegroundColor Blue
Write-Host "• Azure Monitor Alerts" -ForegroundColor Blue
Write-Host "• Health Endpoints: $($config.AppServiceUrl)/health" -ForegroundColor Blue

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Review the demo results in Azure Portal" -ForegroundColor White
Write-Host "2. Examine the deadlock fix files in fixes/ folder" -ForegroundColor White
Write-Host "3. Implement the actual fix in your codebase" -ForegroundColor White
Write-Host "4. Deploy the fix using the same deployment process" -ForegroundColor White

Write-Host "`n🎯 Learning Objectives Achieved:" -ForegroundColor Cyan
Write-Host "✅ Demonstrated thread synchronization deadlock" -ForegroundColor Green
Write-Host "✅ Showed performance degradation detection" -ForegroundColor Green
Write-Host "✅ Illustrated SRE Agent automated remediation" -ForegroundColor Green
Write-Host "✅ Created incident response workflow" -ForegroundColor Green
Write-Host "✅ Generated fix documentation and PR" -ForegroundColor Green

Write-Host "`nThank you for running the Azure SRE Agent Deadlock Demo! 🎭" -ForegroundColor Magenta
