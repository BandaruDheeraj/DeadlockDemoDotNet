# Generate Load to Trigger Performance Degradation
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json",
    
    [Parameter(Mandatory=$false)]
    [int]$DurationMinutes = 15,
    
    [Parameter(Mandatory=$false)]
    [int]$ConcurrentUsers = 5
)

Write-Host "🔥 Generating Load to Trigger Performance Degradation" -ForegroundColor Red
Write-Host "Duration: $DurationMinutes minutes" -ForegroundColor Yellow
Write-Host "Concurrent Users: $ConcurrentUsers" -ForegroundColor Yellow

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "❌ Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Host "Production URL: $($config.AppServiceUrl)" -ForegroundColor White

# Verify deadlock is enabled in production
Write-Host "`n🔍 Verifying deadlock simulation is enabled..." -ForegroundColor Cyan
try {
    $health = Invoke-RestMethod -Uri "$($config.AppServiceUrl)/health" -Method Get -TimeoutSec 10
    Write-Host "Production Status: $($health.status)" -ForegroundColor White
} catch {
    Write-Error "❌ Cannot reach production application"
    exit 1
}

Write-Host "`n⚠️  Starting load generation - this will trigger performance degradation!" -ForegroundColor Red
$confirmation = Read-Host "Press Enter to start load generation (or Ctrl+C to cancel)"
if ($confirmation -eq "q") {
    Write-Host "❌ Load generation cancelled" -ForegroundColor Yellow
    exit 0
}

# Define load test scenarios
$loadScenarios = @(
    @{Weight=60; Endpoints=@("/api/products", "/api/products/1", "/api/products/search?query=test"); Name="Product Operations"},
    @{Weight=20; Endpoints=@("/api/orders/process"); Method="POST"; Name="Order Processing"},
    @{Weight=20; Endpoints=@("/api/inventory/update"); Method="POST"; Name="Inventory Updates"}
)

$stopTime = (Get-Date).AddMinutes($DurationMinutes)
$requestCount = 0
$successCount = 0
$timeoutCount = 0
$responseTimes = @()
$startTime = Get-Date

Write-Host "`n🚀 Load generation started at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Green
Write-Host "Will run until $(Get-Date -Date $stopTime -Format 'HH:mm:ss')" -ForegroundColor White
Write-Host "Press Ctrl+C to stop early" -ForegroundColor Gray

# Create jobs for concurrent load generation
$jobs = @()
for ($user = 1; $user -le $ConcurrentUsers; $user++) {
    $job = Start-Job -ScriptBlock {
        param($ConfigUrl, $Scenarios, $StopTime, $UserId)
        
        $localRequestCount = 0
        $localSuccessCount = 0
        $localTimeoutCount = 0
        $localResponseTimes = @()
        
        while ((Get-Date) -lt $StopTime) {
            # Select scenario based on weight
            $random = Get-Random -Minimum 1 -Maximum 101
            $currentWeight = 0
            $selectedScenario = $null
            
            foreach ($scenario in $Scenarios) {
                $currentWeight += $scenario.Weight
                if ($random -le $currentWeight) {
                    $selectedScenario = $scenario
                    break
                }
            }
            
            if ($selectedScenario) {
                $endpoint = $selectedScenario.Endpoints | Get-Random
                $localRequestCount++
                
                try {
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    
                    if ($selectedScenario.Method -eq "POST") {
                        $body = @{ TestData = "LoadTest-$UserId-$localRequestCount" } | ConvertTo-Json
                        $response = Invoke-RestMethod -Uri "$ConfigUrl$endpoint" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 15
                    } else {
                        $response = Invoke-RestMethod -Uri "$ConfigUrl$endpoint" -Method Get -TimeoutSec 10
                    }
                    
                    $stopwatch.Stop()
                    $responseTime = $stopwatch.ElapsedMilliseconds
                    $localResponseTimes += $responseTime
                    $localSuccessCount++
                    
                } catch {
                    $localTimeoutCount++
                }
            }
            
            # Small delay between requests
            Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
        }
        
        return @{
            RequestCount = $localRequestCount
            SuccessCount = $localSuccessCount
            TimeoutCount = $localTimeoutCount
            ResponseTimes = $localResponseTimes
        }
    } -ArgumentList $config.AppServiceUrl, $loadScenarios, $stopTime, $user
    
    $jobs += $job
}

