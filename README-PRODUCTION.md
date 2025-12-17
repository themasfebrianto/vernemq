# VerneMQ Single Container Production Deployment Guide

This guide provides instructions for deploying VerneMQ as a single production-ready container optimized for IoT data collection and messaging applications.

## 📋 Overview

This single container production setup provides:

- **High-scale IoT support**: Optimized for 50,000+ simultaneous connections
- **Security hardening**: Non-root user, resource limits, security options
- **Production logging**: File-based logging with rotation
- **SSL/TLS support**: For secure IoT communication
- **Health monitoring**: Built-in health checks and metrics
- **Simple deployment**: Single container with optional plugin support
- **Easy testing**: Comprehensive test suite for deployment verification

## 🚀 Quick Start

### Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- 2GB+ RAM available
- Ports 1883, 8883, 8080, 8083, 8888, 8889 available

### 1. Setup Environment

```bash
# Copy environment template
cp .env.prod.template .env.prod

# Edit production settings
nano .env.prod
```

**Important**: Update `DISTRIBUTED_COOKIE` with a secure random value!

### 2. Build and Deploy

```bash
# On Linux/macOS
chmod +x build-production.sh
./build-production.sh full

# On Windows (PowerShell)
.\build-production.sh full
```

### 3. Verify Deployment

```bash
# Check service status
docker-compose -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.prod.yml logs -f vernemq

# Test MQTT connection
mosquitto_pub -h localhost -p 1883 -t "test/topic" -m "Hello IoT!"
mosquitto_sub -h localhost -p 1883 -t "test/topic"
```

### 4. Run Tests

```bash
# Run comprehensive single container tests
./test-automation/test-single-container.sh full

# Or run specific test suites
./test-automation/test-single-container.sh smoke
./test-automation/test-single-container.sh integration
./test-automation/test-single-container.sh performance
```

## 📁 File Structure

```
.
├── Dockerfile                          # Single container Dockerfile
├── docker-compose.prod.yml             # Production Docker Compose configuration
├── build-production.sh                 # Automated build and deployment script
├── vernemq-production.conf.template    # Production configuration template
├── .env.prod.template                  # Environment variables template
├── test-automation/
│   ├── test-single-container.sh        # Single container test suite
│   └── ...                             # Additional test utilities
└── README-PRODUCTION.md                # This file
```

## ⚙️ Configuration

### Environment Variables

Key environment variables in `.env.prod`:

```bash
# Security (MUST CHANGE)
DISTRIBUTED_COOKIE=your_secret_cookie_value

# Resource limits
VERNEMQ_MAX_CONNECTIONS=50000
VERNEMQ_MAX_MESSAGE_SIZE=1048576

# Ports
VERNEMQ_MQTT_DEFAULT_PORT=1883
VERNEMQ_HTTP_DEFAULT_PORT=8888
```

### Custom Configuration

To use custom VerneMQ configuration:

1. Copy the template: `cp vernemq-production.conf.template vernemq-production.conf`
2. Edit the configuration file
3. Uncomment the volume mount in `docker-compose.prod.yml`:

```yaml
volumes:
  - ./vernemq-production.conf:/opt/vernemq/etc/vernemq.conf:ro
```

## 🔒 Security Configuration

### SSL/TLS Setup

For secure IoT communication:

1. **Generate or obtain SSL certificates**:
   ```bash
   # For development/testing
   mkdir ssl
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout ssl/server.key -out ssl/server.crt \
     -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
   ```

2. **Enable SSL in environment**:
   ```bash
   # In .env.prod
   VERNEMQ_LISTENER_SSL_DEFAULT=on
   VERNEMQ_LISTENER_SSL_DEFAULT_PORT=8883
   VERNEMQ_LISTENER_SSL_DEFAULT_CACERTFILE=/opt/vernemq/etc/ssl/cacert.pem
   VERNEMQ_LISTENER_SSL_DEFAULT_CERTFILE=/opt/vernemq/etc/ssl/cert.pem
   VERNEMQ_LISTENER_SSL_DEFAULT_KEYFILE=/opt/vernemq/etc/ssl/key.pem
   ```

3. **Mount SSL certificates**:
   ```yaml
   # In docker-compose.prod.yml
   volumes:
     - ./ssl:/opt/vernemq/etc/ssl:ro
   ```

