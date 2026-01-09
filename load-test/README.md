# Loadtest - High-Performance Distributed Load Testing Tool

A powerful, distributed load testing tool written in Go that provides comprehensive HTTP load testing capabilities with features comparable to popular load testing tools.

## Features

- **Concurrent Request Generation**: Simulate thousands of virtual users making simultaneous HTTP requests
- **Multiple HTTP Methods**: Support for GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- **Flexible Configuration**: YAML-based configuration for all test parameters
- **Detailed Statistics**: Collect and report comprehensive metrics including:
  - Response time percentiles (P50, P90, P95, P99, P99.9)
  - Throughput (requests/second)
  - Error rates and status code distribution
  - Per-endpoint statistics
- **Distributed Testing**: Coordinate multiple nodes for higher throughput
- **Multiple Test Types**: Support for:
  - **Load Testing**: Normal expected load
  - **Stress Testing**: Push system to breaking point
  - **Endurance Testing**: Long-duration stability tests
  - **Spike Testing**: Sudden traffic spikes
- **Multiple Output Formats**: Console, JSON, and HTML reports

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd loadtest

# Build the binary
go build -o loadtest ./cmd/loadtest

# Install dependencies
go mod download
```

## Quick Start

### Basic Load Test

```bash
# Run a basic load test with default configuration
./loadtest run configs/basic.yaml

# Override configuration via command line
./loadtest run configs/basic.yaml \
  --virtual-users=100 \
  --duration=2m \
  --target=http://localhost:8080
```

### Run Different Test Types

```bash
# Stress test (push to breaking point)
./loadtest run configs/stress-test.yaml

# Endurance test (long duration stability)
./loadtest run configs/endurance-test.yaml

# Spike test (sudden traffic surge)
./loadtest run configs/spike-test.yaml

# Distributed test (multiple nodes)
./loadtest run configs/distributed.yaml
```

### Distributed Testing

Start the coordinator on a dedicated machine:
```bash
./loadtest serve --config configs/coordinator.yaml
```

Start worker nodes on each load generator machine:
```bash
./loadtest node --config configs/node.yaml
```

Then run the distributed test:
```bash
./loadtest run configs/distributed.yaml
```

## Configuration

### Basic Configuration Structure

```yaml
target:
  base_url: http://localhost:8080
  protocol: http
  host: localhost
  port: 8080
  path: /
  timeout: 30s
  keep_alive: true
  max_connections: 100
  max_idle_connections: 100

virtual_users: 50
duration: 60s
ramp_up: 10s

requests:
  - name: "homepage"
    method: GET
    endpoint: /
    weight: 1
    think_time: 500ms

  - name: "api_users"
    method: GET
    endpoint: /api/users
    weight: 2

  - name: "create_user"
    method: POST
    endpoint: /api/users
    body: '{"name": "test"}'
    weight: 1
    headers:
      Content-Type: application/json

headers:
  User-Agent: loadtest/1.0
  Accept: application/json

auth:
  type: bearer
  token: ${BEARER_TOKEN}

distributed:
  enabled: false

report:
  output: stdout
  format: console
  percentiles:
    - 50
    - 90
    - 95
    - 99
    - 99.9
```

### Configuration Options

#### Target Configuration

| Option | Type | Description |
|--------|------|-------------|
| `base_url` | string | Full base URL (alternative to host/port/path) |
| `protocol` | string | HTTP protocol (http or https) |
| `host` | string | Target host |
| `port` | int | Target port |
| `path` | string | Base path for all requests |
| `timeout` | duration | Request timeout |
| `keep_alive` | bool | Enable HTTP keep-alive |
| `max_connections` | int | Maximum connections per host |
| `max_idle_connections` | int | Maximum idle connections |

#### Request Configuration

| Option | Type | Description |
|--------|------|-------------|
| `name` | string | Request name for tracking |
| `method` | string | HTTP method (GET, POST, PUT, etc.) |
| `endpoint` | string | Request endpoint (appended to base URL) |
| `body` | string | Request body |
| `body_file` | string | Path to file containing request body |
| `weight` | int | Request weight for distribution |
| `think_time` | duration | Delay between requests |
| `timeout` | duration | Per-request timeout override |
| `headers` | map | Custom headers |

#### Virtual User Configuration

| Option | Type | Description |
|--------|------|-------------|
| `virtual_users` | int | Number of concurrent virtual users |
| `duration` | duration | Test duration |
| `ramp_up` | duration | Time to gradually add all VUs |

#### Report Configuration

| Option | Type | Description |
|--------|------|-------------|
| `output` | string | Output destination (stdout, file path) |
| `format` | string | Format (console, json, html) |
| `percentiles` | []float | Percentiles to calculate |
| `interval` | duration | Reporting interval |
| `detailed` | bool | Include detailed per-request stats |

## Test Scenarios

### 1. Load Testing

For normal expected traffic:
```yaml
target:
  host: api.example.com
  port: 443
  protocol: https

