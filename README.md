# Azure SRE Agent Deadlock Demo

This demo demonstrates Azure SRE Agent's capability to detect and automatically remediate performance issues caused by a thread synchronization deadlock in a .NET application.

## 🎯 Demo Overview

The demo showcases a complete incident response lifecycle:

1. **Deploy healthy application** to production
2. **Deploy deadlock version** to staging slot
3. **Swap to production** (simulating bad deployment)
4. **Generate load** to trigger performance degradation
5. **Azure Monitor alerts fire** with SRE Agent remediation instructions
6. **SRE Agent automatically swaps** back to healthy version
7. **Create GitHub issue and PR** with fix

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   .NET App      │    │   App Service   │    │ Application     │
│   (Deadlock)    │───▶│   (Slots)       │───▶│ Insights        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Performance     │    │ Azure Monitor   │    │ SRE Agent       │
│ Monitoring      │    │ Alerts          │    │ Remediation     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Azure subscription with contributor access
- Azure CLI installed and logged in
- .NET 9.0 SDK
- PowerShell 7.0+
- GitHub account (for issue/PR creation)

### 1. Run Full Demo Sequence

```powershell
cd scripts
.\demo-full-sequence.ps1 -ResourceGroupName "deadlock-demo-rg" -Location "East US"
```

### 2. Manual Step-by-Step

```powershell
# Step 1: Deploy infrastructure
.\1-deploy-infrastructure.ps1 -ResourceGroupName "deadlock-demo-rg" -Location "East US"

# Step 2: Deploy healthy app
.\2-deploy-healthy-app.ps1

# Step 3: Deploy deadlock version to staging
.\3-deploy-deadlock-to-staging.ps1

# Step 4: Swap to production (deploy deadlock version)
.\4-swap-to-production.ps1

# Step 5: Generate load to trigger degradation
.\5-generate-load.ps1 -DurationMinutes 10

# Step 6: Monitor SRE Agent remediation
.\6-monitor-sre-agent.ps1 -MonitorMinutes 10

# Step 7: Create GitHub issue and PR
.\7-create-issue-and-pr.ps1 -GitHubToken "your-token" -RepositoryUrl "https://github.com/owner/repo"
```

## 📊 Demo Timeline

| Time | Phase | Description |
|------|-------|-------------|
| 0-2 min | Deploy | Infrastructure and healthy app deployment |
| 2-4 min | Setup | Deadlock version deployed to staging |
| 4-5 min | Deploy | Slot swap deploys deadlock to production |
| 5-10 min | Load | Performance degrades under load |
| 10-15 min | Alert | Azure Monitor alerts fire |
| 15-20 min | Remediation | SRE Agent swaps back to healthy version |

## 🔍 What to Watch

### Azure Portal Tabs

1. **App Service Overview**: Monitor slot status and deployments
2. **Application Insights Live Metrics**: Real-time performance data
3. **Azure Monitor Alerts**: Alert firing and remediation
4. **Log Analytics**: Custom telemetry and deadlock events

### Key Metrics

- **Response Time**: Baseline ~100ms → Degraded >2000ms
- **Timeout Rate**: Healthy <1% → Degraded >10%
- **Thread Pool**: Available threads decreasing over time
- **Health Status**: Healthy → Degraded → Unhealthy

## 🧪 Deadlock Pattern

### The Problem

```csharp
// OrdersController (LockA → LockB)
lock (lockA) {
    lock (lockB) { /* work */ }
}

// InventoryController (LockB → LockA) - DEADLOCK!
lock (lockB) {
    lock (lockA) { /* work */ }
}
```

### The Fix

```csharp
// Both controllers use consistent ordering (LockA → LockB)
// + Monitor.TryEnter() with timeout
// + Proper finally block cleanup
```

## 🔧 Configuration

### Application Settings

```json
{
  "EnableDeadlockSimulation": false,
  "PerformanceSettings": {
    "TimeoutThresholdMs": 5000,
    "HealthyResponseTimeMs": 500,
    "DegradedResponseTimeMs": 2000
  }
}
```

### Azure Alerts

- **Performance Alert**: Response time > 2000ms for 5 minutes
- **Thread Pool Alert**: CPU usage > 90% for 3 minutes  
- **Timeout Alert**: Error rate > 10% for 3 minutes
- **Health Check Alert**: Health check failures

