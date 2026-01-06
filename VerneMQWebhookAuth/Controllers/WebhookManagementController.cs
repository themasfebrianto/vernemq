using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Models;
using System.Text.Json;
using System.ComponentModel.DataAnnotations;
using System.Net.Http;

namespace VerneMQWebhookAuth.Controllers;

/// <summary>
/// Comprehensive webhook management API controller
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class WebhookManagementController : ControllerBase
{
    private readonly WebhookDbContext _context;
    private readonly ILogger<WebhookManagementController> _logger;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IHubContext<VerneMQWebhookAuth.Hubs.WebhookHub> _hubContext;

    public WebhookManagementController(
        WebhookDbContext context,
        ILogger<WebhookManagementController> logger,
        IHttpClientFactory httpClientFactory,
        IHubContext<VerneMQWebhookAuth.Hubs.WebhookHub> hubContext)
    {
        _context = context;
        _logger = logger;
        _httpClientFactory = httpClientFactory;
        _hubContext = hubContext;
    }

    #region Webhook CRUD Operations

    /// <summary>
    /// Get all webhooks with optional filtering
    /// </summary>
    /// <param name="activeOnly">Filter to active webhooks only</param>
    /// <param name="search">Search term for name/description</param>
    /// <param name="page">Page number for pagination</param>
    /// <param name="pageSize">Page size for pagination</param>
    [HttpGet]
    public async Task<ActionResult<PagedResult<WebhookDto>>> GetWebhooks(
        [FromQuery] bool activeOnly = false,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10)
    {
        try
        {
            var query = _context.Webhooks.AsQueryable();

            if (activeOnly)
            {
                query = query.Where(w => w.IsActive);
            }

            if (!string.IsNullOrEmpty(search))
            {
                query = query.Where(w => w.Name.Contains(search) || w.Description.Contains(search));
            }

            var totalCount = await query.CountAsync();
            var webhooks = await query
                .OrderBy(w => w.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(w => new WebhookDto
                {
                    Id = w.Id,
                    Name = w.Name,
                    Description = w.Description,
                    Url = w.Url,
                    HttpMethod = w.HttpMethod.ToString(),
                    ContentType = w.ContentType,
                    IsActive = w.IsActive,
                    TimeoutSeconds = w.TimeoutSeconds,
                    RetryCount = w.RetryCount,
                    RetryDelaySeconds = w.RetryDelaySeconds,
                    CreatedAt = w.CreatedAt,
                    UpdatedAt = w.UpdatedAt,
                    CreatedBy = w.CreatedByUser != null ? w.CreatedByUser.Username : null
                })
                .ToListAsync();

            var result = new PagedResult<WebhookDto>
            {
                Items = webhooks,
                TotalCount = totalCount,
                Page = page,
                PageSize = pageSize,
                TotalPages = (int)Math.Ceiling((double)totalCount / pageSize)
            };

            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving webhooks");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Get webhook by ID
    /// </summary>
    /// <param name="id">Webhook ID</param>
    [HttpGet("{id}")]
    public async Task<ActionResult<WebhookDetailDto>> GetWebhook(int id)
    {
        try
        {
            var webhook = await _context.Webhooks
                .Include(w => w.CreatedByUser)
                .Include(w => w.ExecutionLogs.OrderByDescending(l => l.ExecutionTime).Take(10))
                .FirstOrDefaultAsync(w => w.Id == id);

            if (webhook == null)
            {
                return NotFound(new { error = "Webhook not found" });
            }

            var result = new WebhookDetailDto
            {
                Id = webhook.Id,
                Name = webhook.Name,
                Description = webhook.Description,
                Url = webhook.Url,
                HttpMethod = webhook.HttpMethod.ToString(),
                ContentType = webhook.ContentType,
                Headers = !string.IsNullOrEmpty(webhook.Headers) ? JsonSerializer.Deserialize<Dictionary<string, string>>(webhook.Headers) : null,
                PayloadTemplate = webhook.PayloadTemplate,
                AuthenticationType = webhook.AuthenticationType,
                IsActive = webhook.IsActive,
                TimeoutSeconds = webhook.TimeoutSeconds,
                RetryCount = webhook.RetryCount,
                RetryDelaySeconds = webhook.RetryDelaySeconds,
                CreatedAt = webhook.CreatedAt,
                UpdatedAt = webhook.UpdatedAt,
                CreatedBy = webhook.CreatedByUser?.Username,
                RecentExecutions = webhook.ExecutionLogs.Select(l => new ExecutionLogDto
                {
                    Id = l.Id,
                    ExecutionTime = l.ExecutionTime,
                    Status = l.Status.ToString(),
                    ResponseTimeMs = l.ResponseTimeMs,
                    ErrorMessage = l.ErrorMessage,
                    TriggeredBy = l.TriggeredBy
                }).ToList()
            };

            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving webhook {WebhookId}", id);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Create new webhook
    /// </summary>
    /// <param name="request">Webhook creation request</param>
    [HttpPost]
    public async Task<ActionResult<WebhookDto>> CreateWebhook([FromBody] CreateWebhookRequest request)
    {
        try
        {
            // Validate URL
            if (!Uri.TryCreate(request.Url, UriKind.Absolute, out var uriResult))
            {
                return BadRequest(new { error = "Invalid URL format" });
            }

            // Validate HTTP method
            if (!Enum.TryParse<VerneMQWebhookAuth.Models.HttpMethod>(request.HttpMethod, true, out var httpMethod))
            {
                return BadRequest(new { error = "Invalid HTTP method" });
            }

            // Check for duplicate webhook name
            if (await _context.Webhooks.AnyAsync(w => w.Name == request.Name))
            {
                return Conflict(new { error = "Webhook name already exists" });
            }

            var webhook = new Webhook
            {
                Name = request.Name,
                Description = request.Description,
                Url = request.Url,
                HttpMethod = httpMethod,
                ContentType = request.ContentType,
                Headers = request.Headers != null ? JsonSerializer.Serialize(request.Headers) : null,
                PayloadTemplate = request.PayloadTemplate,
                AuthenticationType = request.AuthenticationType,
                AuthenticationValue = request.AuthenticationValue, // Note: Should be encrypted in production
                TimeoutSeconds = request.TimeoutSeconds,
                RetryCount = request.RetryCount,
                RetryDelaySeconds = request.RetryDelaySeconds,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
                CreatedByUserId = 1 // TODO: Get from authenticated user
            };

            _context.Webhooks.Add(webhook);
            await _context.SaveChangesAsync();

            var result = new WebhookDto
            {
                Id = webhook.Id,
                Name = webhook.Name,
                Description = webhook.Description,
                Url = webhook.Url,
                HttpMethod = webhook.HttpMethod.ToString(),
                ContentType = webhook.ContentType,
                IsActive = webhook.IsActive,
                TimeoutSeconds = webhook.TimeoutSeconds,
                RetryCount = webhook.RetryCount,
                RetryDelaySeconds = webhook.RetryDelaySeconds,
                CreatedAt = webhook.CreatedAt,
                UpdatedAt = webhook.UpdatedAt,
                CreatedBy = "admin"
            };

            return CreatedAtAction(nameof(GetWebhook), new { id = webhook.Id }, result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating webhook");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Update webhook
    /// </summary>
    /// <param name="id">Webhook ID</param>
    /// <param name="request">Webhook update request</param>
    [HttpPut("{id}")]
    public async Task<ActionResult<WebhookDto>> UpdateWebhook(int id, [FromBody] UpdateWebhookRequest request)
    {
        try
        {
            var webhook = await _context.Webhooks.FindAsync(id);
            if (webhook == null)
            {
                return NotFound(new { error = "Webhook not found" });
            }

            // Validate URL if provided
            if (!string.IsNullOrEmpty(request.Url) && !Uri.TryCreate(request.Url, UriKind.Absolute, out var uriResult))
            {
                return BadRequest(new { error = "Invalid URL format" });
            }

            // Validate HTTP method if provided
            VerneMQWebhookAuth.Models.HttpMethod? httpMethod = null;
            if (!string.IsNullOrEmpty(request.HttpMethod))
            {
                if (!Enum.TryParse<VerneMQWebhookAuth.Models.HttpMethod>(request.HttpMethod, true, out var parsedMethod))
                {
                    return BadRequest(new { error = "Invalid HTTP method" });
                }
                httpMethod = parsedMethod;
            }

            // Update properties if provided
            if (!string.IsNullOrEmpty(request.Name) && request.Name != webhook.Name)
            {
                // Check for duplicate name
                if (await _context.Webhooks.AnyAsync(w => w.Name == request.Name && w.Id != id))
                {
                    return Conflict(new { error = "Webhook name already exists" });
                }
                webhook.Name = request.Name;
            }

            if (!string.IsNullOrEmpty(request.Description))
                webhook.Description = request.Description;

            if (!string.IsNullOrEmpty(request.Url))
                webhook.Url = request.Url;

            if (httpMethod.HasValue)
                webhook.HttpMethod = httpMethod.Value;

            if (!string.IsNullOrEmpty(request.ContentType))
                webhook.ContentType = request.ContentType;

            if (request.Headers != null)
                webhook.Headers = JsonSerializer.Serialize(request.Headers);

            if (request.PayloadTemplate != null)
                webhook.PayloadTemplate = request.PayloadTemplate;

            if (request.AuthenticationType != null)
                webhook.AuthenticationType = request.AuthenticationType;

            if (request.AuthenticationValue != null)
                webhook.AuthenticationValue = request.AuthenticationValue;

            if (request.TimeoutSeconds.HasValue)
                webhook.TimeoutSeconds = request.TimeoutSeconds.Value;

            if (request.RetryCount.HasValue)
                webhook.RetryCount = request.RetryCount.Value;

            if (request.RetryDelaySeconds.HasValue)
                webhook.RetryDelaySeconds = request.RetryDelaySeconds.Value;

            if (request.IsActive.HasValue)
                webhook.IsActive = request.IsActive.Value;

            webhook.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            var result = new WebhookDto
            {
                Id = webhook.Id,
                Name = webhook.Name,
                Description = webhook.Description,
                Url = webhook.Url,
                HttpMethod = webhook.HttpMethod.ToString(),
                ContentType = webhook.ContentType,
                IsActive = webhook.IsActive,
                TimeoutSeconds = webhook.TimeoutSeconds,
                RetryCount = webhook.RetryCount,
                RetryDelaySeconds = webhook.RetryDelaySeconds,
                CreatedAt = webhook.CreatedAt,
                UpdatedAt = webhook.UpdatedAt,
                CreatedBy = "admin"
            };

            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating webhook {WebhookId}", id);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Delete webhook
    /// </summary>
    /// <param name="id">Webhook ID</param>
    [HttpDelete("{id}")]
    public async Task<ActionResult> DeleteWebhook(int id)
    {
        try
        {
            var webhook = await _context.Webhooks.FindAsync(id);
            if (webhook == null)
            {
                return NotFound(new { error = "Webhook not found" });
            }

            _context.Webhooks.Remove(webhook);
            await _context.SaveChangesAsync();

            return NoContent();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting webhook {WebhookId}", id);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    #endregion

    #region Webhook Execution

    /// <summary>
    /// Test webhook execution
    /// </summary>
    /// <param name="id">Webhook ID</param>
    /// <param name="request">Test request with optional payload</param>
    [HttpPost("{id}/test")]
    public async Task<ActionResult<TestWebhookResult>> TestWebhook(int id, [FromBody] TestWebhookRequest? request = null)
    {
        try
        {
            var webhook = await _context.Webhooks.FindAsync(id);
            if (webhook == null)
            {
                return NotFound(new { error = "Webhook not found" });
            }

            if (!webhook.IsActive)
            {
                return BadRequest(new { error = "Webhook is not active" });
            }

            var executionLog = new WebhookExecutionLog
            {
                WebhookId = webhook.Id,
                ExecutionTime = DateTime.UtcNow,
                Status = ExecutionStatus.Pending,
                RetryAttempt = 0,
                TriggeredBy = "Manual Test",
                UserId = 1 // TODO: Get from authenticated user
            };

            _context.WebhookExecutionLogs.Add(executionLog);
            await _context.SaveChangesAsync();

            // Execute webhook asynchronously and notify clients
            _ = Task.Run(async () => await ExecuteWebhookWithRetry(webhook, executionLog, request));

            return Ok(new TestWebhookResult
            {
                ExecutionLogId = executionLog.Id,
                Status = "started",
                Message = "Webhook test execution started"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error testing webhook {WebhookId}", id);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Execute webhook with retry logic
    /// </summary>
    private async Task ExecuteWebhookWithRetry(Webhook webhook, WebhookExecutionLog executionLog, TestWebhookRequest? testRequest)
    {
        var httpClient = _httpClientFactory.CreateClient();
        httpClient.Timeout = TimeSpan.FromSeconds(webhook.TimeoutSeconds);

        var finalStatus = ExecutionStatus.Failed;
        string? finalErrorMessage = null;

        for (int attempt = 0; attempt <= webhook.RetryCount; attempt++)
        {
            try
            {
                executionLog.RetryAttempt = attempt;
                executionLog.Status = ExecutionStatus.Pending;
                await _context.SaveChangesAsync();

                // Notify clients about execution start
                await _hubContext.Clients.Group($"webhook_{webhook.Id}")
                    .SendAsync("ExecutionUpdate", new
                    {
                        ExecutionLogId = executionLog.Id,
                        Status = "started",
                        Attempt = attempt + 1,
                        TotalAttempts = webhook.RetryCount + 1
                    });

                var stopwatch = System.Diagnostics.Stopwatch.StartNew();

                // Prepare request
                var request = new HttpRequestMessage((System.Net.Http.HttpMethod)Enum.Parse(typeof(VerneMQWebhookAuth.Models.HttpMethod), webhook.HttpMethod.ToString()), webhook.Url);

                // Set content type and headers
                if (!string.IsNullOrEmpty(webhook.ContentType))
                {
                    request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(webhook.ContentType);
                }

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
                if (!string.IsNullOrEmpty(webhook.AuthenticationType) && !string.IsNullOrEmpty(webhook.AuthenticationValue))
                {
                    switch (webhook.AuthenticationType.ToLower())
                    {
                        case "bearer":
                            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", webhook.AuthenticationValue);
                            break;
                        case "basic":
                            var credentials = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(webhook.AuthenticationValue));
                            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", credentials);
                            break;
                        case "apikey":
                            request.Headers.TryAddWithoutValidation("X-API-Key", webhook.AuthenticationValue);
                            break;
                    }
                }

                // Set payload
                string payload = testRequest?.Payload ?? webhook.PayloadTemplate ?? "{}";
                if (!string.IsNullOrEmpty(payload) && webhook.HttpMethod != VerneMQWebhookAuth.Models.HttpMethod.GET)
                {
                    request.Content = new StringContent(payload, System.Text.Encoding.UTF8, webhook.ContentType ?? "application/json");
                }

                // Execute request
                var response = await httpClient.SendAsync(request);
                stopwatch.Stop();

                // Update execution log
                executionLog.Status = response.IsSuccessStatusCode ? ExecutionStatus.Success : ExecutionStatus.Failed;
                executionLog.ResponseStatusCode = (int)response.StatusCode;
                executionLog.ResponseTimeMs = stopwatch.ElapsedMilliseconds;

                var responseContent = await response.Content.ReadAsStringAsync();
                executionLog.ResponsePayload = responseContent;

                var responseHeaders = response.Headers.Concat(response.Content.Headers)
                    .ToDictionary(h => h.Key, h => string.Join(", ", h.Value));
                executionLog.ResponseHeaders = JsonSerializer.Serialize(responseHeaders);

                await _context.SaveChangesAsync();

                // Notify clients about execution completion
                await _hubContext.Clients.Group($"webhook_{webhook.Id}")
                    .SendAsync("ExecutionUpdate", new
                    {
                        ExecutionLogId = executionLog.Id,
                        Status = executionLog.Status.ToString().ToLower(),
                        ResponseStatusCode = executionLog.ResponseStatusCode,
                        ResponseTimeMs = executionLog.ResponseTimeMs,
                        Attempt = attempt + 1
                    });

                if (response.IsSuccessStatusCode)
                {
                    finalStatus = ExecutionStatus.Success;
                    break;
                }
                else
                {
                    finalErrorMessage = $"HTTP {response.StatusCode}: {responseContent}";
                }
            }
            catch (TaskCanceledException)
            {
                finalStatus = ExecutionStatus.Timeout;
                finalErrorMessage = "Request timed out";
                executionLog.Status = ExecutionStatus.Timeout;
            }
            catch (Exception ex)
            {
                finalStatus = ExecutionStatus.Failed;
                finalErrorMessage = ex.Message;
                executionLog.Status = ExecutionStatus.Failed;
                executionLog.ErrorMessage = ex.Message;
                executionLog.StackTrace = ex.StackTrace;
            }

            // Wait before retry (except on last attempt)
            if (attempt < webhook.RetryCount)
            {
                await Task.Delay(TimeSpan.FromSeconds(webhook.RetryDelaySeconds));
            }
        }

        if (finalStatus == ExecutionStatus.Failed)
        {
            executionLog.Status = finalStatus;
            executionLog.ErrorMessage = finalErrorMessage;
            await _context.SaveChangesAsync();
        }

        // Notify clients about final status
        await _hubContext.Clients.Group($"webhook_{webhook.Id}")
            .SendAsync("ExecutionUpdate", new
            {
                ExecutionLogId = executionLog.Id,
                Status = finalStatus.ToString().ToLower(),
                Completed = true,
                FinalAttempt = true
            });
    }

    #endregion

    #region Execution Logs

    /// <summary>
    /// Get execution logs for a webhook
    /// </summary>
    /// <param name="id">Webhook ID</param>
    /// <param name="page">Page number</param>
    /// <param name="pageSize">Page size</param>
    /// <param name="status">Filter by status</param>
    /// <param name="fromDate">Filter from date</param>
    /// <param name="toDate">Filter to date</param>
    [HttpGet("{id}/logs")]
    public async Task<ActionResult<PagedResult<ExecutionLogDto>>> GetExecutionLogs(
        int id,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            var webhook = await _context.Webhooks.FindAsync(id);
            if (webhook == null)
            {
                return NotFound(new { error = "Webhook not found" });
            }

            var query = _context.WebhookExecutionLogs.Where(l => l.WebhookId == id);

            if (!string.IsNullOrEmpty(status) && Enum.TryParse<ExecutionStatus>(status, true, out var statusEnum))
            {
                query = query.Where(l => l.Status == statusEnum);
            }

            if (fromDate.HasValue)
            {
                query = query.Where(l => l.ExecutionTime >= fromDate.Value);
            }

            if (toDate.HasValue)
            {
                query = query.Where(l => l.ExecutionTime <= toDate.Value);
            }

            var totalCount = await query.CountAsync();
            var logs = await query
                .OrderByDescending(l => l.ExecutionTime)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(l => new ExecutionLogDto
                {
                    Id = l.Id,
                    ExecutionTime = l.ExecutionTime,
                    Status = l.Status.ToString(),
                    ResponseStatusCode = l.ResponseStatusCode,
                    ResponseTimeMs = l.ResponseTimeMs,
                    ErrorMessage = l.ErrorMessage,
                    RetryAttempt = l.RetryAttempt,
                    TriggeredBy = l.TriggeredBy
                })
                .ToListAsync();

            var result = new PagedResult<ExecutionLogDto>
            {
                Items = logs,
                TotalCount = totalCount,
                Page = page,
                PageSize = pageSize,
                TotalPages = (int)Math.Ceiling((double)totalCount / pageSize)
            };

            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving execution logs for webhook {WebhookId}", id);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    #endregion
}

// DTOs and Request/Response classes
public class WebhookDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Url { get; set; } = string.Empty;
    public string HttpMethod { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public bool IsActive { get; set; }
    public int TimeoutSeconds { get; set; }
    public int RetryCount { get; set; }
    public int RetryDelaySeconds { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public string? CreatedBy { get; set; }
}

public class WebhookDetailDto : WebhookDto
{
    public Dictionary<string, string>? Headers { get; set; }
    public string? PayloadTemplate { get; set; }
    public string? AuthenticationType { get; set; }
    public List<ExecutionLogDto> RecentExecutions { get; set; } = new();
}

public class ExecutionLogDto
{
    public int Id { get; set; }
    public DateTime ExecutionTime { get; set; }
    public string Status { get; set; } = string.Empty;
    public int? ResponseStatusCode { get; set; }
    public long? ResponseTimeMs { get; set; }
    public string? ErrorMessage { get; set; }
    public int RetryAttempt { get; set; }
    public string? TriggeredBy { get; set; }
}

public class PagedResult<T>
{
    public List<T> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalPages { get; set; }
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
}

public class CreateWebhookRequest
{
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [MaxLength(500)]
    public string Description { get; set; } = string.Empty;

    [Required]
    [MaxLength(1000)]
    public string Url { get; set; } = string.Empty;

    [Required]
    public string HttpMethod { get; set; } = "POST";

    [MaxLength(100)]
    public string? ContentType { get; set; } = "application/json";

    public Dictionary<string, string>? Headers { get; set; }
    public string? PayloadTemplate { get; set; }
    public string? AuthenticationType { get; set; }
    public string? AuthenticationValue { get; set; }

    [Range(1, 300)]
    public int TimeoutSeconds { get; set; } = 30;

    [Range(0, 10)]
    public int RetryCount { get; set; } = 3;

    [Range(1, 60)]
    public int RetryDelaySeconds { get; set; } = 5;
}

public class UpdateWebhookRequest
{
    [MaxLength(200)]
    public string? Name { get; set; }

    [MaxLength(500)]
    public string? Description { get; set; }

    [MaxLength(1000)]
    public string? Url { get; set; }

    public string? HttpMethod { get; set; }

    [MaxLength(100)]
    public string? ContentType { get; set; }

    public Dictionary<string, string>? Headers { get; set; }
    public string? PayloadTemplate { get; set; }
    public string? AuthenticationType { get; set; }
    public string? AuthenticationValue { get; set; }

    [Range(1, 300)]
    public int? TimeoutSeconds { get; set; }

    [Range(0, 10)]
    public int? RetryCount { get; set; }

    [Range(1, 60)]
    public int? RetryDelaySeconds { get; set; }

    public bool? IsActive { get; set; }
}

public class TestWebhookRequest
{
    public string? Payload { get; set; }
    public Dictionary<string, string>? Headers { get; set; }
}

public class TestWebhookResult
{
    public int ExecutionLogId { get; set; }
    public string Status { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}