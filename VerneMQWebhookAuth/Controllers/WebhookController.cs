using Microsoft.AspNetCore.Mvc;
using VerneMQWebhookAuth.Models;

namespace VerneMQWebhookAuth.Controllers;

/// <summary>
/// VerneMQ Webhook Authentication Controller
/// Handles authentication and authorization webhooks from VerneMQ
/// </summary>
[ApiController]
[Route("mqtt")]
public class WebhookController : ControllerBase
{
    private readonly ILogger<WebhookController> _logger;
    private readonly IConfiguration _configuration;

    // Test credentials - in production, use a database or external auth service
    private static readonly Dictionary<string, string> ValidUsers = new()
    {
        { "testuser", "testpass" },
        { "admin", "admin123" },
        { "device1", "device1pass" },
        { "devuser", "password" } 
    };

    public WebhookController(ILogger<WebhookController> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    /// <summary>
    /// Called when a client attempts to connect/register
    /// </summary>
    [HttpPost("auth")]
    public IActionResult AuthOnRegister([FromBody] AuthOnRegisterRequest request)
    {
        _logger.LogInformation(
            "Auth request - ClientId: {ClientId}, Username: {Username}, PeerAddr: {PeerAddr}",
            request.ClientId, request.Username, request.PeerAddr);

        // Validate credentials
        if (string.IsNullOrEmpty(request.Username) || string.IsNullOrEmpty(request.Password))
        {
            _logger.LogWarning("Auth failed - Missing username or password");
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "missing_credentials" } });
        }

        if (ValidUsers.TryGetValue(request.Username, out var expectedPassword) && 
            expectedPassword == request.Password)
        {
            _logger.LogInformation("Auth successful for user: {Username}", request.Username);
            return Ok(new VerneMQResponse { Result = "ok" });
        }

        _logger.LogWarning("Auth failed - Invalid credentials for user: {Username}", request.Username);
        return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "invalid_credentials" } });
    }

    /// <summary>
    /// Called when a client attempts to publish a message
    /// </summary>
    [HttpPost("publish")]
    public IActionResult AuthOnPublish([FromBody] AuthOnPublishRequest request)
    {
        _logger.LogInformation(
            "Publish request - ClientId: {ClientId}, Username: {Username}, Topic: {Topic}",
            request.ClientId, request.Username, request.Topic);

        // Example: Block publishing to admin topics unless user is admin
        if (request.Topic?.StartsWith("admin/") == true && request.Username != "admin")
        {
            _logger.LogWarning("Publish denied - User {Username} cannot publish to admin topic", request.Username);
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "not_authorized" } });
        }

        _logger.LogInformation("Publish allowed for user: {Username} on topic: {Topic}", request.Username, request.Topic);
        return Ok(new VerneMQResponse { Result = "ok" });
    }

    /// <summary>
    /// Called when a client attempts to subscribe to topics
    /// </summary>
    [HttpPost("subscribe")]
    public IActionResult AuthOnSubscribe([FromBody] AuthOnSubscribeRequest request)
    {
        _logger.LogInformation(
            "Subscribe request - ClientId: {ClientId}, Username: {Username}, Topics: {Topics}",
            request.ClientId, request.Username, 
            string.Join(", ", request.Topics?.Select(t => t.Topic) ?? []));

        // Example: Block subscribing to admin topics unless user is admin
        var adminTopics = request.Topics?.Where(t => t.Topic?.StartsWith("admin/") == true).ToList();
        if (adminTopics?.Any() == true && request.Username != "admin")
        {
            _logger.LogWarning("Subscribe denied - User {Username} cannot subscribe to admin topics", request.Username);
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "not_authorized" } });
        }

        _logger.LogInformation("Subscribe allowed for user: {Username}", request.Username);
        return Ok(new VerneMQResponse { Result = "ok" });
    }

    /// <summary>
    /// Health check endpoint
    /// </summary>
    [HttpGet("health")]
    public IActionResult Health()
    {
        return Ok(new { status = "healthy", timestamp = DateTime.UtcNow });
    }
}
