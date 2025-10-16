// Minimal version for testing - copy this to Program.cs if needed
var builder = WebApplication.CreateBuilder(args);

// Add minimal services
builder.Services.AddControllers();

var app = builder.Build();

// Configure minimal pipeline
app.MapControllers();

// Simple health check endpoint
app.MapGet("/health", () => new { status = "Healthy", timestamp = DateTime.UtcNow });

// Simple test endpoint
app.MapGet("/", () => "Deadlock Demo API is running");

app.Run();
