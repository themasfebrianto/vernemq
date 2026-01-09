using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.RateLimiting;
using System.Threading.RateLimiting;
using Microsoft.EntityFrameworkCore;
using VerneMQWebhookAuth.Data;
using VerneMQWebhookAuth.Services;
using Serilog;
using System.Security.Cryptography;
using System.Text;
using StackExchange.Redis;

var builder = WebApplication.CreateBuilder(args);

// Configure Serilog
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .WriteTo.File("logs/webhook-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddRazorPages();
builder.Services.AddEndpointsApiExplorer();

// Add Memory Cache (always available as fallback)
builder.Services.AddMemoryCache();

// Add Redis Distributed Cache if enabled
var redisEnabled = builder.Configuration.GetValue<bool>("Redis:Enabled", false);
var redisConnection = builder.Configuration.GetValue<string>("Redis:ConnectionString");

if (redisEnabled && !string.IsNullOrEmpty(redisConnection))
{
    Log.Information("Redis caching enabled, connecting to: {RedisHost}", redisConnection);
    builder.Services.AddStackExchangeRedisCache(options =>
    {
        options.Configuration = redisConnection;
        options.InstanceName = "VerneMQ_";
    });
}
else
{
    Log.Information("Redis caching disabled, using memory cache only");
    // Register a dummy distributed cache that won't be used
    builder.Services.AddDistributedMemoryCache();
}

// Add Hybrid Cache Service (Redis primary, Memory fallback)
builder.Services.AddSingleton<VerneMQWebhookAuth.Services.IHybridCacheService, 
    VerneMQWebhookAuth.Services.HybridCacheService>();

builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "Webhook Management API",
        Version = "v1",
        Description = "Comprehensive webhook management system with SQLite backend"
    });

    // Include XML comments
    var xmlFile = $"{System.Reflection.Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath))
    {
        c.IncludeXmlComments(xmlPath);
    }
});

// Add Entity Framework with SQLite
builder.Services.AddDbContext<WebhookDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection") ??
                     "Data Source=webhook.db"));

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });

    options.AddPolicy("Production", policy =>
    {
        policy.WithOrigins("https://yourdomain.com")
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});

// Add Rate Limiting
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("api", opt =>
    {
        opt.Window = TimeSpan.FromMinutes(1);
        opt.PermitLimit = 60;
    });

    options.AddFixedWindowLimiter("webhook-test", opt =>
    {
        opt.Window = TimeSpan.FromMinutes(1);
        opt.PermitLimit = 10;
    });

    options.RejectionStatusCode = 429;
});

// Add HttpClient for webhook execution
builder.Services.AddHttpClient();

// Add Health Checks
builder.Services.AddHealthChecks()
    .AddSqlite(builder.Configuration.GetConnectionString("DefaultConnection") ??
               "Data Source=webhook.db");

// Add SignalR for real-time updates
builder.Services.AddSignalR();

// Add WebhookTriggerService
builder.Services.AddScoped<VerneMQWebhookAuth.Services.IWebhookTriggerService, 
    VerneMQWebhookAuth.Services.WebhookTriggerService>();

// Add MQTT Activity Logger
builder.Services.AddScoped<VerneMQWebhookAuth.Services.IMqttActivityLogger,
    VerneMQWebhookAuth.Services.MqttActivityLogger>();

// Add Dashboard Authentication Service
builder.Services.AddScoped<IDashboardAuthService, DashboardAuthService>();

// Add Cookie Authentication
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/Login";
        options.LogoutPath = "/api/auth/logout";
        options.AccessDeniedPath = "/Login";
        options.ExpireTimeSpan = TimeSpan.FromHours(8);
        options.SlidingExpiration = true;
        options.Cookie.Name = "VerneMQ.Dashboard.Auth";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
        options.Events = new CookieAuthenticationEvents
        {
            OnRedirectToLogin = context =>
            {
                // For API calls, return 401 instead of redirect
                if (context.Request.Path.StartsWithSegments("/api") && 
                    !context.Request.Path.StartsWithSegments("/api/auth"))
                {
                    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    return Task.CompletedTask;
                }
                context.Response.Redirect(context.RedirectUri);
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

var app = builder.Build();

// Initialize database
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<WebhookDbContext>();
    context.Database.EnsureCreated();
}

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Webhook Management API v1");
        c.RoutePrefix = "swagger";
    });
}

app.UseSerilogRequestLogging();

app.UseHttpsRedirection();
app.UseRateLimiter();

// Configure CORS based on environment
if (app.Environment.IsDevelopment())
{
    app.UseCors("AllowAll");
}
else
{
    app.UseCors("Production");
}

// Enable serving static files from wwwroot
app.UseStaticFiles();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapRazorPages();
app.MapHub<VerneMQWebhookAuth.Hubs.WebhookHub>("/webhookHub");
app.MapHealthChecks("/health");

// Default route to the main page
app.MapGet("/", async context =>
{
    context.Response.Redirect("/Index");
});

Log.Information("Webhook Management System started");

app.Run();

