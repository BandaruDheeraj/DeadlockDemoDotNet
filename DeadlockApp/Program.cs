using System.Diagnostics;
using DeadlockApp;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddOpenApi();

// Application Insights - Configure with proper error handling
try
{
    var connectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
    if (!string.IsNullOrEmpty(connectionString))
    {
        builder.Services.AddApplicationInsightsTelemetry(options =>
        {
            options.ConnectionString = connectionString;
        });
        Console.WriteLine("Application Insights configured successfully");
    }
    else
    {
        Console.WriteLine("Application Insights connection string not found - skipping telemetry");
    }
}
catch (Exception ex)
{
    Console.WriteLine($"Failed to configure Application Insights: {ex.Message}");
    // Continue without Application Insights
}

// Add health checks with custom performance checks
builder.Services.AddHealthChecks()
    .AddCheck<PerformanceHealthCheck>("performance")
    .AddCheck("memory", () =>
    {
        var memoryUsage = GC.GetTotalMemory(false);
        var threshold = 200 * 1024 * 1024; // 200MB threshold
        return memoryUsage < threshold
            ? Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Healthy($"Memory usage: {memoryUsage / 1024 / 1024}MB")
            : Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Degraded($"High memory usage: {memoryUsage / 1024 / 1024}MB");
    })
    .AddCheck("thread-pool", () =>
    {
        ThreadPool.GetAvailableThreads(out int workerThreads, out int ioThreads);
        ThreadPool.GetMaxThreads(out int maxWorkerThreads, out int maxIoThreads);
        var availablePercentage = (double)workerThreads / maxWorkerThreads * 100;

        if (availablePercentage < 10)
            return Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Unhealthy($"Critical thread pool exhaustion: {availablePercentage:F1}% available");
        if (availablePercentage < 30)
            return Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Degraded($"Thread pool pressure: {availablePercentage:F1}% available");

        return Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Healthy($"Thread pool healthy: {availablePercentage:F1}% available");
    });

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

// Add performance monitoring middleware
app.UseMiddleware<PerformanceMiddleware>();

// Add health check endpoints
app.MapHealthChecks("/health", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
    {
        context.Response.ContentType = "application/json";
        var response = new
        {
            status = report.Status.ToString(),
            timestamp = DateTime.UtcNow,
            checks = report.Entries.Select(entry => new
            {
                name = entry.Key,
                status = entry.Value.Status.ToString(),
                description = entry.Value.Description,
                duration = entry.Value.Duration.TotalMilliseconds,
                data = entry.Value.Data
            }),
            totalDuration = report.TotalDuration.TotalMilliseconds
        };
        await context.Response.WriteAsync(System.Text.Json.JsonSerializer.Serialize(response));
    }
});

// Map controllers
app.MapControllers();

// Simple test endpoint
app.MapGet("/", () => "Deadlock Demo API is running");

app.Run();