### Authentication & Authorization

#### Password-based Authentication

```bash
# Create password file
docker exec -it vernemq-prod /opt/vernemq/bin/vmq-passwd \
  create /opt/vernemq/etc/vmq.password user1
```

#### ACL Configuration

Create `/opt/vernemq/etc/vmq.acl` with rules:

```
# Allow all access for authenticated users
user readwrite

# Or specific topic rules
user iot-sensor1
topic readwrite sensors/+/data

user iot-sensor2  
topic readwrite sensors/device-2/#
```

### Plugin Configuration (Optional)

Enable plugins for enhanced functionality:

```bash
# In .env.prod
# Webhooks for backend integration
VERNEMQ_PLUGIN_VMQ_WEBHOOKS=on
VERNEMQ_PLUGIN_VMQ_WEBHOOKS_HOOK_TIMEOUT=10000

# HTTP Publishing
VERNEMQ_PLUGIN_VMQ_HTTP_PUB=on

# Diversity plugin for database auth (requires external database)
# VERNEMQ_PLUGIN_VMQ_DIVERSITY=on
# VERNEMQ_VMQ_DIVERSITY_AUTH_BACKEND=vmq_plugin
```

## 📊 Monitoring & Management

### Health Checks

The container includes built-in health checks:

```bash
# Check health status
docker-compose -f docker-compose.prod.yml ps

# Manual health check
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin cluster status
```

### Metrics

Enable Prometheus metrics:

```bash
# In .env.prod
VERNEMQ_METRICS_ENABLED=on
VERNEMQ_METRICS_LISTENER=127.0.0.1:8889
```

Metrics available at: `http://localhost:8889/metrics`

### Management API

Access the management API:

```bash
# Cluster status
curl http://localhost:8888/api/v1/status

# Node statistics
curl http://localhost:8888/api/v1/node
```

### Logging

Logs are written to files with rotation:

```bash
# View logs
docker exec vernemq-prod tail -f /opt/vernemq/log/console.log
docker exec vernemq-prod tail -f /opt/vernemq/log/error.log

# Or use Docker logs
docker-compose -f docker-compose.prod.yml logs -f vernemq
```

## 🧪 Testing

### Single Container Test Suite

The repository includes a comprehensive test suite specifically designed for single container deployment:

```bash
# Run all tests
./test-automation/test-single-container.sh full

# Run specific test categories
./test-automation/test-single-container.sh smoke         # Basic connectivity
./test-automation/test-single-container.sh integration   # MQTT protocol tests
./test-automation/test-single-container.sh performance   # Load and throughput tests
./test-automation/test-single-container.sh security      # Security validation

# Verify deployment
./test-automation/test-single-container.sh verify

# Setup and teardown
./test-automation/test-single-container.sh setup
./test-automation/test-single-container.sh teardown
```

### Test Coverage

The test suite validates:

- **Container Health**: Health checks, restart policies, resource limits
- **MQTT Protocol**: Connectivity, QoS levels, message handling, retained messages
- **WebSocket Support**: MQTT over WebSocket functionality
- **Management API**: HTTP API for monitoring and management
- **Security**: Authentication, authorization, message size limits
- **Performance**: Concurrent connections, message throughput, latency
- **Reliability**: Error handling, recovery, graceful shutdown

## 🛠️ Operations

### Backup

Backup VerneMQ data:

```bash
# Backup data volumes
docker run --rm -v vernemq_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/vernemq-data-backup.tar.gz /data

# Backup configuration
docker exec vernemq-prod tar czf - /opt/vernemq/etc/ > vernemq-config-backup.tar.gz
```

### Updates

Update to new version:

```bash
# Pull latest changes
git pull

# Rebuild image
./build-production.sh build

# Rolling update
docker-compose -f docker-compose.prod.yml up -d --no-deps vernemq
```

### Scaling

For higher capacity requirements:

1. **Vertical Scaling**: Increase resource limits in `docker-compose.prod.yml`
2. **Load Balancing**: Use external load balancer (nginx, HAProxy, etc.)
3. **Database Offloading**: Use external Redis/PostgreSQL for session/auth data

```yaml
# Example: Increase resource limits
deploy:
  resources:
    limits:
      memory: 4G      # Increase for higher load
      cpus: '4.0'     # Increase CPU cores
    reservations:
      memory: 2G
      cpus: '2.0'
```

