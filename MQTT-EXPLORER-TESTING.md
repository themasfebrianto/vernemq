# Testing VerneMQ with MQTT Explorer

MQTT Explorer is a powerful GUI tool for testing, monitoring, and debugging MQTT brokers. This guide will show you how to connect and test your VerneMQ single container setup using MQTT Explorer.

## 📥 Installing MQTT Explorer

### Download and Install

**Windows:**
- Download from: https://github.com/mqtt-explorer/mqtt-explorer/releases
- Run the `.exe` installer and follow the installation wizard

**macOS:**
- Download the `.dmg` file from the releases page
- Drag MQTT Explorer to your Applications folder
- If you get a security warning, go to System Preferences → Security & Privacy → Allow Anyway

**Linux (Ubuntu/Debian):**
```bash
# Download the AppImage
wget https://github.com/mqtt-explorer/mqtt-explorer/releases/download/v0.3.5/mqtt-explorer_0.3.5_amd64.AppImage

# Make it executable
chmod +x mqtt-explorer_0.3.5_amd64.AppImage

# Run it
./mqtt-explorer_0.3.5_amd64.AppImage
```

**Linux (using snap):**
```bash
sudo snap install mqtt-explorer
```

## 🔗 Step 1: Connect to Your VerneMQ Server

### Basic Connection Settings

1. **Open MQTT Explorer**
2. **Click "Add Connection"** or the "+" button
3. **Fill in the connection details:**

```
Host: localhost (or your server IP)
Port: 1883
Protocol: MQTT v3.1.1 (or MQTT v5.0)
Client ID: Leave empty for auto-generated
```

### Authentication Settings

Since your VerneMQ is configured with `VERNEMQ_ALLOW_ANONYMOUS=on` by default for testing:

```
Username: (leave empty)
Password: (leave empty)
```

**⚠️ For Production:** You'll need to set up authentication. See the "Production Authentication" section below.

### Connection Configuration

```
Connection Tab:
✅ Enable SSL/TLS: (unchecked for basic testing)
✅ Auto-reconnect: (checked)
✅ Clean session: (checked for testing)

Advanced Tab:
✅ Connection timeout: 30 seconds
✅ Keepalive interval: 60 seconds
✅ Will QoS: 0
```

### Test the Connection

1. **Click "Test Connection"** - You should see "Connected successfully!"
2. **Click "Connect"** to establish the connection
3. **You should see the MQTT Explorer interface** with your topics list

## 🧪 Step 2: Test MQTT Functionality

### 1. Test Topic Publishing

**Subscribe to a test topic:**
1. **Right-click** in the left sidebar
2. **Select "Add subscription"**
3. **Enter topic:** `test/explorer`
4. **Click OK**

**Publish a message:**
1. **Click the "Publish" tab** at the bottom
2. **Enter topic:** `test/explorer`
3. **Enter message:** `Hello from MQTT Explorer!`
4. **Click the "Publish" button**
5. **Switch back to "Subscribe" tab** to see your message

**Expected Result:** You should see your message appear in the subscription area.

### 2. Test Topic Filtering

**Subscribe to wildcard topics:**
1. **Add subscription:** `test/#` (receives all test subtopics)
2. **Add subscription:** `+/explorer` (receives single-level wildcards)
3. **Publish to different topics:**
   - `test/explorer`
   - `test/sensor/temperature`
   - `data/explorer`

**Expected Result:** You should see messages appear based on your subscription filters.

### 3. Test QoS Levels

**Test different QoS levels:**
1. **Subscribe with QoS 0, 1, and 2** to the same topic
2. **Publish messages with different QoS levels**
3. **Check the message details** to see QoS indicators

**Expected Result:** You should see QoS level indicators on received messages.

### 4. Test Retained Messages

**Publish a retained message:**
1. **Click the "Retained" checkbox** in the publish area
2. **Enter topic:** `test/retained`
3. **Enter message:** `This is a retained message`
4. **Click "Publish"**