# Monitor progress
$lastUpdateTime = Get-Date
while ((Get-Date) -lt $stopTime -and $jobs.Count -gt 0) {
    Start-Sleep -Seconds 5
    
    $currentTime = Get-Date
    $elapsedMinutes = [Math]::Round(($currentTime - $startTime).TotalMinutes, 1)
    $remainingMinutes = [Math]::Round(($stopTime - $currentTime).TotalMinutes, 1)
    
    # Update display every 30 seconds
    if (($currentTime - $lastUpdateTime).TotalSeconds -ge 30) {
        Clear-Host
        Write-Host "🔥 Load Generation in Progress" -ForegroundColor Red
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "Elapsed Time: $elapsedMinutes minutes" -ForegroundColor White
        Write-Host "Remaining Time: $remainingMinutes minutes" -ForegroundColor White
        Write-Host "Concurrent Users: $ConcurrentUsers" -ForegroundColor White
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
        
        # Get aggregated results from all jobs
        $totalRequests = 0
        $totalSuccesses = 0
        $totalTimeouts = 0
        $allResponseTimes = @()
        
        foreach ($job in $jobs) {
            if ($job.State -eq "Completed") {
                $result = Receive-Job -Job $job
                $totalRequests += $result.RequestCount
                $totalSuccesses += $result.SuccessCount
                $totalTimeouts += $result.TimeoutCount
                $allResponseTimes += $result.ResponseTimes
                Remove-Job -Job $job
            }
        }
        
        if ($allResponseTimes.Count -gt 0) {
            $avgResponseTime = [Math]::Round(($allResponseTimes | Measure-Object -Average).Average, 0)
            $p95ResponseTime = [Math]::Round(($allResponseTimes | Sort-Object | Select-Object -Skip [Math]::Floor($allResponseTimes.Count * 0.95) | Select-Object -First 1), 0)
            $maxResponseTime = ($allResponseTimes | Measure-Object -Maximum).Maximum
            $successRate = if ($totalRequests -gt 0) { [Math]::Round(($totalSuccesses / $totalRequests) * 100, 1) } else { 0 }
            $timeoutRate = if ($totalRequests -gt 0) { [Math]::Round(($totalTimeouts / $totalRequests) * 100, 1) } else { 0 }
            
            Write-Host "📊 Current Metrics:" -ForegroundColor Cyan
            Write-Host "  Total Requests: $totalRequests" -ForegroundColor White
            Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -gt 95) { "Green" } elseif ($successRate -gt 80) { "Yellow" } else { "Red" })
            Write-Host "  Timeout Rate: $timeoutRate%" -ForegroundColor $(if ($timeoutRate -lt 5) { "Green" } elseif ($timeoutRate -lt 15) { "Yellow" } else { "Red" })
            Write-Host "  Avg Response Time: $avgResponseTime ms" -ForegroundColor $(if ($avgResponseTime -lt 500) { "Green" } elseif ($avgResponseTime -lt 2000) { "Yellow" } else { "Red" })
            Write-Host "  95th Percentile: $p95ResponseTime ms" -ForegroundColor $(if ($p95ResponseTime -lt 1000) { "Green" } elseif ($p95ResponseTime -lt 3000) { "Yellow" } else { "Red" })
            Write-Host "  Max Response Time: $maxResponseTime ms" -ForegroundColor $(if ($maxResponseTime -lt 2000) { "Green" } elseif ($maxResponseTime -lt 5000) { "Yellow" } else { "Red" })
            
            # Performance degradation indicators
            if ($avgResponseTime -gt 2000) {
                Write-Host "`n🚨 ALERT THRESHOLD BREACHED!" -ForegroundColor Red
                Write-Host "Average response time ($avgResponseTime ms) exceeds alert threshold (2000 ms)" -ForegroundColor Red
                Write-Host "Azure Monitor alerts should fire shortly..." -ForegroundColor Yellow
            } elseif ($avgResponseTime -gt 1000) {
                Write-Host "`n⚠️  Performance Degradation Detected" -ForegroundColor Yellow
                Write-Host "Response times are increasing - deadlock simulation is working" -ForegroundColor Yellow
            }
            
            if ($timeoutRate -gt 10) {
                Write-Host "`n🚨 HIGH TIMEOUT RATE!" -ForegroundColor Red
                Write-Host "Timeout rate ($timeoutRate%) indicates potential deadlock" -ForegroundColor Red
            }
        }
        
        Write-Host "`n🔗 Monitor in Azure Portal:" -ForegroundColor Cyan
        Write-Host "• Application Insights Live Metrics" -ForegroundColor Blue
        Write-Host "• Azure Monitor Alerts" -ForegroundColor Blue
        Write-Host "• App Service Metrics" -ForegroundColor Blue
        
        $lastUpdateTime = $currentTime
    }
    
    # Check if all jobs are complete
    $activeJobs = $jobs | Where-Object { $_.State -ne "Completed" }
    if ($activeJobs.Count -eq 0) {
        break
    }
}

