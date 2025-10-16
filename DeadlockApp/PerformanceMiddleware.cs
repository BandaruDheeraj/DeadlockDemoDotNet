using System.Collections.Concurrent;
using System.Diagnostics;

namespace DeadlockApp;

public class PerformanceMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<PerformanceMiddleware> _logger;
    private readonly IConfiguration _configuration;

    // Thread-safe metrics tracking
    private static readonly ConcurrentQueue<long> ResponseTimes = new();
    private static volatile int _concurrentRequests = 0;
    private static long _totalRequests = 0;
    private static long _timeoutRequests = 0;
    private static readonly object _metricsLock = new object();

    // Performance thresholds
    private readonly double _timeoutThresholdMs;
    private readonly int _maxResponseTimeHistory = 1000;

    public PerformanceMiddleware(RequestDelegate next, ILogger<PerformanceMiddleware> logger, IConfiguration configuration)
    {
        _next = next;
        _logger = logger;
        _configuration = configuration;
        _timeoutThresholdMs = _configuration.GetValue<double>("PerformanceSettings:TimeoutThresholdMs", 5000);
    }

    public async Task InvokeAsync(HttpContext context)
    {
        Interlocked.Increment(ref _concurrentRequests);
        Interlocked.Increment(ref _totalRequests);

        var stopwatch = Stopwatch.StartNew();
        var requestId = context.TraceIdentifier;
        var path = context.Request.Path.Value ?? "";

        // Skip health checks and metrics endpoints from performance tracking
        if (path.Contains("/health") || path.Contains("/metrics"))
        {
            await _next(context);
            return;
        }

        _logger.LogDebug("Request {RequestId} started: {Method} {Path}", requestId, context.Request.Method, path);

        try
        {
            // Set timeout for the request
            using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(_timeoutThresholdMs * 1.5));
            using var combinedCts = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted, cts.Token);

            var originalCancellationToken = context.RequestAborted;
            context.RequestAborted = combinedCts.Token;

            await _next(context);

            stopwatch.Stop();
            RecordResponseTime(stopwatch.ElapsedMilliseconds, path, context.Response.StatusCode);

            _logger.LogDebug("Request {RequestId} completed: {StatusCode} in {ElapsedMs}ms", 
                requestId, context.Response.StatusCode, stopwatch.ElapsedMilliseconds);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            stopwatch.Stop();
            Interlocked.Increment(ref _timeoutRequests);

            _logger.LogWarning("Request {RequestId} timed out after {ElapsedMs}ms: {Method} {Path}", 
                requestId, stopwatch.ElapsedMilliseconds, context.Request.Method, path);

            if (!context.Response.HasStarted)
            {
                context.Response.StatusCode = 408; // Request Timeout
                await context.Response.WriteAsync("Request timeout");
            }

            throw; // Re-throw to let the framework handle it
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            
            _logger.LogError(ex, "Request {RequestId} failed after {ElapsedMs}ms: {Method} {Path}", 
                requestId, stopwatch.ElapsedMilliseconds, context.Request.Method, path);
            throw;
        }
        finally
        {
            Interlocked.Decrement(ref _concurrentRequests);
        }
    }

    private void RecordResponseTime(long responseTimeMs, string path, int statusCode)
    {
        // Add to rolling window of response times
        ResponseTimes.Enqueue(responseTimeMs);
        
        // Keep only the most recent response times
        while (ResponseTimes.Count > _maxResponseTimeHistory)
        {
            ResponseTimes.TryDequeue(out _);
        }

        // Track custom metrics via logging
        _logger.LogDebug("Response time: {ResponseTime}ms, Concurrent requests: {ConcurrentRequests}", 
            responseTimeMs, _concurrentRequests);

        // Check for potential deadlock indicators
        if (responseTimeMs > _timeoutThresholdMs * 0.8) // 80% of timeout threshold
        {
            _logger.LogWarning("Slow response detected - Path: {Path}, ResponseTime: {ResponseTimeMs}ms, StatusCode: {StatusCode}, ConcurrentRequests: {ConcurrentRequests}", 
                path, responseTimeMs, statusCode, _concurrentRequests);
        }

        // Check for deadlock suspicion based on response pattern
        if (IsDeadlockSuspected(responseTimeMs, path))
        {
            _logger.LogWarning("Deadlock suspected - Path: {Path}, ResponseTime: {ResponseTimeMs}ms, ConcurrentRequests: {ConcurrentRequests}, TimeoutRate: {TimeoutRate}%", 
                path, responseTimeMs, _concurrentRequests, GetTimeoutRate());
        }
    }

    private bool IsDeadlockSuspected(long responseTimeMs, string path)
    {
        // Deadlock suspicion indicators:
        // 1. Very high response times on order/inventory endpoints
        // 2. High concurrent request count
        // 3. High timeout rate
        
        var isDeadlockEndpoint = path.Contains("/orders") || path.Contains("/inventory");
        var highResponseTime = responseTimeMs > _timeoutThresholdMs * 0.6; // 60% of timeout
        var highConcurrency = _concurrentRequests > 10;
        var highTimeoutRate = GetTimeoutRate() > 5.0; // 5% timeout rate

        return isDeadlockEndpoint && (highResponseTime || (highConcurrency && highTimeoutRate));
    }

    private string GetEndpointName(string path)
    {
        return path switch
        {
            var p when p.Contains("/products") => "Products",
            var p when p.Contains("/orders") => "Orders",
            var p when p.Contains("/inventory") => "Inventory",
            _ => "Other"
        };
    }

    public static PerformanceMetrics GetCurrentMetrics()
    {
        lock (_metricsLock)
        {
            var responseTimes = ResponseTimes.ToArray();
            
            if (responseTimes.Length == 0)
            {
                return new PerformanceMetrics
                {
                    TotalRequests = _totalRequests,
                    ConcurrentRequests = _concurrentRequests,
                    TimeoutRequests = _timeoutRequests,
                    AverageResponseTime = 0,
                    ResponseTimeP50 = 0,
                    ResponseTimeP95 = 0,
                    ResponseTimeP99 = 0,
                    TimeoutRate = 0
                };
            }

            Array.Sort(responseTimes);
            
            var p50 = GetPercentile(responseTimes, 0.50);
            var p95 = GetPercentile(responseTimes, 0.95);
            var p99 = GetPercentile(responseTimes, 0.99);
            var average = responseTimes.Average();

            return new PerformanceMetrics
            {
                TotalRequests = _totalRequests,
                ConcurrentRequests = _concurrentRequests,
                TimeoutRequests = _timeoutRequests,
                AverageResponseTime = Math.Round(average, 2),
                ResponseTimeP50 = p50,
                ResponseTimeP95 = p95,
                ResponseTimeP99 = p99,
                TimeoutRate = _totalRequests > 0 ? Math.Round((double)_timeoutRequests / _totalRequests * 100, 2) : 0
            };
        }
    }

    private static long GetPercentile(long[] sortedArray, double percentile)
    {
        if (sortedArray.Length == 0) return 0;
        
        var index = (int)Math.Ceiling(percentile * sortedArray.Length) - 1;
        index = Math.Max(0, Math.Min(index, sortedArray.Length - 1));
        return sortedArray[index];
    }

    private static double GetTimeoutRate()
    {
        return _totalRequests > 0 ? (double)_timeoutRequests / _totalRequests * 100 : 0;
    }
}

public class PerformanceMetrics
{
    public long TotalRequests { get; set; }
    public int ConcurrentRequests { get; set; }
    public long TimeoutRequests { get; set; }
    public double AverageResponseTime { get; set; }
    public long ResponseTimeP50 { get; set; }
    public long ResponseTimeP95 { get; set; }
    public long ResponseTimeP99 { get; set; }
    public double TimeoutRate { get; set; }
}
