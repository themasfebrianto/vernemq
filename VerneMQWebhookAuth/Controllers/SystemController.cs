using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Newtonsoft.Json;
using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Models;
using System.Text;
using System.Security.Cryptography;
using System.Diagnostics;

namespace VerneMQWebhookAuth.Controllers;

/// <summary>
/// System management and utilities controller
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class SystemController : ControllerBase
{
    private readonly WebhookDbContext _context;
    private readonly ILogger<SystemController> _logger;
    private readonly IConfiguration _configuration;
    private readonly IWebHostEnvironment _environment;
    
    // Static field to track application start time (reliable in Docker)
    private static readonly DateTime AppStartTime = DateTime.UtcNow;

    public SystemController(
        WebhookDbContext context,
        ILogger<SystemController> logger,
        IConfiguration configuration,
        IWebHostEnvironment environment)
    {
        _context = context;
        _logger = logger;
        _configuration = configuration;
        _environment = environment;
    }

    /// <summary>
    /// Get system statistics and health information
    /// </summary>
    [HttpGet("statistics")]
    public async Task<ActionResult<SystemStatisticsDto>> GetStatistics()
    {
        try
        {
            var stats = new SystemStatisticsDto
            {
                TotalWebhooks = await _context.Webhooks.CountAsync(),
                ActiveWebhooks = await _context.Webhooks.CountAsync(w => w.IsActive),
                InactiveWebhooks = await _context.Webhooks.CountAsync(w => !w.IsActive),
                TotalExecutions = await _context.WebhookExecutionLogs.CountAsync(),
                SuccessfulExecutions = await _context.WebhookExecutionLogs.CountAsync(l => l.Status == ExecutionStatus.Success),
                FailedExecutions = await _context.WebhookExecutionLogs.CountAsync(l => l.Status == ExecutionStatus.Failed),
                TimeoutExecutions = await _context.WebhookExecutionLogs.CountAsync(l => l.Status == ExecutionStatus.Timeout),
                PendingExecutions = await _context.WebhookExecutionLogs.CountAsync(l => l.Status == ExecutionStatus.Pending),
                TotalUsers = await _context.Users.CountAsync(),
                ActiveUsers = await _context.Users.CountAsync(u => u.IsActive),
                DatabaseSizeBytes = GetDatabaseSize(),
                LogRetentionDays = int.Parse(_configuration["WebhookSettings:LogRetentionDays"] ?? "30"),
                MaxConcurrentWebhooks = int.Parse(_configuration["WebhookSettings:MaxConcurrentWebhooks"] ?? "10"),
                Uptime = DateTime.UtcNow - AppStartTime,
                LastExecution = (await _context.WebhookExecutionLogs.OrderByDescending(l => l.ExecutionTime).FirstOrDefaultAsync())?.ExecutionTime,
                SystemInfo = new SystemInfoDto
                {
                    MachineName = Environment.MachineName,
                    OSVersion = Environment.OSVersion.ToString(),
                    ProcessorCount = Environment.ProcessorCount,
                    WorkingSet = Environment.WorkingSet,
                    FrameworkVersion = Environment.Version.ToString(),
                    EnvironmentName = _environment.EnvironmentName
                }
            };

            // Calculate success rate
            if (stats.TotalExecutions > 0)
            {
                stats.SuccessRate = Math.Round((double)stats.SuccessfulExecutions / stats.TotalExecutions * 100, 2);
            }

            // Calculate average response time (handle empty collection)
            var logsWithResponseTime = await _context.WebhookExecutionLogs
                .Where(l => l.ResponseTimeMs.HasValue)
                .Select(l => (double)l.ResponseTimeMs!)
                .ToListAsync();
            stats.AverageResponseTimeMs = logsWithResponseTime.Count > 0 
                ? Math.Round(logsWithResponseTime.Average(), 2) 
                : 0;

            return Ok(stats);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting system statistics");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Get system health check information
    /// </summary>
    [HttpGet("health")]
    public async Task<ActionResult<SystemHealthDto>> GetHealth()
    {
        try
        {
            var health = new SystemHealthDto
            {
                Status = "healthy",
                Timestamp = DateTime.UtcNow,
                Version = "1.0.0",
                Environment = _environment.EnvironmentName
            };

            // Check database connectivity
            try
            {
                await _context.Database.CanConnectAsync();
                health.Database = new HealthCheckDto { Status = "healthy", Message = "Database connection successful" };
            }
            catch (Exception ex)
            {
                health.Database = new HealthCheckDto { Status = "unhealthy", Message = $"Database connection failed: {ex.Message}" };
                health.Status = "unhealthy";
            }

            // Check disk space
            var totalBytes = 0L;
            var freeBytes = 0L;
            try
            {
                var driveInfo = new DriveInfo(Path.GetPathRoot(_environment.ContentRootPath) ?? "C:\\");
                totalBytes = driveInfo.TotalSize;
                freeBytes = driveInfo.AvailableFreeSpace;
                var usagePercent = (double)(totalBytes - freeBytes) / totalBytes * 100;

                health.DiskSpace = new HealthCheckDto
                {
                    Status = usagePercent > 90 ? "unhealthy" : usagePercent > 80 ? "degraded" : "healthy",
                    Message = $"Disk usage: {usagePercent:F1}% ({FormatBytes(freeBytes)} free of {FormatBytes(totalBytes)})"
                };
            }
            catch (Exception ex)
            {
                health.DiskSpace = new HealthCheckDto { Status = "unknown", Message = $"Unable to check disk space: {ex.Message}" };
            }

            // Check memory usage
            try
            {
                var workingSet = Environment.WorkingSet;
                var gcMemory = GC.GetTotalMemory(false);
                health.Memory = new HealthCheckDto
                {
                    Status = "healthy",
                    Message = $"Working Set: {FormatBytes(workingSet)}, GC Memory: {FormatBytes(gcMemory)}"
                };
            }
            catch (Exception ex)
            {
                health.Memory = new HealthCheckDto { Status = "unknown", Message = $"Unable to check memory: {ex.Message}" };
            }

            // Check configuration
            health.Configuration = new HealthCheckDto
            {
                Status = "healthy",
                Message = "Configuration loaded successfully"
            };

            return Ok(health);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting system health");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Get VerneMQ broker metrics
    /// </summary>
    [HttpGet("vernemq-metrics")]
    public async Task<ActionResult<VerneMQMetricsDto>> GetVerneMQMetrics()
    {
        var metrics = new VerneMQMetricsDto
        {
            Timestamp = DateTime.UtcNow,
            IsOnline = false
        };

        try
        {
            // VerneMQ status endpoint - inside Docker network use container name
            // From outside, use localhost:8888
            var vernemqHost = Environment.GetEnvironmentVariable("VERNEMQ_HOST") ?? "vernemq";
            var vernemqPort = Environment.GetEnvironmentVariable("VERNEMQ_METRICS_PORT") ?? "8888";
            var statusUrl = $"http://{vernemqHost}:{vernemqPort}/status.json";

            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            
            try
            {
                var response = await httpClient.GetAsync(statusUrl);
                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync();
                    var status = JsonConvert.DeserializeObject<dynamic>(json);
                    
                    metrics.IsOnline = true;
                    
                    // Parse VerneMQ status response
                    if (status != null)
                    {
                        // Try to get metrics from the response
                        try { metrics.ActiveConnections = (int?)status.num_online ?? 0; } catch { }
                        try { metrics.TotalSubscriptions = (int?)status.num_subscriptions ?? 0; } catch { }
                        try { metrics.MessagesReceived = (long?)status.router_matches_local ?? 0; } catch { }
                        try { metrics.MessagesSent = (long?)status.router_matches_remote ?? 0; } catch { }
                        try { metrics.BytesReceived = (long?)status.bytes_received ?? 0; } catch { }
                        try { metrics.BytesSent = (long?)status.bytes_sent ?? 0; } catch { }
                    }
                }
            }
            catch (HttpRequestException)
            {
                // VerneMQ might not be accessible, try alternative endpoint
                _logger.LogWarning("Could not connect to VerneMQ status endpoint at {Url}", statusUrl);
            }

            // Also try the Prometheus metrics endpoint for more detailed data
            var metricsUrl = $"http://{vernemqHost}:{vernemqPort}/metrics";
            try
            {
                var metricsResponse = await httpClient.GetAsync(metricsUrl);
                if (metricsResponse.IsSuccessStatusCode)
                {
                    metrics.IsOnline = true;
                    var metricsText = await metricsResponse.Content.ReadAsStringAsync();
                    
                    // Parse VerneMQ Prometheus metrics (actual metric names)
                    var connReceived = ParsePrometheusMetric(metricsText, "vernemq_mqtt_connect_received");
                    if (connReceived > 0) metrics.ActiveConnections = (int)connReceived;
                    
                    var publishReceived = ParsePrometheusMetric(metricsText, "vernemq_mqtt_publish_received");
                    var publishSent = ParsePrometheusMetric(metricsText, "vernemq_mqtt_publish_sent");
                    
                    if (publishReceived > 0) metrics.MessagesReceived = publishReceived;
                    if (publishSent > 0) metrics.MessagesSent = publishSent;
                    
                    // Get subscriptions
                    var subscriptions = ParsePrometheusMetric(metricsText, "vernemq_mqtt_subscribe_received");
                    if (subscriptions > 0) metrics.TotalSubscriptions = (int)subscriptions;
                    
                    // Calculate messages per minute
                    metrics.MessagesPerMinute = (metrics.MessagesReceived + metrics.MessagesSent) / 
                        Math.Max(1, (DateTime.UtcNow - Process.GetCurrentProcess().StartTime).TotalMinutes);
                }
            }
            catch (HttpRequestException ex)
            {
                _logger.LogWarning("Could not fetch VerneMQ Prometheus metrics: {Message}", ex.Message);
            }

            return Ok(metrics);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting VerneMQ metrics");
            metrics.Error = ex.Message;
            return Ok(metrics);
        }
    }

    private static long ParsePrometheusMetric(string metricsText, string metricName)
    {
        try
        {
            var lines = metricsText.Split('\n');
            foreach (var line in lines)
            {
                if (line.StartsWith(metricName) && !line.StartsWith("#"))
                {
                    var parts = line.Split(' ');
                    if (parts.Length >= 2 && double.TryParse(parts[^1], out var value))
                    {
                        return (long)value;
                    }
                }
            }
        }
        catch { }
        return 0;
    }

    /// <summary>
    /// Export system data for backup
    /// </summary>
    [HttpPost("backup")]
    public async Task<ActionResult> CreateBackup()
    {
        try
        {
            var backup = new SystemBackupDto
            {
                Timestamp = DateTime.UtcNow,
                Version = "1.0.0",
                Database = await ExportDatabaseData(),
                Configuration = ExportConfiguration(),
                Metadata = new BackupMetadataDto
                {
                    TotalWebhooks = await _context.Webhooks.CountAsync(),
                    TotalExecutions = await _context.WebhookExecutionLogs.CountAsync(),
                    TotalUsers = await _context.Users.CountAsync()
                }
            };

            var json = JsonConvert.SerializeObject(backup, Formatting.Indented);
            var fileName = $"webhook_backup_{DateTime.UtcNow:yyyyMMdd_HHmmss}.json";
            var filePath = Path.Combine(_environment.ContentRootPath, "backups", fileName);

            Directory.CreateDirectory(Path.GetDirectoryName(filePath)!);
            await System.IO.File.WriteAllTextAsync(filePath, json);

            _logger.LogInformation("System backup created: {FilePath}", filePath);

            return Ok(new { message = "Backup created successfully", fileName });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating system backup");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Import system data from backup
    /// </summary>
    [HttpPost("restore")]
    [RequestSizeLimit(50 * 1024 * 1024)] // 50MB limit
    public async Task<ActionResult> RestoreFromBackup([FromBody] SystemBackupDto backup)
    {
        try
        {
            // Validate backup format
            if (backup.Version == null || backup.Database == null)
            {
                return BadRequest(new { error = "Invalid backup format" });
            }

            // Create backup of current state
            var currentBackup = await CreateBackup();

            // Import data
            await ImportDatabaseData(backup.Database);

            _logger.LogInformation("System restore completed from backup timestamp: {Timestamp}", backup.Timestamp);

            return Ok(new { message = "System restored successfully", backupTimestamp = backup.Timestamp });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error restoring system from backup");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Clean up old execution logs based on retention policy
    /// </summary>
    [HttpPost("cleanup")]
    public async Task<ActionResult> CleanupOldData()
    {
        try
        {
            var retentionDays = int.Parse(_configuration["WebhookSettings:LogRetentionDays"] ?? "30");
            var cutoffDate = DateTime.UtcNow.AddDays(-retentionDays);

            var deletedCount = await _context.WebhookExecutionLogs
                .Where(l => l.ExecutionTime < cutoffDate)
                .ExecuteDeleteAsync();

            _logger.LogInformation("Cleaned up {Count} old execution logs older than {CutoffDate}", deletedCount, cutoffDate);

            return Ok(new { message = "Cleanup completed", deletedCount, retentionDays });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during cleanup");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Generate API key for a user
    /// </summary>
    [HttpPost("generate-api-key")]
    public async Task<ActionResult<ApiKeyResult>> GenerateApiKey([FromBody] GenerateApiKeyRequest request)
    {
        try
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == request.UserId);
            if (user == null)
            {
                return NotFound(new { error = "User not found" });
            }

            var apiKey = GenerateSecureApiKey();
            user.ApiKey = apiKey;
            await _context.SaveChangesAsync();

            return Ok(new ApiKeyResult { ApiKey = apiKey, UserId = user.Id, Username = user.Username });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error generating API key for user {UserId}", request.UserId);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    /// <summary>
    /// Validate API key
    /// </summary>
    [HttpPost("validate-api-key")]
    public async Task<ActionResult<ApiKeyValidationResult>> ValidateApiKey([FromBody] ValidateApiKeyRequest request)
    {
        try
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.ApiKey == request.ApiKey && u.IsActive);
            if (user == null)
            {
                return Ok(new ApiKeyValidationResult { Valid = false, Message = "Invalid or inactive API key" });
            }

            return Ok(new ApiKeyValidationResult
            {
                Valid = true,
                UserId = user.Id,
                Username = user.Username,
                Role = user.Role.ToString(),
                Message = "API key is valid"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating API key");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    #region Private Methods

    private long GetDatabaseSize()
    {
        try
        {
            var connectionString = _configuration.GetConnectionString("DefaultConnection");
            if (connectionString?.Contains("Data Source=") == true)
            {
                var dbPath = connectionString.Split('=')[1];
                if (System.IO.File.Exists(dbPath))
                {
                    return new FileInfo(dbPath).Length;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Unable to get database size");
        }
        return 0;
    }

    private string FormatBytes(long bytes)
    {
        string[] sizes = { "B", "KB", "MB", "GB", "TB" };
        double len = bytes;
        int order = 0;
        while (len >= 1024 && order < sizes.Length - 1)
        {
            order++;
            len = len / 1024;
        }
        return $"{len:0.##} {sizes[order]}";
    }

    private async Task<DatabaseExportDto> ExportDatabaseData()
    {
        var webhooks = await _context.Webhooks
            .Include(w => w.CreatedByUser)
            .Include(w => w.ExecutionLogs)
            .ToListAsync();

        var users = await _context.Users.ToListAsync();
        var triggers = await _context.WebhookTriggers.ToListAsync();
        var configs = await _context.SystemConfigurations.ToListAsync();

        return new DatabaseExportDto
        {
            Webhooks = webhooks,
            Users = users,
            WebhookTriggers = triggers,
            SystemConfigurations = configs
        };
    }

    private async Task ImportDatabaseData(DatabaseExportDto data)
    {
        // Clear existing data
        await _context.WebhookExecutionLogs.ExecuteDeleteAsync();
        await _context.WebhookTriggers.ExecuteDeleteAsync();
        await _context.Webhooks.ExecuteDeleteAsync();
        await _context.Users.ExecuteDeleteAsync();
        await _context.SystemConfigurations.ExecuteDeleteAsync();

        // Import data
        _context.SystemConfigurations.AddRange(data.SystemConfigurations);
        _context.Users.AddRange(data.Users);
        _context.Webhooks.AddRange(data.Webhooks);
        _context.WebhookTriggers.AddRange(data.WebhookTriggers);

        await _context.SaveChangesAsync();
    }

    private Dictionary<string, string> ExportConfiguration()
    {
        return new Dictionary<string, string>
        {
            { "Environment", _environment.EnvironmentName },
            { "ConnectionString", _configuration.GetConnectionString("DefaultConnection") ?? "" },
            { "DefaultTimeoutSeconds", _configuration["WebhookSettings:DefaultTimeoutSeconds"] ?? "" },
            { "MaxConcurrentWebhooks", _configuration["WebhookSettings:MaxConcurrentWebhooks"] ?? "" },
            { "EnableRateLimiting", _configuration["WebhookSettings:EnableRateLimiting"] ?? "" },
            { "RateLimitPerMinute", _configuration["WebhookSettings:RateLimitPerMinute"] ?? "" },
            { "LogRetentionDays", _configuration["WebhookSettings:LogRetentionDays"] ?? "" },
            { "EnableHttpsOnly", _configuration["WebhookSettings:EnableHttpsOnly"] ?? "" }
        };
    }

    private string GenerateSecureApiKey()
    {
        using var rng = RandomNumberGenerator.Create();
        var bytes = new byte[32];
        rng.GetBytes(bytes);
        return Convert.ToBase64String(bytes).Replace("+", "").Replace("/", "").Replace("=", "");
    }

    #endregion
}

// DTOs for system management
public class SystemStatisticsDto
{
    public int TotalWebhooks { get; set; }
    public int ActiveWebhooks { get; set; }
    public int InactiveWebhooks { get; set; }
    public int TotalExecutions { get; set; }
    public int SuccessfulExecutions { get; set; }
    public int FailedExecutions { get; set; }
    public int TimeoutExecutions { get; set; }
    public int PendingExecutions { get; set; }
    public int TotalUsers { get; set; }
    public int ActiveUsers { get; set; }
    public long DatabaseSizeBytes { get; set; }
    public int LogRetentionDays { get; set; }
    public int MaxConcurrentWebhooks { get; set; }
    public TimeSpan Uptime { get; set; }
    public DateTime? LastExecution { get; set; }
    public double SuccessRate { get; set; }
    public double AverageResponseTimeMs { get; set; }
    public SystemInfoDto SystemInfo { get; set; } = new();
}

public class SystemInfoDto
{
    public string MachineName { get; set; } = string.Empty;
    public string OSVersion { get; set; } = string.Empty;
    public int ProcessorCount { get; set; }
    public long WorkingSet { get; set; }
    public string FrameworkVersion { get; set; } = string.Empty;
    public string EnvironmentName { get; set; } = string.Empty;
}

public class SystemHealthDto
{
    public string Status { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string Version { get; set; } = string.Empty;
    public string Environment { get; set; } = string.Empty;
    public HealthCheckDto Database { get; set; } = new();
    public HealthCheckDto DiskSpace { get; set; } = new();
    public HealthCheckDto Memory { get; set; } = new();
    public HealthCheckDto Configuration { get; set; } = new();
}

public class HealthCheckDto
{
    public string Status { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}

public class SystemBackupDto
{
    public DateTime Timestamp { get; set; }
    public string Version { get; set; } = string.Empty;
    public DatabaseExportDto Database { get; set; } = new();
    public Dictionary<string, string> Configuration { get; set; } = new();
    public BackupMetadataDto Metadata { get; set; } = new();
}

public class DatabaseExportDto
{
    public List<Models.User> Users { get; set; } = new();
    public List<Models.Webhook> Webhooks { get; set; } = new();
    public List<Models.WebhookExecutionLog> WebhookExecutionLogs { get; set; } = new();
    public List<Models.WebhookTrigger> WebhookTriggers { get; set; } = new();
    public List<Models.SystemConfiguration> SystemConfigurations { get; set; } = new();
}

public class BackupMetadataDto
{
    public int TotalWebhooks { get; set; }
    public int TotalExecutions { get; set; }
    public int TotalUsers { get; set; }
}

public class GenerateApiKeyRequest
{
    public int UserId { get; set; }
}

public class ApiKeyResult
{
    public string ApiKey { get; set; } = string.Empty;
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
}

public class ValidateApiKeyRequest
{
    public string ApiKey { get; set; } = string.Empty;
}

public class ApiKeyValidationResult
{
    public bool Valid { get; set; }
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}

public class VerneMQMetricsDto
{
    public DateTime Timestamp { get; set; }
    public bool IsOnline { get; set; }
    public int ActiveConnections { get; set; }
    public int TotalSubscriptions { get; set; }
    public long MessagesReceived { get; set; }
    public long MessagesSent { get; set; }
    public double MessagesPerMinute { get; set; }
    public long BytesReceived { get; set; }
    public long BytesSent { get; set; }
    public string? Error { get; set; }
}