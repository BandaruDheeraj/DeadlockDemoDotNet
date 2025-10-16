using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace DeadlockApp;

public class PerformanceHealthCheck : IHealthCheck
{
    private readonly ILogger<PerformanceHealthCheck> _logger;
    private readonly IConfiguration _configuration;

    public PerformanceHealthCheck(ILogger<PerformanceHealthCheck> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            var metrics = PerformanceMiddleware.GetCurrentMetrics();
            var threadPoolInfo = GetThreadPoolInfo();
            
            // Calculate health status based on multiple factors
            var healthStatus = DetermineHealthStatus(metrics, threadPoolInfo);
            var data = new Dictionary<string, object>
            {
                ["ResponseTimeP50"] = metrics.ResponseTimeP50,
                ["ResponseTimeP95"] = metrics.ResponseTimeP95,
                ["ResponseTimeP99"] = metrics.ResponseTimeP99,
                ["AverageResponseTime"] = metrics.AverageResponseTime,
                ["ConcurrentRequests"] = metrics.ConcurrentRequests,
                ["TotalRequests"] = metrics.TotalRequests,
                ["TimeoutRate"] = metrics.TimeoutRate,
                ["AvailableWorkerThreads"] = threadPoolInfo.AvailableWorkerThreads,
                ["AvailableIOThreads"] = threadPoolInfo.AvailableIOThreads,
                ["MaxWorkerThreads"] = threadPoolInfo.MaxWorkerThreads,
                ["MaxIOThreads"] = threadPoolInfo.MaxIOThreads,
                ["ThreadPoolUtilization"] = threadPoolInfo.UtilizationPercentage,
                ["Timestamp"] = DateTime.UtcNow
            };

            // Add deadlock-specific metrics
            if (metrics.TimeoutRate > 5)
            {
                data["DeadlockSuspected"] = true;
                data["DeadlockProbability"] = CalculateDeadlockProbability(metrics, threadPoolInfo);
                
                // Log deadlock suspicion instead of telemetry
                _logger.LogWarning("Deadlock suspected - TimeoutRate: {TimeoutRate}%, ThreadPoolUtilization: {ThreadPoolUtilization}%, AverageResponseTime: {AverageResponseTime}ms", 
                    metrics.TimeoutRate, threadPoolInfo.UtilizationPercentage, metrics.AverageResponseTime);
            }

            var description = GenerateHealthDescription(metrics, threadPoolInfo, healthStatus);

            var result = healthStatus switch
            {
                HealthStatus.Healthy => HealthCheckResult.Healthy(description, data),
                HealthStatus.Degraded => HealthCheckResult.Degraded(description, null, data),
                HealthStatus.Unhealthy => HealthCheckResult.Unhealthy(description, null, data),
                _ => HealthCheckResult.Unhealthy("Unknown health status")
            };

            // Log health check result instead of telemetry
            _logger.LogInformation("Health check completed - Status: {Status}, AvgResponseTime: {AvgResponseTime}ms", 
                healthStatus, metrics.AverageResponseTime);
            
            return Task.FromResult(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during health check");
            return Task.FromResult(HealthCheckResult.Unhealthy("Health check failed", ex));
        }
    }

