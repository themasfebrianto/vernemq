#!/bin/bash

# Plugin Integration Tests for VerneMQ
# Tests various plugins and their integration with the broker

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
MQTT_HOST="${MQTT_HOST:-localhost}"
MQTT_PORT="${MQTT_PORT:-1883}"
TEST_TOPIC_PREFIX="integration/plugin"
LOG_FILE="logs/plugin-integration-tests.log"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="vernemq_test"
POSTGRES_USER="vmq_test_user"
POSTGRES_PASSWORD="vmq_test_password"
MONGODB_HOST="${MONGODB_HOST:-localhost}"
MONGODB_PORT="${MONGODB_PORT:-27017}"
MONGODB_DB="vernemq_test"
MONGODB_USER="vmq_test_user"
MONGODB_PASSWORD="vmq_test_password"

# Print functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1" | tee -a "$LOG_FILE"
}

# Test functions
test_diversity_plugin_redis() {
    log "Testing Diversity plugin with Redis..."
    
    # Configure Redis authentication in VerneMQ
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_diversity": {
                "redis": {
                    "enabled": true,
                    "host": "'$REDIS_HOST'",
                    "port": '$REDIS_PORT',
                    "database": 0,
                    "password": ""
                }
            }
        }' || log_warning "Failed to configure Redis via API"
    
    sleep 3
    
    # Test basic connectivity with Redis plugin
    local test_topic="$TEST_TOPIC_PREFIX/redis"
    local test_message="Redis plugin test $(date +%s)"
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published with Redis plugin configured"
    else
        log_error "Failed to publish with Redis plugin"
        return 1
    fi
    
    # Test subscriber
    local received_message=""
    received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 2>/dev/null || echo "")
    
    if [ -n "$received_message" ]; then
        log_success "Redis plugin working: message received"
    else
        log_error "Redis plugin test failed: no message received"
        return 1
    fi
    
    return 0
}

test_diversity_plugin_postgresql() {
    log "Testing Diversity plugin with PostgreSQL..."
    
    # Configure PostgreSQL authentication
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_diversity": {
                "postgresql": {
                    "enabled": true,
                    "host": "'$POSTGRES_HOST'",
                    "port": '$POSTGRES_PORT',
                    "database": "'$POSTGRES_DB'",
                    "user": "'$POSTGRES_USER'",
                    "password": "'$POSTGRES_PASSWORD'"
                }
            }
        }' || log_warning "Failed to configure PostgreSQL via API"
    
    sleep 3
    
    # Test basic connectivity with PostgreSQL plugin
    local test_topic="$TEST_TOPIC_PREFIX/postgres"
    local test_message="PostgreSQL plugin test $(date +%s)"
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published with PostgreSQL plugin configured"
    else
        log_error "Failed to publish with PostgreSQL plugin"
        return 1
    fi
    
    return 0
}

test_diversity_plugin_mongodb() {
    log "Testing Diversity plugin with MongoDB..."
    
    # Configure MongoDB authentication
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_diversity": {
                "mongodb": {
                    "enabled": true,
                    "host": "'$MONGODB_HOST'",
                    "port": '$MONGODB_PORT',
                    "database": "'$MONGODB_DB'",
                    "username": "'$MONGODB_USER'",
                    "password": "'$MONGODB_PASSWORD'"
                }
            }
        }' || log_warning "Failed to configure MongoDB via API"
    
    sleep 3
    
    # Test basic connectivity with MongoDB plugin
    local test_topic="$TEST_TOPIC_PREFIX/mongodb"
    local test_message="MongoDB plugin test $(date +%s)"
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published with MongoDB plugin configured"
    else
        log_error "Failed to publish with MongoDB plugin"
        return 1
    fi
    
    return 0
}

