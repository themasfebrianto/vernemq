# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a VerneMQ load testing infrastructure with two main components:

1. **`mqtt-loadtest`** (`cmd/mqtt-loadtest/`) - MQTT load tester for VerneMQ broker
2. **`loadtest`** (`cmd/loadtest/`) - HTTP load testing tool with distributed capabilities

The mqtt-loadtest tool simulates RTU (Remote Terminal Unit) devices publishing realistic electrical measurement data to an MQTT broker for testing VerneMQ capacity under load.

## Build and Run Commands

### Build Commands

```bash
# Build HTTP load test binary
go build -o loadtest ./cmd/loadtest

# Build MQTT load test binary
go build -o mqtt-loadtest ./cmd/mqtt-loadtest

# Build with race detector
go build -race -o loadtest-race ./cmd/loadtest

# Install dependencies
go mod download

# Update dependencies
go get -u ./... && go mod tidy
```

### MQTT Load Test Commands

```bash
# Basic MQTT load test
./mqtt-loadtest --broker tcp://localhost:1883 --clients 10 --duration 60

# With authentication
./mqtt-loadtest -b tcp://localhost:1883 -c 50 -d 300 -u username -P password

# Custom topic and interval
./mqtt-loadtest -b tcp://localhost:1883 -c 100 -i 10 -t custom/topic --rtu-prefix "RTU"

# QoS level and verbose output
./mqtt-loadtest -b tcp://localhost:1883 -c 50 --qos 1 --verbose
```

### HTTP Load Test Commands

```bash
# Run basic HTTP load test
./loadtest run configs/basic.yaml

# Run different test types
./loadtest run configs/stress-test.yaml      # High load test
./loadtest run configs/endurance-test.yaml   # Long-duration stability
./loadtest run configs/spike-test.yaml       # Sudden traffic surge
./loadtest run configs/distributed.yaml      # Multi-node coordination

# Override config via CLI
./loadtest run configs/basic.yaml --virtual-users=100 --duration=2m

# Distributed testing - start coordinator
./loadtest serve --config configs/coordinator.yaml

# Distributed testing - start worker node
./loadtest node --config configs/node.yaml
```

### Test and Lint Commands

```bash
# Run all tests
go test ./... -v

# Format code
go fmt ./...

# Lint code (requires golangci-lint)
golangci-lint run ./...

# Generate coverage report
go test ./... -coverprofile=coverage.out
go tool cover -html=coverage.out -o coverage.html
```

### Makefile Targets

```bash
make build              # Build loadtest binary
make clean             # Clean build artifacts
make test              # Run all tests
make run-basic         # Run basic load test
make run-stress        # Run stress test
make run-endurance     # Run endurance test
make run-spike         # Run spike test
make run-distributed   # Run distributed test
make deps              # Install dependencies
make fmt               # Format code
make lint              # Lint code
make coverage          # Generate coverage report
```

## Architecture

### MQTT Load Tester (`cmd/mqtt-loadtest/main.go`)

**Key Components:**

- **`MQTTLoadClient`** struct wraps the MQTT client with:
  - `ID` and `ClientID` for identification
  - `client` (paho.mqtt.golang mqtt.Client)
  - `Config` (ClientConfig with broker, topic, auth, QoS settings)
  - `Stats` pointer to shared statistics
  - `Done` channel for graceful shutdown

- **Connection Management:**
  - Uses semaphore pattern with `maxConcurrentConns = 500` to prevent TCP backlog overwhelm
  - 20ms stagger between connection attempts to avoid thundering herd
  - Auto-reconnect disabled for controlled testing
  - 30-second connect timeout, 60-second keepalive

- **RTU Data Simulation:**
  - Generates realistic CSV payload with electrical measurements (voltage, current, power, temperature)
  - Each client publishes to its own topic: `{base_topic}/{rtu_id}`
  - RTU ID format: `{prefix}{sequential_number}` (e.g., "250901000001", "250901000002")

- **Statistics Tracking:**
  - Atomic counters for thread-safe operations
  - Tracks connections (total, success, failed) and publishes (total, success, failed)
  - Error records with timestamp, type, client ID, and message
  - Real-time progress reporting during test

### HTTP Load Tester (`cmd/loadtest/`)

The HTTP load tester uses an internal package structure under `internal/`:

- **`internal/client/`** - HTTP client implementation
- **`internal/config/`** - Configuration management with Viper
- **`internal/coordinator/`** - Distributed testing coordinator
- **`internal/metrics/`** - Metrics collection and statistics
- **`internal/reporter/`** - Result reporting
- **`internal/test/`** - Test runner implementations

**Configuration:** YAML-based with environment variable support (`${VAR_NAME}`)

**Test Scenarios:** Load, stress, endurance, spike, and distributed testing

**Distributed Architecture:** Coordinator-worker pattern for linear scaling

## Key Dependencies

- **`github.com/eclipse/paho.mqtt.golang`** v1.4.3 - MQTT client library
- **`github.com/spf13/cobra`** v1.8.0 - CLI framework
- **`github.com/spf13/viper`** v1.18.2 - Configuration management (HTTP load test)
- **`go.uber.org/zap`** v1.26.0 - Structured logging (HTTP load test)
- **`github.com/google/uuid`** v1.4.0 - UUID generation (HTTP load test)

## Important Implementation Details

### MQTT Load Tester Concurrency

The semaphore pattern at line 302 in `main.go` prevents race conditions in the MQTT client library during rapid connections:

```go
maxConcurrentConns := 500
semaphore := make(chan struct{}, maxConcurrentConns)
```

When modifying this value, be aware:
- Lower values may reduce connection rate
- Higher values may increase race conditions
- 500 provides good balance for most scenarios

### Topic Structure

Each RTU publishes to its own topic: `{base_topic}/{rtu_id}`

Example: With topic="rtu/data" and rtu-prefix="25090100000", clients publish to:
- `rtu/data/250901000001`
- `rtu/data/250901000002`
- `rtu/data/250901000003`
- `rtu/data/250901000004`
- `rtu/data/250901000005`
- `rtu/data/250901000010`
- `rtu/data/250901000011`
- `rtu/data/250901000100`
- `rtu/data/250901001000`
- etc.

### Error Handling

Errors are collected with client correlation for debugging:
- Connection errors include client ID
- Publish errors include client ID
- Recent errors (last 10) displayed in final report

### JSON Output

Set `MQTT_LOADTEST_JSON` environment variable to get JSON report:
```bash
MQTT_LOADTEST_JSON=1 ./mqtt-loadtest -b tcp://localhost:1883 -c 10
```

## Windows Environment

The project includes pre-built `.exe` files:
- `loadtest.exe` - HTTP load test binary
- `mqtt-loadtest.exe` - MQTT load test binary

PowerShell runner script: `run-load-test.ps1`