**Subscribe to the retained topic:**
1. **Add subscription:** `test/retained`
2. **Disconnect and reconnect** your MQTT Explorer session

**Expected Result:** The retained message should appear immediately upon subscription.

## 📊 Step 3: Advanced Testing Features

### 1. Message History and Analysis

**Use the message history:**
- **Switch to "History" tab** to see all published messages
- **Filter by topic** using the search box
- **Export messages** to CSV or JSON format

**Analyze message patterns:**
- **Check message timestamps** and frequency
- **Monitor message sizes** and payload structure
- **Track connection/disconnection events**

### 2. Connection Monitoring

**Monitor connection status:**
- **Check the bottom status bar** for connection indicators
- **View connection statistics** in the "Connection" menu
- **Monitor message rates** and broker statistics

### 3. Bulk Operations

**Subscribe to multiple topics:**
1. **Right-click in subscription area**
2. **Select "Bulk subscribe"**
3. **Enter multiple topics** (one per line)
4. **Set QoS levels** for each topic

**Publish to multiple topics:**
1. **Use the "Bulk publish" tab**
2. **Enter multiple topic/message pairs**
3. **Execute bulk publish** operation

## 🔒 Step 4: SSL/TLS Testing (Optional)

### Configure SSL Connection

1. **Create SSL certificates** (if not already done):
```bash
mkdir ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/server.key -out ssl/server.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
```

2. **Enable SSL in VerneMQ** (in `.env.prod`):
```
VERNEMQ_LISTENER_SSL_DEFAULT=on
VERNEMQ_LISTENER_SSL_DEFAULT_PORT=8883
```

3. **Restart VerneMQ**:
```bash
docker-compose -f docker-compose.prod.yml restart vernemq
```

4. **Configure MQTT Explorer for SSL**:
```
Enable SSL/TLS: ✅ (checked)
Port: 8883
Certificate file: (path to your server.crt)
```

### Test SSL Connection

1. **Click "Test Connection"** - Should show SSL connection success
2. **Connect** and verify you can publish/subscribe over SSL
3. **Check the lock icon** in MQTT Explorer indicating secure connection

## 🔐 Step 5: Production Authentication Testing

### Setup Password Authentication

1. **Create password file** in the VerneMQ container:
```bash
docker exec -it vernemq-prod /opt/vernemq/bin/vmq-passwd \
  create /opt/vernemq/etc/vmq.password testuser
```

2. **Update VerneMQ configuration** (in `.env.prod`):
```
VERNEMQ_ALLOW_ANONYMOUS=off
VERNEMQ_PASSWORD_FILE=/opt/vernemq/etc/vmq.password
```

3. **Restart VerneMQ**:
```bash
docker-compose -f docker-compose.prod.yml restart vernemq
```

4. **Configure MQTT Explorer**:
```
Username: testuser
Password: (the password you created)
```

### Test Authentication

1. **Try connecting without credentials** - Should fail
2. **Connect with correct credentials** - Should succeed
3. **Publish/subscribe** to verify authenticated access

## 🎯 Step 6: Real-World Testing Scenarios

### IoT Sensor Simulation

**Simulate sensor data:**
1. **Subscribe to:** `sensors/+/data`
2. **Bulk publish sensor data:**
```
Topic: sensors/temperature/data
Payload: {"device": "sensor_1", "temperature": 23.5, "timestamp": "2025-12-17T05:37:00Z"}

Topic: sensors/humidity/data  
Payload: {"device": "sensor_2", "humidity": 65.2, "timestamp": "2025-12-17T05:37:00Z"}
```

### Command and Control Testing

**Test command publishing:**
1. **Subscribe to:** `device/+/commands`
2. **Publish commands:**
```
Topic: device/sensor_1/commands
Payload: {"command": "restart", "delay": 10}

Topic: device/sensor_2/commands
Payload: {"command": "calibrate", "parameter": "temperature"}
```

