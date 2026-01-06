using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace VerneMQWebhookAuth.Models;

/// <summary>
/// User entity for API authentication
/// </summary>
public class User
{
    [Key]
    public int Id { get; set; }

    [Required]
    [MaxLength(100)]
    public string Username { get; set; } = string.Empty;

    [Required]
    public string PasswordHash { get; set; } = string.Empty;

    [Required]
    [MaxLength(256)]
    public string Email { get; set; } = string.Empty;

    [Required]
    public string ApiKey { get; set; } = string.Empty;

    [Required]
    public UserRole Role { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastLoginAt { get; set; }
    public bool IsActive { get; set; } = true;

    public virtual ICollection<Webhook> Webhooks { get; set; } = new List<Webhook>();
    public virtual ICollection<WebhookExecutionLog> ExecutionLogs { get; set; } = new List<WebhookExecutionLog>();
}

public enum UserRole
{
    Admin = 1,
    User = 2,
    ReadOnly = 3
}

/// <summary>
/// Webhook configuration entity
/// </summary>
public class Webhook
{
    [Key]
    public int Id { get; set; }

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
    public HttpMethod HttpMethod { get; set; }

    [MaxLength(100)]
    public string? ContentType { get; set; } = "application/json";

    public string? Headers { get; set; } // JSON string for custom headers

    public string? PayloadTemplate { get; set; } // JSON string for payload template

    public string? AuthenticationType { get; set; } // None, Basic, Bearer, APIKey

    public string? AuthenticationValue { get; set; } // Encrypted auth value

    public int TimeoutSeconds { get; set; } = 30;

    public int RetryCount { get; set; } = 3;

    public int RetryDelaySeconds { get; set; } = 5;

    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public int? CreatedByUserId { get; set; }
    [ForeignKey("CreatedByUserId")]
    public virtual User? CreatedByUser { get; set; }

    public virtual ICollection<WebhookExecutionLog> ExecutionLogs { get; set; } = new List<WebhookExecutionLog>();
    public virtual ICollection<WebhookTrigger> Triggers { get; set; } = new List<WebhookTrigger>();
}

/// <summary>
/// HTTP Method enum
/// </summary>
public enum HttpMethod
{
    GET = 1,
    POST = 2,
    PUT = 3,
    PATCH = 4,
    DELETE = 5
}

/// <summary>
/// Webhook execution log entity
/// </summary>
public class WebhookExecutionLog
{
    [Key]
    public int Id { get; set; }

    [Required]
    public int WebhookId { get; set; }
    [ForeignKey("WebhookId")]
    public virtual Webhook Webhook { get; set; } = null!;

    [Required]
    public DateTime ExecutionTime { get; set; } = DateTime.UtcNow;

    [Required]
    public ExecutionStatus Status { get; set; }

    public string? RequestPayload { get; set; }
    public string? ResponsePayload { get; set; }
    public int? ResponseStatusCode { get; set; }
    public string? ResponseHeaders { get; set; }
    public long? ResponseTimeMs { get; set; }
    public string? ErrorMessage { get; set; }
    public string? StackTrace { get; set; }

    public int RetryAttempt { get; set; } = 0;

    public string? TriggeredBy { get; set; } // Manual, MQTT, Scheduled, etc.

    public int? UserId { get; set; }
    [ForeignKey("UserId")]
    public virtual User? User { get; set; }
}

/// <summary>
/// Execution status enum
/// </summary>
public enum ExecutionStatus
{
    Pending = 1,
    Success = 2,
    Failed = 3,
    Timeout = 4,
    Cancelled = 5
}

/// <summary>
/// Webhook trigger configuration
/// </summary>
public class WebhookTrigger
{
    [Key]
    public int Id { get; set; }

    [Required]
    public int WebhookId { get; set; }
    [ForeignKey("WebhookId")]
    public virtual Webhook Webhook { get; set; } = null!;

    [Required]
    [MaxLength(100)]
    public string TriggerType { get; set; } = string.Empty; // MQTT, HTTP, Scheduled, Manual

    [MaxLength(200)]
    public string? TriggerCondition { get; set; } // JSON string for trigger conditions

    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// System configuration entity
/// </summary>
public class SystemConfiguration
{
    [Key]
    [MaxLength(100)]
    public string Key { get; set; } = string.Empty;

    [Required]
    public string Value { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    [MaxLength(100)]
    public string? UpdatedBy { get; set; }
}