using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using VerneMQWebhookAuth.Services;

namespace VerneMQWebhookAuth.Controllers;

/// <summary>
/// Authentication controller for dashboard access
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly IDashboardAuthService _authService;
    private readonly ILogger<AuthController> _logger;

    public AuthController(IDashboardAuthService authService, ILogger<AuthController> logger)
    {
        _authService = authService;
        _logger = logger;
    }

    /// <summary>
    /// Login to the dashboard
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        if (string.IsNullOrEmpty(request.Username) || string.IsNullOrEmpty(request.Password))
        {
            return BadRequest(new LoginResponse
            {
                Success = false,
                Message = "Username and password are required"
            });
        }

        var user = await _authService.ValidateCredentialsAsync(request.Username, request.Password);
        if (user == null)
        {
            return Unauthorized(new LoginResponse
            {
                Success = false,
                Message = "Invalid username or password"
            });
        }

        // Create claims
        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Username),
            new Claim(ClaimTypes.Email, user.Email),
            new Claim(ClaimTypes.Role, user.Role.ToString())
        };

        var claimsIdentity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
        var authProperties = new AuthenticationProperties
        {
            IsPersistent = request.RememberMe,
            ExpiresUtc = request.RememberMe 
                ? DateTimeOffset.UtcNow.AddDays(30) 
                : DateTimeOffset.UtcNow.AddHours(8)
        };

        await HttpContext.SignInAsync(
            CookieAuthenticationDefaults.AuthenticationScheme,
            new ClaimsPrincipal(claimsIdentity),
            authProperties);

        await _authService.UpdateLastLoginAsync(user.Id);

        _logger.LogInformation("User {Username} logged in successfully", user.Username);

        return Ok(new LoginResponse
        {
            Success = true,
            Message = "Login successful",
            RedirectUrl = "/Index",
            User = new UserInfo
            {
                Id = user.Id,
                Username = user.Username,
                Email = user.Email,
                Role = user.Role.ToString()
            }
        });
    }

    /// <summary>
    /// Logout from the dashboard
    /// </summary>
    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        var username = User.Identity?.Name;
        await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        
        _logger.LogInformation("User {Username} logged out", username ?? "Unknown");

        return Ok(new { success = true, message = "Logged out successfully", redirectUrl = "/Login" });
    }

    /// <summary>
    /// Get current user info
    /// </summary>
    [HttpGet("me")]
    [Authorize]
    public IActionResult GetCurrentUser()
    {
        var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var username = User.FindFirst(ClaimTypes.Name)?.Value;
        var email = User.FindFirst(ClaimTypes.Email)?.Value;
        var role = User.FindFirst(ClaimTypes.Role)?.Value;

        return Ok(new UserInfo
        {
            Id = int.TryParse(userId, out var id) ? id : 0,
            Username = username ?? "",
            Email = email ?? "",
            Role = role ?? ""
        });
    }

    /// <summary>
    /// Check if user is authenticated
    /// </summary>
    [HttpGet("check")]
    [AllowAnonymous]
    public IActionResult CheckAuth()
    {
        return Ok(new
        {
            isAuthenticated = User.Identity?.IsAuthenticated ?? false,
            username = User.Identity?.Name
        });
    }
}