### Multi-Tenant Testing

**Simulate multiple clients:**
1. **Create multiple MQTT Explorer instances** or connections
2. **Test topic isolation** between different clients
3. **Verify client-specific subscriptions** work correctly

## 📈 Step 7: Performance Testing

### Connection Load Testing

1. **Create multiple connections** to the same broker
2. **Subscribe each connection** to different topic ranges
3. **Monitor broker performance** via VerneMQ management API

### Message Throughput Testing

1. **Use the bulk publish feature** to send high volumes
2. **Monitor message delivery** in real-time
3. **Check for message loss** or delays

### Long-Running Tests

1. **Keep connections active** for extended periods
2. **Monitor memory and resource usage**
3. **Test connection recovery** after network interruptions

## 🛠️ Step 8: Troubleshooting with MQTT Explorer

### Common Connection Issues

**"Connection refused" error:**
- Check if VerneMQ is running: `docker ps | grep vernemq-prod`
- Verify port 1883 is accessible: `nc -zv localhost 1883`
- Check VerneMQ logs: `docker-compose -f docker-compose.prod.yml logs vernemq`

**"Authentication failed" error:**
- Verify `VERNEMQ_ALLOW_ANONYMOUS` setting
- Check username/password if using authentication
- Ensure password file is accessible in container

**"SSL/TLS error":**
- Verify SSL certificates are valid
- Check certificate file paths in MQTT Explorer
- Ensure VerneMQ SSL configuration is correct

### Debugging Tips

1. **Use the "Connection" menu** to view detailed connection information
2. **Check the message log** for detailed MQTT packet information
3. **Monitor the status bar** for real-time connection metrics
4. **Use "Clear history"** to start fresh testing sessions

## ✅ Step 9: Verification Checklist

Use this checklist to verify your VerneMQ setup:

- [ ] MQTT Explorer connects successfully
- [ ] Can publish messages to test topics
- [ ] Can subscribe and receive messages
- [ ] Topic filtering with wildcards works
- [ ] QoS levels are properly handled
- [ ] Retained messages work correctly
- [ ] SSL/TLS connection works (if configured)
- [ ] Authentication works (if enabled)
- [ ] Multiple concurrent connections work
- [ ] Message history and monitoring work
- [ ] Connection recovery after disconnect works
- [ ] Performance meets requirements

## 🎯 Step 10: Integration Testing

### Test with Real Applications

**Test with actual IoT applications:**
1. **Connect your IoT devices** to the same broker
2. **Use MQTT Explorer to monitor** device communications
3. **Simulate various scenarios** and verify behavior

**Test with applications:**
- **Home Assistant** (MQTT integration)
- **Node-RED** (MQTT nodes)
- **Python/JavaScript MQTT clients**
- **Mobile MQTT apps**

### Bridge Testing

**If using VerneMQ bridge plugin:**
1. **Configure bridge connections** to other MQTT brokers
2. **Monitor cross-broker message flow** in MQTT Explorer
3. **Test message routing** between brokers

## 📚 Additional Resources

- [MQTT Explorer Documentation](https://github.com/mqtt-explorer/mqtt-explorer)
- [MQTT Protocol Specification](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html)
- [VerneMQ Documentation](https://docs.vernemq.com/)
- [MQTT Security Best Practices](https://www.eclipse.org/paho/index.php?page=presentations/paho-mqtt-security-best-practices.php)

## 🎉 Success!

Congratulations! You now have a comprehensive understanding of how to test your VerneMQ single container setup using MQTT Explorer. This powerful combination provides an excellent foundation for developing, debugging, and monitoring MQTT-based IoT applications.

MQTT Explorer serves as an invaluable tool for:
- **Rapid prototyping** and development
- **Debugging MQTT issues** in production
- **Monitoring message flows** in real-time
- **Testing security configurations**
- **Validating performance** under various conditions

Your VerneMQ single container deployment is now fully validated and ready for production use!