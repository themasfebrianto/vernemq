using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Models;
using VerneMQWebhookAuth.Services;

namespace VerneMQWebhookAuth.Controllers;

/// <summary>
/// VerneMQ Webhook Authentication Controller
/// Handles authentication and authorization webhooks from VerneMQ
/// Now uses database for credentials instead of hardcoded values
/// </summary>
[ApiController]
[Route("mqtt")]
public class WebhookController : ControllerBase
{
    private readonly ILogger<WebhookController> _logger;
    private readonly IConfiguration _configuration;
    private readonly WebhookDbContext _db;
    private readonly IWebhookTriggerService _webhookTriggerService;
    private readonly IHybridCacheService _cache;
    private readonly IMqttActivityLogger _activityLogger;
    
    // Cache settings
    private static readonly TimeSpan AuthCacheDuration = TimeSpan.FromMinutes(5);
    private const string AuthCachePrefix = "auth_";
    private const string UserCachePrefix = "user_";

    public WebhookController(
        ILogger<WebhookController> logger, 
        IConfiguration configuration,
        WebhookDbContext db,
        IWebhookTriggerService webhookTriggerService,
        IHybridCacheService cache,
        IMqttActivityLogger activityLogger)
    {
        _logger = logger;
        _configuration = configuration;
        _db = db;
        _webhookTriggerService = webhookTriggerService;
        _cache = cache;
        _activityLogger = activityLogger;
    }

