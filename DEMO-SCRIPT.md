# Azure SRE Agent Deadlock Demo - Presenter Script

## 🎭 Demo Overview

**Duration**: 25-30 minutes  
**Audience**: Developers, SREs, DevOps engineers  
**Objective**: Demonstrate Azure SRE Agent's automated incident response to performance degradation caused by thread synchronization deadlock

## 📋 Pre-Demo Setup

### Browser Tabs to Open
1. **Azure Portal**: App Service overview page
2. **Application Insights**: Live Metrics Stream
3. **Azure Monitor**: Alerts dashboard
4. **GitHub**: Repository (for issue/PR creation)

### Prerequisites Check
- [ ] Azure subscription with contributor access
- [ ] Azure CLI logged in (`az account show`)
- [ ] .NET 9.0 SDK installed (`dotnet --version`)
- [ ] PowerShell 7.0+ (`$PSVersionTable.PSVersion`)
- [ ] Demo scripts accessible in `scripts/` folder

## 🎯 Demo Flow & Talking Points

### Phase 1: Setup and Healthy Deployment (5 minutes)

**Script**: `.\1-deploy-infrastructure.ps1` and `.\2-deploy-healthy-app.ps1`

**Presenter Notes**:
> "Today we'll demonstrate how Azure SRE Agent can automatically detect and remediate a performance issue caused by a classic thread synchronization deadlock. Let's start by deploying our infrastructure and a healthy version of the application."

**What to Show**:
- Azure Portal: Resource group creation
- App Service with production and staging slots
- Application Insights workspace
- Health endpoint showing "Healthy" status

**Key Points**:
- "We're using Azure App Service deployment slots for blue-green deployments"
- "Application Insights provides real-time telemetry and custom metrics"
- "The application starts with deadlock simulation disabled"

### Phase 2: Deploy Deadlock Version (3 minutes)

**Script**: `.\3-deploy-deadlock-to-staging.ps1`

**Presenter Notes**:
> "Now let's deploy a version with a deliberate deadlock bug to our staging slot. This simulates a bad deployment that somehow passed initial testing."

**What to Show**:
- Staging slot deployment
- Configuration showing `EnableDeadlockSimulation=true`
- Initial health check (may still show healthy)

**Key Points**:
- "The deadlock occurs due to inconsistent lock ordering"
- "OrdersController acquires LockA → LockB"
- "InventoryController acquires LockB → LockA (reverse order)"
- "Under concurrent load, this creates a circular wait condition"

### Phase 3: Deploy to Production (2 minutes)

**Script**: `.\4-swap-to-production.ps1`

**Presenter Notes**:
> "Now we'll swap the staging slot to production, deploying the problematic version to our live environment. This simulates what happens when a bad deployment reaches production."

**What to Show**:
- Slot swap operation
- Production URL now serving deadlock version
- Health endpoint still showing healthy (initially)

**Key Points**:
- "The application appears healthy initially"
- "Deadlocks only manifest under concurrent load"
- "This is why the issue wasn't caught in staging"

### Phase 4: Load Generation and Degradation (10 minutes)

**Script**: `.\5-generate-load.ps1`

**Presenter Notes**:
> "Now let's generate realistic load to trigger the deadlock. We'll send concurrent requests to both the order processing and inventory endpoints."

**What to Show**:
- Real-time response time metrics
- Color-coded performance indicators:
  - Green: < 500ms (healthy)
  - Yellow: 500-2000ms (degraded)
  - Red: > 2000ms (critical)
- Increasing timeout rates
- Thread pool utilization

**Key Points**:
- "Watch the response times gradually increase"
- "Timeout rates will spike as threads get blocked"
- "Thread pool exhaustion leads to cascading failures"
- "This is exactly what users experience during incidents"

**Timeline Expectations**:
- 0-2 minutes: Healthy performance
- 2-5 minutes: Gradual degradation
- 5-8 minutes: Significant performance issues
- 8-10 minutes: Alert threshold breached

### Phase 5: SRE Agent Remediation (8 minutes)

**Script**: `.\6-monitor-sre-agent.ps1`

**Presenter Notes**:
> "Azure Monitor has detected the performance degradation and fired alerts. The SRE Agent is now processing the remediation instructions to automatically resolve the issue."

**What to Show**:
- Azure Monitor alerts firing
- SRE Agent remediation steps:
  1. Verify staging slot health
  2. Compare production vs staging metrics
  3. Execute slot swap (staging → production)
  4. Monitor post-swap metrics
  5. Create incident report

**Key Points**:
- "The SRE Agent follows structured remediation instructions"
- "It verifies that the staging slot is healthier before swapping"
- "The swap happens automatically without human intervention"
- "Production is restored to the previous healthy version"

