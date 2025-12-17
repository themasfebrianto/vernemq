# VerneMQ Test Automation Suite

A comprehensive test automation framework for VerneMQ MQTT broker that covers unit tests, integration tests, performance testing, security testing, and end-to-end workflows.

## Overview

This test automation suite provides comprehensive testing capabilities for VerneMQ deployments, including:

- **Unit Tests**: Core functionality and protocol parsing
- **Integration Tests**: MQTT protocol, plugins, clustering
- **Performance Tests**: Load testing, throughput, and latency
- **Security Tests**: Authentication, authorization, TLS/SSL
- **End-to-End Tests**: Complete MQTT workflows and business scenarios

## Quick Start

### Prerequisites

Ensure you have the following tools installed:

```bash
# Required tools
- Docker & Docker Compose
- Mosquitto clients (mosquitto_pub, mosquitto_sub)
- curl, jq, nc (netcat)
- Erlang/OTP (for unit tests)
- Python3 (for some utilities)

# Install mosquitto clients on Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y mosquitto-clients

# Install on macOS
brew install mosquitto

# Install on CentOS/RHEL
sudo yum install -y mosquitto
```

### Running Tests

1. **Run all tests:**
   ```bash
   ./test-automation/run-tests.sh full
   ```

2. **Run specific test categories:**
   ```bash
   ./test-automation/run-tests.sh unit          # Unit tests only
   ./test-automation/run-tests.sh integration   # Integration tests only
   ./test-automation/run-tests.sh performance   # Performance tests only
   ./test-automation/run-tests.sh security      # Security tests only
   ./test-automation/run-tests.sh e2e           # End-to-end tests only
   ./test-automation/run-tests.sh smoke         # Smoke tests only
   ```

3. **Setup and cleanup:**
   ```bash
   ./test-automation/run-tests.sh setup         # Setup test environment
   ./test-automation/run-tests.sh clean         # Clean up test environment
   ./test-automation/run-tests.sh report        # Generate test report
   ```

## Test Categories

### 1. Unit Tests
Located in `integration/` directory:
- Core MQTT protocol functionality
- Message parsing and validation
- Plugin system components
- Authentication mechanisms

**Run unit tests:**
```bash
./test-automation/run-tests.sh unit
```

### 2. Integration Tests
Located in `integration/` directory:

#### MQTT Integration Tests (`mqtt-integration-tests.sh`)
- Basic connectivity
- Publish/subscribe functionality
- QoS levels (0, 1, 2)
- Retained messages
- Will messages
- Topic filtering
- Message size limits
- Keep-alive mechanism
- Clean session behavior

#### Plugin Integration Tests (`plugin-integration-tests.sh`)
- Diversity plugin (Redis, PostgreSQL, MongoDB, MySQL, HTTP)
- ACL plugin
- HTTP Pub plugin
- Bridge plugin
- Webhooks plugin
- Plugin configuration management

#### Clustering Integration Tests (`clustering-integration-tests.sh`)
- Cluster status monitoring
- Node discovery
- Message replication
- Session replication
- Shared subscriptions
- Load balancing
- Metrics collection
- Health monitoring

**Run integration tests:**
```bash
./test-automation/run-tests.sh integration
```

### 3. Performance Tests
Located in `performance/` directory:

#### Load Tests (`load-tests.sh`)
- Connection load handling
- Message rate testing
- Concurrent subscribers
- Sustained load
- Memory usage under load

**Run performance tests:**
```bash
./test-automation/run-tests.sh performance
```

**Performance test parameters:**
```bash
export MAX_CONNECTIONS=100           # Max concurrent connections
export MESSAGE_RATE=10              # Messages per second
export TEST_DURATION=60             # Test duration in seconds
export CONNECTION_RATE=5            # Connections per second
```

### 4. Security Tests
Located in `security/` directory:

#### Authentication Tests (`authentication-tests.sh`)
- Anonymous connection handling
- Password-based authentication
- Client certificate authentication
- Token-based authentication
- Session authentication
- Brute force protection
- Rate limiting
- Credential stuffing protection
- Session hijacking protection

**Run security tests:**
```bash
./test-automation/run-tests.sh security
```

### 5. End-to-End Tests
Located in `e2e/` directory:

#### MQTT Workflow Tests (`mqtt-workflow-tests.sh`)
- IoT sensor data workflow
- Command and control workflow
- Publish-subscribe messaging
- Data pipeline processing
- Multi-tenant scenarios
- Event sourcing patterns
- WebSocket workflows

**Run end-to-end tests:**
```bash
./test-automation/run-tests.sh e2e
```

## Test Environment

### Docker Compose Configuration

The test suite uses `docker-compose.test.yml` to set up a complete test environment:

- **VerneMQ**: Primary MQTT broker under test
- **Redis**: Session storage and caching
- **PostgreSQL**: User authentication and metadata
- **MongoDB**: Plugin data storage
- **MySQL**: Diversity plugin testing
- **Memcached**: Plugin caching
- **Nginx**: Load balancer and SSL termination

### Test Configuration

#### Environment Variables

Set these environment variables to customize test behavior:

```bash
# VerneMQ connection
export MQTT_HOST=localhost
export MQTT_PORT=1883
export SSL_PORT=8883
export WS_PORT=8080

# Database connections
export REDIS_HOST=localhost
export REDIS_PORT=6379
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export MONGODB_HOST=localhost
export MONGODB_PORT=27017

# Test parameters
export VERNEMQ_TEST_TIMEOUT=300
export VERNEMQ_TEST_PARALLEL=4
export VERNEMQ_TEST_VERBOSE=false

# Test user credentials
export TEST_USER=testuser
export TEST_PASSWORD=testpassword123
```