test_diversity_plugin_mysql() {
    log "Testing Diversity plugin with MySQL..."
    
    # Configure MySQL authentication
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_diversity": {
                "mysql": {
                    "enabled": true,
                    "host": "mysql",
                    "port": 3306,
                    "database": "'$POSTGRES_DB'",
                    "user": "'$POSTGRES_USER'",
                    "password": "'$POSTGRES_PASSWORD'"
                }
            }
        }' || log_warning "Failed to configure MySQL via API"
    
    sleep 3
    
    # Test basic connectivity with MySQL plugin
    local test_topic="$TEST_TOPIC_PREFIX/mysql"
    local test_message="MySQL plugin test $(date +%s)"
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published with MySQL plugin configured"
    else
        log_error "Failed to publish with MySQL plugin"
        return 1
    fi
    
    return 0
}

test_diversity_plugin_http() {
    log "Testing Diversity plugin with HTTP authentication..."
    
    # Test HTTP authentication endpoint
    local test_topic="$TEST_TOPIC_PREFIX/http"
    local test_message="HTTP plugin test $(date +%s)"
    
    # Create a simple test HTTP server for authentication
    python3 -m http.server 8081 --directory /tmp > /tmp/http_server.log 2>&1 &
    local http_pid=$!
    
    sleep 2
    
    # Configure HTTP authentication
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_diversity": {
                "http": {
                    "enabled": true,
                    "auth": "http://localhost:8081/auth"
                }
            }
        }' || log_warning "Failed to configure HTTP via API"
    
    sleep 3
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published with HTTP plugin configured"
    else
        log_error "Failed to publish with HTTP plugin"
        kill $http_pid 2>/dev/null || true
        return 1
    fi
    
    kill $http_pid 2>/dev/null || true
    return 0
}

test_acl_plugin() {
    log "Testing ACL plugin..."
    
    # Configure ACL plugin
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_acl": {
                "enabled": true,
                "config_file": "/opt/vernemq/etc/vmq.acl"
            }
        }' || log_warning "Failed to configure ACL via API"
    
    sleep 3
    
    # Test ACL functionality - try to publish to restricted topic
    local restricted_topic="$TEST_TOPIC_PREFIX/restricted"
    local test_message="ACL test $(date +%s)"
    
    # This should work if ACL allows it
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$restricted_topic" -m "$test_message" -q 1; then
        log_success "ACL plugin configured successfully"
    else
        log_warning "ACL plugin test: message publish failed (may be expected)"
    fi
    
    return 0
}

test_http_pub_plugin() {
    log "Testing HTTP Pub plugin..."
    
    # Test HTTP publishing endpoint
    local test_message="HTTP pub test $(date +%s)"
    
    # Try to publish via HTTP endpoint
    local response=$(curl -s -X POST "http://$MQTT_HOST:8888/api/v1/publish" \
        -H "Content-Type: application/json" \
        -d '{
            "topic": "'$TEST_TOPIC_PREFIX/http-pub'",
            "payload": "'$test_message'",
            "qos": 1
        }' || echo "")
    
    if [ -n "$response" ]; then
        log_success "HTTP Pub plugin responded: $response"
    else
        log_warning "HTTP Pub plugin test: no response received"
    fi
    
    # Verify the message was published
    local received_message=""
    received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$TEST_TOPIC_PREFIX/http-pub" -W 5 -C 1 2>/dev/null || echo "")
    
    if [ "$received_message" = "$test_message" ]; then
        log_success "HTTP Pub plugin working: message received"
        return 0
    else
        log_error "HTTP Pub plugin test failed: message not received"
        return 1
    fi
}

test_bridge_plugin() {
    log "Testing Bridge plugin..."
    
    # Configure bridge plugin (if available)
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_bridge": {
                "enabled": false
            }
        }' || log_warning "Failed to configure Bridge via API"
    
    sleep 3
    
    # Test basic functionality (bridge may not be active in test environment)
    local test_topic="$TEST_TOPIC_PREFIX/bridge"
    local test_message="Bridge plugin test $(date +%s)"
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published with Bridge plugin configured"
    else
        log_error "Failed to publish with Bridge plugin"
        return 1
    fi
    
    return 0
}