**Timeline Expectations**:
- 0-2 minutes: Alert detection and analysis
- 2-5 minutes: Remediation execution
- 5-8 minutes: Verification and monitoring

### Phase 6: Issue Documentation (2 minutes)

**Script**: `.\7-create-issue-and-pr.ps1`

**Presenter Notes**:
> "Finally, let's document this incident and create a fix. The SRE Agent has resolved the immediate issue, but we need to fix the root cause."

**What to Show**:
- GitHub issue creation with incident details
- Pull request with deadlock fix
- Fixed controller code showing consistent lock ordering

**Key Points**:
- "Proper incident documentation is crucial for learning"
- "The fix involves consistent lock ordering across all controllers"
- "We use Monitor.TryEnter() with timeouts for better resilience"

## 🎯 Key Learning Points

### For Developers
1. **Deadlock Prevention**: Always acquire locks in consistent order
2. **Timeout Handling**: Use Monitor.TryEnter() instead of lock statements
3. **Monitoring**: Implement custom metrics for deadlock detection
4. **Testing**: Load testing reveals concurrency issues not caught by unit tests

### For SREs
1. **Automated Remediation**: SRE Agent can resolve incidents without human intervention
2. **Monitoring Strategy**: Multiple alert types (response time, thread pool, timeouts)
3. **Slot-Based Deployments**: Enable quick rollbacks during incidents
4. **Incident Response**: Structured approach to detection, analysis, and remediation

### For DevOps Teams
1. **Infrastructure as Code**: Bicep templates for consistent deployments
2. **GitHub Actions**: Automated deployment pipelines with health checks
3. **Blue-Green Deployments**: Zero-downtime deployments with rollback capability
4. **Observability**: Comprehensive monitoring with Application Insights

## 🚨 Backup Plans

### If SRE Agent Integration Not Available
1. Show manual slot swap process
2. Demonstrate Azure CLI commands for remediation
3. Explain how SRE Agent would automate these steps

### If Demo Environment Issues
1. Pre-recorded video of successful demo run
2. Screenshots of expected outputs at each phase
3. Local simulation using the application without Azure deployment

### If Network/Performance Issues
1. Reduce load test duration to 5 minutes
2. Use fewer concurrent users (2-3 instead of 5)
3. Show historical data from previous demo runs

## ❓ Common Q&A

### Q: "How realistic is this deadlock scenario?"
**A**: "Very realistic. This is a classic deadlock pattern that occurs in production systems when different components acquire shared resources in different orders. The gradual degradation pattern is exactly what we see in real incidents."

### Q: "What if the SRE Agent makes the wrong decision?"
**A**: "The remediation instructions include verification steps and rollback procedures. The agent compares metrics before swapping and monitors post-swap to ensure the remediation was successful."

### Q: "How do you prevent this in the first place?"
**A**: "Code reviews, static analysis tools, and comprehensive load testing. But the reality is that some issues only manifest under production load, which is why automated remediation is crucial."

### Q: "What about data consistency during slot swaps?"
**A**: "This demo focuses on stateless endpoints. In production, you'd need to consider database connections, session state, and other shared resources. Azure App Service handles connection draining during swaps."

### Q: "How does this scale to larger applications?"
**A**: "The principles apply at any scale. You'd have more complex monitoring, multiple deployment slots, and potentially more sophisticated SRE Agent rules, but the core pattern remains the same."

## 📊 Demo Metrics to Highlight

### Performance Degradation
- Baseline: ~100ms average response time
- Degraded: >2000ms average response time
- Timeout rate: <1% → >10%
- Thread pool: 90%+ utilization

### Remediation Success
- Detection time: ~5 minutes
- Remediation time: ~3 minutes
- Recovery time: ~2 minutes
- Total incident duration: ~10 minutes

### Business Impact
- User experience: Severe degradation → Full recovery
- System availability: Maintained throughout (no downtime)
- Mean Time to Recovery (MTTR): Significantly reduced with automation

## 🎉 Demo Conclusion

**Key Takeaways**:
1. **Automated Incident Response**: SRE Agent can detect and remediate issues automatically
2. **Proactive Monitoring**: Multiple alert types catch different failure modes
3. **Quick Recovery**: Slot-based deployments enable rapid rollbacks
4. **Learning Culture**: Proper documentation leads to better prevention

**Next Steps for Audience**:
1. Implement similar monitoring in their applications
2. Set up deployment slots for critical services
3. Configure Azure Monitor alerts with remediation instructions
4. Establish incident response runbooks

**Demo Resources**:
- All code and scripts available in the repository
- Infrastructure templates can be adapted for their environment
- Monitoring patterns can be applied to any .NET application

---

**Note**: This demo script should be customized based on the specific audience and time constraints. The full demo takes 25-30 minutes, but can be shortened to 15 minutes by reducing load test and monitoring phases.

