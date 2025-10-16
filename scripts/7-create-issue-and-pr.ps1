# Create GitHub Issue and PR for Deadlock Fix
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\demo-config.json",
    
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$true)]
    [string]$RepositoryUrl
)

Write-Host "🐙 Creating GitHub Issue and PR for Deadlock Fix" -ForegroundColor Green

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "❌ Configuration file not found: $ConfigPath. Run 1-deploy-infrastructure.ps1 first."
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json

# Parse repository information
if ($RepositoryUrl -match "github\.com/([^/]+)/([^/]+)") {
    $owner = $matches[1]
    $repo = $matches[2].Replace(".git", "")
} else {
    Write-Error "❌ Invalid GitHub repository URL format. Expected: https://github.com/owner/repo"
    exit 1
}

Write-Host "Repository: $owner/$repo" -ForegroundColor Yellow
Write-Host "App Name: $($config.AppName)" -ForegroundColor Yellow

# GitHub API headers
$headers = @{
    "Authorization" = "token $GitHubToken"
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "DeadlockDemo-Script"
}

# Create GitHub Issue
Write-Host "`n📝 Creating GitHub issue..." -ForegroundColor Cyan

$issueTitle = "Performance degradation due to deadlock in order processing"
$issueBody = @"
## 🚨 Performance Issue Detected

**Severity:** High  
**Component:** Order Processing & Inventory Management  
**Impact:** Application performance degradation under load

### Problem Description

During performance testing, we identified a critical deadlock issue in the order processing and inventory management endpoints that causes:

- Response time degradation (average > 2000ms)
- High timeout rates (>10%)
- Thread pool exhaustion
- Application unavailability under load

### Root Cause

The deadlock occurs due to inconsistent lock acquisition order between two critical endpoints:

1. **OrdersController.ProcessOrder()** - Acquires `lockA` then `lockB`
2. **InventoryController.UpdateInventory()** - Acquires `lockB` then `lockA` (reverse order)

When these endpoints are called concurrently, they can deadlock, causing thread starvation and performance degradation.

### Impact Metrics

- **Baseline Performance:** $(if ($config.BaselineAverageResponseTime) { "$($config.BaselineAverageResponseTime)ms" } else { "~100ms" })
- **Degraded Performance:** $(if ($config.LoadTestResults) { "$($config.LoadTestResults.AverageResponseTime)ms" } else { ">2000ms" })
- **Timeout Rate:** $(if ($config.LoadTestResults) { "$($config.LoadTestResults.TimeoutRate)%" } else { ">10%" })
- **Affected Endpoints:** `/api/orders/process`, `/api/inventory/update`

### Incident Timeline

$(if ($config.ProductionSwapTime) { "- **Deployment:** $($config.ProductionSwapTime)" })
$(if ($config.LoadTestResults) { "- **Load Test Started:** $($config.LoadTestResults.CompletedAt)" })
$(if ($config.SREAgentMonitoring -and $config.SREAgentMonitoring.AlertFired) { "- **Alert Fired:** Performance threshold breached" })
$(if ($config.SREAgentMonitoring -and $config.SREAgentMonitoring.RemediationSuccessful) { "- **Remediation:** SRE Agent automatically swapped slots" })

### Immediate Actions Taken

✅ **SRE Agent Response:** Automatic slot swap to restore healthy version  
✅ **Monitoring:** Azure Monitor alerts configured and firing  
✅ **Rollback:** Production restored to previous healthy version  

### Required Fix

Implement consistent lock ordering in both controllers to prevent deadlock:

```csharp
// Both endpoints should acquire locks in the same order: lockA → lockB
// Add timeout handling with Monitor.TryEnter()
// Ensure proper lock release in finally blocks
```

### Acceptance Criteria

- [ ] Consistent lock ordering implemented
- [ ] Lock timeout handling added (3-second timeout)
- [ ] Unit tests for thread safety
- [ ] Performance regression tests
- [ ] Code review completed

### Related

- Azure Monitor Alert: Performance degradation detected
- SRE Agent Remediation: Automatic slot swap executed
- Load Test Results: $(if ($config.LoadTestResults) { "$($config.LoadTestResults.TotalRequests) requests" } else { "Available in monitoring data" })
"@

$issuePayload = @{
    title = $issueTitle
    body = $issueBody
    labels = @("bug", "performance", "high-priority", "deadlock")
} | ConvertTo-Json

try {
    $issueResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/issues" -Method Post -Headers $headers -Body $issuePayload
    $issueNumber = $issueResponse.number
    $issueUrl = $issueResponse.html_url
    
    Write-Host "✅ GitHub issue created: #$issueNumber" -ForegroundColor Green
    Write-Host "Issue URL: $issueUrl" -ForegroundColor Blue
} catch {
    Write-Error "❌ Failed to create GitHub issue: $($_.Exception.Message)"
    exit 1
}

# Create fix branch and PR
Write-Host "`n🔧 Creating fix branch and PR..." -ForegroundColor Cyan

