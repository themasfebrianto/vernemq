# VerneMQ Single Container - Run and Test Tutorial

This tutorial will guide you through deploying and testing a single VerneMQ container for production use.

## 📋 Prerequisites

Before starting, ensure you have:

- **Docker** 20.10+ installed and running
- **Docker Compose** 2.0+ installed
- **2GB+ available RAM**
- **Ports 1883, 8883, 8080, 8083, 8888, 8889** available
- **Git** (for cloning the repository)

### Installing Prerequisites

**On Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install docker.io docker-compose git
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

**On CentOS/RHEL:**
```bash
sudo yum install docker docker-compose git
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

**On Windows:**
- Install [Docker Desktop](https://docs.docker.com/desktop/windows/install/)
- Install [Git for Windows](https://git-scm.com/download/win)

**On macOS:**
- Install [Docker Desktop](https://docs.docker.com/desktop/mac/install/)
- Install Git: `brew install git`

## 🚀 Step 1: Repository Setup

### Clone or Download the Repository

```bash
# If you have the repository locally, navigate to it
cd vernemq

# Or if you need to clone from GitHub
git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY_NAME.git
cd YOUR_REPOSITORY_NAME
```

### Verify Setup Files

```bash
# Check that required files exist
ls -la docker-compose.prod.yml
ls -la .env.prod.template
ls -la Dockerfile

# Check test scripts exist
ls -la test-automation/test-single-container.*
```

## ⚙️ Step 2: Environment Configuration

### Create Production Environment File

```bash
# Copy the template
cp .env.prod.template .env.prod

# Edit the environment file
nano .env.prod    # Linux/macOS
notepad .env.prod # Windows
```

### Required Configuration Updates

Edit `.env.prod` and update these critical settings:

```bash
# SECURITY: Change this to a unique, secure value
DISTRIBUTED_COOKIE=your_super_secret_cookie_value_$(date +%s)

# Build information (optional)
BUILD_DATE=2025-12-17
VCS_REF=main

# Node name (keep default for single container)
VERNEMQ_NODENAME=VerneMQ@vernemq

# Resource limits (adjust based on your system)
VERNEMQ_MAX_CONNECTIONS=50000
VERNEMQ_MAX_MESSAGE_SIZE=1048576

# Ports (default values are fine)
VERNEMQ_MQTT_DEFAULT_PORT=1883
VERNEMQ_HTTP_DEFAULT_PORT=8888
```

**⚠️ IMPORTANT:** Never use the default `DISTRIBUTED_COOKIE` in production!

## 🔧 Step 3: Build and Deploy

### Option A: Using Build Script (Recommended)

**On Linux/macOS:**
```bash
# Make script executable
chmod +x build-production.sh

# Build and deploy everything
./build-production.sh full
```

**On Windows:**
```powershell
# Using PowerShell
.\build-production.sh full

# Or using Command Prompt
build-production.sh full
```

### Option B: Manual Deployment

```bash
# 1. Build the Docker image
docker build -t vernemq:latest .

# 2. Start the VerneMQ container
docker-compose -f docker-compose.prod.yml up -d

# 3. Check status
docker-compose -f docker-compose.prod.yml ps
```

## ✅ Step 4: Verify Deployment

### Check Container Status

```bash
# Check if container is running
docker ps | grep vernemq-prod

# Check container logs
docker-compose -f docker-compose.prod.yml logs vernemq

# Check container health
docker inspect --format='{{.State.Health.Status}}' vernemq-prod
```

### Verify Network Connectivity

```bash
# Test MQTT port (1883)
nc -zv localhost 1883

# Test management API (8888)
curl -s http://localhost:8888/api/v1/status

# Test WebSocket port (8080)
nc -zv localhost 8080
```

Expected outputs:
- MQTT port: `Connection to localhost port 1883 succeeded!`
- Management API: `{"status":"ok"}` or similar JSON response
- WebSocket port: `Connection to localhost port 8080 succeeded!`

## 🧪 Step 5: Run Tests

### Automated Testing

**On Linux/macOS:**
```bash
# Run all tests
./test-automation/test-single-container.sh full

# Run specific test types
./test-automation/test-single-container.sh smoke
./test-automation/test-single-container.sh integration
./test-automation/test-single-container.sh performance
./test-automation/test-single-container.sh security
```

**On Windows:**
```cmd
REM Run all tests
test-automation\test-single-container.bat full

REM Run specific test types
test-automation\test-single-container.bat smoke
test-automation\test-single-container.bat integration
```

### Manual Testing

If you have mosquitto clients installed:

```bash
# Test basic MQTT connection
mosquitto_pub -h localhost -p 1883 -t "test/topic" -m "Hello VerneMQ!"

# Test message subscription
mosquitto_sub -h localhost -p 1883 -t "test/topic"

# Test WebSocket connection (requires browser or WebSocket client)
# Connect to: ws://localhost:8080/mqtt
```

### Management API Testing

```bash
# Check cluster status
curl http://localhost:8888/api/v1/status

# Check node information
curl http://localhost:8888/api/v1/node

# Check metrics (if enabled)
curl http://localhost:8889/metrics
```

## 🔍 Step 6: Advanced Verification

### Performance Testing

```bash
# Test concurrent connections (install apache bench if needed)
ab -n 1000 -c 10 http://localhost:8888/api/v1/status

# Monitor resource usage
docker stats vernemq-prod
```

### Security Testing

```bash
# Test authentication (should fail without credentials)
mosquitto_pub -h localhost -p 1883 -t "secure/test" -m "This should fail"