## 📈 API Endpoints

### Fast Endpoints (No Deadlock)
- `GET /api/products` - Product listing (10-50ms)
- `GET /api/products/{id}` - Single product (5-25ms)
- `GET /api/products/search?query={query}` - Search (20-100ms)

### Deadlock-Prone Endpoints (When Enabled)
- `POST /api/orders/process` - Order processing (50-300ms baseline)
- `POST /api/inventory/update` - Inventory update (30-250ms baseline)

### Monitoring Endpoints
- `GET /health` - Health check with performance data
- `GET /api/orders/metrics` - Order processing metrics
- `GET /api/inventory/metrics` - Inventory update metrics

## 🚨 SRE Agent Integration

### Alert Remediation Instructions

```json
{
  "remediation_type": "slot_swap",
  "steps": [
    "1. Verify staging slot health",
    "2. Compare production vs staging metrics", 
    "3. Execute slot swap if staging is healthier",
    "4. Monitor production for 5 minutes",
    "5. Create incident report"
  ]
}
```

### Expected SRE Agent Actions

1. **Detection**: Azure Monitor alert fires
2. **Analysis**: Compare staging vs production health
3. **Remediation**: Swap staging → production
4. **Verification**: Monitor post-swap metrics
5. **Reporting**: Create incident documentation

## 🔧 Troubleshooting

### Common Issues

1. **Health Check Failures**
   - Verify Application Insights connection
   - Check endpoint accessibility
   - Review memory thresholds

2. **Performance Test Failures**
   - Confirm response time thresholds
   - Check network connectivity
   - Review Application Insights data

3. **Deployment Issues**
   - Ensure Azure CLI is logged in
   - Verify resource group permissions
   - Check Bicep template syntax

### Debug Commands

```bash
# Check application logs
az webapp log tail --name deadlock-demo-app --resource-group deadlock-demo-rg

# Check deployment status  
az webapp deployment list --name deadlock-demo-app --resource-group deadlock-demo-rg

# Manual health check
curl https://deadlock-demo-app.azurewebsites.net/health

# Check metrics
curl https://deadlock-demo-app.azurewebsites.net/api/orders/metrics
```

## 📚 Learning Objectives

After completing this demo, you will understand:

1. **Thread Synchronization Deadlocks**: How inconsistent lock ordering causes deadlocks
2. **Performance Monitoring**: Implementing health checks with custom metrics
3. **Azure Monitor Alerts**: Configuring alerts with remediation instructions
4. **SRE Agent Integration**: Automated incident response workflows
5. **Slot-Based Deployments**: Blue-green deployment patterns
6. **Incident Response**: Complete lifecycle from detection to fix

## 🎯 Next Steps

- Integrate with Azure Monitor for advanced alerting
- Add custom performance counters and dashboards
- Implement distributed tracing with Application Insights
- Set up automated performance regression testing
- Configure SRE runbooks for incident response
- Implement chaos engineering scenarios

## 📁 File Structure

```
DeadlockDemo/
├── DeadlockApp/                 # .NET 9.0 Web API
│   ├── Controllers/             # API endpoints with deadlock pattern
│   ├── PerformanceHealthCheck.cs # Custom health monitoring
│   ├── PerformanceMiddleware.cs # Request tracking and metrics
│   └── Program.cs              # Application configuration
├── infrastructure/             # Azure infrastructure as code
│   ├── main.bicep             # App Service, slots, monitoring
│   └── alert-remediation-instructions.json
├── scripts/                   # Demo automation scripts
│   ├── 1-deploy-infrastructure.ps1
│   ├── 2-deploy-healthy-app.ps1
│   ├── 3-deploy-deadlock-to-staging.ps1
│   ├── 4-swap-to-production.ps1
│   ├── 5-generate-load.ps1
│   ├── 6-monitor-sre-agent.ps1
│   ├── 7-create-issue-and-pr.ps1
│   └── demo-full-sequence.ps1
├── fixes/                     # Fixed controller versions
│   ├── OrdersController.Fixed.cs
│   └── InventoryController.Fixed.cs
├── .github/workflows/         # GitHub Actions deployment
└── README.md                 # This file
```

---

**Note**: This is a demo application for educational purposes. In production environments, ensure proper security practices, monitoring, and testing procedures are in place.
#   D e a d l o c k D e m o D o t N e t  
 