test_webhooks_plugin() {
    log "Testing Webhooks plugin..."
    
    # Configure webhooks plugin
    local webhook_url="http://localhost:8081/webhook"
    
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{
            "vmq_webhooks": {
                "enabled": true,
                "webhook_url": "'$webhook_url'",
                "secret": "test_secret"
            }
        }' || log_warning "Failed to configure Webhooks via API"
    
    sleep 3
    
    # Test webhook functionality
    local test_topic="$TEST_TOPIC_PREFIX/webhook"
    local test_message="Webhook test $(date +%s)"
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published with Webhooks plugin configured"
    else
        log_error "Failed to publish with Webhooks plugin"
        return 1
    fi
    
    return 0
}

test_plugin_configuration() {
    log "Testing plugin configuration management..."
    
    # Test retrieving current plugin configuration
    local config_response=$(curl -s "http://$MQTT_HOST:8888/api/v1/configuration" || echo "{}")
    
    if [ -n "$config_response" ] && [ "$config_response" != "{}" ]; then
        log_success "Plugin configuration retrieved successfully"
        
        # Check if key plugins are mentioned in config
        if echo "$config_response" | grep -q "vmq_diversity\|vmq_acl\|vmq_webhooks"; then
            log_success "Plugin configuration contains expected plugins"
        else
            log_warning "Plugin configuration may not contain expected plugins"
        fi
    else
        log_error "Failed to retrieve plugin configuration"
        return 1
    fi
    
    return 0
}

test_plugin_status() {
    log "Testing plugin status monitoring..."
    
    # Check plugin status via management API
    local status_response=$(curl -s "http://$MQTT_HOST:8888/api/v1/status" || echo "{}")
    
    if [ -n "$status_response" ] && echo "$status_response" | grep -q "vmq"; then
        log_success "Plugin status retrieved successfully"
        
        # Check for specific plugin metrics
        if echo "$status_response" | grep -q "vmq_diversity\|vmq_acl\|vmq_webhooks"; then
            log_success "Plugin metrics found in status"
        else
            log_warning "Plugin metrics not found in status"
        fi
    else
        log_error "Failed to retrieve plugin status"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log "Starting Plugin Integration Tests"
    log "Target: $MQTT_HOST:$MQTT_PORT"
    log "Test Topic Prefix: $TEST_TOPIC_PREFIX"
    log "Redis: $REDIS_HOST:$REDIS_PORT"
    log "PostgreSQL: $POSTGRES_HOST:$POSTGRES_PORT"
    log "MongoDB: $MONGODB_HOST:$MONGODB_PORT"
    
    local test_count=0
    local pass_count=0
    local fail_count=0
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Run all tests
    local tests=(
        "test_diversity_plugin_redis"
        "test_diversity_plugin_postgresql"
        "test_diversity_plugin_mongodb"
        "test_diversity_plugin_mysql"
        "test_diversity_plugin_http"
        "test_acl_plugin"
        "test_http_pub_plugin"
        "test_bridge_plugin"
        "test_webhooks_plugin"
        "test_plugin_configuration"
        "test_plugin_status"
    )
    
    for test in "${tests[@]}"; do
        test_count=$((test_count + 1))
        log "Running test $test_count: $test"
        
        if $test; then
            pass_count=$((pass_count + 1))
            log_success "Test $test_count passed"
        else
            fail_count=$((fail_count + 1))
            log_error "Test $test_count failed"
        fi
        
        log "----------------------------------------"
        sleep 2
    done
    
    log "Plugin Integration Tests Summary:"
    log "Total tests: $test_count"
    log "Passed: $pass_count"
    log "Failed: $fail_count"
    
    if [ "$fail_count" -eq 0 ]; then
        log_success "All plugin integration tests passed!"
        return 0
    else
        log_error "$fail_count plugin integration tests failed"
        return 1
    fi
}

# Run main function
main "$@"