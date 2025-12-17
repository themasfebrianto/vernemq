# VerneMQ Production Container - Complete Guide

## Table of Contents
1. [What is This Container?](#what-is-this-container)
2. [Architecture Overview](#architecture-overview)
3. [Container Build Process](#container-build-process)
4. [Dependencies and Requirements](#dependencies-and-requirements)
5. [Installation and Setup](#installation-and-setup)
6. [Configuration Guide](#configuration-guide)
7. [Deployment Methods](#deployment-methods)
8. [Testing and Validation](#testing-and-validation)
9. [Monitoring and Management](#monitoring-and-management)
10. [Security Configuration](#security-configuration)
11. [Troubleshooting](#troubleshooting)
12. [Advanced Usage](#advanced-usage)

---

## What is This Container?

This is a **production-ready VerneMQ container** designed for high-scale IoT messaging applications. VerneMQ is a high-performance, distributed MQTT message broker that supports the MQTT protocol versions 3.1, 3.1.1, and 5.0.

### Key Features

- **High-Scale IoT Support**: Optimized for 50,000+ simultaneous connections
- **Multi-Protocol Support**: MQTT TCP, MQTT SSL/TLS, WebSocket, WebSocket SSL
- **Production Security**: Non-root user, resource limits, security hardening
- **Health Monitoring**: Built-in health checks and metrics collection
- **Easy Deployment**: Single container with Docker Compose automation
- **Comprehensive Testing**: Full test suite for validation
- **Persistent Storage**: Named volumes for data and configuration
- **Management API**: HTTP API for monitoring and administration

### Supported Protocols and Ports

| Protocol | Port | Description |
|----------|------|-------------|
| MQTT TCP | 1883 | Standard MQTT connection |
| MQTT SSL/TLS | 8883 | Secure MQTT with SSL/TLS |
| WebSocket | 8080 | MQTT over WebSocket |
| WebSocket SSL | 8083 | Secure MQTT over WebSocket |
| Management HTTP | 8888 | HTTP API for management |
| Management HTTPS | 8889 | Secure HTTP API |

---

## Architecture Overview

### Single Container Design
This setup uses a **single container approach** rather than a clustered setup, making it ideal for:
- Small to medium IoT deployments
- Development and testing environments
- Edge computing scenarios
- Simplified operational management

### Container Architecture

```
┌─────────────────────────────────────────┐
│           VerneMQ Container             │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │   MQTT      │  │   WebSocket     │  │
│  │   Broker    │  │   Handler       │  │
│  │  (Port 1883)│  │  (Port 8080)    │  │
│  └─────────────┘  └─────────────────┘  │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │   SSL/TLS   │  │  Management     │  │
│  │   Handler   │  │  API (8888)     │  │
│  │ (Port 8883) │  │                 │  │
│  └─────────────┘  └─────────────────┘  │
│  ┌─────────────────────────────────┐    │
│  │        VerneMQ Core             │    │
│  │    - Message Routing            │    │
│  │    - Session Management         │    │
│  │    - Authentication             │    │
│  │    - Authorization              │    │
│  └─────────────────────────────────┘    │
│  ┌─────────────┐  ┌─────────────────┐    │
│  │   Volume    │  │   Log Files     │    │
│  │   Mounts    │  │   (Rotation)    │    │
│  └─────────────┘  └─────────────────┘    │
└─────────────────────────────────────────┘
         │                │
    ┌────▼────┐      ┌───▼────┐
    │  Data   │      │  Logs  │
    │ Storage │      │ Storage│
    │ Volume  │      │ Volume │
    └─────────┘      └────────┘
```

### Technology Stack

- **Base Image**: `erlang:26.2-slim` - Erlang/OTP runtime
- **Build Tool**: `rebar3` - Erlang project management
- **Container Runtime**: Docker with Docker Compose
- **Operating System**: Debian-based (slim)
- **MQTT Broker**: VerneMQ (latest version)
- **Monitoring**: Health checks and Prometheus metrics

---

## Container Build Process

### Multi-Stage Dockerfile

The container uses a **two-stage build process** for optimal image size and security:

#### Stage 1: Builder (Build Dependencies)
```dockerfile
FROM erlang:26.2-slim as builder

# Install build tools
RUN apt-get update && apt-get install -y \
    git make gcc g++ libc6-dev \
    libssl-dev libncurses-dev \
    libatomic1 libsnappy-dev wget

# Install rebar3
RUN wget https://github.com/erlang/rebar3/releases/download/3.23.0/rebar3 && \
    chmod +x rebar3 && mv rebar3 /usr/local/bin/

# Build the application
COPY rebar.config rebar.lock ./
COPY Makefile ./
COPY apps/ ./
RUN rebar3 release
```

#### Stage 2: Runtime (Minimal Dependencies)
```dockerfile
FROM erlang:26.2-slim as runtime

# Create non-root user
RUN groupadd -r vernemq && useradd -r -g vernemq vernemq

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y \
    libatomic1 libncurses6 libssl3 libsnappy1v5

# Copy built application
COPY --from=builder /build/_build/default/rel/vernemq/ /opt/vernemq/

# Setup directories and permissions
RUN mkdir -p /opt/vernemq/data/broker \
    /opt/vernemq/data/msgstore \
    /opt/vernemq/log/sasl \
    /opt/vernemq/etc/conf.d && \
    chown -R vernemq:vernemq /opt/vernemq

USER vernemq
EXPOSE 1883 8883 8080 8083 44053 8888
ENTRYPOINT ["/opt/vernemq/bin/vernemq"]
```

### Build Process Flow

1. **Source Code Compilation**: Erlang source code compiled with rebar3
2. **Release Creation**: Creates self-contained Erlang release
3. **Dependency Optimization**: Only runtime dependencies in final image
4. **Security Hardening**: Non-root user, minimal attack surface
5. **Health Checks**: Built-in health monitoring
6. **Version Tagging**: Build metadata and version tracking

---

## Dependencies and Requirements

### System Requirements

#### Minimum Requirements
- **OS**: Linux, macOS, or Windows with Docker Desktop
- **RAM**: 2GB available memory
- **CPU**: 2 cores recommended
- **Storage**: 10GB free space
- **Network**: Ports 1883, 8883, 8080, 8083, 8888, 8889 available

#### Recommended Requirements
- **RAM**: 4GB+ for production workloads
- **CPU**: 4+ cores for high concurrency
- **Storage**: SSD for better I/O performance
- **Network**: Gigabit Ethernet for high throughput

### Required Software

#### Essential Dependencies
```bash
# Docker Engine 20.10+
docker --version

# Docker Compose 2.0+
docker-compose --version

# Git (for version tracking)
git --version

# Build tools (on host system)
# Ubuntu/Debian
sudo apt-get install build-essential

# CentOS/RHEL
sudo yum groupinstall "Development Tools"

# macOS (with Homebrew)
brew install gcc make
```

#### Testing Dependencies
```bash
# MQTT client tools
sudo apt-get install mosquitto-clients  # Ubuntu/Debian
brew install mosquitto                  # macOS
choco install mosquitto                 # Windows

# HTTP testing tools
curl --version
nc (netcat) -- version

# Optional: Load testing tools
sudo apt-get install apache2-utils      # Ubuntu/Debian
brew install httpd-tools                # macOS
```

### Environment Variables

#### Required Variables
```bash
# SECURITY: MUST be changed for production
DISTRIBUTED_COOKIE=your_super_secret_cookie_value

# Build information
BUILD_DATE=2025-12-17
VCS_REF=main

# Resource configuration
VERNE_MQ_MAX_CONNECTIONS=50000
VERNE_MQ_MAX_MESSAGE_SIZE=1048576
```

#### Optional Variables
```bash
# SSL/TLS Configuration
VERNE_MQ_LISTENER_SSL_DEFAULT=on
VERNE_MQ_LISTENER_SSL_DEFAULT_CERTFILE=/opt/vernemq/etc/ssl/cert.pem

# Plugin Configuration
VERNE_MQ_PLUGIN_VMQ_DIVERSITY=on
VERNE_MQ_VMQ_DIVERSITY_AUTH_BACKEND=vmq_plugin

# Monitoring
VERNE_MQ_METRICS_ENABLED=on
VERNE_MQ_METRICS_LISTENER=127.0.0.1:8889
```

---

## Installation and Setup

### Quick Start

#### 1. Clone or Download Repository
```bash
# If you have the repository locally
cd vernemq

# Verify required files exist
ls -la Dockerfile docker-compose.prod.yml .env.prod.template
```

#### 2. Environment Setup
```bash
# Copy environment template
cp .env.prod.template .env.prod

# Edit with your settings (REQUIRED)
nano .env.prod  # Linux/macOS
notepad .env.prod  # Windows
```

#### 3. Critical Configuration
Edit `.env.prod` and update these values:
```bash
# SECURITY: Change this to a unique, secure value
DISTRIBUTED_COOKIE=your_secret_cookie_$(date +%s)

# Optional: Build information
BUILD_DATE=2025-12-17
VCS_REF=main

# Resource limits (adjust based on your system)
VERNE_MQ_MAX_CONNECTIONS=50000
```

#### 4. Build and Deploy
```bash
# Make script executable (Linux/macOS)
chmod +x build-production.sh

# Automated build and deployment
./build-production.sh full

# Or manual deployment
docker build -t vernemq:latest .
docker-compose -f docker-compose.prod.yml up -d
```

#### 5. Verify Deployment
```bash
# Check container status
docker-compose -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.prod.yml logs -f vernemq

# Test connectivity
curl http://localhost:8888/api/v1/status
```

---

## Configuration Guide

### Environment Configuration

#### Basic Configuration (`.env.prod`)
```bash
# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

# IMPORTANT: Change this to a unique, secret value
DISTRIBUTED_COOKIE=CHANGE_THIS_SECRET_COOKIE_VALUE

# =============================================================================
# RESOURCE CONFIGURATION
# =============================================================================

# Node name (single container)
VERNE_MQ_NODENAME=VerneMQ@vernemq

# Maximum connections (optimized for IoT)
VERNE_MQ_MAX_CONNECTIONS=50000

# Maximum message size in bytes (1MB)
VERNE_MQ_MAX_MESSAGE_SIZE=1048576

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================

# MQTT ports
VERNE_MQ_MQTT_DEFAULT_PORT=1883
VERNE_MQ_MQTTS_DEFAULT_PORT=8883
VERNE_MQ_MQTT_DEFAULT_WS_PORT=8080
VERNE_MQ_MQTTS_DEFAULT_WS_PORT=8083

# Management ports
VERNE_MQ_HTTP_DEFAULT_PORT=8888
VERNE_MQ_HTTPS_DEFAULT_PORT=8889

# =============================================================================
# SECURITY SETTINGS
# =============================================================================

# Authentication settings
VERNE_MQ_ALLOW_ANONYMOUS=off

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

# Log levels
VERNE_MQ_LOG_CONSOLE=file
VERNE_MQ_LOG_ERROR=on
VERNE_MQ_LOG_CONSOLE_LEVEL=info

# Memory high watermark
VERNE_MQ_VMQ_MEMORY_HIGH_WATERMARK=0.75

# File descriptor limit
VERNE_MQ_ULIMIT_OPEN_FILES=65536
```

#### SSL/TLS Configuration
```bash
# Enable SSL/TLS
VERNE_MQ_LISTENER_SSL_DEFAULT=on
VERNE_MQ_LISTENER_SSL_DEFAULT_PORT=8883
VERNE_MQ_LISTENER_SSL_DEFAULT_PROTOCOLS=tlsv1.2,tlsv1.3

# Certificate files (mount these in docker-compose.prod.yml)
VERNE_MQ_LISTENER_SSL_DEFAULT_CACERTFILE=/opt/vernemq/etc/ssl/cacert.pem
VERNE_MQ_LISTENER_SSL_DEFAULT_CERTFILE=/opt/vernemq/etc/ssl/cert.pem
VERNE_MQ_LISTENER_SSL_DEFAULT_KEYFILE=/opt/vernemq/etc/ssl/key.pem
```

#### Plugin Configuration
```bash
# Webhooks for backend integration
VERNE_MQ_PLUGIN_VMQ_WEBHOOKS=on
VERNE_MQ_PLUGIN_VMQ_WEBHOOKS_HOOK_TIMEOUT=10000

# HTTP publishing
VERNE_MQ_PLUGIN_VMQ_HTTP_PUB=on
VERNE_MQ_PLUGIN_VMQ_HTTP_PUB_BIND=127.0.0.1
VERNE_MQ_PLUGIN_VMQ_HTTP_PUB_PORT=8889

# Diversity plugin for database authentication
VERNE_MQ_PLUGIN_VMQ_DIVERSITY=on
VERNE_MQ_VMQ_DIVERSITY_AUTH_BACKEND=vmq_plugin
```

### Docker Compose Configuration

#### Production Configuration (`docker-compose.prod.yml`)
```yaml
version: "3.9"

services:
  vernemq:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        - BUILD_DATE=${BUILD_DATE:-latest}
        - VCS_REF=${VCS_REF:-local}
    image: vernemq:latest
    container_name: vernemq-prod
    restart: unless-stopped
    
    # Network configuration
    ports:
      - "1883:1883"   # MQTT TCP
      - "8883:8883"   # MQTT SSL/TLS
      - "8080:8080"   # WebSocket
      - "8083:8083"   # WebSocket SSL/TLS
      - "8888:8888"   # Management HTTP
      - "8889:8889"   # Management HTTPS
    
    # Environment variables
    environment:
      - VERNEMQ_NODENAME=VerneMQ@vernemq
      - VERNEMQ_DISTRIBUTED_COOKIE=${DISTRIBUTED_COOKIE}
      - VERNEMQ_MAX_CONNECTIONS=50000
      - VERNEMQ_ALLOW_ANONYMOUS=off
      - VERNEMQ_LOG_CONSOLE=file
      - VERNEMQ_LOG_ERROR=file
      - VERNEMQ_MAX_MESSAGE_SIZE=1048576
      - VERNEMQ_METRICS_ENABLED=on
    
    # Resource limits
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '2.0'
        reservations:
          memory: 1G
          cpus: '1.0'
    
    # Volume mounts
    volumes:
      - vernemq_data:/opt/vernemq/data
      - vernemq_log:/opt/vernemq/log
      - vernemq_etc:/opt/vernemq/etc
    
    # Health check
    healthcheck:
      test: ["CMD", "/opt/vernemq/bin/vmq-admin", "cluster", "status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    # Security options
    security_opt:
      - no-new-privileges:true
    
    # User configuration
    user: "vernemq:vernemq"
    
    # Network
    networks:
      - vernemq_network

# Named volumes
volumes:
  vernemq_data:
    driver: local
  vernemq_log:
    driver: local
  vernemq_etc:
    driver: local

# Custom network
networks:
  vernemq_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

---

## Deployment Methods

### Method 1: Automated Build Script

#### Linux/macOS
```bash
# Make executable
chmod +x build-production.sh

# Full build and deployment
./build-production.sh full

# Build only
./build-production.sh build

# Deploy only
./build-production.sh deploy

# Clean up
./build-production.sh clean
```

#### Windows
```powershell
# Using PowerShell
.\build-production.sh full

# Using Command Prompt
build-production.sh full
```

### Method 2: Manual Deployment

#### Step 1: Build Image
```bash
# Build with version metadata
docker build \
    --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
    --build-arg VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "local") \
    -t vernemq:latest \
    -f Dockerfile .
```

#### Step 2: Start Services
```bash
# Start production environment
docker-compose -f docker-compose.prod.yml up -d

# Check status
docker-compose -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.prod.yml logs -f vernemq
```

#### Step 3: Verify Deployment
```bash
# Test health check
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin cluster status

# Test management API
curl http://localhost:8888/api/v1/status

# Test MQTT connectivity
mosquitto_pub -h localhost -p 1883 -t "test/topic" -m "Hello VerneMQ!"
```

### Method 3: Development Environment

#### Start All Services (Including Databases)
```bash
# Start full development stack
docker-compose up -d

# Start only VerneMQ
docker-compose up -d vernemq

# View all service logs
docker-compose logs -f
```

### Method 4: Custom Configuration

#### SSL/TLS Setup
```bash
# Create SSL directory
mkdir ssl

# Generate self-signed certificate (for testing)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/server.key -out ssl/server.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Update docker-compose.prod.yml to mount SSL certificates
# volumes:
#   - ./ssl:/opt/vernemq/etc/ssl:ro

# Enable SSL in .env.prod
echo "VERNE_MQ_LISTENER_SSL_DEFAULT=on" >> .env.prod
echo "VERNE_MQ_LISTENER_SSL_DEFAULT_PORT=8883" >> .env.prod
```

---

## Testing and Validation

### Automated Testing

#### Run Full Test Suite
```bash
# All tests
./test-automation/test-single-container.sh full

# Specific test categories
./test-automation/test-single-container.sh smoke        # Basic connectivity
./test-automation/test-single-container.sh integration  # MQTT protocol tests
./test-automation/test-single-container.sh performance  # Load tests
./test-automation/test-single-container.sh security     # Security validation

# Setup and cleanup
./test-automation/test-single-container.sh setup
./test-automation/test-single-container.sh teardown

# Verify deployment
./test-automation/test-single-container.sh verify
```

#### Windows Testing
```cmd
REM All tests
test-automation\test-single-container.bat full

REM Specific tests
test-automation\test-single-container.bat smoke
test-automation\test-single-container.bat integration
test-automation\test-single-container.bat performance
```

### Manual Testing

#### Basic MQTT Tests
```bash
# Test basic connectivity
nc -zv localhost 1883

# Publish test message
mosquitto_pub -h localhost -p 1883 -t "test/topic" -m "Hello VerneMQ!"

# Subscribe to messages
mosquitto_sub -h localhost -p 1883 -t "test/topic"

# Test with QoS levels
mosquitto_pub -h localhost -p 1883 -t "test/qos" -m "QoS test" -q 1

# Test retained messages
mosquitto_pub -h localhost -p 1883 -t "test/retained" -m "Retained message" -r
```

#### Management API Tests
```bash
# Cluster status
curl http://localhost:8888/api/v1/status

# Node information
curl http://localhost:8888/api/v1/node

# Client sessions
curl http://localhost:8888/api/v1/sessions

# Topic metrics
curl http://localhost:8888/api/v1/topics

# Prometheus metrics (if enabled)
curl http://localhost:8889/metrics
```

#### WebSocket Testing
```javascript
// Browser console test
const client = mqtt.connect('ws://localhost:8080/mqtt');

client.on('connect', function () {
    console.log('Connected to WebSocket MQTT');
    client.subscribe('test/webSocket');
});

client.on('message', function (topic, message) {
    console.log(topic + ': ' + message);
});

// Publish test message
client.publish('test/webSocket', 'WebSocket test message');
```

### Load Testing

#### Concurrent Connections Test
```bash
# Test multiple concurrent publishers
for i in {1..10}; do
    mosquitto_pub -h localhost -p 1883 \
        -t "load/test$i" -m "Message $i" -q 1 &
done
wait

# Monitor resource usage
docker stats vernemq-prod
```

#### Message Rate Testing
```bash
# High-frequency message test
for i in {1..100}; do
    mosquitto_pub -h localhost -p 1883 \
        -t "rate/test" -m "Message $i" -q 0 &
    sleep 0.1
done
wait
```

---

## Monitoring and Management

### Health Monitoring

#### Built-in Health Checks
```bash
# Docker health check
docker ps | grep vernemq-prod

# Manual health check
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin cluster status

# Check container health
docker inspect --format='{{.State.Health.Status}}' vernemq-prod
```

#### Resource Monitoring
```bash
# Container statistics
docker stats vernemq-prod

# Memory usage
docker exec vernemq-prod free -h

# Disk usage
docker exec vernemq-prod df -h

# Process status
docker exec vernemq-prod ps aux | grep vernemq
```

### Log Management

#### View Logs
```bash
# Real-time Docker logs
docker-compose -f docker-compose.prod.yml logs -f vernemq

# Container-specific logs
docker logs -f vernemq-prod

# VerneMQ application logs
docker exec vernemq-prod tail -f /opt/vernemq/log/console.log
docker exec vernemq-prod tail -f /opt/vernemq/log/error.log

# SASL logs (Erlang/OTP)
docker exec vernemq-prod tail -f /opt/vernemq/log/sasl/error.log
```

#### Log Rotation
Logs are automatically rotated by VerneMQ configuration:
- **console.log**: Application messages
- **error.log**: Error messages only
- **sasl/**: Erlang system messages

### Management API

#### Available Endpoints
```bash
# System status
GET /api/v1/status

# Node information
GET /api/v1/node

# Client sessions
GET /api/v1/sessions
GET /api/v1/sessions/{client_id}

# Topic information
GET /api/v1/topics
GET /api/v1/topics/{topic}

# Metrics (if enabled)
GET /metrics  # Prometheus format
```

#### Management Examples
```bash
# Get system status
curl -s http://localhost:8888/api/v1/status | jq .

# List active sessions
curl -s http://localhost:8888/api/v1/sessions | jq '.sessions | length'

# Get topic metrics
curl -s http://localhost:8888/api/v1/topics | jq .

# Monitor with watch
watch -n 5 'curl -s http://localhost:8888/api/v1/status | jq .'
```

---

## Security Configuration

### Authentication Setup

#### Password-based Authentication
```bash
# Create password file
docker exec -it vernemq-prod /opt/vernemq/bin/vmq-passwd \
    create /opt/vernemq/etc/vmq.password user1

# Add more users
docker exec -it vernemq-prod /opt/vernemq/bin/vmq-passwd \
    adduser /opt/vernemq/etc/vmq.password user2
```

#### ACL Configuration
```bash
# Create ACL file
docker exec vernemq-prod sh -c "cat > /opt/vernemq/etc/vmq.acl << 'EOF'
# Allow all access for authenticated users
user readwrite

# Specific user permissions
user iot-sensor1
topic readwrite sensors/+/data

user iot-device2
topic readwrite devices/device-2/#

# Topic-level permissions
user admin
topic readwrite #
EOF"
```

### SSL/TLS Configuration

#### Generate SSL Certificates
```bash
# Create SSL directory
mkdir -p ssl

# Generate private key
openssl genrsa -out ssl/server.key 2048

# Generate certificate signing request
openssl req -new -key ssl/server.key -out ssl/server.csr \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Generate self-signed certificate
openssl x509 -req -days 365 -in ssl/server.csr \
    -signkey ssl/server.key -out ssl/server.crt

# Create certificate bundle (if needed)
cat ssl/server.crt ssl/server.key > ssl/server.pem
```

#### SSL Configuration in Docker Compose
```yaml
# In docker-compose.prod.yml
volumes:
  - ./ssl:/opt/vernemq/etc/ssl:ro
  # ... other volumes

# In .env.prod
VERNE_MQ_LISTENER_SSL_DEFAULT=on
VERNE_MQ_LISTENER_SSL_DEFAULT_PORT=8883
VERNE_MQ_LISTENER_SSL_DEFAULT_CACERTFILE=/opt/vernemq/etc/ssl/cacert.pem
VERNE_MQ_LISTENER_SSL_DEFAULT_CERTFILE=/opt/vernemq/etc/ssl/cert.pem
VERNE_MQ_LISTENER_SSL_DEFAULT_KEYFILE=/opt/vernemq/etc/ssl/key.pem
```

### Security Best Practices

#### Container Security
- **Non-root user**: Container runs as `vernemq:vernemq`
- **Resource limits**: Prevents resource exhaustion attacks
- **Read-only root**: Consider adding `read-only: true` to docker-compose
- **No new privileges**: Security option prevents privilege escalation

#### Network Security
```bash
# Use Docker networks for isolation
docker network create vernemq_network

# Consider firewall rules
sudo ufw allow 1883/tcp
sudo ufw allow 8883/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 8083/tcp
sudo ufw allow 8888/tcp
```

#### Environment Security
```bash
# Use strong, unique secrets
DISTRIBUTED_COOKIE=$(openssl rand -base64 32)

# Disable anonymous access
VERNE_MQ_ALLOW_ANONYMOUS=off

# Enable SSL/TLS in production
VERNE_MQ_LISTENER_SSL_DEFAULT=on

# Use proper file permissions
chmod 600 ssl/server.key
```

---

## Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check logs for errors
docker-compose -f docker-compose.prod.yml logs vernemq

# Check if ports are already in use
netstat -tlnp | grep -E '1883|8883|8080|8083|8888|8889'

# Verify environment file
cat .env.prod | grep DISTRIBUTED_COOKIE

# Check Docker daemon
docker info
```

#### Port Conflicts
```bash
# Find process using port 1883
lsof -i :1883  # Linux/macOS
netstat -ano | findstr :1883  # Windows

# Stop conflicting service or change port
# Edit docker-compose.prod.yml to use different ports
```

#### Memory Issues
```bash
# Check system memory
free -h  # Linux/macOS
wmic OS get TotalVisibleMemorySize,FreePhysicalMemory  # Windows

# Monitor container memory
docker stats vernemq-prod

# Reduce resource limits in docker-compose.prod.yml
# deploy:
#   resources:
#     limits:
#       memory: 1G  # Reduced from 2G
```

#### Permission Issues
```bash
# Check Docker permissions
docker ps  # Should work without sudo

# Add user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Check file ownership
ls -la ssl/
chown vernemq:vernemq ssl/*
```

### Debug Mode

#### Interactive Debugging
```bash
# Run container in debug mode
docker run -it --rm vernemq:latest /bin/bash

# Access running container
docker exec -it vernemq-prod /bin/bash

# Check VerneMQ status
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin cluster status

# View configuration
docker exec vernemq-prod cat /opt/vernemq/etc/vernemq.conf
```

#### Performance Debugging
```bash
# Monitor in real-time
docker stats vernemq-prod

# Check Erlang VM status
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin show status

# View detailed logs
docker exec vernemq-prod tail -f /opt/vernemq/log/console.log

# Check network connections
docker exec vernemq-prod netstat -tlnp
```

### Log Analysis

#### Common Log Messages
```bash
# Check error patterns
docker exec vernemq-prod grep -i error /opt/vernemq/log/error.log

# Monitor connection attempts
docker exec vernemq-prod grep -i "connected" /opt/vernemq/log/console.log

# Check authentication failures
docker exec vernemq-prod grep -i "auth" /opt/vernemq/log/console.log
```

#### Performance Analysis
```bash
# Monitor message rates
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin show metrics

# Check session counts
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin show sessions

# View topic statistics
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin show topics
```

---

## Advanced Usage

### Clustering (Future Enhancement)

While this is a single container setup, VerneMQ supports clustering for high availability:

```yaml
# Example cluster configuration (future enhancement)
services:
  vernemq-1:
    # ... vernemq configuration
    environment:
      - VERNEMQ_NODENAME=VerneMQ@vernemq-1
      - VERNEMQ_DISTRIBUTED_COOKIE=cluster_secret
  
  vernemq-2:
    # ... vernemq configuration
    environment:
      - VERNEMQ_NODENAME=VerneMQ@vernemq-2
      - VERNEMQ_DISTRIBUTED_COOKIE=cluster_secret
      - VERNEMQ_JOIN_CLUSTER=VerneMQ@vernemq-1
```

### Load Balancing

#### External Load Balancer
```nginx
# Nginx configuration for MQTT load balancing
upstream vernemq_mqtt {
    server vernemq-host1:1883;
    server vernemq-host2:1883;
    server vernemq-host3:1883;
}

server {
    listen 1883;
    proxy_pass vernemq_mqtt;
    proxy_set_header Host $host;
}
```

### Database Integration

#### Redis for Session Storage
```yaml
# In docker-compose.yml
redis:
  image: redis:alpine
  ports:
    - "6379:6379"
  
vernemq:
  environment:
    - VERNEMQ_PLUGIN_VMQ_DIVERSITY=on
    - VERNEMQ_VMQ_DIVERSITY_AUTH_BACKEND=vmq_plugin
```

### Monitoring Integration

#### Prometheus Metrics
```bash
# Enable metrics in .env.prod
VERNE_MQ_METRICS_ENABLED=on
VERNE_MQ_METRICS_LISTENER=127.0.0.1:8889

# Scrape configuration for Prometheus
# prometheus.yml
scrape_configs:
  - job_name: 'vernemq'
    static_configs:
      - targets: ['vernemq-host:8889']
    metrics_path: /metrics
```

#### Grafana Dashboard
Import the VerneMQ dashboard for Grafana:
- Dashboard ID: Search "VerneMQ" in Grafana dashboard repository
- Metrics: Connection counts, message rates, memory usage
- Alerts: High connection counts, memory usage, message failures

### Backup and Recovery

#### Data Backup
```bash
# Backup VerneMQ data
docker run --rm -v vernemq_vernemq_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/vernemq-data-backup.tar.gz /data

# Backup configuration
docker exec vernemq-prod tar czf - /opt/vernemq/etc/ > vernemq-config-backup.tar.gz

# Backup SSL certificates
tar czf ssl-backup.tar.gz ssl/
```

#### Data Recovery
```bash
# Restore VerneMQ data
docker run --rm -v vernemq_vernemq_data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/vernemq-data-backup.tar.gz -C /

# Restore configuration
docker exec -i vernemq-prod tar xzf - -C /opt/vernemq/etc/

# Restart container
docker-compose -f docker-compose.prod.yml restart vernemq
```

### Custom Plugins

#### Developing Custom Plugins
```erlang
%% Example VerneMQ plugin (Erlang)
-module(my_plugin).
-vsn("1.0.0").

%% VerneMQ plugin callbacks
-export([auth_on_register/3, auth_on_publish/6, auth_on_subscribe/3]).

auth_on_register(_, ClientId, User) ->
    % Custom authentication logic
    ok.

auth_on_publish(_, ClientId, Topic, Payload, QoS, IsRetain) ->
    % Custom publish authorization
    ok.

auth_on_subscribe(_, ClientId, Topics) ->
    % Custom subscription authorization
    ok.
```

### Performance Tuning

#### Erlang VM Tuning
```bash
# Custom vm.args configuration
# Add to docker-compose.prod.yml
# volumes:
#   - ./vm.args:/opt/vernemq/releases/1.0.0/vm.args:ro

# vm.args content
+P 1000000
+A 30
+K true
```

#### System Tuning
```bash
# Increase file descriptor limits
# In docker-compose.prod.yml
# ulimits:
#   nofile:
#     soft: 65536
#     hard: 65536

# TCP settings (host system)
echo 'net.core.somaxconn = 65535' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Conclusion

This VerneMQ container setup provides a complete, production-ready MQTT broker solution optimized for IoT applications. The single-container approach offers simplicity while maintaining enterprise-grade features including:

- **High Performance**: 50,000+ concurrent connections
- **Security**: SSL/TLS, authentication, authorization
- **Monitoring**: Health checks, metrics, management API
- **Reliability**: Health checks, restart policies, logging
- **Flexibility**: Plugin support, custom configuration
- **Ease of Use**: Automated deployment, comprehensive testing

The setup is ideal for:
- IoT data collection applications
- Real-time messaging systems
- Development and testing environments
- Edge computing scenarios
- Small to medium-scale deployments

For larger deployments or high availability requirements, consider expanding to a clustered configuration with load balancing and database integration.