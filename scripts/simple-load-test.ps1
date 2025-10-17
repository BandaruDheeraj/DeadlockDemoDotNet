# Simple Load Test Script
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json",
    
    [Parameter(Mandatory=$false)]
    [int]$DurationMinutes = 10,
    
    [Parameter(Mandatory=$false)]
    [int]$ConcurrentUsers = 5
)

Write-Host "Starting load test for $DurationMinutes minutes with $ConcurrentUsers concurrent users"

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
$baseUrl = $config.AppServiceUrl

# Test endpoints
$endpoints = @(
    "/api/products",
    "/api/products/1", 
    "/api/orders/process",
    "/api/inventory/update"
)

Write-Host "Testing connectivity to $baseUrl"
try {
    $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method Get -TimeoutSec 10
    Write-Host "Health check passed: $($health.status)"
} catch {
    Write-Error "Cannot reach application: $($_.Exception.Message)"
    exit 1
}

$stopTime = (Get-Date).AddMinutes($DurationMinutes)
$startTime = Get-Date

Write-Host "Load test started at $(Get-Date -Format 'HH:mm:ss')"
Write-Host "Will run until $(Get-Date -Date $stopTime -Format 'HH:mm:ss')"

# Create background jobs for load generation
$jobs = @()
for ($user = 1; $user -le $ConcurrentUsers; $user++) {
    $job = Start-Job -ScriptBlock {
        param($BaseUrl, $Endpoints, $StopTime, $UserId)
        
        $requestCount = 0
        $successCount = 0
        $timeoutCount = 0
        $responseTimes = @()
        
        while ((Get-Date) -lt $StopTime) {
            $endpoint = $Endpoints | Get-Random
            $requestCount++
            
            try {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                
                if ($endpoint -like "*process" -or $endpoint -like "*update") {
                    $body = @{ TestData = "LoadTest-$UserId-$requestCount" } | ConvertTo-Json
                    $response = Invoke-RestMethod -Uri "$BaseUrl$endpoint" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 30
                } else {
                    $response = Invoke-RestMethod -Uri "$BaseUrl$endpoint" -Method Get -TimeoutSec 20
                }
                
                $stopwatch.Stop()
                $responseTime = $stopwatch.ElapsedMilliseconds
                $responseTimes += $responseTime
                $successCount++
                
            } catch {
                $timeoutCount++
            }
            
            # Random delay between requests
            Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 800)
        }
        
        return @{
            RequestCount = $requestCount
            SuccessCount = $successCount
            TimeoutCount = $timeoutCount
            ResponseTimes = $responseTimes
        }
    } -ArgumentList $baseUrl, $endpoints, $stopTime, $user
    
    $jobs += $job
}

# Monitor progress
Write-Host "Monitoring load test progress..."
while ((Get-Date) -lt $stopTime) {
    Start-Sleep -Seconds 10
    
    $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    $remaining = [Math]::Round(($stopTime - (Get-Date)).TotalMinutes, 1)
    
    Write-Host "Elapsed: $elapsed min, Remaining: $remaining min"
    
    # Check if all jobs are done
    $activeJobs = $jobs | Where-Object { $_.State -ne "Completed" }
    if ($activeJobs.Count -eq 0) {
        break
    }
}

# Clean up jobs
foreach ($job in $jobs) {
    if ($job.State -eq "Running") {
        Stop-Job -Job $job
    }
    Remove-Job -Job $job
}

# Collect final results
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
    }
}

# Display results
$totalTime = (Get-Date) - $startTime
Write-Host "Load test completed in $([Math]::Round($totalTime.TotalMinutes, 1)) minutes"

if ($allResponseTimes.Count -gt 0) {
    $avgResponseTime = [Math]::Round(($allResponseTimes | Measure-Object -Average).Average, 0)
    $maxResponseTime = ($allResponseTimes | Measure-Object -Maximum).Maximum
    $successRate = [Math]::Round(($totalSuccesses / $totalRequests) * 100, 1)
    $timeoutRate = [Math]::Round(($totalTimeouts / $totalRequests) * 100, 1)
    
    Write-Host "Results:"
    Write-Host "  Total Requests: $totalRequests"
    Write-Host "  Success Rate: $successRate%"
    Write-Host "  Timeout Rate: $timeoutRate%"
    Write-Host "  Average Response Time: $avgResponseTime ms"
    Write-Host "  Max Response Time: $maxResponseTime ms"
    
    # Check for alert conditions
    if ($avgResponseTime -gt 2000) {
        Write-Host "ALERT: Average response time ($avgResponseTime ms) exceeds 2000ms threshold"
    }
    
    if ($timeoutRate -gt 10) {
        Write-Host "ALERT: High timeout rate ($timeoutRate%) indicates potential deadlock"
    }
    
    # Update config with results
    $config.LoadTestResults = @{
        TotalRequests = $totalRequests
        SuccessRate = $successRate
        TimeoutRate = $timeoutRate
        AverageResponseTime = $avgResponseTime
        MaxResponseTime = $maxResponseTime
        DurationMinutes = [Math]::Round($totalTime.TotalMinutes, 1)
        CompletedAt = Get-Date
    }
    $config | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigPath -Encoding UTF8
}

Write-Host "Load test finished. Check Azure Monitor for alerts."
