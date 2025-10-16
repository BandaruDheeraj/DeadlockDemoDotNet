using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace DeadlockApp.Controllers;

[ApiController]
[Route("api/[controller]")]
public class InventoryController : ControllerBase
{
    private readonly ILogger<InventoryController> _logger;
    
    // Static locks for deadlock simulation - SAME LOCKS as OrdersController
    private static readonly object LockA = new object();
    private static readonly object LockB = new object();
    
    // Metrics tracking
    private static long _totalRequests = 0;
    private static long _successfulRequests = 0;
    private static long _timeoutRequests = 0;
    private static long _deadlockDetected = 0;

    public InventoryController(ILogger<InventoryController> logger)
    {
        _logger = logger;
    }

    [HttpPost("update")]
    public async Task<ActionResult> UpdateInventory([FromBody] InventoryUpdateRequest? request = null)
    {
        Interlocked.Increment(ref _totalRequests);
        
        var stopwatch = Stopwatch.StartNew();
        var updateId = request?.UpdateId ?? Random.Shared.Next(1000, 9999);
        
        _logger.LogInformation("Updating inventory {UpdateId}", updateId);

        try
        {
            // Simulate business logic with potential deadlock
            await UpdateInventoryWithDeadlock(updateId);
            
            stopwatch.Stop();
            Interlocked.Increment(ref _successfulRequests);
            
            _logger.LogInformation("Inventory update {UpdateId} completed successfully in {ElapsedMs}ms", 
                updateId, stopwatch.ElapsedMilliseconds);
                
            // Track custom metric
            _logger.LogInformation("Inventory updated successfully in {ElapsedMs}ms", stopwatch.ElapsedMilliseconds);
            
            return Ok(new { 
                UpdateId = updateId, 
                Status = "Updated", 
                ProcessingTimeMs = stopwatch.ElapsedMilliseconds,
                Message = "Inventory updated successfully"
            });
        }
        catch (TimeoutException ex)
        {
            stopwatch.Stop();
            Interlocked.Increment(ref _timeoutRequests);
            
            _logger.LogWarning(ex, "Inventory update {UpdateId} timed out after {ElapsedMs}ms", 
                updateId, stopwatch.ElapsedMilliseconds);
                
            _logger.LogWarning("Inventory update timeout - UpdateId: {UpdateId}, ElapsedMs: {ElapsedMs}", 
                updateId, stopwatch.ElapsedMilliseconds);
            
            return StatusCode(408, new { 
                UpdateId = updateId, 
                Status = "Timeout", 
                ProcessingTimeMs = stopwatch.ElapsedMilliseconds,
                Error = "Inventory update timed out"
            });
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _logger.LogError(ex, "Inventory update {UpdateId} failed after {ElapsedMs}ms", 
                updateId, stopwatch.ElapsedMilliseconds);
                
            return StatusCode(500, new { 
                UpdateId = updateId, 
                Status = "Error", 
                ProcessingTimeMs = stopwatch.ElapsedMilliseconds,
                Error = "Inventory update failed"
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

    private async Task UpdateInventoryWithDeadlock(int updateId)
    {
        var enableDeadlock = HttpContext.RequestServices.GetRequiredService<IConfiguration>()
            .GetValue<bool>("EnableDeadlockSimulation");
            
        if (!enableDeadlock)
        {
            // Fast path when deadlock simulation is disabled
            await Task.Delay(Random.Shared.Next(15, 60));
            return;
        }

        // DEADLOCK SCENARIO: This method acquires LockB then LockA (REVERSE ORDER!)
        // This creates a classic deadlock when called concurrently with OrdersController
        var lockTimeout = TimeSpan.FromSeconds(5);
        bool lockBAcquired = false;
        bool lockAAcquired = false;

        try
        {
            // Try to acquire LockB with timeout
            if (!Monitor.TryEnter(LockB, lockTimeout))
            {
                throw new TimeoutException($"Failed to acquire LockB for inventory update {updateId} within {lockTimeout.TotalSeconds}s");
            }
            lockBAcquired = true;
            
            _logger.LogDebug("Inventory update {UpdateId} acquired LockB", updateId);
            
            // Simulate some work with LockB
            await Task.Delay(Random.Shared.Next(30, 150));
            
            // Try to acquire LockA with timeout
            if (!Monitor.TryEnter(LockA, lockTimeout))
            {
                throw new TimeoutException($"Failed to acquire LockA for inventory update {updateId} within {lockTimeout.TotalSeconds}s - potential deadlock");
            }
            lockAAcquired = true;
            
            _logger.LogDebug("Inventory update {UpdateId} acquired LockA", updateId);
            
            // Simulate work with both locks
            await Task.Delay(Random.Shared.Next(80, 250));
            
            // Simulate calling order processing (which might try to acquire locks in different order)
            var orderProcessingDelay = Random.Shared.Next(15, 80);
            await Task.Delay(orderProcessingDelay);
            
            _logger.LogDebug("Inventory update {UpdateId} completed processing", updateId);
        }
        finally
        {
            // Always release locks in reverse order
            if (lockAAcquired)
            {
                Monitor.Exit(LockA);
                _logger.LogDebug("Inventory update {UpdateId} released LockA", updateId);
            }
            
            if (lockBAcquired)
            {
                Monitor.Exit(LockB);
                _logger.LogDebug("Inventory update {UpdateId} released LockB", updateId);
            }
        }
    }
}

public class InventoryUpdateRequest
{
    public int UpdateId { get; set; }
    public int ProductId { get; set; }
    public int QuantityChange { get; set; }
    public string Reason { get; set; } = string.Empty;
}