### Troubleshooting

#### Check service status

```bash
docker-compose -f docker-compose.prod.yml ps
docker-compose -f docker-compose.prod.yml logs vernemq
```

#### Test connectivity

```bash
# Test MQTT connection
mosquitto_pub -h localhost -p 1883 -t "test" -m "hello"

# Test WebSocket connection
# Use browser or WebSocket client to connect to ws://localhost:8080/mqtt
```

#### Debug mode

Run container in debug mode:

```bash
docker run -it --rm vernemq:latest /bin/bash
```

#### Performance tuning

1. **Monitor memory usage**: `docker stats vernemq-prod`
2. **Check connection limits**: `docker exec vernemq-prod ulimit -n`
3. **Tune Erlang VM**: Adjust `vm.args` parameters

## 📝 IoT Integration Examples

### Arduino/ESP32 Example

```cpp
#include <WiFi.h>
#include <PubSubClient.h>

const char* ssid = "your_wifi";
const char* password = "your_password";
const char* mqtt_server = "your-vernemq-host";
const int mqtt_port = 1883;
const char* mqtt_user = "iot-sensor1";
const char* mqtt_password = "sensor_password";

WiFiClient espClient;
PubSubClient client(espClient);

void setup() {
  Serial.begin(115200);
  WiFi.begin(ssid, password);
  
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);
  
  while (!client.connected()) {
    if (client.connect("ESP32Client", mqtt_user, mqtt_password)) {
      Serial.println("Connected to VerneMQ");
      client.subscribe("sensors/+/data");
    }
  }
}

void loop() {
  if (!client.connected()) {
    client.connect("ESP32Client", mqtt_user, mqtt_password);
  }
  client.loop();
  
  // Publish sensor data
  String payload = "{\"temperature\": " + String(random(20,30)) + "}";
  client.publish("sensors/device-1/data", payload.c_str());
  
  delay(5000);
}
```

### Python Client Example

```python
import paho.mqtt.client as mqtt
import json
import time

# MQTT configuration
broker = "localhost"
port = 1883
topic = "sensors/device-1/data"

def on_connect(client, userdata, flags, rc):
    print(f"Connected with result code {rc}")
    client.subscribe(topic)

def on_message(client, userdata, msg):
    print(f"{msg.topic}: {msg.payload.decode()}")

client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

client.connect(broker, port, 60)
client.loop_start()

# Publish sensor data
while True:
    data = {
        "temperature": 25.5,
        "humidity": 60.0,
        "timestamp": time.time()
    }
    client.publish(topic, json.dumps(data))
    time.sleep(5)

client.loop_stop()
```

## 🔐 Security Best Practices

1. **Change default credentials**: Update `DISTRIBUTED_COOKIE` and authentication
2. **Use SSL/TLS**: Enable SSL for production deployments
3. **Network isolation**: Use Docker networks and firewalls
4. **Regular updates**: Keep images and dependencies updated
5. **Monitor access**: Enable logging and monitoring
6. **Backup regularly**: Implement automated backup procedures
7. **Limit resources**: Set appropriate resource limits

## 📚 Additional Resources

- [VerneMQ Documentation](https://docs.vernemq.com/)
- [MQTT Protocol Specification](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [IoT Security Guidelines](https://www.nist.gov/cybersecurity/iot)

## 📞 Support

For issues and support:

1. Check the logs: `docker-compose -f docker-compose.prod.yml logs vernemq`
2. Run the test suite: `./test-automation/test-single-container.sh verify`
3. Review the troubleshooting section above
4. Consult the [VerneMQ GitHub Issues](https://github.com/vernemq/vernemq/issues)
5. Review the VerneMQ documentation

---

**Production Deployment Checklist:**

- [ ] Updated `DISTRIBUTED_COOKIE` with secure value
- [ ] Configured SSL/TLS certificates
- [ ] Set up proper authentication and authorization
- [ ] Configured resource limits
- [ ] Enabled monitoring and logging
- [ ] Tested connectivity from IoT devices
- [ ] Verified backup and recovery procedures
- [ ] Documented operational procedures
- [ ] Ran comprehensive test suite
- [ ] Validated single container deployment