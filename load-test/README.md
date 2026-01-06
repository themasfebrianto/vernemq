# VerneMQ Load Testing Worker

Simple Node.js worker to generate MQTT traffic for load testing VerneMQ.

## Quick Start

```bash
cd load-test
npm install
npm start
```

## Usage

```bash
node worker.js [options]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--host` | localhost | MQTT broker host |
| `--port` | 1883 | MQTT broker port |
| `--clients` | 10 | Number of clients to simulate |
| `--interval` | 1000 | Message interval in milliseconds |
| `--duration` | 60 | Test duration in seconds |
| `--qos` | 1 | QoS level (0, 1, or 2) |

### Presets

```bash
# Light load: 5 clients, 2s interval, 60s duration
npm run light

# Medium load: 20 clients, 500ms interval, 120s duration
npm run medium

# Heavy load: 50 clients, 100ms interval, 300s duration
npm run heavy
```

### Custom Example

```bash
# 30 clients, publishing every 200ms for 2 minutes
node worker.js --clients 30 --interval 200 --duration 120
```

## What It Does

1. **Connects** multiple MQTT clients using test users (testuser, devuser, device1)
2. **Publishes** random sensor data (temperature, humidity, pressure, battery)
3. **Subscribes** to test topics to receive messages
4. **Shows** real-time statistics (publish rate, receive rate, errors)

## Topics Used

- `sensors/temperature`
- `sensors/humidity`
- `sensors/pressure`
- `devices/status`
- `devices/telemetry`
- `test/load`
- `test/stress`

## Sample Output

```
╔════════════════════════════════════════════════════════════╗
║         VerneMQ Load Testing Worker                        ║
╠════════════════════════════════════════════════════════════╣
║  Host:        localhost:1883                               ║
║  Clients:     10                                           ║
║  Interval:    1000ms                                       ║
║  Duration:    60s                                          ║
╠════════════════════════════════════════════════════════════╣
║  ⏱️  Elapsed:     15.2s                                    ║
║  🔗 Connected:   10                                        ║
║  📤 Published:   152                                       ║
║  📥 Received:    1520                                      ║
║  ⚡ Pub Rate:    10.0 msg/sec                              ║
║  📊 Recv Rate:   100.0 msg/sec                             ║
║  ❌ Errors:      0                                         ║
╚════════════════════════════════════════════════════════════╝
```

## Monitor in Dashboard

While the load test runs, open http://localhost:5000/ and check the **Monitoring** tab to see VerneMQ metrics.