#### Test Configuration Files

- `test-automation/config/`: VerneMQ configuration overrides
- `test-automation/sql/`: Database initialization scripts
- `test-automation/ssl/`: SSL/TLS certificates for testing
- `test-automation/nginx/`: Nginx configuration for testing

## Test Results and Reporting

### Test Output

Test results are stored in:
- `test-results/`: HTML test reports and summaries
- `logs/`: Detailed test logs and metrics

### Generated Reports

After running tests, you can generate an HTML report:

```bash
./test-automation/run-tests.sh report
```

This creates `test-results/test-report.html` with:
- Test summary and statistics
- Test coverage information
- Performance metrics
- Security test results
- Infrastructure details

### Log Files

Detailed logs are stored in `logs/`:
- `mqtt-integration-tests.log`: MQTT protocol tests
- `plugin-integration-tests.log`: Plugin integration tests
- `clustering-integration-tests.log`: Clustering tests
- `load-tests.log`: Performance test results
- `authentication-tests.log`: Security test results
- `e2e-workflow-tests.log`: End-to-end test results

## Continuous Integration

### GitHub Actions Integration

The test suite integrates with the existing GitHub Actions workflow:

```yaml
# Add to your .github/workflows/pr.yml
- name: Run Comprehensive Tests
  run: |
    cd test-automation
    chmod +x run-tests.sh
    ./run-tests.sh full
```

### Docker CI/CD

Run tests in CI/CD pipelines:

```bash
# Build test environment
docker-compose -f docker-compose.test.yml up -d

# Run tests
./test-automation/run-tests.sh full

# Clean up
docker-compose -f docker-compose.test.yml down --volumes
```

## Customization

### Adding New Tests

1. **Create test script** in appropriate directory:
   ```bash
   # Example: test-automation/integration/my-new-test.sh
   #!/bin/bash
   
   log "Running my new test..."
   
   # Your test logic here
   
   if [ $? -eq 0 ]; then
       log_success "My new test passed"
       return 0
   else
       log_error "My new test failed"
       return 1
   fi
   ```

2. **Make executable**:
   ```bash
   chmod +x test-automation/integration/my-new-test.sh
   ```

3. **Add to main runner** in `run-tests.sh`:
   ```bash
   # Add to the tests array
   local tests=(
       # ... existing tests
       "my-new-test"
   )
   ```

### Customizing Test Parameters

Modify test parameters by editing environment variables:

```bash
# Example: Custom performance test
export MAX_CONNECTIONS=500
export MESSAGE_RATE=50
export TEST_DURATION=300
./test-automation/run-tests.sh performance
```

### Adding Custom Configurations

1. **Database configurations**: Edit `test-automation/sql/init-test.sql`
2. **VerneMQ settings**: Add to `test-automation/config/`
3. **SSL certificates**: Place in `test-automation/ssl/`
4. **Nginx settings**: Modify `test-automation/nginx/`

## Troubleshooting

### Common Issues

1. **Port conflicts**: Ensure ports 1883, 8080, 8888, etc. are available
2. **Docker issues**: Restart Docker daemon if containers fail to start
3. **Missing dependencies**: Install required tools (mosquitto-clients, jq, etc.)
4. **Network issues**: Check Docker network configuration

### Debug Mode

Enable verbose output:

```bash
export VERNEMQ_TEST_VERBOSE=true
./test-automation/run-tests.sh integration
```

### Check Logs

```bash
# View test logs
tail -f logs/*.log

# View VerneMQ logs
docker-compose -f docker-compose.test.yml logs vernemq

# View all service logs
docker-compose -f docker-compose.test.yml logs
```

## Best Practices

### Test Development

1. **Use descriptive test names**: Clear, self-documenting test functions
2. **Implement proper cleanup**: Clean up test data and resources
3. **Add comprehensive logging**: Log test steps and results
4. **Handle timeouts**: Use appropriate timeouts for network operations
5. **Test isolation**: Ensure tests don't interfere with each other

### Performance Testing

1. **Gradual load increase**: Start with low load and increase gradually
2. **Resource monitoring**: Monitor CPU, memory, and network usage
3. **Multiple runs**: Run performance tests multiple times for consistency
4. **Baseline establishment**: Establish performance baselines for comparison

### Security Testing

1. **Authentication coverage**: Test all authentication mechanisms
2. **Authorization testing**: Verify access control is working
3. **Attack simulation**: Simulate common attack vectors
4. **Compliance checking**: Ensure security configurations meet standards

## Contributing

### Adding New Test Categories

1. Create new directory under `test-automation/`
2. Implement test scripts with proper logging
3. Update main runner script to include new tests
4. Add documentation and examples

### Improving Existing Tests

1. Add more comprehensive test scenarios
2. Improve error handling and reporting
3. Optimize test execution time
4. Add support for new VerneMQ features

## License

This test automation suite is part of the VerneMQ project and follows the same license terms.

## Support

For issues and questions:
1. Check existing test logs and outputs
2. Review this documentation
3. Check VerneMQ documentation
4. Create issues in the VerneMQ repository

---

**Note**: This test suite is designed for testing VerneMQ in development and staging environments. Always review and customize configurations before running in production environments.