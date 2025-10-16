using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace DeadlockApp.Controllers;

[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    private readonly ILogger<OrdersController> _logger;
    
    // Static locks for deadlock simulation
    private static readonly object LockA = new object();
    private static readonly object LockB = new object();
    
    // Metrics tracking
    private static long _totalRequests = 0;
    private static long _successfulRequests = 0;
    private static long _timeoutRequests = 0;
    private static long _deadlockDetected = 0;

    public OrdersController(ILogger<OrdersController> logger)
    {
        _logger = logger;
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
            // Simulate business logic with potential deadlock
            await ProcessOrderWithDeadlock(orderId);
            
            stopwatch.Stop();
            Interlocked.Increment(ref _successfulRequests);
            
            _logger.LogInformation("Order {OrderId} processed successfully in {ElapsedMs}ms", 
                orderId, stopwatch.ElapsedMilliseconds);
                
            // Track custom metric
            _logger.LogInformation("Order processed successfully in {ElapsedMs}ms", stopwatch.ElapsedMilliseconds);
            
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
                
            _logger.LogWarning("Order processing timeout - OrderId: {OrderId}, ElapsedMs: {ElapsedMs}", 
                orderId, stopwatch.ElapsedMilliseconds);
            
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

    private async Task ProcessOrderWithDeadlock(int orderId)
    {
        var enableDeadlock = HttpContext.RequestServices.GetRequiredService<IConfiguration>()
            .GetValue<bool>("EnableDeadlockSimulation");
            
        if (!enableDeadlock)
        {
            // Fast path when deadlock simulation is disabled
            await Task.Delay(Random.Shared.Next(20, 80));
            return;
        }

        // DEADLOCK SCENARIO: This method acquires LockA then LockB
        var lockTimeout = TimeSpan.FromSeconds(5);
        bool lockAAcquired = false;
        bool lockBAcquired = false;

        try
        {
            // Try to acquire LockA with timeout
            if (!Monitor.TryEnter(LockA, lockTimeout))
            {
                throw new TimeoutException($"Failed to acquire LockA for order {orderId} within {lockTimeout.TotalSeconds}s");
            }
            lockAAcquired = true;
            
            _logger.LogDebug("Order {OrderId} acquired LockA", orderId);
            
            // Simulate some work with LockA
            await Task.Delay(Random.Shared.Next(50, 200));
            
            // Try to acquire LockB with timeout
            if (!Monitor.TryEnter(LockB, lockTimeout))
            {
                throw new TimeoutException($"Failed to acquire LockB for order {orderId} within {lockTimeout.TotalSeconds}s - potential deadlock");
            }
            lockBAcquired = true;
            
            _logger.LogDebug("Order {OrderId} acquired LockB", orderId);
            
            // Simulate work with both locks
            await Task.Delay(Random.Shared.Next(100, 300));
            
            // Simulate calling inventory update (which might try to acquire locks in reverse order)
            var inventoryUpdateDelay = Random.Shared.Next(20, 100);
            await Task.Delay(inventoryUpdateDelay);
            
            _logger.LogDebug("Order {OrderId} completed processing", orderId);
        }
        finally
        {
            // Always release locks in reverse order
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
