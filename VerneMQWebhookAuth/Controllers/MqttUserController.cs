using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Models;

namespace VerneMQWebhookAuth.Controllers;

/// <summary>
/// API Controller for managing MQTT users
/// Provides CRUD operations for MQTT device/client credentials
/// </summary>
[ApiController]
[Route("api/mqttusers")]
[Produces("application/json")]
[Authorize]
public class MqttUserController : ControllerBase
{
    private readonly ILogger<MqttUserController> _logger;
    private readonly WebhookDbContext _db;
    private readonly IMemoryCache _cache;
    
    // Same prefix as WebhookController for auth cache
    private const string AuthCachePrefix = "auth_";

    public MqttUserController(ILogger<MqttUserController> logger, WebhookDbContext db, IMemoryCache cache)
    {
        _logger = logger;
        _db = db;
        _cache = cache;
    }
    
    /// <summary>
    /// Invalidate all cached auth entries for a specific username.
    /// Since cache keys include password hash, we need to iterate and remove matching entries.
    /// This is a simple approach - for production, consider a more sophisticated cache key strategy.
    /// </summary>
    private void InvalidateUserAuthCache(string username)
    {
        // MemoryCache doesn't support key enumeration, so we use a marker approach
        // Set a "version" that gets checked on auth - simpler than trying to remove specific entries
        var versionKey = $"auth_version_{username}";
        _cache.Set(versionKey, Guid.NewGuid().ToString(), TimeSpan.FromMinutes(10));
        _logger.LogInformation("Invalidated auth cache for user: {Username}", username);
    }