    private HealthStatus DetermineHealthStatus(PerformanceMetrics metrics, ThreadPoolInfo threadPoolInfo)
    {
        // Define thresholds
        var healthyThreshold = _configuration.GetValue<double>("PerformanceSettings:HealthyResponseTimeMs", 500);
        var degradedThreshold = _configuration.GetValue<double>("PerformanceSettings:DegradedResponseTimeMs", 2000);
        var timeoutThreshold = 5.0; // 5% timeout rate
        var criticalTimeoutThreshold = 20.0; // 20% timeout rate
        var threadPoolCriticalThreshold = 10.0; // 10% available threads

        // Critical conditions - Unhealthy
        if (metrics.TimeoutRate >= criticalTimeoutThreshold)
        {
            _logger.LogWarning("Critical timeout rate detected: {TimeoutRate}%", metrics.TimeoutRate);
            return HealthStatus.Unhealthy;
        }

        if (threadPoolInfo.UtilizationPercentage >= (100 - threadPoolCriticalThreshold))
        {
            _logger.LogWarning("Critical thread pool exhaustion: {Utilization}%", threadPoolInfo.UtilizationPercentage);
            return HealthStatus.Unhealthy;
        }

        if (metrics.AverageResponseTime >= degradedThreshold * 2)
        {
            _logger.LogWarning("Critical response time: {ResponseTime}ms", metrics.AverageResponseTime);
            return HealthStatus.Unhealthy;
        }

        // Warning conditions - Degraded
        if (metrics.TimeoutRate >= timeoutThreshold)
        {
            _logger.LogWarning("High timeout rate: {TimeoutRate}%", metrics.TimeoutRate);
            return HealthStatus.Degraded;
        }

        if (metrics.AverageResponseTime >= degradedThreshold)
        {
            _logger.LogWarning("High response time: {ResponseTime}ms", metrics.AverageResponseTime);
            return HealthStatus.Degraded;
        }

        if (threadPoolInfo.UtilizationPercentage >= 80)
        {
            _logger.LogWarning("High thread pool utilization: {Utilization}%", threadPoolInfo.UtilizationPercentage);
            return HealthStatus.Degraded;
        }

        // Everything looks good - Healthy
        return HealthStatus.Healthy;
    }

    private ThreadPoolInfo GetThreadPoolInfo()
    {
        ThreadPool.GetAvailableThreads(out int availableWorkerThreads, out int availableIOThreads);
        ThreadPool.GetMaxThreads(out int maxWorkerThreads, out int maxIOThreads);
        
        var utilizationPercentage = ((double)(maxWorkerThreads - availableWorkerThreads) / maxWorkerThreads) * 100;
        
        return new ThreadPoolInfo
        {
            AvailableWorkerThreads = availableWorkerThreads,
            AvailableIOThreads = availableIOThreads,
            MaxWorkerThreads = maxWorkerThreads,
            MaxIOThreads = maxIOThreads,
            UtilizationPercentage = utilizationPercentage
        };
    }

    private double CalculateDeadlockProbability(PerformanceMetrics metrics, ThreadPoolInfo threadPoolInfo)
    {
        // Simple heuristic for deadlock probability
        var timeoutWeight = Math.Min(metrics.TimeoutRate / 20.0, 1.0); // 0-1 based on timeout rate
        var responseTimeWeight = Math.Min(metrics.AverageResponseTime / 5000.0, 1.0); // 0-1 based on response time
        var threadPoolWeight = Math.Min(threadPoolInfo.UtilizationPercentage / 100.0, 1.0); // 0-1 based on thread utilization
        
        // Weighted average
        return (timeoutWeight * 0.5 + responseTimeWeight * 0.3 + threadPoolWeight * 0.2) * 100;
    }

    private string GenerateHealthDescription(PerformanceMetrics metrics, ThreadPoolInfo threadPoolInfo, HealthStatus status)
    {
        var statusText = status switch
        {
            HealthStatus.Healthy => "Healthy",
            HealthStatus.Degraded => "Degraded",
            HealthStatus.Unhealthy => "Unhealthy",
            _ => "Unknown"
        };

        return $"{statusText} - Avg: {metrics.AverageResponseTime:F0}ms, " +
               $"P95: {metrics.ResponseTimeP95:F0}ms, " +
               $"Timeouts: {metrics.TimeoutRate:F1}%, " +
               $"Threads: {threadPoolInfo.UtilizationPercentage:F1}% utilized";
    }
}

public class ThreadPoolInfo
{
    public int AvailableWorkerThreads { get; set; }
    public int AvailableIOThreads { get; set; }
    public int MaxWorkerThreads { get; set; }
    public int MaxIOThreads { get; set; }
    public double UtilizationPercentage { get; set; }
}
