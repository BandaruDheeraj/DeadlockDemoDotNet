# Check Azure Monitor Metrics and Alert Status

Write-Host "`n=== Checking Azure Monitor Metrics ===" -ForegroundColor Cyan

# Get HttpResponseTime metrics for the last hour
Write-Host "`nQuerying HttpResponseTime metrics (last hour)..." -ForegroundColor Yellow
$resourceId = "/subscriptions/3eaf90b4-f4fa-416e-a0aa-ac2321d9decb/resourceGroups/deadlock-demo-rg/providers/Microsoft.Web/sites/deadlock-demo-app"

$metrics = az monitor metrics list `
    --resource $resourceId `
    --metric HttpResponseTime `
    --start-time "2025-10-16T18:10:00Z" `
    --interval PT1M `
    --output json | ConvertFrom-Json

if ($metrics.value -and $metrics.value[0].timeseries) {
    $data = $metrics.value[0].timeseries[0].data | Where-Object { $_.average -ne $null } | Sort-Object timeStamp -Descending | Select-Object -First 20

    Write-Host "`n📊 Recent Response Time Metrics (Last 20 minutes):" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Yellow

    foreach ($point in $data) {
        $timeStamp = $point.timeStamp
        $responseMs = [math]::Round($point.average * 1000, 0)

        $color = if ($responseMs -gt 2000) { "Red" } elseif ($responseMs -gt 1000) { "Yellow" } else { "Green" }
        Write-Host "$timeStamp`: $responseMs ms" -ForegroundColor $color
    }

    # Calculate max during load test
    $maxResponseTime = ($data | Measure-Object -Property average -Maximum).Maximum * 1000
    $avgResponseTime = ($data | Measure-Object -Property average -Average).Average * 1000

    Write-Host "`n📈 Summary (Last 20 minutes):" -ForegroundColor Cyan
    Write-Host "  Max Response Time: $([math]::Round($maxResponseTime, 0)) ms" -ForegroundColor White
    Write-Host "  Avg Response Time: $([math]::Round($avgResponseTime, 0)) ms" -ForegroundColor White

    if ($avgResponseTime -gt 2000) {
        Write-Host "`n🚨 ALERT THRESHOLD EXCEEDED!" -ForegroundColor Red
        Write-Host "Average response time ($([math]::Round($avgResponseTime, 0)) ms) > 2000 ms" -ForegroundColor Red
    } elseif ($maxResponseTime -gt 2000) {
        Write-Host "`n⚠️  PEAK RESPONSE TIME HIGH" -ForegroundColor Yellow
        Write-Host "Peak response time ($([math]::Round($maxResponseTime, 0)) ms) > 2000 ms" -ForegroundColor Yellow
    }
}

# Check alert state
Write-Host "`n`n=== Checking Alert Status ===" -ForegroundColor Cyan

$alerts = az monitor metrics alert list --resource-group deadlock-demo-rg --output json | ConvertFrom-Json

Write-Host "`n📋 Configured Alerts:" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════" -ForegroundColor Yellow

foreach ($alert in $alerts) {
    $statusColor = if ($alert.enabled) { "Green" } else { "Red" }
    $status = if ($alert.enabled) { "Enabled" } else { "Disabled" }

    Write-Host "`n  Name: $($alert.name)" -ForegroundColor White
    Write-Host "  Description: $($alert.description)" -ForegroundColor Gray
    Write-Host "  Status: $status" -ForegroundColor $statusColor
    Write-Host "  Evaluation Frequency: $($alert.evaluationFrequency)" -ForegroundColor Gray
    Write-Host "  Window Size: $($alert.windowSize)" -ForegroundColor Gray
}

# Check for fired alerts in activity log
Write-Host "`n`n=== Checking Recent Alert Activity ===" -ForegroundColor Cyan

$activityLog = az monitor activity-log list `
    --resource-group deadlock-demo-rg `
    --start-time "2025-10-16T18:00:00Z" `
    --output json | ConvertFrom-Json

$alertActivity = $activityLog | Where-Object { $_.operationName.localizedValue -like "*alert*" -or $_.operationName.localizedValue -like "*Alert*" }

if ($alertActivity) {
    Write-Host "`n📢 Alert Activity Found:" -ForegroundColor Yellow
    foreach ($activity in $alertActivity) {
        Write-Host "  Time: $($activity.eventTimestamp)" -ForegroundColor White
        Write-Host "  Operation: $($activity.operationName.localizedValue)" -ForegroundColor Gray
        Write-Host "  Status: $($activity.status.value)" -ForegroundColor Gray
        Write-Host ""
    }
} else {
    Write-Host "`n⚠️  No alert activity found in recent logs" -ForegroundColor Yellow
    Write-Host "This could mean:" -ForegroundColor Gray
    Write-Host "  1. Alerts have not triggered yet (need sustained degradation over 5 minutes)" -ForegroundColor Gray
    Write-Host "  2. Response times didn't exceed the 2000ms average threshold for 5 minutes" -ForegroundColor Gray
    Write-Host "  3. Azure Monitor metrics collection delay (can be 3-5 minutes)" -ForegroundColor Gray
}

Write-Host "`n`n💡 To trigger the alert:" -ForegroundColor Cyan
Write-Host "  • Alert needs average response time > 2000ms sustained for 5 minutes" -ForegroundColor White
Write-Host "  • Current load test showed peaks but average may be below threshold" -ForegroundColor White
Write-Host "  • Run longer load test or increase concurrent users" -ForegroundColor White
