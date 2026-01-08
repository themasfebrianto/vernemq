using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Models;

namespace VerneMQWebhookAuth.Services;

/// <summary>
/// Service for logging MQTT activities
/// </summary>
public interface IMqttActivityLogger
{
    Task LogAsync(string eventType, MqttEventResult result, string? clientId, string? username, 
        string? peerAddr, string? topic = null, string? details = null, string? errorMessage = null);
}

public class MqttActivityLogger : IMqttActivityLogger
{
    private readonly WebhookDbContext _db;
    private readonly ILogger<MqttActivityLogger> _logger;

    public MqttActivityLogger(WebhookDbContext db, ILogger<MqttActivityLogger> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task LogAsync(string eventType, MqttEventResult result, string? clientId, string? username,
        string? peerAddr, string? topic = null, string? details = null, string? errorMessage = null)
    {
        try
        {
            var log = new MqttActivityLog
            {
                Timestamp = DateTime.UtcNow,
                EventType = eventType,
                Result = result,
                ClientId = clientId?.Length > 200 ? clientId[..200] : clientId,
                Username = username?.Length > 100 ? username[..100] : username,
                PeerAddr = peerAddr?.Length > 50 ? peerAddr[..50] : peerAddr,
                Topic = topic?.Length > 500 ? topic[..500] : topic,
                Details = details?.Length > 1000 ? details[..1000] : details,
                ErrorMessage = errorMessage?.Length > 500 ? errorMessage[..500] : errorMessage
            };

            _db.MqttActivityLogs.Add(log);
            await _db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to log MQTT activity: {EventType}", eventType);
        }
    }
}

/// <summary>
/// Static class containing MQTT event type constants
/// </summary>
public static class MqttEventTypes
{
    public const string Auth = "auth";
    public const string Publish = "publish";
    public const string Subscribe = "subscribe";
    public const string Connect = "connect";
    public const string Disconnect = "disconnect";
    public const string Wakeup = "wakeup";
}