virtual_users: 100
duration: 5m
ramp_up: 1m

requests:
  - name: "api_call"
    method: GET
    endpoint: /api/data
    weight: 1
```

### 2. Stress Testing

To find system breaking point:
```yaml
target:
  host: api.example.com
  port: 443
  protocol: https

virtual_users: 2000
duration: 10m
ramp_up: 2m

requests:
  - name: "heavy_query"
    method: GET
    endpoint: /api/search?q=complex
    weight: 5
```

### 3. Endurance Testing

For long-running stability tests:
```yaml
target:
  host: api.example.com
  port: 8080
  protocol: http

virtual_users: 50
duration: 4h
ramp_up: 5m

requests:
  - name: "health_check"
    method: GET
    endpoint: /health
    weight: 1
```

### 4. Spike Testing

For sudden traffic spikes:
```yaml
target:
  host: api.example.com
  port: 8080
  protocol: http

virtual_users: 50
duration: 2m
ramp_up: 10s

scenarios:
  - name: "spike"
    type: spike
    virtual_users: 500
    duration: 30s
```

## Interpreting Results

### Key Metrics

- **Throughput (RPS)**: Requests per second - indicates system capacity
- **Error Rate**: Percentage of failed requests - should be < 1% for healthy systems
- **Latency Percentiles**:
  - P50: Median response time
  - P95: 95% of requests are faster than this
  - P99: Extreme outliers
- **Standard Deviation**: Consistency of response times

### Example Output

```
=======================================
         LOAD TEST RESULTS
=======================================

Test Information:
  Start Time:      2024-01-15T10:00:00Z
  Duration:        1m0s
  Total Requests:  15000
  Virtual Users:   250

Performance Summary:
  Throughput:      250.00 req/s
  Total Bytes:     15.5 MB sent, 45.2 MB received

Latency Distribution (in milliseconds):
  Min:            12.5 ms
  Average:        45.2 ms
  Std Dev:        15.3 ms
  Median (P50):   38.5 ms
  P90:            72.1 ms
  P95:            95.4 ms
  P99:            185.3 ms
  P99.9:          312.3 ms
  Max:            542.0 ms

Error Summary:
  Total Errors:   45
  Error Rate:     0.30%
```

## Environment Variables

Support for environment variables in configuration:

```yaml
auth:
  token: ${API_TOKEN}
  api_key: ${API_KEY}
```

Set environment variables:
```bash
export API_TOKEN="your-token-here"
export API_KEY="your-api-key"
```

## Architecture

### Components

1. **Config Loader**: Loads and validates YAML configurations
2. **HTTP Client**: Optimized HTTP client with connection pooling
3. **Virtual User Scheduler**: Manages concurrent virtual users
4. **Metrics Collector**: Collects and aggregates response data
5. **Reporter**: Generates formatted output reports
6. **Distributed Coordinator**: Manages multi-node test coordination

### Performance Characteristics

- **Single Node**: Can simulate 1000+ VUs on modern hardware
- **Distributed**: Linear scaling with additional nodes
- **Low Overhead**: < 5% CPU overhead from load test tool itself

## Best Practices

1. **Start Small**: Begin with lower VU count and increase gradually
2. **Monitor Target**: Watch system metrics on the target system
3. **Isolate Network**: Run load generators from isolated network
4. **Warm Up**: Always include ramp-up period
5. **Multiple Runs**: Run tests multiple times for consistency
6. **Save Results**: Always save JSON results for later analysis

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `go test ./...`
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

Inspired by:
- k6
- Gatling
- Locust
- Artillery
