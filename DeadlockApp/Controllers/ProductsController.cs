using Microsoft.AspNetCore.Mvc;

namespace DeadlockApp.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    private readonly ILogger<ProductsController> _logger;
    private static readonly List<Product> Products = GenerateProducts();

    public ProductsController(ILogger<ProductsController> logger)
    {
        _logger = logger;
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<Product>>> GetProducts()
    {
        _logger.LogInformation("Getting all products");

        // Simulate fast database query with minimal processing
        await Task.Delay(Random.Shared.Next(10, 50)); // 10-50ms delay

        // Occasionally trigger deadlock-prone operations when enabled
        var enableDeadlock = HttpContext.RequestServices.GetRequiredService<IConfiguration>()
            .GetValue<bool>("EnableDeadlockSimulation");
        
        if (enableDeadlock && Random.Shared.Next(1, 100) <= 10) // 10% chance
        {
            _logger.LogInformation("Triggering order/inventory operations from product listing");
            await TriggerDeadlockOperations();
        }

        return Ok(Products.Take(20)); // Return first 20 products
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<Product>> GetProduct(int id)
    {
        _logger.LogInformation("Getting product {ProductId}", id);

        // Simulate fast database lookup
        await Task.Delay(Random.Shared.Next(5, 25)); // 5-25ms delay

        var product = Products.FirstOrDefault(p => p.Id == id);
        if (product == null)
        {
            return NotFound();
        }

        return Ok(product);
    }

    [HttpGet("search")]
    public async Task<ActionResult<IEnumerable<Product>>> SearchProducts([FromQuery] string query)
    {
        _logger.LogInformation("Searching products with query: {Query}", query);

        // Simulate efficient search with indexing
        await Task.Delay(Random.Shared.Next(20, 100)); // 20-100ms delay

        if (string.IsNullOrWhiteSpace(query))
        {
            return Ok(Products.Take(10));
        }

        var results = Products
            .Where(p => p.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                       p.Category.Contains(query, StringComparison.OrdinalIgnoreCase))
            .Take(10);

        return Ok(results);
    }

    private async Task TriggerDeadlockOperations()
    {
        // Simulate realistic business logic that could trigger deadlocks
        var httpClient = HttpContext.RequestServices.GetRequiredService<HttpClient>();
        var baseUrl = $"{Request.Scheme}://{Request.Host}";

        // Fire-and-forget calls to potentially deadlock endpoints
        _ = Task.Run(async () =>
        {
            try
            {
                await httpClient.PostAsync($"{baseUrl}/api/orders/process", null);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Order processing call failed during product listing");
            }
        });

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(Random.Shared.Next(10, 50)); // Slight delay to increase deadlock chance
                await httpClient.PostAsync($"{baseUrl}/api/inventory/update", null);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Inventory update call failed during product listing");
            }
        });
    }

    private static List<Product> GenerateProducts()
    {
        var categories = new[] { "Electronics", "Clothing", "Books", "Home", "Sports", "Food" };
        var products = new List<Product>();

        for (int i = 1; i <= 1000; i++)
        {
            products.Add(new Product
            {
                Id = i,
                Name = $"Product {i}",
                Category = categories[Random.Shared.Next(categories.Length)],
                Price = Math.Round(Random.Shared.NextDouble() * 1000, 2),
                InStock = Random.Shared.Next(0, 100) > 20
            });
        }

        return products;
    }
}

public class Product
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public double Price { get; set; }
    public bool InStock { get; set; }
}
