# Webhook Management System

A comprehensive local webhook management system featuring an SQLite database backend and a web-based configuration interface. This system provides a complete solution for managing, testing, and monitoring webhooks with real-time capabilities.

## Features

### Core Functionality
- **SQLite Database Backend**: Persistent storage for webhook configurations, execution logs, and user management
- **RESTful API**: Complete CRUD operations for webhook management with input validation and error handling
- **Web-based UI**: Lightweight, responsive interface for webhook configuration and monitoring
- **Real-time Updates**: SignalR integration for live webhook execution monitoring
- **Test Execution**: Built-in testing capabilities with payload customization

### Webhook Management
- **Flexible Configuration**: Support for all HTTP methods (GET, POST, PUT, PATCH, DELETE)
- **Template Processing**: JSON payload templates with dynamic data replacement
- **Authentication Support**: Bearer, Basic, and API Key authentication methods
- **Custom Headers**: Configurable request headers for each webhook
- **Retry Policies**: Configurable retry count and delay settings
- **Timeout Controls**: Customizable request timeout settings

### Monitoring & Logging
- **Execution Tracking**: Detailed logs of all webhook executions with timestamps
- **Status Monitoring**: Real-time status updates for webhook executions
- **Performance Metrics**: Response time tracking and performance analysis
- **Error Handling**: Comprehensive error logging with stack traces
- **Filtering & Search**: Advanced filtering for logs and webhook configurations

### Security Features
- **Input Validation**: Comprehensive input sanitization and validation
- **Rate Limiting**: API rate limiting to prevent abuse
- **CORS Configuration**: Configurable cross-origin request handling
- **Secure Configuration**: Environment-based configuration management

## Technology Stack

- **Backend**: .NET 8.0 with ASP.NET Core
- **Database**: SQLite with Entity Framework Core
- **Frontend**: Bootstrap 5, Font Awesome, SignalR for real-time updates
- **Authentication**: BCrypt for password hashing
- **Logging**: Serilog for structured logging
- **API Documentation**: Swagger/OpenAPI

## Installation

### Prerequisites
- .NET 8.0 SDK or later
- Visual Studio 2022 or VS Code (optional)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd VerneMQWebhookAuth
   ```

2. **Restore dependencies**
   ```bash
   dotnet restore
   ```

3. **Run the application**
   ```bash
   dotnet run
   ```

4. **Access the web interface**
   - Web UI: http://localhost:5000
   - API Documentation: http://localhost:5000/swagger
   - Health Check: http://localhost:5000/health

### Configuration

The application can be configured through `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=webhook.db"
  },
  "WebhookSettings": {
    "DefaultTimeoutSeconds": 30,
    "MaxConcurrentWebhooks": 10,
    "EnableRateLimiting": true,
    "RateLimitPerMinute": 60,
    "LogRetentionDays": 30,
    "EnableHttpsOnly": false
  }
}
```

## API Reference

### Webhook Management

#### Get All Webhooks
```http
GET /api/webhookmanagement
```

Query Parameters:
- `activeOnly` (bool): Filter to active webhooks only
- `search` (string): Search term for name/description
- `page` (int): Page number (default: 1)
- `pageSize` (int): Page size (default: 10)

#### Create Webhook
```http
POST /api/webhookmanagement
Content-Type: application/json

{
  "name": "My Webhook",
  "description": "Description of the webhook",
  "url": "https://example.com/webhook",
  "httpMethod": "POST",
  "contentType": "application/json",
  "headers": {
    "Authorization": "Bearer token123"
  },
  "payloadTemplate": "{\"message\": \"Hello World\"}",
  "timeoutSeconds": 30,
  "retryCount": 3,
  "retryDelaySeconds": 5
}
```

#### Get Webhook Details
```http
GET /api/webhookmanagement/{id}
```

#### Update Webhook
```http
PUT /api/webhookmanagement/{id}
Content-Type: application/json

{
  "name": "Updated Webhook Name",
  "description": "Updated description",
  "isActive": true
}
```

#### Delete Webhook
```http
DELETE /api/webhookmanagement/{id}
```

#### Test Webhook
```http
POST /api/webhookmanagement/{id}/test
Content-Type: application/json

{
  "payload": "{\"test\": \"data\"}",
  "headers": {
    "X-Test": "value"
  }
}
```

#### Get Execution Logs
```http
GET /api/webhookmanagement/{id}/logs
```

Query Parameters:
- `page` (int): Page number
- `pageSize` (int): Page size
- `status` (string): Filter by execution status
- `fromDate` (datetime): Filter from date
- `toDate` (datetime): Filter to date

### VerneMQ Integration

#### Authentication Webhook
```http
POST /mqtt/auth
Content-Type: application/json

{
  "mountpoint": "",
  "clientid": "test-client",
  "username": "testuser",
  "password": "testpass",
  "peeraddr": "127.0.0.1",
  "peerport": 12345,
  "cleansession": true
}
```

#### Publish Authorization
```http
POST /mqtt/publish
Content-Type: application/json

{
  "mountpoint": "",
  "clientid": "test-client",
  "username": "testuser",
  "qos": 1,
  "topic": "test/topic",
  "payload": "Hello MQTT",
  "retain": false,
  "peeraddr": "127.0.0.1",
  "peerport": 12345
}
```

#### Subscribe Authorization
```http
POST /mqtt/subscribe
Content-Type: application/json