# Test message size limits
echo "Large message test: $(python3 -c "print('x' * 1024)")" | \
mosquitto_pub -h localhost -p 1883 -t "size/test" -q 1
```

### Load Testing

```bash
# Install required tools (Ubuntu/Debian)
sudo apt-get install apache2-utils

# Test HTTP endpoint under load
ab -n 100 -c 10 http://localhost:8888/api/v1/status

# Test MQTT message throughput
for i in {1..50}; do
    mosquitto_pub -h localhost -p 1883 -t "load/test" -m "Message $i" &
done
wait
```

## 📊 Step 7: Monitoring and Logging

### View Logs

```bash
# Real-time logs
docker-compose -f docker-compose.prod.yml logs -f vernemq

# Container-specific logs
docker logs -f vernemq-prod

# View specific log files (inside container)
docker exec vernemq-prod tail -f /opt/vernemq/log/console.log
docker exec vernemq-prod tail -f /opt/vernemq/log/error.log
```

### Check Resource Usage

```bash
# Monitor container resources
docker stats vernemq-prod

# Check disk usage
docker system df
docker volume ls

# Check memory usage inside container
docker exec vernemq-prod free -h
```

### Health Checks

```bash
# Manual health check
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin cluster status

# Check listening ports
docker exec vernemq-prod netstat -tlnp | grep -E '1883|8883|8080|8083|8888|8889'

# Check process status
docker exec vernemq-prod ps aux | grep vernemq
```

## 🛠️ Step 8: Troubleshooting

### Common Issues and Solutions

#### Container Won't Start

```bash
# Check logs for errors
docker-compose -f docker-compose.prod.yml logs vernemq

# Check if ports are already in use
netstat -tlnp | grep -E '1883|8883|8080|8083|8888|8889'

# Restart Docker daemon (Linux)
sudo systemctl restart docker
```

#### Port Conflicts

```bash
# Find process using a port
lsof -i :1883  # Linux/macOS
netstat -ano | findstr :1883  # Windows

# Stop conflicting services or change ports in docker-compose.prod.yml
```

#### Memory Issues

```bash
# Check system memory
free -h  # Linux/macOS
wmic OS get TotalVisibleMemorySize,FreePhysicalMemory  # Windows

# Adjust container memory limits in docker-compose.prod.yml
# Reduce VERNEMQ_MAX_CONNECTIONS if needed
```

#### Permission Issues

```bash
# Check Docker permissions
docker ps  # Should work without sudo

# Add user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker
```

### Reset and Retry

```bash
# Clean up everything
docker-compose -f docker-compose.prod.yml down --volumes --remove-orphans
docker system prune -f

# Start fresh
./build-production.sh full
```

## 🔄 Step 9: Production Deployment

### SSL/TLS Setup (Optional)

```bash
# Create SSL directory
mkdir ssl

# Generate self-signed certificates (for testing)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/server.key -out ssl/server.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Enable SSL in .env.prod
echo "VERNEMQ_LISTENER_SSL_DEFAULT=on" >> .env.prod
echo "VERNEMQ_LISTENER_SSL_DEFAULT_PORT=8883" >> .env.prod
```

### Backup Configuration

```bash
# Backup VerneMQ data
docker run --rm -v vernemq_vernemq_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/vernemq-data-backup.tar.gz /data

# Backup configuration
docker exec vernemq-prod tar czf - /opt/vernemq/etc/ > vernemq-config-backup.tar.gz
```

### Production Checklist

- [ ] Updated `DISTRIBUTED_COOKIE` with secure value
- [ ] Configured SSL/TLS certificates (if needed)
- [ ] Set up proper authentication and authorization
- [ ] Configured resource limits appropriately
- [ ] Enabled monitoring and logging
- [ ] Tested connectivity from client applications
- [ ] Verified backup and recovery procedures
- [ ] Documented operational procedures

## 🎯 Step 10: Performance Tuning

### Resource Optimization

Edit `docker-compose.prod.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 4G      # Increase for higher load
      cpus: '4.0'     # Increase CPU cores
    reservations:
      memory: 2G
      cpus: '2.0'
```

### VerneMQ Configuration

Edit `.env.prod`:

```bash
# Increase connection limits
VERNEMQ_MAX_CONNECTIONS=100000

# Optimize message handling
VERNEMQ_MAX_INFLIGHT_MESSAGES=50
VERNEMQ_MAX_MESSAGE_QUEUE_SIZE=2000

# Memory optimization
VERNEMQ_VMQ_MEMORY_HIGH_WATERMARK=0.85
```

## 📚 Next Steps

1. **Client Integration**: Connect your IoT devices and applications
2. **Monitoring Setup**: Configure Prometheus, Grafana, or similar
3. **Load Balancing**: Set up external load balancer if needed
4. **High Availability**: Consider clustering for redundancy
5. **Security Hardening**: Implement additional security measures

## 🆘 Getting Help

If you encounter issues:

1. Check the logs: `docker-compose -f docker-compose.prod.yml logs vernemq`
2. Run the verification script: `./verify-setup.sh` or `verify-setup.bat`
3. Check the [VerneMQ documentation](https://docs.vernemq.com/)
4. Review the [MQTT specification](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html)

## ✅ Success Criteria

Your VerneMQ deployment is successful when:

- [ ] Container starts without errors
- [ ] All required ports are accessible
- [ ] Management API responds correctly
- [ ] MQTT messages can be published and received
- [ ] WebSocket connections work
- [ ] Health checks pass
- [ ] Test suite completes successfully
- [ ] Resource usage is within expected limits

**Congratulations!** You now have a production-ready VerneMQ single container deployment.