# Clean up remaining jobs
foreach ($job in $jobs) {
    if ($job.State -eq "Running") {
        Stop-Job -Job $job
    }
    Remove-Job -Job $job
}

# Final results
$totalTime = (Get-Date) - $startTime
Write-Host "`n🏁 Load Generation Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Total Duration: $([Math]::Round($totalTime.TotalMinutes, 1)) minutes" -ForegroundColor White
Write-Host "Concurrent Users: $ConcurrentUsers" -ForegroundColor White

if ($allResponseTimes.Count -gt 0) {
    $avgResponseTime = [Math]::Round(($allResponseTimes | Measure-Object -Average).Average, 0)
    $p95ResponseTime = [Math]::Round(($allResponseTimes | Sort-Object | Select-Object -Skip [Math]::Floor($allResponseTimes.Count * 0.95) | Select-Object -First 1), 0)
    $successRate = [Math]::Round(($totalSuccesses / $totalRequests) * 100, 1)
    $timeoutRate = [Math]::Round(($totalTimeouts / $totalRequests) * 100, 1)
    
    Write-Host "`n📊 Final Results:" -ForegroundColor Cyan
    Write-Host "  Total Requests: $totalRequests" -ForegroundColor White
    Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -gt 95) { "Green" } elseif ($successRate -gt 80) { "Yellow" } else { "Red" })
    Write-Host "  Timeout Rate: $timeoutRate%" -ForegroundColor $(if ($timeoutRate -lt 5) { "Green" } elseif ($timeoutRate -lt 15) { "Yellow" } else { "Red" })
    Write-Host "  Avg Response Time: $avgResponseTime ms" -ForegroundColor $(if ($avgResponseTime -lt 500) { "Green" } elseif ($avgResponseTime -lt 2000) { "Yellow" } else { "Red" })
    Write-Host "  95th Percentile: $p95ResponseTime ms" -ForegroundColor $(if ($p95ResponseTime -lt 1000) { "Green" } elseif ($p95ResponseTime -lt 3000) { "Yellow" } else { "Red" })
    
    # Update config with load test results
    $config.LoadTestResults = @{
        TotalRequests = $totalRequests
        SuccessRate = $successRate
        TimeoutRate = $timeoutRate
        AverageResponseTime = $avgResponseTime
        P95ResponseTime = $p95ResponseTime
        DurationMinutes = [Math]::Round($totalTime.TotalMinutes, 1)
        CompletedAt = Get-Date
    }
    $config | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigPath -Encoding UTF8
}

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Run: .\6-monitor-sre-agent.ps1 (to watch for automatic remediation)" -ForegroundColor White
Write-Host "2. Check Azure Monitor alerts in the portal" -ForegroundColor White
Write-Host "3. Monitor Application Insights for performance data" -ForegroundColor White

Write-Host "`n🔗 Monitoring Links:" -ForegroundColor Cyan
Write-Host "• Production Health: $($config.AppServiceUrl)/health" -ForegroundColor Blue
Write-Host "• Orders Metrics: $($config.AppServiceUrl)/api/orders/metrics" -ForegroundColor Blue
Write-Host "• Inventory Metrics: $($config.AppServiceUrl)/api/inventory/metrics" -ForegroundColor Blue
