using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.SignalR;
using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Models;
using VerneMQWebhookAuth.Hubs;
using System.Text.Json;

namespace VerneMQWebhookAuth.Services;

/// <summary>
/// Available webhook trigger events
/// </summary>
public static class WebhookEvents
{
    public const string OnClientConnect = "on_client_connect";
    public const string OnClientDisconnect = "on_client_disconnect";
    public const string OnAuthSuccess = "on_auth_success";
    public const string OnAuthFailed = "on_auth_failed";
    public const string OnPublish = "on_publish";
    public const string OnSubscribe = "on_subscribe";
    
    public static readonly string[] All = new[]
    {
        OnClientConnect,
        OnClientDisconnect,
        OnAuthSuccess,
        OnAuthFailed,
        OnPublish,
        OnSubscribe
    };
}

/// <summary>
/// Event data passed to webhooks
/// </summary>
public class WebhookEventData
{
    public string Event { get; set; } = string.Empty;
    public string? ClientId { get; set; }
    public string? Username { get; set; }
    public string? PeerAddr { get; set; }
    public string? Topic { get; set; }
    public string? Payload { get; set; }
    public string? ErrorReason { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Service to trigger webhooks based on VerneMQ events
/// </summary>
public interface IWebhookTriggerService
{
    Task TriggerWebhooksAsync(string eventType, WebhookEventData eventData);
}

public class WebhookTriggerService : IWebhookTriggerService
{
    private readonly WebhookDbContext _context;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IHubContext<WebhookHub> _hubContext;
    private readonly ILogger<WebhookTriggerService> _logger;

    public WebhookTriggerService(
        WebhookDbContext context,
        IHttpClientFactory httpClientFactory,
        IHubContext<WebhookHub> hubContext,
        ILogger<WebhookTriggerService> logger)
    {
        _context = context;
        _httpClientFactory = httpClientFactory;
        _hubContext = hubContext;
        _logger = logger;
    }

    public async Task TriggerWebhooksAsync(string eventType, WebhookEventData eventData)
    {
        try
        {
            // Find all active webhooks with matching triggers
            var webhooksToTrigger = await _context.Webhooks
                .Include(w => w.Triggers)
                .Where(w => w.IsActive && 
                       w.Triggers.Any(t => t.IsActive && t.TriggerType == eventType))
                .ToListAsync();

            if (!webhooksToTrigger.Any())
            {
                _logger.LogDebug("No webhooks configured for event: {EventType}", eventType);
                return;
            }

            _logger.LogInformation("Triggering {Count} webhooks for event: {EventType}", 
                webhooksToTrigger.Count, eventType);

            // Execute webhooks in parallel (fire and forget)
            var tasks = webhooksToTrigger.Select(webhook => 
                ExecuteWebhookAsync(webhook, eventData, eventType));
            
            await Task.WhenAll(tasks);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error triggering webhooks for event: {EventType}", eventType);
        }
    }

    private async Task ExecuteWebhookAsync(Webhook webhook, WebhookEventData eventData, string triggeredBy)
    {
        var executionLog = new WebhookExecutionLog
        {
            WebhookId = webhook.Id,
            ExecutionTime = DateTime.UtcNow,
            Status = ExecutionStatus.Pending,
            RetryAttempt = 0,
            TriggeredBy = triggeredBy
        };

        try
        {
            _context.WebhookExecutionLogs.Add(executionLog);
            await _context.SaveChangesAsync();

            var httpClient = _httpClientFactory.CreateClient();
            httpClient.Timeout = TimeSpan.FromSeconds(webhook.TimeoutSeconds);

            var stopwatch = System.Diagnostics.Stopwatch.StartNew();

            // Build the payload from template
            var payload = BuildPayload(webhook.PayloadTemplate, eventData);
            executionLog.RequestPayload = payload;

            // Prepare request
            var request = new HttpRequestMessage(
                GetHttpMethod(webhook.HttpMethod), 
                webhook.Url);

            // Set content
            if (webhook.HttpMethod != Models.HttpMethod.GET && !string.IsNullOrEmpty(payload))
            {
                request.Content = new StringContent(
                    payload, 
                    System.Text.Encoding.UTF8, 
                    webhook.ContentType ?? "application/json");
            }

            // Set headers
            if (!string.IsNullOrEmpty(webhook.Headers))
            {
                var headers = JsonSerializer.Deserialize<Dictionary<string, string>>(webhook.Headers);
                if (headers != null)
                {
                    foreach (var header in headers)
                    {
                        request.Headers.TryAddWithoutValidation(header.Key, header.Value);
                    }
                }
            }

            // Set authentication
            if (!string.IsNullOrEmpty(webhook.AuthenticationType) && 
                !string.IsNullOrEmpty(webhook.AuthenticationValue))
            {
                switch (webhook.AuthenticationType.ToLower())
                {
                    case "bearer":
                        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue(
                            "Bearer", webhook.AuthenticationValue);
                        break;
                    case "basic":
                        var credentials = Convert.ToBase64String(
                            System.Text.Encoding.UTF8.GetBytes(webhook.AuthenticationValue));
                        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue(
                            "Basic", credentials);
                        break;
                    case "apikey":
                        request.Headers.TryAddWithoutValidation("X-API-Key", webhook.AuthenticationValue);
                        break;
                }
            }

            // Execute request with retry
            var response = await ExecuteWithRetryAsync(httpClient, request, webhook.RetryCount, webhook.RetryDelaySeconds);
            stopwatch.Stop();

            // Update execution log
            executionLog.ResponseStatusCode = (int)response.StatusCode;
            executionLog.ResponseTimeMs = stopwatch.ElapsedMilliseconds;
            executionLog.ResponsePayload = await response.Content.ReadAsStringAsync();
            executionLog.Status = response.IsSuccessStatusCode ? ExecutionStatus.Success : ExecutionStatus.Failed;

            if (!response.IsSuccessStatusCode)
            {
                executionLog.ErrorMessage = $"HTTP {response.StatusCode}";
            }

            await _context.SaveChangesAsync();

            // Notify clients via SignalR
            await _hubContext.Clients.All.SendAsync("WebhookExecuted", new
            {
                WebhookId = webhook.Id,
                WebhookName = webhook.Name,
                Event = triggeredBy,
                Status = executionLog.Status.ToString(),
                ResponseTimeMs = executionLog.ResponseTimeMs
            });

            _logger.LogInformation(
                "Webhook {WebhookName} executed: {Status} ({ResponseTimeMs}ms)",
                webhook.Name, executionLog.Status, executionLog.ResponseTimeMs);
        }
        catch (TaskCanceledException)
        {
            executionLog.Status = ExecutionStatus.Timeout;
            executionLog.ErrorMessage = "Request timed out";
            await _context.SaveChangesAsync();
            _logger.LogWarning("Webhook {WebhookName} timed out", webhook.Name);
        }
        catch (Exception ex)
        {
            executionLog.Status = ExecutionStatus.Failed;
            executionLog.ErrorMessage = ex.Message;
            executionLog.StackTrace = ex.StackTrace;
            await _context.SaveChangesAsync();
            _logger.LogError(ex, "Webhook {WebhookName} failed", webhook.Name);
        }
    }

    private async Task<HttpResponseMessage> ExecuteWithRetryAsync(
        HttpClient client, 
        HttpRequestMessage request, 
        int retryCount, 
        int retryDelaySeconds)
    {
        HttpResponseMessage? response = null;
        
        for (int attempt = 0; attempt <= retryCount; attempt++)
        {
            if (attempt > 0)
            {
                await Task.Delay(TimeSpan.FromSeconds(retryDelaySeconds));
                // Clone request for retry
                request = await CloneRequestAsync(request);
            }

            response = await client.SendAsync(request);
            
            if (response.IsSuccessStatusCode)
            {
                break;
            }
        }

        return response!;
    }

    private async Task<HttpRequestMessage> CloneRequestAsync(HttpRequestMessage original)
    {
        var clone = new HttpRequestMessage(original.Method, original.RequestUri);
        
        if (original.Content != null)
        {
            var content = await original.Content.ReadAsStringAsync();
            clone.Content = new StringContent(content, System.Text.Encoding.UTF8, 
                original.Content.Headers.ContentType?.MediaType ?? "application/json");
        }

        foreach (var header in original.Headers)
        {
            clone.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        return clone;
    }

    private string BuildPayload(string? template, WebhookEventData eventData)
    {
        if (string.IsNullOrEmpty(template))
        {
            // Return default JSON payload
            return JsonSerializer.Serialize(eventData);
        }

        // Replace placeholders in template
        var result = template
            .Replace("{{event}}", eventData.Event)
            .Replace("{{client_id}}", eventData.ClientId ?? "")
            .Replace("{{username}}", eventData.Username ?? "")
            .Replace("{{peer_addr}}", eventData.PeerAddr ?? "")
            .Replace("{{topic}}", eventData.Topic ?? "")
            .Replace("{{payload}}", eventData.Payload ?? "")
            .Replace("{{error_reason}}", eventData.ErrorReason ?? "")
            .Replace("{{timestamp}}", eventData.Timestamp.ToString("o"));

        return result;
    }

    private static System.Net.Http.HttpMethod GetHttpMethod(Models.HttpMethod method)
    {
        return method switch
        {
            Models.HttpMethod.GET => System.Net.Http.HttpMethod.Get,
            Models.HttpMethod.POST => System.Net.Http.HttpMethod.Post,
            Models.HttpMethod.PUT => System.Net.Http.HttpMethod.Put,
            Models.HttpMethod.PATCH => System.Net.Http.HttpMethod.Patch,
            Models.HttpMethod.DELETE => System.Net.Http.HttpMethod.Delete,
            _ => System.Net.Http.HttpMethod.Post
        };
    }
}
