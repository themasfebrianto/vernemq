# VerneMQ + Webhook Auth - VPS Deployment Plan

**Created:** 2026-01-06  
**Updated:** 2026-01-06  
**Purpose:** Deploy VerneMQ MQTT Broker with .NET 8 Webhook Authentication Service for development on local VPS

---

## 📋 Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Deployment Steps](#4-deployment-steps)
5. [Configuration](#5-configuration)
6. [Dashboard & User Management](#6-dashboard--user-management)
7. [Traffic Monitoring (Prometheus + Grafana)](#7-traffic-monitoring-prometheus--grafana)
8. [Testing & Validation](#8-testing--validation)
9. [Troubleshooting](#9-troubleshooting)
10. [Security Considerations](#10-security-considerations)

---

## 1. Project Overview

### What is VerneMQ?

VerneMQ is a **high-performance, distributed MQTT message broker** that supports:
- MQTT 3.1, 3.1.1, and 5.0 protocols
- High scalability (50,000+ concurrent connections)
- WebSocket support for browser-based clients
- Plugin architecture for extensibility
- Webhook-based authentication and authorization

### ✅ New Features (2026-01-06 Update)

| Feature | Description |
|---------|-------------|
| **Database-backed Users** | MQTT credentials stored in SQLite (no more hardcoded users!) |
| **Dashboard UI** | Web interface for managing MQTT users |
| **Topic Permissions** | Per-user publish/subscribe topic restrictions |
| **Login Tracking** | Last login time, IP, and login count |
| **Monitoring Guide** | Prometheus + Grafana integration for traffic visualization |

### Project Components

| Component | Technology | Port | Description |
|-----------|------------|------|-------------|
| **VerneMQ Broker** | VerneMQ (Docker) | 1883, 8080, 8888 | MQTT message broker |
| **Webhook Auth Service** | ASP.NET Core 8.0 | 5000 | Authentication/authorization webhooks |
| **SQLite Database** | SQLite | - | Stores webhook configs and logs |

### Webhook Flow

```
┌──────────────┐      ┌─────────────────┐      ┌───────────────────────┐
│  MQTT Client │─────▶│    VerneMQ      │─────▶│  Webhook Auth Service │
│  (Connect)   │      │   (Port 1883)   │      │    (Port 5000)        │
└──────────────┘      └─────────────────┘      └───────────────────────┘
                              │                          │
                              │  POST /mqtt/auth         │
                              │  POST /mqtt/publish      │
                              │  POST /mqtt/subscribe    │
                              │                          │
                              ◀──────────────────────────┘
                              {"result": "ok"} or {"result": {"error": "..."}}
```

---

## 2. Architecture

### Docker Compose Setup

```yaml
services:
  webhook-auth:       # .NET 8 Auth Service (exposed on port 5000)
    └── /mqtt/auth         # Client registration/login
    └── /mqtt/publish      # Publish authorization
    └── /mqtt/subscribe    # Subscribe authorization
    └── /mqtt/health       # Health check

  vernemq:            # VerneMQ MQTT Broker
    └── Port 1883    # MQTT TCP connections
    └── Port 8080    # WebSocket connections
    └── Port 8888    # Metrics/Status endpoint
```

### Default Test Credentials

The webhook auth service has built-in test users:

| Username | Password | Notes |
|----------|----------|-------|
| `testuser` | `testpass` | Standard test user |
| `admin` | `admin123` | Admin access (can pub/sub to admin/* topics) |
| `device1` | `device1pass` | Device simulation |
| `devuser` | `password` | Development testing |

---

## 3. Prerequisites

### VPS Requirements

- **OS:** Ubuntu 20.04+ / Debian 11+ (recommended)
- **RAM:** Minimum 2GB, recommended 4GB+
- **CPU:** 2+ cores
- **Disk:** 20GB+ free space
- **Network:** Ports 1883, 5000, 8080, 8888 available

### Required Software

```bash
# Install Docker & Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose-plugin

# Verify installation
docker --version
docker compose version

# Add your user to docker group (optional, for non-root docker)
sudo usermod -aG docker $USER
newgrp docker
```

### Optional: MQTT Testing Tools

```bash
# Install Mosquitto clients for testing
sudo apt install -y mosquitto-clients

# Verify
mosquitto_pub --help
mosquitto_sub --help
```

---

## 4. Deployment Steps

### Step 1: Transfer Project to VPS

**Option A: Git Clone (if repo exists)**
```bash
cd /home/$USER
git clone <your-repo-url> vernemq
cd vernemq
```

**Option B: SCP/SFTP Upload**
```bash
# From your local Windows machine
scp -r D:\LCS\vernemq user@your-vps-ip:/home/user/vernemq
```

**Option C: Create files manually on VPS**
```bash
mkdir -p /home/$USER/vernemq
cd /home/$USER/vernemq
# Then create docker-compose.yml and VerneMQWebhookAuth directory
```

### Step 2: Verify Project Structure

```bash
# Verify required files exist
ls -la
# Should see:
#   docker-compose.yml
#   VerneMQWebhookAuth/
#   vernemq.conf

ls -la VerneMQWebhookAuth/
# Should see:
#   Dockerfile
#   Program.cs
#   VerneMQWebhookAuth.csproj
#   Controllers/
#   Models/
```

### Step 3: Update Docker Compose Port Mapping (if needed)

The Dockerfile in `VerneMQWebhookAuth/` exposes port 80, but `docker-compose.yml` maps it to 5000. Update if needed:

```bash
# Edit the docker-compose.yml
nano docker-compose.yml
```

Ensure the mapping matches:
```yaml
webhook-auth:
  ports:
    - "5000:80"  # Host:Container - webhook app runs on port 80 inside container
```

### Step 4: Build and Start Services

```bash
# Navigate to project root
cd /home/$USER/vernemq

# Build and start all services
docker compose up -d --build

# Watch the build logs
docker compose logs -f
```

### Step 5: Verify Services are Running

```bash
# Check container status
docker compose ps

# Expected output:
# NAME           STATUS   PORTS
# webhook-auth   Up       0.0.0.0:5000->80/tcp
# vernemq        Up       0.0.0.0:1883->1883/tcp, 0.0.0.0:8080->8080/tcp, 0.0.0.0:8888->8888/tcp

# Check webhook auth health
curl http://localhost:5000/mqtt/health

# Expected: {"status":"healthy","timestamp":"..."}
```

---

## 5. Configuration

### VerneMQ Webhook Configuration

The docker-compose.yml configures three webhook endpoints:

| Hook | Endpoint | Purpose |
|------|----------|---------|
| `auth_on_register` | `http://webhook-auth:5000/mqtt/auth` | Validate client credentials on connect |
| `auth_on_publish` | `http://webhook-auth:5000/mqtt/publish` | Authorize publish to topic |
| `auth_on_subscribe` | `http://webhook-auth:5000/mqtt/subscribe` | Authorize subscription to topic |

### Webhook Cache

```yaml
DOCKER_VERNEMQ_VMQ_WEBHOOKS__CACHE_TIMEOUT=60000  # Cache auth results for 60 seconds
```

### Environment Variables (Optional Customization)

Create a `.env` file for custom settings:

```bash
# Create .env file
cat > .env << 'EOF'
# VerneMQ Settings
VERNEMQ_ACCEPT_EULA=yes
VERNEMQ_ALLOW_ANONYMOUS=off

# Webhook Cache (milliseconds)
WEBHOOK_CACHE_TIMEOUT=60000

# Port mappings
MQTT_PORT=1883
WEBSOCKET_PORT=8080
METRICS_PORT=8888
WEBHOOK_PORT=5000
EOF
```

### Custom Credentials in Webhook Service

**⚠️ DEPRECATED:** Hardcoded credentials are no longer used!

Users are now managed via:
1. **Dashboard UI** at `http://localhost:5000/` 
2. **REST API** at `/api/mqttusers`

See [Section 6: Dashboard & User Management](#6-dashboard--user-management) for details.

---

## 6. Dashboard & User Management

### Accessing the Dashboard

Open your browser and navigate to:
```
http://YOUR_VPS_IP:5000/
```

### Dashboard Features

| Tab | Description |
|-----|-------------|
| **MQTT Users** | Create, edit, delete MQTT user credentials |
| **Webhooks** | Manage outgoing webhooks |
| **Monitoring** | View VerneMQ status and traffic metrics |
| **Logs** | View webhook execution history |

### User Management via Dashboard

1. **Navigate to MQTT Users tab**
2. **Click "Add User"**
3. **Fill in the form:**
   - Username (required)
   - Password (min 8 characters)
   - Description (optional)
   - Allowed Client ID (optional - restrict to specific client)
   - Allowed Publish Topics (optional - comma-separated patterns)
   - Allowed Subscribe Topics (optional - comma-separated patterns)
   - Is Admin (checkbox for admin/* topic access)
4. **Click "Create User"**

### User Management via API

```bash
# List all users
curl http://localhost:5000/api/mqttusers

# Create a new user
curl -X POST http://localhost:5000/api/mqttusers \
  -H "Content-Type: application/json" \
  -d '{
    "username": "sensor1",
    "password": "secure_password_123",
    "description": "Temperature Sensor in Room 1",
    "allowedPublishTopics": "sensors/room1/#",
    "allowedSubscribeTopics": "commands/room1/#",
    "isAdmin": false
  }'

# Update a user
curl -X PUT http://localhost:5000/api/mqttusers/5 \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Updated description",
    "isActive": true
  }'

# Delete a user
curl -X DELETE http://localhost:5000/api/mqttusers/5

# Get user statistics
curl http://localhost:5000/api/mqttusers/stats
```

### Topic Permission Patterns

Use MQTT wildcards for topic restrictions:

| Pattern | Matches |
|---------|---------|
| `sensors/#` | `sensors/temp`, `sensors/room/1/temp`, etc. |
| `devices/+/status` | `devices/abc/status`, `devices/123/status` |
| `admin/#` | Admin topics (requires IsAdmin=true) |
| *(empty)* | All topics allowed |

---

## 7. Traffic Monitoring (Prometheus + Grafana)

### Best Practice: Prometheus + Grafana Stack

For production traffic monitoring, VerneMQ recommends using:
- **Prometheus** - Metrics collection (pull-based)
- **Grafana** - Visualization and dashboards

### VerneMQ Metrics Endpoint

VerneMQ exposes metrics at:
```
http://YOUR_VPS_IP:8888/metrics
```

### Quick Prometheus Setup (Docker)

Add to your `docker-compose.yml`:

```yaml
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    restart: always

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    restart: always

volumes:
  grafana_data:
```

### Prometheus Configuration

Create `prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'vernemq'
    static_configs:
      - targets: ['vernemq:8888']
    metrics_path: /metrics
```

### Key VerneMQ Metrics to Monitor

| Metric | Description |
|--------|-------------|
| `mqtt_connack_sent_total` | Total client connections |
| `mqtt_publish_received_total` | Messages received |
| `mqtt_publish_sent_total` | Messages sent |
| `mqtt_subscribe_received_total` | Subscriptions |
| `queue_message_in` | Messages enqueued |
| `queue_message_out` | Messages dequeued |
| `socket_open` | Open sockets |

### Pre-built Grafana Dashboards

Import these community dashboards:
- **VerneMQ Cluster TEST** (ID: 15892) - Overview metrics
- **VerneMQ Node Metrics** (ID: 9830) - Node-level details

### Steps to Set Up Grafana:

1. Access Grafana at `http://YOUR_VPS_IP:3000`
2. Login with `admin` / `admin`
3. Add Prometheus as a data source:
   - URL: `http://prometheus:9090`
4. Import dashboard (ID: 15892)
5. Select Prometheus datasource
6. View your metrics!

### Simple Monitoring Without Prometheus

For quick checks without full stack:

```bash
# Get VerneMQ status
curl http://localhost:8888/status

# List connected clients (from inside container)
docker compose exec vernemq vmq-admin session show

# Show cluster metrics
docker compose exec vernemq vmq-admin metrics show
```

---

## 8. Testing & Validation

### Test 1: Webhook Health Check

```bash
curl http://localhost:5000/mqtt/health
# Expected: {"status":"healthy","timestamp":"2026-01-06T..."}
```

### Test 2: Direct Auth Webhook Test

```bash
# Test valid credentials
curl -X POST http://localhost:5000/mqtt/auth \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "test-client-1",
    "username": "testuser",
    "password": "testpass",
    "peerAddr": "127.0.0.1"
  }'
# Expected: {"result":"ok"}

# Test invalid credentials
curl -X POST http://localhost:5000/mqtt/auth \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "test-client-1",
    "username": "testuser",
    "password": "wrongpassword",
    "peerAddr": "127.0.0.1"
  }'
# Expected: {"result":{"error":"invalid_credentials"}}
```

### Test 3: MQTT Connection (with mosquitto_pub/sub)

```bash
# Test publish with valid credentials
mosquitto_pub -h localhost -p 1883 \
  -u "testuser" -P "testpass" \
  -t "test/topic" \
  -m "Hello from VPS!"

# If successful, no output (success)
# If failed, you'll see connection refused or auth error

# Test subscribe in one terminal
mosquitto_sub -h localhost -p 1883 \
  -u "testuser" -P "testpass" \
  -t "test/topic" -v

# Then publish in another terminal
mosquitto_pub -h localhost -p 1883 \
  -u "testuser" -P "testpass" \
  -t "test/topic" \
  -m "Hello World!"
```

### Test 4: Admin Topic Authorization

```bash
# Non-admin user trying admin topic (should fail)
mosquitto_pub -h localhost -p 1883 \
  -u "testuser" -P "testpass" \
  -t "admin/secret" \
  -m "This should fail"
# Expected: Error or connection closed

# Admin user on admin topic (should succeed)
mosquitto_pub -h localhost -p 1883 \
  -u "admin" -P "admin123" \
  -t "admin/secret" \
  -m "Admin message"
# Expected: Success (no output)
```

### Test 5: WebSocket Connection

```javascript
// Test in browser console or Node.js app
// Install: npm install mqtt

const mqtt = require('mqtt');

const client = mqtt.connect('ws://YOUR_VPS_IP:8080/mqtt', {
  username: 'testuser',
  password: 'testpass',
  clientId: 'browser-client-' + Math.random().toString(16).substr(2, 8)
});

client.on('connect', () => {
  console.log('Connected!');
  client.subscribe('test/topic');
  client.publish('test/topic', 'Hello from WebSocket!');
});

client.on('message', (topic, message) => {
  console.log(`${topic}: ${message.toString()}`);
});

client.on('error', (err) => {
  console.error('Connection error:', err);
});
```

### Test 6: VerneMQ Metrics

```bash
curl http://localhost:8888/status
# Returns VerneMQ cluster status
```

---

## 9. Troubleshooting

### Common Issues

#### Issue: Container won't start

```bash
# Check logs
docker compose logs webhook-auth
docker compose logs vernemq

# Common causes:
# 1. Port already in use
sudo lsof -i :1883
sudo lsof -i :5000

# 2. Docker network issues
docker network ls
docker compose down && docker compose up -d
```

#### Issue: MQTT Connection Refused

```bash
# Verify VerneMQ is running
docker compose ps

# Check VerneMQ logs for authentication errors
docker compose logs vernemq | grep -i "auth\|error\|webhook"

# Test webhook service directly
curl http://localhost:5000/mqtt/health
```

#### Issue: Authentication Always Fails

```bash
# Check webhook-auth logs
docker compose logs webhook-auth

# Verify webhook URL is reachable from vernemq container
docker compose exec vernemq wget -qO- http://webhook-auth:5000/mqtt/health
```

#### Issue: Webhook Timeout

```bash
# Increase webhook timeout in docker-compose.yml environment
DOCKER_VERNEMQ_VMQ_WEBHOOKS__MYAUTH1__TIMEOUT=15000  # 15 seconds
```

### Useful Debug Commands

```bash
# Enter VerneMQ container shell
docker compose exec vernemq /bin/bash

# Check VerneMQ status
docker compose exec vernemq vmq-admin cluster status

# Show connected clients
docker compose exec vernemq vmq-admin session show

# Enter webhook-auth container shell
docker compose exec webhook-auth /bin/bash

# View webhook database
docker compose exec webhook-auth cat /app/webhook.db
```

---

## 10. Security Considerations

### For Development (Current Setup)

- ✅ Credentials stored in SQLite database with BCrypt hashing
- ✅ Anonymous access disabled
- ⚠️ Uses HTTP (not HTTPS) for webhook communication
- ⚠️ No TLS/SSL for MQTT connections

### For Production (Future Improvements)

```bash
# Add these to docker-compose.yml for production:

# 1. Enable MQTT TLS (port 8883)
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT=0.0.0.0:8883
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT__CERTFILE=/etc/vernemq/certs/server.crt
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT__KEYFILE=/etc/vernemq/certs/server.key

# 2. Use environment variables for credentials
# 3. Add reverse proxy (nginx) with HTTPS
# 4. Configure firewall rules
sudo ufw allow 1883/tcp  # MQTT
sudo ufw allow 8080/tcp  # WebSocket
sudo ufw allow 5000/tcp  # Webhook (internal only in production)
```

---

## 📝 Quick Reference

### Start Services
```bash
docker compose up -d --build
```

### Stop Services
```bash
docker compose down
```

### View Logs
```bash
docker compose logs -f
```

### Restart Single Service
```bash
docker compose restart webhook-auth
docker compose restart vernemq
```

### Rebuild After Code Changes
```bash
docker compose up -d --build webhook-auth
```

### Full Reset (Clear Data)
```bash
docker compose down -v  # -v removes volumes
docker compose up -d --build
```

---

## ✅ Deployment Checklist

- [ ] VPS has Docker & Docker Compose installed
- [ ] Project files transferred to VPS
- [ ] `docker compose up -d --build` completed successfully
- [ ] Both containers showing as "Up" in `docker compose ps`
- [ ] Webhook health check returns healthy (`curl http://localhost:5000/mqtt/health`)
- [ ] Dashboard accessible at `http://YOUR_VPS_IP:5000/`
- [ ] MQTT connection with `mosquitto_pub` works
- [ ] WebSocket connection (if needed) tested
- [ ] Firewall ports opened (1883, 8080, 5000, 8888)
- [ ] Custom MQTT users created via Dashboard or API
- [ ] (Optional) Prometheus + Grafana set up for monitoring

---

*Generated for VerneMQ + Webhook Auth development deployment*
*Updated: 2026-01-06 - Added database-backed users, dashboard UI, and monitoring guide*
