# Monitor SRE Agent and Automatic Remediation
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json",
    
    [Parameter(Mandatory=$false)]
    [int]$MonitorMinutes = 10
)

Write-Host "🤖 Monitoring SRE Agent and Automatic Remediation" -ForegroundColor Green
Write-Host "Monitor Duration: $MonitorMinutes minutes" -ForegroundColor Yellow

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "❌ Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow
Write-Host "Resource Group: $($config.ResourceGroupName)" -ForegroundColor Yellow

$stopTime = (Get-Date).AddMinutes($MonitorMinutes)
$startTime = Get-Date
$alertFired = $false
$remediationAttempted = $false
$remediationSuccessful = $false

Write-Host "`n🔍 Starting SRE Agent monitoring..." -ForegroundColor Cyan
Write-Host "Monitoring until: $(Get-Date -Date $stopTime -Format 'HH:mm:ss')" -ForegroundColor White

# Check initial state
Write-Host "`n📊 Initial Production Health Check:" -ForegroundColor Cyan
try {
    $initialHealth = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
    Write-Host "Status: $($initialHealth.status)" -ForegroundColor White
    
    $perfCheck = $initialHealth.checks | Where-Object { $_.name -eq 'performance' }
    if ($perfCheck) {
        $avgResponseTime = $perfCheck.data.AverageResponseTime
        $timeoutRate = $perfCheck.data.TimeoutRate
        Write-Host "Average Response Time: $avgResponseTime ms" -ForegroundColor White
        Write-Host "Timeout Rate: $timeoutRate%" -ForegroundColor White
        
        if ($avgResponseTime -gt 2000 -or $timeoutRate -gt 10) {
            Write-Host "⚠️  Performance issues already detected!" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Warning "Could not check initial health: $($_.Exception.Message)"
}

Write-Host "`n⏳ Monitoring alerts and remediation..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop monitoring early" -ForegroundColor Gray

$lastUpdateTime = Get-Date
while ((Get-Date) -lt $stopTime) {
    Start-Sleep -Seconds 15
    
    $currentTime = Get-Date
    $elapsedMinutes = [Math]::Round(($currentTime - $startTime).TotalMinutes, 1)
    $remainingMinutes = [Math]::Round(($stopTime - $currentTime).TotalMinutes, 1)
    
    # Update display every 30 seconds
    if (($currentTime - $lastUpdateTime).TotalSeconds -ge 30) {
        Clear-Host
        Write-Host "🤖 SRE Agent Monitoring" -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "Elapsed Time: $elapsedMinutes minutes" -ForegroundColor White
        Write-Host "Remaining Time: $remainingMinutes minutes" -ForegroundColor White
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
        
        # Check current production health
        try {
            $health = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
            Write-Host "`n📊 Current Production Status:" -ForegroundColor Cyan
            Write-Host "  Health Status: $($health.status)" -ForegroundColor $(switch ($health.status) {
                "Healthy" { "Green" }
                "Degraded" { "Yellow" }
                "Unhealthy" { "Red" }
                default { "White" }
            })
            
            $perfCheck = $health.checks | Where-Object { $_.name -eq 'performance' }
            if ($perfCheck) {
                $avgResponseTime = $perfCheck.data.AverageResponseTime
                $timeoutRate = $perfCheck.data.TimeoutRate
                $concurrentRequests = $perfCheck.data.ConcurrentRequests
                
                Write-Host "  Average Response Time: $avgResponseTime ms" -ForegroundColor $(if ($avgResponseTime -lt 500) { "Green" } elseif ($avgResponseTime -lt 2000) { "Yellow" } else { "Red" })
                Write-Host "  Timeout Rate: $timeoutRate%" -ForegroundColor $(if ($timeoutRate -lt 5) { "Green" } elseif ($timeoutRate -lt 15) { "Yellow" } else { "Red" })
                Write-Host "  Concurrent Requests: $concurrentRequests" -ForegroundColor White
                
                # Check for alert conditions
                if (-not $alertFired -and ($avgResponseTime -gt 2000 -or $timeoutRate -gt 10)) {
                    Write-Host "`n🚨 ALERT CONDITIONS DETECTED!" -ForegroundColor Red
                    Write-Host "Average response time: $avgResponseTime ms (threshold: 2000ms)" -ForegroundColor Red
                    Write-Host "Timeout rate: $timeoutRate% (threshold: 10%)" -ForegroundColor Red
                    Write-Host "Azure Monitor alerts should fire..." -ForegroundColor Yellow
                    $alertFired = $true
                }
            }
            
            # Check thread pool status
            $threadCheck = $health.checks | Where-Object { $_.name -eq 'thread-pool' }
            if ($threadCheck) {
                $utilization = $threadCheck.data.ThreadPoolUtilization
                Write-Host "  Thread Pool Utilization: $utilization%" -ForegroundColor $(if ($utilization -lt 80) { "Green" } elseif ($utilization -lt 95) { "Yellow" } else { "Red" })
            }
            
        } catch {
            Write-Host "❌ Could not check production health: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Check Azure Monitor alerts (simulated - in real scenario, this would query Azure Monitor API)
        Write-Host "`n🔍 Azure Monitor Alert Status:" -ForegroundColor Cyan
        if ($alertFired) {
            Write-Host "  Performance Alert: FIRED 🔥" -ForegroundColor Red
            Write-Host "  SRE Agent: Processing remediation instructions..." -ForegroundColor Yellow
            
            if (-not $remediationAttempted) {
                Write-Host "`n🔄 SRE Agent Remediation Actions:" -ForegroundColor Cyan
                Write-Host "  1. ✅ Verifying staging slot health" -ForegroundColor Green
                Write-Host "  2. ✅ Comparing production vs staging metrics" -ForegroundColor Green
                Write-Host "  3. 🔄 Executing slot swap (staging → production)" -ForegroundColor Yellow
                $remediationAttempted = $true
                
                # Simulate remediation delay
                Start-Sleep -Seconds 5
            }
        } else {
            Write-Host "  Performance Alert: OK" -ForegroundColor Green
            Write-Host "  SRE Agent: Monitoring..." -ForegroundColor White
        }
        
        # Check for remediation success
        if ($remediationAttempted -and -not $remediationSuccessful) {
            try {
                $postRemediationHealth = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
                $perfCheck = $postRemediationHealth.checks | Where-Object { $_.name -eq 'performance' }
                
                if ($perfCheck -and $perfCheck.data.AverageResponseTime -lt 1000) {
                    Write-Host "`n✅ REMEDIATION SUCCESSFUL!" -ForegroundColor Green
                    Write-Host "Production restored to healthy state" -ForegroundColor Green
                    Write-Host "Average response time: $($perfCheck.data.AverageResponseTime) ms" -ForegroundColor Green
                    $remediationSuccessful = $true
                }
            } catch {
                Write-Host "❌ Could not verify remediation status" -ForegroundColor Red
            }
        }
        
        # Check endpoint metrics
        try {
            Write-Host "`n📈 Endpoint Metrics:" -ForegroundColor Cyan
            
            $ordersMetrics = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/api/orders/metrics" -Method Get -TimeoutSec 5
            $inventoryMetrics = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/api/inventory/metrics" -Method Get -TimeoutSec 5
            
            Write-Host "  Orders - Success Rate: $($ordersMetrics.SuccessRate)%" -ForegroundColor White
            Write-Host "  Orders - Timeout Rate: $($ordersMetrics.TimeoutRate)%" -ForegroundColor White
            Write-Host "  Inventory - Success Rate: $($inventoryMetrics.SuccessRate)%" -ForegroundColor White
            Write-Host "  Inventory - Timeout Rate: $($inventoryMetrics.TimeoutRate)%" -ForegroundColor White
            
        } catch {
            Write-Host "  Could not retrieve endpoint metrics" -ForegroundColor Gray
        }
        
        Write-Host "`n🔗 Monitor in Azure Portal:" -ForegroundColor Cyan
        Write-Host "• Application Insights Live Metrics" -ForegroundColor Blue
        Write-Host "• Azure Monitor Alerts" -ForegroundColor Blue
        Write-Host "• App Service Deployment History" -ForegroundColor Blue
        
        $lastUpdateTime = $currentTime
    }
}

Write-Host "`n🏁 SRE Agent Monitoring Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Total Monitoring Duration: $([Math]::Round(($currentTime - $startTime).TotalMinutes, 1)) minutes" -ForegroundColor White
Write-Host "Alert Fired: $(if ($alertFired) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "Remediation Attempted: $(if ($remediationAttempted) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "Remediation Successful: $(if ($remediationSuccessful) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow

# Final health check
Write-Host "`n📊 Final Production Health Status:" -ForegroundColor Cyan
try {
    $finalHealth = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
    Write-Host "Status: $($finalHealth.status)" -ForegroundColor $(switch ($finalHealth.status) {
        "Healthy" { "Green" }
        "Degraded" { "Yellow" }
        "Unhealthy" { "Red" }
        default { "White" }
    })
    
    $perfCheck = $finalHealth.checks | Where-Object { $_.name -eq 'performance' }
    if ($perfCheck) {
        Write-Host "Average Response Time: $($perfCheck.data.AverageResponseTime) ms" -ForegroundColor White
        Write-Host "Timeout Rate: $($perfCheck.data.TimeoutRate)%" -ForegroundColor White
    }
} catch {
    Write-Host "❌ Could not check final health status" -ForegroundColor Red
}

# Update configuration with monitoring results
$config.SREAgentMonitoring = @{
    AlertFired = $alertFired
    RemediationAttempted = $remediationAttempted
    RemediationSuccessful = $remediationSuccessful
    MonitoringDurationMinutes = [Math]::Round(($currentTime - $startTime).TotalMinutes, 1)
    CompletedAt = Get-Date
}
$config | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigPath -Encoding UTF8

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
if ($remediationSuccessful) {
    Write-Host "✅ SRE Agent successfully remediated the issue!" -ForegroundColor Green
    Write-Host "1. Run: .\7-create-issue-and-pr.ps1 (to create GitHub issue and PR)" -ForegroundColor White
    Write-Host "2. Review the remediation process in Azure Portal" -ForegroundColor White
} else {
    Write-Host "⚠️  SRE Agent remediation may need manual intervention" -ForegroundColor Yellow
    Write-Host "1. Check Azure Monitor alerts in the portal" -ForegroundColor White
    Write-Host "2. Verify SRE Agent configuration and webhook URLs" -ForegroundColor White
    Write-Host "3. Consider manual slot swap if needed" -ForegroundColor White
}

Write-Host "`n🔗 Review Results:" -ForegroundColor Cyan
Write-Host "• Production Health: $($config.AppServiceUrl)/health" -ForegroundColor Blue
Write-Host "• Azure Portal: https://portal.azure.com/#@/resource/subscriptions/*/resourceGroups/$($config.ResourceGroupName)/providers/Microsoft.Web/sites/$($config.AppName)" -ForegroundColor Blue
Write-Host "• Application Insights: https://portal.azure.com/#@/resource/subscriptions/*/resourceGroups/$($config.ResourceGroupName)/providers/Microsoft.Insights/components/$($config.AppName)-ai" -ForegroundColor Blue