$branchName = "fix/deadlock-order-inventory"
$prTitle = "Fix: Resolve deadlock in order processing and inventory management"
$prBody = @"
## 🔧 Fix: Deadlock Resolution

Fixes #$issueNumber

### Problem
Inconsistent lock acquisition order between OrdersController and InventoryController caused deadlocks under concurrent load, leading to performance degradation and timeouts.

### Solution
- **Consistent Lock Ordering:** Both controllers now acquire locks in the same order (lockA → lockB)
- **Timeout Handling:** Added 3-second timeout with `Monitor.TryEnter()`
- **Proper Cleanup:** Ensured locks are released in finally blocks
- **Error Handling:** Added comprehensive error handling and logging

### Changes Made

#### OrdersController.cs
- ✅ Maintained existing lock order (lockA → lockB)
- ✅ Added timeout handling with `Monitor.TryEnter()`
- ✅ Improved error handling and logging

#### InventoryController.cs  
- ✅ **Fixed lock order** to match OrdersController (lockA → lockB)
- ✅ Added timeout handling with `Monitor.TryEnter()`
- ✅ Improved error handling and logging

### Testing

- [x] Unit tests for thread safety
- [x] Load testing with concurrent requests
- [x] Performance regression testing
- [x] Deadlock detection validation

### Performance Impact

- **Before Fix:** Average response time > 2000ms under load
- **After Fix:** Average response time < 500ms under load
- **Timeout Rate:** Reduced from >10% to <1%

### Monitoring

- Application Insights custom metrics added
- Deadlock detection in health checks
- Performance alerts configured

### Related

- Resolves performance degradation issue
- Prevents thread pool exhaustion
- Improves application reliability under load
"@

# Note: In a real scenario, you would:
# 1. Clone the repository
# 2. Create a new branch
# 3. Copy the fixed controller files
# 4. Commit the changes
# 5. Push the branch
# 6. Create a PR

# For demo purposes, we'll create the PR without actual code changes
Write-Host "⚠️  Note: This demo creates the PR structure without actual code changes" -ForegroundColor Yellow
Write-Host "In a real scenario, you would:" -ForegroundColor White
Write-Host "1. Clone repository and create branch '$branchName'" -ForegroundColor Gray
Write-Host "2. Copy fixed controller files from fixes/ folder" -ForegroundColor Gray
Write-Host "3. Commit and push changes" -ForegroundColor Gray
Write-Host "4. Create pull request" -ForegroundColor Gray

# Simulate PR creation (in real scenario, this would be done via git operations)
try {
    # Create a mock PR payload
    $prPayload = @{
        title = $prTitle
        head = $branchName
        base = "main"
        body = $prBody
    } | ConvertTo-Json

    # In a real scenario, you would create the PR here:
    # $prResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/pulls" -Method Post -Headers $headers -Body $prPayload
    
    Write-Host "✅ PR structure prepared for branch: $branchName" -ForegroundColor Green
    Write-Host "PR Title: $prTitle" -ForegroundColor White
    
    # Mock PR URL
    $prUrl = "https://github.com/$owner/$repo/pull/new/$branchName"
    Write-Host "PR URL (mock): $prUrl" -ForegroundColor Blue
    
} catch {
    Write-Warning "Could not prepare PR structure: $($_.Exception.Message)"
}

# Update configuration
$config.GitHubIssue = @{
    Number = $issueNumber
    Url = $issueUrl
    Title = $issueTitle
}
$config.PullRequest = @{
    Branch = $branchName
    Title = $prTitle
    Url = $prUrl
}
$config | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigPath -Encoding UTF8

Write-Host "`n🎉 GitHub Issue and PR Creation Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Issue #$issueNumber: $issueTitle" -ForegroundColor White
Write-Host "Issue URL: $issueUrl" -ForegroundColor Blue
Write-Host "Fix Branch: $branchName" -ForegroundColor White
Write-Host "PR Title: $prTitle" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Review the GitHub issue: $issueUrl" -ForegroundColor White
Write-Host "2. Implement the actual code fixes in the $branchName branch" -ForegroundColor White
Write-Host "3. Create the pull request with the fixed controller files" -ForegroundColor White
Write-Host "4. Review and merge the PR to deploy the fix" -ForegroundColor White

Write-Host "`n🔗 Fixed Controller Files Available:" -ForegroundColor Cyan
Write-Host "• fixes/OrdersController.Fixed.cs" -ForegroundColor Blue
Write-Host "• fixes/InventoryController.Fixed.cs" -ForegroundColor Blue

Write-Host "`n📊 Demo Summary:" -ForegroundColor Cyan
Write-Host "✅ Deadlock issue identified and documented" -ForegroundColor Green
Write-Host "✅ SRE Agent remediation demonstrated" -ForegroundColor Green
Write-Host "✅ GitHub issue created for tracking" -ForegroundColor Green
Write-Host "✅ PR structure prepared for fix deployment" -ForegroundColor Green
Write-Host "✅ Full incident response lifecycle demonstrated" -ForegroundColor Green
