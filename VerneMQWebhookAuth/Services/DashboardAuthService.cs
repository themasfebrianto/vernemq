using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Models;

namespace VerneMQWebhookAuth.Services;

/// <summary>
/// Service for dashboard authentication
/// </summary>
public interface IDashboardAuthService
{
    Task<User?> ValidateCredentialsAsync(string username, string password);
    Task<User?> ValidateApiKeyAsync(string apiKey);
    Task<User?> GetUserByIdAsync(int userId);
    Task UpdateLastLoginAsync(int userId);
}

public class DashboardAuthService : IDashboardAuthService
{
    private readonly WebhookDbContext _context;
    private readonly ILogger<DashboardAuthService> _logger;

    public DashboardAuthService(WebhookDbContext context, ILogger<DashboardAuthService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<User?> ValidateCredentialsAsync(string username, string password)
    {
        try
        {
            var user = await _context.Users
                .FirstOrDefaultAsync(u => u.Username == username && u.IsActive);

            if (user == null)
            {
                _logger.LogWarning("Dashboard login failed - User not found: {Username}", username);
                return null;
            }

            if (!BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
            {
                _logger.LogWarning("Dashboard login failed - Invalid password for user: {Username}", username);
                return null;
            }

            _logger.LogInformation("Dashboard login successful for user: {Username}", username);
            return user;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating dashboard credentials for user: {Username}", username);
            return null;
        }
    }

    public async Task<User?> ValidateApiKeyAsync(string apiKey)
    {
        try
        {
            var user = await _context.Users
                .FirstOrDefaultAsync(u => u.ApiKey == apiKey && u.IsActive);

            if (user == null)
            {
                _logger.LogWarning("API key validation failed - Invalid or inactive key");
                return null;
            }

            return user;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating API key");
            return null;
        }
    }

    public async Task<User?> GetUserByIdAsync(int userId)
    {
        return await _context.Users.FindAsync(userId);
    }

    public async Task UpdateLastLoginAsync(int userId)
    {
        try
        {
            var user = await _context.Users.FindAsync(userId);
            if (user != null)
            {
                user.LastLoginAt = DateTime.UtcNow;
                await _context.SaveChangesAsync();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating last login for user: {UserId}", userId);
        }
    }
}

/// <summary>
/// Login request DTO
/// </summary>
public class LoginRequest
{
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public bool RememberMe { get; set; } = false;
}

/// <summary>
/// Login response DTO
/// </summary>
public class LoginResponse
{
    public bool Success { get; set; }
    public string? Message { get; set; }
    public string? RedirectUrl { get; set; }
    public UserInfo? User { get; set; }
}

public class UserInfo
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
}
