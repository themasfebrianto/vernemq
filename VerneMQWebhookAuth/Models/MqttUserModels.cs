using System.ComponentModel.DataAnnotations;

namespace VerneMQWebhookAuth.Models;

/// <summary>
/// MQTT User/Device credentials for VerneMQ authentication
/// Separate from dashboard User model - these are MQTT clients (devices, apps, etc.)
/// </summary>
public class MqttUser
{
    [Key]
    public int Id { get; set; }

    /// <summary>
    /// MQTT username (must be unique)
    /// </summary>
    [Required]
    [MaxLength(100)]
    public string Username { get; set; } = string.Empty;

    /// <summary>
    /// BCrypt hashed password
    /// </summary>
    [Required]
    public string PasswordHash { get; set; } = string.Empty;

    /// <summary>
    /// Optional client ID restriction (if set, only this client ID can use these credentials)
    /// </summary>
    [MaxLength(256)]
    public string? AllowedClientId { get; set; }

    /// <summary>
    /// Description of this user/device (e.g., "Temperature Sensor #1", "Mobile App User")
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Whether this user has admin privileges (can pub/sub to admin/* topics)
    /// </summary>
    public bool IsAdmin { get; set; } = false;

    /// <summary>
    /// Whether this user is currently active
    /// </summary>
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Comma-separated list of topic patterns this user can publish to
    /// Use * for single-level wildcard, # for multi-level wildcard
    /// Empty = all topics allowed
    /// Example: "sensors/#,devices/+/status"
    /// </summary>
    [MaxLength(2000)]
    public string? AllowedPublishTopics { get; set; }

    /// <summary>
    /// Comma-separated list of topic patterns this user can subscribe to
    /// Empty = all topics allowed
    /// </summary>
    [MaxLength(2000)]
    public string? AllowedSubscribeTopics { get; set; }

    /// <summary>
    /// Maximum number of concurrent connections for this user (0 = unlimited)
    /// </summary>
    public int MaxConnections { get; set; } = 0;

    /// <summary>
    /// When this user was created
    /// </summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When this user was last updated
    /// </summary>
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When this user last connected (updated by webhook)
    /// </summary>
    public DateTime? LastLoginAt { get; set; }

    /// <summary>
    /// Last IP address this user connected from
    /// </summary>
    [MaxLength(45)]
    public string? LastLoginIp { get; set; }

    /// <summary>
    /// Total number of successful authentications
    /// </summary>
    public int LoginCount { get; set; } = 0;
}

/// <summary>
/// DTO for creating a new MQTT user
/// </summary>
public class CreateMqttUserRequest
{
    [Required]
    [MaxLength(100)]
    public string Username { get; set; } = string.Empty;

    [Required]
    [MinLength(8)]
    public string Password { get; set; } = string.Empty;

    [MaxLength(256)]
    public string? AllowedClientId { get; set; }

    [MaxLength(500)]
    public string? Description { get; set; }

    public bool IsAdmin { get; set; } = false;

    [MaxLength(2000)]
    public string? AllowedPublishTopics { get; set; }

    [MaxLength(2000)]
    public string? AllowedSubscribeTopics { get; set; }

    public int MaxConnections { get; set; } = 0;
}

/// <summary>
/// DTO for updating an MQTT user
/// </summary>
public class UpdateMqttUserRequest
{
    [MaxLength(500)]
    public string? Description { get; set; }

    public bool? IsAdmin { get; set; }

    public bool? IsActive { get; set; }

    [MaxLength(2000)]
    public string? AllowedPublishTopics { get; set; }

    [MaxLength(2000)]
    public string? AllowedSubscribeTopics { get; set; }

    public int? MaxConnections { get; set; }

    /// <summary>
    /// New password (only set if changing password)
    /// </summary>
    [MinLength(8)]
    public string? NewPassword { get; set; }
}

/// <summary>
/// DTO for MQTT user response (without password hash)
/// </summary>
public class MqttUserResponse
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string? AllowedClientId { get; set; }
    public string? Description { get; set; }
    public bool IsAdmin { get; set; }
    public bool IsActive { get; set; }
    public string? AllowedPublishTopics { get; set; }
    public string? AllowedSubscribeTopics { get; set; }
    public int MaxConnections { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public string? LastLoginIp { get; set; }
    public int LoginCount { get; set; }
}
