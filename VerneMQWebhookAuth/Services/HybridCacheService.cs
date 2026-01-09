using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Memory;
using System.Text.Json;

namespace VerneMQWebhookAuth.Services;

/// <summary>
/// Interface for hybrid cache service that uses Redis as primary and Memory as fallback
/// </summary>
public interface IHybridCacheService
{
    Task<T?> GetAsync<T>(string key) where T : class;
    Task SetAsync<T>(string key, T value, TimeSpan? expiration = null) where T : class;
    Task RemoveAsync(string key);
    Task<bool> IsRedisAvailable();
}

/// <summary>
/// Hybrid cache service that uses Redis as primary cache with Memory cache as fallback
/// Provides high-performance caching for authentication results
/// </summary>
public class HybridCacheService : IHybridCacheService
{
    private readonly IDistributedCache? _distributedCache;
    private readonly IMemoryCache _memoryCache;
    private readonly ILogger<HybridCacheService> _logger;
    private readonly bool _redisEnabled;
    private readonly TimeSpan _defaultExpiration = TimeSpan.FromMinutes(5);
    
    private static bool _redisAvailable = true;
    private static DateTime _lastRedisCheck = DateTime.MinValue;
    private static readonly TimeSpan RedisCheckInterval = TimeSpan.FromSeconds(30);

    public HybridCacheService(
        IMemoryCache memoryCache,
        ILogger<HybridCacheService> logger,
        IConfiguration configuration,
        IDistributedCache? distributedCache = null)
    {
        _memoryCache = memoryCache;
        _logger = logger;
        _distributedCache = distributedCache;
        _redisEnabled = configuration.GetValue<bool>("Redis:Enabled", false);
        
        if (_redisEnabled && _distributedCache != null)
        {
            _logger.LogInformation("Hybrid cache initialized with Redis as primary cache");
        }
        else
        {
            _logger.LogInformation("Hybrid cache initialized with Memory cache only");
        }
    }

    public async Task<T?> GetAsync<T>(string key) where T : class
    {
        // Try Redis first if enabled and available
        if (_redisEnabled && _distributedCache != null && _redisAvailable)
        {
            try
            {
                var data = await _distributedCache.GetStringAsync(key);
                if (data != null)
                {
                    _logger.LogDebug("Redis cache HIT for key: {Key}", key);
                    return JsonSerializer.Deserialize<T>(data);
                }
            }
            catch (Exception ex)
            {
                HandleRedisError(ex);
            }
        }

        // Fallback to memory cache
        if (_memoryCache.TryGetValue(key, out T? memoryValue))
        {
            _logger.LogDebug("Memory cache HIT for key: {Key}", key);
            return memoryValue;
        }

        _logger.LogDebug("Cache MISS for key: {Key}", key);
        return null;
    }

    public async Task SetAsync<T>(string key, T value, TimeSpan? expiration = null) where T : class
    {
        var exp = expiration ?? _defaultExpiration;

        // Always set in memory cache
        _memoryCache.Set(key, value, exp);

        // Also set in Redis if enabled and available
        if (_redisEnabled && _distributedCache != null && _redisAvailable)
        {
            try
            {
                var data = JsonSerializer.Serialize(value);
                var options = new DistributedCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = exp
                };
                await _distributedCache.SetStringAsync(key, data, options);
                _logger.LogDebug("Cache SET in Redis for key: {Key}", key);
            }
            catch (Exception ex)
            {
                HandleRedisError(ex);
                _logger.LogDebug("Cache SET in Memory only for key: {Key}", key);
            }
        }
    }

    public async Task RemoveAsync(string key)
    {
        // Remove from memory cache
        _memoryCache.Remove(key);

        // Remove from Redis if enabled and available
        if (_redisEnabled && _distributedCache != null && _redisAvailable)
        {
            try
            {
                await _distributedCache.RemoveAsync(key);
                _logger.LogDebug("Cache REMOVE from Redis for key: {Key}", key);
            }
            catch (Exception ex)
            {
                HandleRedisError(ex);
            }
        }
    }

    public async Task<bool> IsRedisAvailable()
    {
        if (!_redisEnabled || _distributedCache == null)
            return false;

        // Use cached result if checked recently
        if (DateTime.UtcNow - _lastRedisCheck < RedisCheckInterval)
            return _redisAvailable;

        try
        {
            // Simple ping test
            await _distributedCache.GetStringAsync("__health_check__");
            _redisAvailable = true;
            _lastRedisCheck = DateTime.UtcNow;
            return true;
        }
        catch
        {
            _redisAvailable = false;
            _lastRedisCheck = DateTime.UtcNow;
            return false;
        }
    }

    private void HandleRedisError(Exception ex)
    {
        if (_redisAvailable)
        {
            _logger.LogWarning(ex, "Redis cache error, falling back to memory cache");
            _redisAvailable = false;
            _lastRedisCheck = DateTime.UtcNow;
            
            // Schedule recheck
            Task.Run(async () =>
            {
                await Task.Delay(RedisCheckInterval);
                await IsRedisAvailable();
            });
        }
    }
}

/// <summary>
/// Cached auth result for high-performance authentication
/// </summary>
public class CachedAuthResult
{
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public bool IsAdmin { get; set; }
    public string? AllowedClientId { get; set; }
    public string? AllowedPublishTopics { get; set; }
    public string? AllowedSubscribeTopics { get; set; }
    public string CacheVersion { get; set; } = string.Empty;
}
