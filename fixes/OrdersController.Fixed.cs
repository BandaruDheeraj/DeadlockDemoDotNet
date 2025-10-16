using Microsoft.AspNetCore.Mvc;
using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.DataContracts;

namespace DeadlockApp.Controllers;

[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    private readonly ILogger<OrdersController> _logger;
    private readonly TelemetryClient _telemetryClient;
    
    // Static locks for deadlock prevention - CONSISTENT ORDER with InventoryController
    private static readonly object LockA = new object();
    private static readonly object LockB = new object();
    
    // Metrics tracking
    private static long _totalRequests = 0;
    private static long _successfulRequests = 0;
    private static long _timeoutRequests = 0;
    private static long _deadlockDetected = 0;

    public OrdersController(ILogger<OrdersController> logger, TelemetryClient telemetryClient)
    {
        _logger = logger;
        _telemetryClient = telemetryClient;
    }

    [HttpPost("process")]
    public async Task<ActionResult> ProcessOrder([FromBody] OrderRequest? request = null)
    {
        Interlocked.Increment(ref _totalRequests);
        
        var stopwatch = Stopwatch.StartNew();
        var orderId = request?.OrderId ?? Random.Shared.Next(1000, 9999);
        
        _logger.LogInformation("Processing order {OrderId}", orderId);

        try
        {
            // Process order with deadlock prevention
            await ProcessOrderWithDeadlockPrevention(orderId);
            
            stopwatch.Stop();
            Interlocked.Increment(ref _successfulRequests);
            
            _logger.LogInformation("Order {OrderId} processed successfully in {ElapsedMs}ms", 
                orderId, stopwatch.ElapsedMilliseconds);
                
            // Track custom metric
            _telemetryClient.TrackMetric("OrderProcessingTime", stopwatch.ElapsedMilliseconds);
            
            return Ok(new { 
                OrderId = orderId, 
                Status = "Processed", 
                ProcessingTimeMs = stopwatch.ElapsedMilliseconds,
                Message = "Order processed successfully"
            });
        }
        catch (TimeoutException ex)
        {
            stopwatch.Stop();
            Interlocked.Increment(ref _timeoutRequests);
            
            _logger.LogWarning(ex, "Order {OrderId} processing timed out after {ElapsedMs}ms", 
                orderId, stopwatch.ElapsedMilliseconds);
                
            // Track timeout event
            _telemetryClient.TrackEvent("OrderProcessingTimeout", new Dictionary<string, string>
            {
                { "OrderId", orderId.ToString() },
                { "ElapsedMs", stopwatch.ElapsedMilliseconds.ToString() }
            });
            
            return StatusCode(408, new { 
                OrderId = orderId, 
                Status = "Timeout", 
                ProcessingTimeMs = stopwatch.ElapsedMilliseconds,
                Error = "Order processing timed out"
            });
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _logger.LogError(ex, "Order {OrderId} processing failed after {ElapsedMs}ms", 
                orderId, stopwatch.ElapsedMilliseconds);
                
            return StatusCode(500, new { 
                OrderId = orderId, 
                Status = "Error", 
                ProcessingTimeMs = stopwatch.ElapsedMilliseconds,
                Error = "Order processing failed"
            });
        }
    }

    [HttpGet("metrics")]
    public ActionResult GetMetrics()
    {
        return Ok(new
        {
            TotalRequests = _totalRequests,
            SuccessfulRequests = _successfulRequests,
            TimeoutRequests = _timeoutRequests,
            DeadlockDetected = _deadlockDetected,
            SuccessRate = _totalRequests > 0 ? (double)_successfulRequests / _totalRequests * 100 : 0,
            TimeoutRate = _totalRequests > 0 ? (double)_timeoutRequests / _totalRequests * 100 : 0
        });
    }

    /// <summary>
    /// Process order with deadlock prevention using consistent lock ordering.
    /// Both OrdersController and InventoryController use the same lock order: LockA → LockB
    /// </summary>
    private async Task ProcessOrderWithDeadlockPrevention(int orderId)
    {
        var enableDeadlock = HttpContext.RequestServices.GetRequiredService<IConfiguration>()
            .GetValue<bool>("EnableDeadlockSimulation");
            
        if (!enableDeadlock)
        {
            // Fast path when deadlock simulation is disabled
            await Task.Delay(Random.Shared.Next(20, 80));
            return;
        }

        // DEADLOCK PREVENTION: Consistent lock ordering (LockA → LockB)
        // This matches the lock order used in InventoryController to prevent deadlock
        var lockTimeout = TimeSpan.FromSeconds(3); // Reduced timeout for better responsiveness
        bool lockAAcquired = false;
        bool lockBAcquired = false;

        try
        {
            // Try to acquire LockA with timeout
            if (!Monitor.TryEnter(LockA, lockTimeout))
            {
                Interlocked.Increment(ref _deadlockDetected);
                throw new TimeoutException($"Failed to acquire LockA for order {orderId} within {lockTimeout.TotalSeconds}s - potential contention detected");
            }
            lockAAcquired = true;
            
            _logger.LogDebug("Order {OrderId} acquired LockA", orderId);
            
            // Simulate some work with LockA
            await Task.Delay(Random.Shared.Next(50, 200));
            
            // Try to acquire LockB with timeout
            if (!Monitor.TryEnter(LockB, lockTimeout))
            {
                Interlocked.Increment(ref _deadlockDetected);
                throw new TimeoutException($"Failed to acquire LockB for order {orderId} within {lockTimeout.TotalSeconds}s - potential contention detected");
            }
            lockBAcquired = true;
            
            _logger.LogDebug("Order {OrderId} acquired LockB", orderId);
            
            // Simulate work with both locks
            await Task.Delay(Random.Shared.Next(100, 300));
            
            // Simulate calling inventory update (which now uses the same lock order)
            var inventoryUpdateDelay = Random.Shared.Next(20, 100);
            await Task.Delay(inventoryUpdateDelay);
            
            _logger.LogDebug("Order {OrderId} completed processing", orderId);
        }
        finally
        {
            // Always release locks in reverse order (LockB → LockA)
            if (lockBAcquired)
            {
                Monitor.Exit(LockB);
                _logger.LogDebug("Order {OrderId} released LockB", orderId);
            }
            
            if (lockAAcquired)
            {
                Monitor.Exit(LockA);
                _logger.LogDebug("Order {OrderId} released LockA", orderId);
            }
        }
    }
}

public class OrderRequest
{
    public int OrderId { get; set; }
    public string CustomerId { get; set; } = string.Empty;
    public List<int> ProductIds { get; set; } = new();
}