    /// <summary>
    /// Get all MQTT users with optional filtering
    /// </summary>
    /// <param name="search">Search term for username/description</param>
    /// <param name="activeOnly">Filter to active users only</param>
    /// <param name="page">Page number (default: 1)</param>
    /// <param name="pageSize">Page size (default: 20)</param>
    [HttpGet]
    public async Task<ActionResult<object>> GetAll(
        [FromQuery] string? search = null,
        [FromQuery] bool? activeOnly = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var query = _db.MqttUsers.AsQueryable();

            // Apply filters
            if (!string.IsNullOrEmpty(search))
            {
                query = query.Where(u => 
                    u.Username.Contains(search) || 
                    (u.Description != null && u.Description.Contains(search)));
            }

            if (activeOnly.HasValue)
            {
                query = query.Where(u => u.IsActive == activeOnly.Value);
            }

            // Get total count
            var totalCount = await query.CountAsync();

            // Apply pagination
            var users = await query
                .OrderBy(u => u.Username)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(u => new MqttUserResponse
                {
                    Id = u.Id,
                    Username = u.Username,
                    AllowedClientId = u.AllowedClientId,
                    Description = u.Description,
                    IsAdmin = u.IsAdmin,
                    IsActive = u.IsActive,
                    AllowedPublishTopics = u.AllowedPublishTopics,
                    AllowedSubscribeTopics = u.AllowedSubscribeTopics,
                    MaxConnections = u.MaxConnections,
                    CreatedAt = u.CreatedAt,
                    UpdatedAt = u.UpdatedAt,
                    LastLoginAt = u.LastLoginAt,
                    LastLoginIp = u.LastLoginIp,
                    LoginCount = u.LoginCount
                })
                .ToListAsync();

            return Ok(new
            {
                items = users,
                totalCount,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)totalCount / pageSize)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting MQTT users");
            return StatusCode(500, new { error = "Failed to retrieve MQTT users" });
        }
    }

    /// <summary>
    /// Get a single MQTT user by ID
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<MqttUserResponse>> GetById(int id)
    {
        try
        {
            var user = await _db.MqttUsers.FindAsync(id);
            if (user == null)
            {
                return NotFound(new { error = "MQTT user not found" });
            }

            return Ok(new MqttUserResponse
            {
                Id = user.Id,
                Username = user.Username,
                AllowedClientId = user.AllowedClientId,
                Description = user.Description,
                IsAdmin = user.IsAdmin,
                IsActive = user.IsActive,
                AllowedPublishTopics = user.AllowedPublishTopics,
                AllowedSubscribeTopics = user.AllowedSubscribeTopics,
                MaxConnections = user.MaxConnections,
                CreatedAt = user.CreatedAt,
                UpdatedAt = user.UpdatedAt,
                LastLoginAt = user.LastLoginAt,
                LastLoginIp = user.LastLoginIp,
                LoginCount = user.LoginCount
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting MQTT user {Id}", id);
            return StatusCode(500, new { error = "Failed to retrieve MQTT user" });
        }
    }

    /// <summary>
    /// Create a new MQTT user
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<MqttUserResponse>> Create([FromBody] CreateMqttUserRequest request)
    {
        try
        {
            // Validate request
            if (string.IsNullOrEmpty(request.Username))
            {
                return BadRequest(new { error = "Username is required" });
            }

            if (string.IsNullOrEmpty(request.Password) || request.Password.Length < 8)
            {
                return BadRequest(new { error = "Password must be at least 8 characters" });
            }

            // Check for duplicate username
            var existingUser = await _db.MqttUsers
                .FirstOrDefaultAsync(u => u.Username == request.Username);
            if (existingUser != null)
            {
                return Conflict(new { error = "Username already exists" });
            }

            // Create new user
            var user = new MqttUser
            {
                Username = request.Username,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
                AllowedClientId = request.AllowedClientId,
                Description = request.Description,
                IsAdmin = request.IsAdmin,
                IsActive = true,
                AllowedPublishTopics = request.AllowedPublishTopics,
                AllowedSubscribeTopics = request.AllowedSubscribeTopics,
                MaxConnections = request.MaxConnections,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            _db.MqttUsers.Add(user);
            await _db.SaveChangesAsync();

            _logger.LogInformation("Created MQTT user: {Username}", user.Username);

            return CreatedAtAction(nameof(GetById), new { id = user.Id }, new MqttUserResponse
            {
                Id = user.Id,
                Username = user.Username,
                AllowedClientId = user.AllowedClientId,
                Description = user.Description,
                IsAdmin = user.IsAdmin,
                IsActive = user.IsActive,
                AllowedPublishTopics = user.AllowedPublishTopics,
                AllowedSubscribeTopics = user.AllowedSubscribeTopics,
                MaxConnections = user.MaxConnections,
                CreatedAt = user.CreatedAt,
                UpdatedAt = user.UpdatedAt,
                LastLoginAt = user.LastLoginAt,
                LastLoginIp = user.LastLoginIp,
                LoginCount = user.LoginCount
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating MQTT user");
            return StatusCode(500, new { error = "Failed to create MQTT user" });
        }
    }

    /// <summary>
    /// Update an existing MQTT user
    /// </summary>
    [HttpPut("{id}")]
    public async Task<ActionResult<MqttUserResponse>> Update(int id, [FromBody] UpdateMqttUserRequest request)
    {
        try
        {
            var user = await _db.MqttUsers.FindAsync(id);
            if (user == null)
            {
                return NotFound(new { error = "MQTT user not found" });
            }

            // Update fields if provided
            if (request.Description != null)
                user.Description = request.Description;

            if (request.IsAdmin.HasValue)
                user.IsAdmin = request.IsAdmin.Value;

            if (request.IsActive.HasValue)
                user.IsActive = request.IsActive.Value;

            if (request.AllowedPublishTopics != null)
                user.AllowedPublishTopics = request.AllowedPublishTopics;

            if (request.AllowedSubscribeTopics != null)
                user.AllowedSubscribeTopics = request.AllowedSubscribeTopics;

            if (request.MaxConnections.HasValue)
                user.MaxConnections = request.MaxConnections.Value;

            // Update password if provided
            if (!string.IsNullOrEmpty(request.NewPassword))
            {
                if (request.NewPassword.Length < 8)
                {
                    return BadRequest(new { error = "Password must be at least 8 characters" });
                }
                user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            }

            user.UpdatedAt = DateTime.UtcNow;

            await _db.SaveChangesAsync();
            
            // Invalidate auth cache for this user
            InvalidateUserAuthCache(user.Username);

            _logger.LogInformation("Updated MQTT user: {Username}", user.Username);

            return Ok(new MqttUserResponse
            {
                Id = user.Id,
                Username = user.Username,
                AllowedClientId = user.AllowedClientId,
                Description = user.Description,
                IsAdmin = user.IsAdmin,
                IsActive = user.IsActive,
                AllowedPublishTopics = user.AllowedPublishTopics,
                AllowedSubscribeTopics = user.AllowedSubscribeTopics,
                MaxConnections = user.MaxConnections,
                CreatedAt = user.CreatedAt,
                UpdatedAt = user.UpdatedAt,
                LastLoginAt = user.LastLoginAt,
                LastLoginIp = user.LastLoginIp,
                LoginCount = user.LoginCount
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating MQTT user {Id}", id);
            return StatusCode(500, new { error = "Failed to update MQTT user" });
        }
    }

    /// <summary>
    /// Delete an MQTT user
    /// </summary>
    [HttpDelete("{id}")]
    public async Task<ActionResult> Delete(int id)
    {
        try
        {
            var user = await _db.MqttUsers.FindAsync(id);
            if (user == null)
            {
                return NotFound(new { error = "MQTT user not found" });
            }

            _db.MqttUsers.Remove(user);
            await _db.SaveChangesAsync();
            
            // Invalidate auth cache for this user
            InvalidateUserAuthCache(user.Username);

            _logger.LogInformation("Deleted MQTT user: {Username}", user.Username);

            return NoContent();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting MQTT user {Id}", id);
            return StatusCode(500, new { error = "Failed to delete MQTT user" });
        }
    }

    /// <summary>
    /// Toggle user active status
    /// </summary>
    [HttpPost("{id}/toggle-active")]
    public async Task<ActionResult<MqttUserResponse>> ToggleActive(int id)
    {
        try
        {
            var user = await _db.MqttUsers.FindAsync(id);
            if (user == null)
            {
                return NotFound(new { error = "MQTT user not found" });
            }

            user.IsActive = !user.IsActive;
            user.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            
            // Invalidate auth cache for this user
            InvalidateUserAuthCache(user.Username);

            _logger.LogInformation("Toggled MQTT user {Username} active status to {IsActive}", 
                user.Username, user.IsActive);

            return Ok(new MqttUserResponse
            {
                Id = user.Id,
                Username = user.Username,
                AllowedClientId = user.AllowedClientId,
                Description = user.Description,
                IsAdmin = user.IsAdmin,
                IsActive = user.IsActive,
                AllowedPublishTopics = user.AllowedPublishTopics,
                AllowedSubscribeTopics = user.AllowedSubscribeTopics,
                MaxConnections = user.MaxConnections,
                CreatedAt = user.CreatedAt,
                UpdatedAt = user.UpdatedAt,
                LastLoginAt = user.LastLoginAt,
                LastLoginIp = user.LastLoginIp,
                LoginCount = user.LoginCount
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error toggling MQTT user {Id}", id);
            return StatusCode(500, new { error = "Failed to toggle MQTT user active status" });
        }
    }

    /// <summary>
    /// Reset user password
    /// </summary>
    [HttpPost("{id}/reset-password")]
    public async Task<ActionResult> ResetPassword(int id, [FromBody] ResetPasswordRequest request)
    {
        try
        {
            var user = await _db.MqttUsers.FindAsync(id);
            if (user == null)
            {
                return NotFound(new { error = "MQTT user not found" });
            }

            if (string.IsNullOrEmpty(request.NewPassword) || request.NewPassword.Length < 8)
            {
                return BadRequest(new { error = "Password must be at least 8 characters" });
            }

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            user.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            
            // Invalidate auth cache for this user
            InvalidateUserAuthCache(user.Username);

            _logger.LogInformation("Reset password for MQTT user: {Username}", user.Username);

            return Ok(new { message = "Password reset successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resetting password for MQTT user {Id}", id);
            return StatusCode(500, new { error = "Failed to reset password" });
        }
    }

    /// <summary>
    /// Get user statistics
    /// </summary>
    [HttpGet("stats")]
    public async Task<ActionResult<object>> GetStats()
    {
        try
        {
            var totalUsers = await _db.MqttUsers.CountAsync();
            var activeUsers = await _db.MqttUsers.CountAsync(u => u.IsActive);
            var adminUsers = await _db.MqttUsers.CountAsync(u => u.IsAdmin);
            var recentLogins = await _db.MqttUsers
                .CountAsync(u => u.LastLoginAt != null && u.LastLoginAt > DateTime.UtcNow.AddHours(-24));

            return Ok(new
            {
                totalUsers,
                activeUsers,
                inactiveUsers = totalUsers - activeUsers,
                adminUsers,
                recentLogins24h = recentLogins
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting MQTT user stats");
            return StatusCode(500, new { error = "Failed to retrieve stats" });
        }
    }
}

/// <summary>
/// Request DTO for password reset
/// </summary>
public class ResetPasswordRequest
{
    public string NewPassword { get; set; } = string.Empty;
}