    /// <summary>
    /// Called when a client attempts to connect/register
    /// </summary>
    [HttpPost("auth")]
    public async Task<IActionResult> AuthOnRegister([FromBody] AuthOnRegisterRequest request)
    {
        _logger.LogInformation(
            "Auth request - ClientId: {ClientId}, Username: {Username}, PeerAddr: {PeerAddr}",
            request.ClientId, request.Username, request.PeerAddr);

        // Validate credentials
        if (string.IsNullOrEmpty(request.Username) || string.IsNullOrEmpty(request.Password))
        {
            _logger.LogWarning("Auth failed - Missing username or password");
            
            // Log activity
            _ = _activityLogger.LogAsync(MqttEventTypes.Auth, MqttEventResult.Failed,
                request.ClientId, request.Username, request.PeerAddr, 
                errorMessage: "Username atau password tidak diberikan");
            
            // Trigger on_auth_failed webhook
            _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnAuthFailed, new WebhookEventData
            {
                Event = WebhookEvents.OnAuthFailed,
                ClientId = request.ClientId,
                Username = request.Username,
                PeerAddr = request.PeerAddr,
                ErrorReason = "missing_credentials"
            }));
            
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "missing_credentials" } });
        }

        // Check cache first (cache key includes password hash to invalidate on password change)
        var cacheKey = $"{AuthCachePrefix}{request.Username}_{request.Password.GetHashCode()}";
        
        // Try to get cached auth result
        var cachedAuth = await _cache.GetAsync<CachedAuthResult>(cacheKey);
        if (cachedAuth != null)
        {
            _logger.LogDebug("Auth cache HIT for user: {Username}", request.Username);
            // Update login stats (fire and forget)
            _ = UpdateLoginStats(cachedAuth.UserId, request.PeerAddr);
            
            return Ok(new VerneMQResponse { Result = "ok" });
        }

        // Cache miss - query database for user
        var user = await _db.MqttUsers
            .FirstOrDefaultAsync(u => u.Username == request.Username && u.IsActive);

        if (user == null)
        {
            _logger.LogWarning("Auth failed - User not found: {Username}", request.Username);
            
            // Log activity
            _ = _activityLogger.LogAsync(MqttEventTypes.Auth, MqttEventResult.Failed,
                request.ClientId, request.Username, request.PeerAddr,
                errorMessage: "User tidak ditemukan atau tidak aktif");
            
            // Trigger on_auth_failed webhook
            _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnAuthFailed, new WebhookEventData
            {
                Event = WebhookEvents.OnAuthFailed,
                ClientId = request.ClientId,
                Username = request.Username,
                PeerAddr = request.PeerAddr,
                ErrorReason = "invalid_credentials"
            }));

            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "invalid_credentials" } });
        }

        // Verify password using BCrypt
        if (!BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
        {
            _logger.LogWarning("Auth failed - Invalid password for user: {Username}", request.Username);
            
            // Log activity
            _ = _activityLogger.LogAsync(MqttEventTypes.Auth, MqttEventResult.Failed,
                request.ClientId, request.Username, request.PeerAddr,
                errorMessage: "Password salah");
            
            // Trigger on_auth_failed webhook
            _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnAuthFailed, new WebhookEventData
            {
                Event = WebhookEvents.OnAuthFailed,
                ClientId = request.ClientId,
                Username = request.Username,
                PeerAddr = request.PeerAddr,
                ErrorReason = "invalid_credentials"
            }));

            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "invalid_credentials" } });
        }

        // Check client ID restriction if set
        if (!string.IsNullOrEmpty(user.AllowedClientId) && 
            user.AllowedClientId != request.ClientId)
        {
            _logger.LogWarning(
                "Auth failed - ClientId mismatch for user: {Username}. Expected: {Expected}, Got: {Got}",
                request.Username, user.AllowedClientId, request.ClientId);
            
            // Log activity
            _ = _activityLogger.LogAsync(MqttEventTypes.Auth, MqttEventResult.Denied,
                request.ClientId, request.Username, request.PeerAddr,
                errorMessage: $"Client ID tidak sesuai. Diharapkan: {user.AllowedClientId}");
            
            // Trigger on_auth_failed webhook
            _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnAuthFailed, new WebhookEventData
            {
                Event = WebhookEvents.OnAuthFailed,
                ClientId = request.ClientId,
                Username = request.Username,
                PeerAddr = request.PeerAddr,
                ErrorReason = "client_id_mismatch"
            }));

            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "client_id_mismatch" } });
        }

        // Update login stats (fire and forget, don't wait)
        _ = UpdateLoginStats(user.Id, request.PeerAddr);

        // Cache successful auth for 5 minutes using Redis-backed hybrid cache
        var authResult = new CachedAuthResult
        {
            UserId = user.Id,
            Username = user.Username,
            IsActive = user.IsActive,
            IsAdmin = user.IsAdmin,
            AllowedClientId = user.AllowedClientId,
            AllowedPublishTopics = user.AllowedPublishTopics,
            AllowedSubscribeTopics = user.AllowedSubscribeTopics
        };
        _ = _cache.SetAsync(cacheKey, authResult, AuthCacheDuration);


        // Trigger on_auth_success and on_client_connect webhooks
        _ = Task.Run(async () => 
        {
            await _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnAuthSuccess, new WebhookEventData
            {
                Event = WebhookEvents.OnAuthSuccess,
                ClientId = request.ClientId,
                Username = request.Username,
                PeerAddr = request.PeerAddr
            });
            
            await _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnClientConnect, new WebhookEventData
            {
                Event = WebhookEvents.OnClientConnect,
                ClientId = request.ClientId,
                Username = request.Username,
                PeerAddr = request.PeerAddr
            });
        });

        // Log successful auth with details
        var cleanSession = request.CleanSession == true ? "Clean Session" : "Persistent Session";
        _ = _activityLogger.LogAsync(MqttEventTypes.Auth, MqttEventResult.Success,
            request.ClientId, request.Username, request.PeerAddr,
            details: $"Login berhasil. {cleanSession}");

        _logger.LogInformation("Auth successful for user: {Username}", request.Username);
        return Ok(new VerneMQResponse { Result = "ok" });
    }

    /// <summary>
    /// Called when a client attempts to publish a message
    /// </summary>
    [HttpPost("publish")]
    public async Task<IActionResult> AuthOnPublish([FromBody] AuthOnPublishRequest request)
    {
        _logger.LogInformation(
            "Publish request - ClientId: {ClientId}, Username: {Username}, Topic: {Topic}",
            request.ClientId, request.Username, request.Topic);

        // Get user from database
        var user = await _db.MqttUsers
            .FirstOrDefaultAsync(u => u.Username == request.Username && u.IsActive);

        if (user == null)
        {
            _logger.LogWarning("Publish denied - User not found: {Username}", request.Username);
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "not_authorized" } });
        }

        // Check admin topic access
        if (request.Topic?.StartsWith("admin/") == true && !user.IsAdmin)
        {
            _logger.LogWarning("Publish denied - User {Username} cannot publish to admin topic", request.Username);
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "not_authorized" } });
        }

        // Check topic permissions if configured
        if (!string.IsNullOrEmpty(user.AllowedPublishTopics))
        {
            var allowedPatterns = user.AllowedPublishTopics.Split(',', StringSplitOptions.RemoveEmptyEntries);
            if (!IsTopicAllowed(request.Topic, allowedPatterns))
            {
                _logger.LogWarning(
                    "Publish denied - User {Username} not allowed to publish to topic: {Topic}",
                    request.Username, request.Topic);
                return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "topic_not_allowed" } });
            }
        }

        _logger.LogInformation("Publish allowed for user: {Username} on topic: {Topic}", request.Username, request.Topic);
        
        // Trigger on_publish webhook
        _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnPublish, new WebhookEventData
        {
            Event = WebhookEvents.OnPublish,
            ClientId = request.ClientId,
            Username = request.Username,
            PeerAddr = request.PeerAddr,
            Topic = request.Topic,
            Payload = request.Payload
        }));
        
        return Ok(new VerneMQResponse { Result = "ok" });
    }

    /// <summary>
    /// Called when a client attempts to subscribe to topics
    /// </summary>
    [HttpPost("subscribe")]
    public async Task<IActionResult> AuthOnSubscribe([FromBody] AuthOnSubscribeRequest request)
    {
        _logger.LogInformation(
            "Subscribe request - ClientId: {ClientId}, Username: {Username}, Topics: {Topics}",
            request.ClientId, request.Username, 
            string.Join(", ", request.Topics?.Select(t => t.Topic) ?? []));

        // Get user from database
        var user = await _db.MqttUsers
            .FirstOrDefaultAsync(u => u.Username == request.Username && u.IsActive);

        if (user == null)
        {
            _logger.LogWarning("Subscribe denied - User not found: {Username}", request.Username);
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "not_authorized" } });
        }

        // Check admin topic access
        var adminTopics = request.Topics?.Where(t => t.Topic?.StartsWith("admin/") == true).ToList();
        if (adminTopics?.Any() == true && !user.IsAdmin)
        {
            _logger.LogWarning("Subscribe denied - User {Username} cannot subscribe to admin topics", request.Username);
            return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "not_authorized" } });
        }

        // Check topic permissions if configured
        if (!string.IsNullOrEmpty(user.AllowedSubscribeTopics))
        {
            var allowedPatterns = user.AllowedSubscribeTopics.Split(',', StringSplitOptions.RemoveEmptyEntries);
            var requestedTopics = request.Topics?.Select(t => t.Topic).Where(t => t != null) ?? [];
            
            foreach (var topic in requestedTopics)
            {
                if (!IsTopicAllowed(topic, allowedPatterns))
                {
                    _logger.LogWarning(
                        "Subscribe denied - User {Username} not allowed to subscribe to topic: {Topic}",
                        request.Username, topic);
                    return Ok(new VerneMQResponse { Result = new VerneMQErrorResult { Error = "topic_not_allowed" } });
                }
            }
        }

        _logger.LogInformation("Subscribe allowed for user: {Username}", request.Username);
        
        // Trigger on_subscribe webhook
        _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnSubscribe, new WebhookEventData
        {
            Event = WebhookEvents.OnSubscribe,
            ClientId = request.ClientId,
            Username = request.Username,
            PeerAddr = request.PeerAddr,
            Topic = string.Join(", ", request.Topics?.Select(t => t.Topic) ?? Array.Empty<string>())
        }));
        
        return Ok(new VerneMQResponse { Result = "ok" });
    }

    /// <summary>
    /// Called when a client goes offline (disconnects or session expires)
    /// </summary>
    [HttpPost("client-offline")]
    public async Task<IActionResult> OnClientOffline([FromBody] ClientStatusRequest request)
    {
        _logger.LogInformation(
            "Client offline - ClientId: {ClientId}, Username: {Username}",
            request.ClientId, request.Username);

        // Log activity
        await _activityLogger.LogAsync(MqttEventTypes.Disconnect, MqttEventResult.Success,
            request.ClientId, request.Username, request.PeerAddr,
            details: "Client disconnected");

        // Trigger on_client_disconnect webhook
        _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnClientDisconnect, new WebhookEventData
        {
            Event = WebhookEvents.OnClientDisconnect,
            ClientId = request.ClientId,
            Username = request.Username,
            PeerAddr = request.PeerAddr
        }));

        return Ok(new VerneMQResponse { Result = "ok" });
    }

    /// <summary>
    /// Called when a client wakes up (reconnects with existing session)
    /// </summary>
    [HttpPost("client-wakeup")]
    public async Task<IActionResult> OnClientWakeup([FromBody] ClientStatusRequest request)
    {
        _logger.LogInformation(
            "Client wakeup - ClientId: {ClientId}, Username: {Username}",
            request.ClientId, request.Username);

        // Log activity
        await _activityLogger.LogAsync(MqttEventTypes.Wakeup, MqttEventResult.Success,
            request.ClientId, request.Username, request.PeerAddr,
            details: "Session resumed");

        // Trigger on_client_connect webhook for wake up
        _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnClientConnect, new WebhookEventData
        {
            Event = WebhookEvents.OnClientConnect,
            ClientId = request.ClientId,
            Username = request.Username,
            PeerAddr = request.PeerAddr
        }));

        return Ok(new VerneMQResponse { Result = "ok" });
    }

    /// <summary>
    /// Called when a client disconnects with clean_session=true (session fully removed)
    /// </summary>
    [HttpPost("client-gone")]
    public async Task<IActionResult> OnClientGone([FromBody] ClientStatusRequest request)
    {
        _logger.LogInformation(
            "Client gone - ClientId: {ClientId}, Username: {Username}",
            request.ClientId, request.Username);

        // Log activity
        await _activityLogger.LogAsync(MqttEventTypes.Disconnect, MqttEventResult.Success,
            request.ClientId, request.Username, request.PeerAddr,
            details: "Client disconnected (clean session)");

        // Trigger on_client_disconnect webhook
        _ = Task.Run(() => _webhookTriggerService.TriggerWebhooksAsync(WebhookEvents.OnClientDisconnect, new WebhookEventData
        {
            Event = WebhookEvents.OnClientDisconnect,
            ClientId = request.ClientId,
            Username = request.Username,
            PeerAddr = request.PeerAddr
        }));

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

    /// <summary>
    /// Check if a topic matches any of the allowed patterns
    /// Supports MQTT wildcards: + (single level) and # (multi-level)
    /// </summary>
    private static bool IsTopicAllowed(string? topic, string[] allowedPatterns)
    {
        if (string.IsNullOrEmpty(topic)) return false;
        
        foreach (var pattern in allowedPatterns)
        {
            var trimmedPattern = pattern.Trim();
            if (MatchesMqttPattern(topic, trimmedPattern))
            {
                return true;
            }
        }
        
        return false;
    }

    /// <summary>
    /// Match a topic against an MQTT pattern with wildcards
    /// </summary>
    private static bool MatchesMqttPattern(string topic, string pattern)
    {
        // Exact match
        if (topic == pattern) return true;
        
        // Multi-level wildcard at end
        if (pattern.EndsWith("/#"))
        {
            var prefix = pattern[..^2];
            return topic == prefix || topic.StartsWith(prefix + "/");
        }
        
        // Multi-level wildcard only
        if (pattern == "#") return true;
        
        // Single-level wildcard matching
        if (pattern.Contains('+'))
        {
            var topicParts = topic.Split('/');
            var patternParts = pattern.Split('/');
            
            if (topicParts.Length != patternParts.Length) return false;
            
            for (int i = 0; i < patternParts.Length; i++)
            {
                if (patternParts[i] != "+" && patternParts[i] != topicParts[i])
                {
                    return false;
                }
            }
            return true;
        }
        
        return false;
    }

    /// <summary>
    /// Update user login statistics
    /// </summary>
    private async Task UpdateLoginStats(int userId, string? peerAddr)
    {
        try
        {
            var user = await _db.MqttUsers.FindAsync(userId);
            if (user != null)
            {
                user.LastLoginAt = DateTime.UtcNow;
                user.LastLoginIp = peerAddr;
                user.LoginCount++;
                await _db.SaveChangesAsync();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to update login stats for user {UserId}", userId);
        }
    }
}