{
  "mountpoint": "",
  "clientid": "test-client",
  "username": "testuser",
  "topics": [
    {"topic": "test/topic", "qos": 1}
  ],
  "peeraddr": "127.0.0.1",
  "peerport": 12345
}
```

## Usage Examples

### Creating Your First Webhook

1. **Open the web interface** at http://localhost:5000
2. **Click "Create Webhook"** button
3. **Fill in the webhook details**:
   - Name: "Hello World Webhook"
   - Description: "A simple test webhook"
   - URL: "https://httpbin.org/post"
   - Method: "POST"
   - Content Type: "application/json"
   - Payload Template: `{"message": "Hello from Webhook Management System!"}`
4. **Click "Create Webhook"**
5. **Test the webhook** by clicking the "Test" button

### VerneMQ Integration

To integrate with VerneMQ, configure the webhook plugin:

```erlang
{mqtt, [{plugins, [
    {vmq_webhook, [
        {hook, auth_on_register, [
            {uri, "http://localhost:5000/mqtt/auth"}
        ]},
        {hook, auth_on_publish, [
            {uri, "http://localhost:5000/mqtt/publish"}
        ]},
        {hook, auth_on_subscribe, [
            {uri, "http://localhost:5000/mqtt/subscribe"}
        ]}
    ]}
]}].
```

### Payload Templates

The system supports JSON payload templates with dynamic data replacement:

```json
{
  "timestamp": "{{now}}",
  "clientId": "{{clientId}}",
  "username": "{{username}}",
  "topic": "{{topic}}",
  "payload": "{{payload}}",
  "metadata": {
    "source": "verneq-webhook-system",
    "version": "1.0"
  }
}
```

### Authentication Methods

#### Bearer Token
```json
{
  "authenticationType": "Bearer",
  "authenticationValue": "your-jwt-token"
}
```

#### Basic Authentication
```json
{
  "authenticationType": "Basic",
  "authenticationValue": "username:password"
}
```

#### API Key
```json
{
  "authenticationType": "APIKey",
  "authenticationValue": "your-api-key"
}
```

## Configuration

### Environment Variables

Override configuration using environment variables:

```bash
export ConnectionStrings__DefaultConnection="Data Source=/custom/path/webhook.db"
export WebhookSettings__DefaultTimeoutSeconds=60
export WebhookSettings__MaxConcurrentWebhooks=20
```

### Production Deployment

For production deployment:

1. **Enable HTTPS**
   ```json
   {
     "WebhookSettings": {
       "EnableHttpsOnly": true
     }
   }
   ```

2. **Configure reverse proxy** (nginx example)
   ```nginx
   server {
       listen 80;
       server_name yourdomain.com;
       return 301 https://$server_name$request_uri;
   }

   server {
       listen 443 ssl;
       server_name yourdomain.com;

       ssl_certificate /path/to/certificate.pem;
       ssl_certificate_key /path/to/private.key;

       location / {
           proxy_pass http://localhost:5000;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

3. **Set up monitoring**
   ```json
   {
     "Serilog": {
       "MinimumLevel": {
         "Default": "Information",
         "Override": {
           "Microsoft": "Warning",
           "System": "Warning"
         }
       }
     }
   }
   ```

## Troubleshooting

### Common Issues

1. **Database locked error**
   - Ensure no other processes are using the SQLite database
   - Check file permissions on the database file

2. **Webhook execution failures**
   - Verify the target URL is accessible
   - Check network connectivity and firewall settings
   - Review execution logs for detailed error messages

3. **SignalR connection issues**
   - Ensure WebSocket support is enabled
   - Check browser console for JavaScript errors
   - Verify CORS configuration

### Logging

Logs are written to:
- Console output (development)
- File: `logs/webhook-.txt` (daily rolling)

### Performance Tuning

1. **Database optimization**
   ```sql
   -- Add indexes for better query performance
   CREATE INDEX idx_webhook_executions_time ON WebhookExecutionLogs(ExecutionTime);
   CREATE INDEX idx_webhooks_active ON Webhooks(IsActive);
   ```

2. **Memory usage**
   - Configure appropriate timeout values
   - Monitor execution log retention
   - Limit concurrent webhook executions

## Development

### Building from Source

```bash
# Clone repository
git clone <repository-url>
cd VerneMQWebhookAuth

# Restore dependencies
dotnet restore

# Build project
dotnet build

# Run tests
dotnet test

# Run application
dotnet run
```

### Database Migrations

```bash
# Create migration
dotnet ef migrations add InitialCreate

# Update database
dotnet ef database update

# Remove migration
dotnet ef migrations remove
```

### Adding New Features

1. **New API endpoints**: Add to `WebhookManagementController.cs`
2. **Database changes**: Create new migration
3. **UI enhancements**: Update `Index.cshtml`
4. **Background services**: Implement `IHostedService`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the troubleshooting section
- Review API documentation at `/swagger`
- Create an issue on GitHub

## Changelog

### v1.0.0 (2025-12-23)
- Initial release
- SQLite database integration
- Web-based management interface
- Real-time monitoring with SignalR
- VerneMQ webhook integration
- Comprehensive API with Swagger documentation