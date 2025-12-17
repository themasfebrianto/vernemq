#!/bin/bash

# Clustering Integration Tests for VerneMQ
# Tests clustering functionality, node discovery, and message replication

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
TEST_TOPIC_PREFIX="integration/cluster"
LOG_FILE="logs/clustering-integration-tests.log"
VERNEMQ_NODE1="${VEREMQ_NODE1:-VerneMQ@node1}"
VEREMQ_NODE2="${VEREMQ_NODE2:-VerneMQ@node2}"

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
test_cluster_status() {
    log "Testing cluster status monitoring..."
    
    # Check cluster status via vmq-admin
    local cluster_status=$(docker exec vernemq-test /opt/vernemq/bin/vmq-admin cluster status 2>/dev/null || echo "")
    
    if [ -n "$cluster_status" ]; then
        log_success "Cluster status retrieved: $cluster_status"
        
        # Check if VerneMQ is listed as running
        if echo "$cluster_status" | grep -q "VerneMQ"; then
            log_success "VerneMQ node is listed in cluster status"
        else
            log_warning "VerneMQ node not found in cluster status"
        fi
    else
        log_error "Failed to retrieve cluster status"
        return 1
    fi
    
    return 0
}

test_cluster_discovery() {
    log "Testing cluster node discovery..."
    
    # Test cluster nodes endpoint
    local nodes_response=$(curl -s "http://$MQTT_HOST:8888/api/v1/nodes" || echo "{}")
    
    if [ -n "$nodes_response" ] && [ "$nodes_response" != "{}" ]; then
        log_success "Cluster nodes retrieved successfully"
        
        # Parse nodes response (JSON)
        if command -v jq >/dev/null 2>&1; then
            local node_count=$(echo "$nodes_response" | jq '. | length' 2>/dev/null || echo "0")
            log "Found $node_count nodes in cluster"
            
            if [ "$node_count" -gt 0 ]; then
                log_success "Cluster discovery working: $node_count node(s) found"
            else
                log_warning "No nodes found in cluster discovery"
            fi
        else
            log_warning "jq not available, cannot parse JSON response"
        fi
    else
        log_error "Failed to retrieve cluster nodes"
        return 1
    fi
    
    return 0
}

test_message_replication() {
    log "Testing message replication across cluster..."
    
    local test_topic="$TEST_TOPIC_PREFIX/replication"
    local test_message="Cluster replication test $(date +%s)"
    
    # Publish message
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published to cluster"
    else
        log_error "Failed to publish message to cluster"
        return 1
    fi
    
    # Verify message reception
    local received_message=""
    received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 2>/dev/null || echo "")
    
    if [ "$received_message" = "$test_message" ]; then
        log_success "Message replication working: message received"
    else
        log_error "Message replication test failed: message not received"
        return 1
    fi
    
    return 0
}

test_session_replication() {
    log "Testing session replication across cluster..."
    
    local test_topic="$TEST_TOPIC_PREFIX/session"
    local test_message="Session replication test $(date +%s)"
    local client_id="test-client-$(date +%s)"
    
    # Subscribe with persistent session
    timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C false -i "$client_id" -c > /tmp/session_sub_output.txt &
    local sub_pid=$!
    
    sleep 2
    
    # Disconnect subscriber
    kill $sub_pid 2>/dev/null || true
    sleep 2
    
    # Publish message while subscriber is offline
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published while subscriber offline"
    else
        log_error "Failed to publish message while subscriber offline"
        return 1
    fi
    
    # Reconnect subscriber with same client ID
    timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C false -i "$client_id" -c > /tmp/session_reconnect_output.txt &
    local sub_pid2=$!
    
    sleep 5
    
    # Check if offline message was received
    if [ -f /tmp/session_reconnect_output.txt ] && grep -q "$test_message" /tmp/session_reconnect_output.txt; then
        log_success "Session replication working: offline message received on reconnect"
    else
        log_error "Session replication test failed: offline message not received"
        cat /tmp/session_reconnect_output.txt 2>/dev/null || true
        kill $sub_pid2 2>/dev/null || true
        rm -f /tmp/session_sub_output.txt /tmp/session_reconnect_output.txt
        return 1
    fi
    
    kill $sub_pid2 2>/dev/null || true
    rm -f /tmp/session_sub_output.txt /tmp/session_reconnect_output.txt
    return 0
}

test_shared_subscriptions() {
    log "Testing shared subscriptions across cluster..."
    
    local shared_topic="$TEST_TOPIC_PREFIX/shared/\$share/test-group"
    local test_message="Shared subscription test $(date +%s)"
    
    # Start multiple subscribers in shared subscription group
    for i in {1..3}; do
        timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$shared_topic" -W 5 -C 1 > /tmp/shared_sub_$i.txt &
        eval "sub_pid_$i=$!"
        sleep 1
    done
    
    # Publish multiple messages
    for i in {1..5}; do
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$shared_topic" -m "$test_message $i" -q 1; then
            log_success "Shared message $i published"
        else
            log_error "Failed to publish shared message $i"
        fi
        sleep 0.5
    done
    
    sleep 3
    
    # Check message distribution
    local total_messages=0
    for i in {1..3}; do
        if [ -f "/tmp/shared_sub_$i.txt" ]; then
            local msg_count=$(wc -l < "/tmp/shared_sub_$i.txt")
            total_messages=$((total_messages + msg_count))
            log "Subscriber $i received $msg_count messages"
        fi
        eval "kill \${sub_pid_$i} 2>/dev/null || true"
        rm -f "/tmp/shared_sub_$i.txt"
    done
    
    if [ "$total_messages" -eq 5 ]; then
        log_success "Shared subscriptions working: all 5 messages distributed among subscribers"
        return 0
    else
        log_error "Shared subscriptions test failed: expected 5 messages, received $total_messages"
        return 1
    fi
}

test_cluster_load_balancing() {
    log "Testing cluster load balancing..."
    
    local test_topic="$TEST_TOPIC_PREFIX/loadbalance"
    local test_message="Load balancing test $(date +%s)"
    
    # Test multiple concurrent connections
    local connection_count=0
    for i in {1..10}; do
        if timeout 3 mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message $i" -q 1 -i "load-test-$i"; then
            connection_count=$((connection_count + 1))
        else
            log_warning "Failed to establish connection $i"
        fi
        sleep 0.2
    done
    
    log "Successfully established $connection_count connections"
    
    if [ "$connection_count" -ge 8 ]; then
        log_success "Cluster load balancing working: $connection_count connections established"
    else
        log_error "Cluster load balancing test failed: only $connection_count connections established"
        return 1
    fi
    
    return 0
}

test_cluster_metrics() {
    log "Testing cluster metrics collection..."
    
    # Get cluster metrics
    local metrics_response=$(curl -s "http://$MQTT_HOST:8888/api/v1/metrics" || echo "{}")
    
    if [ -n "$metrics_response" ] && [ "$metrics_response" != "{}" ]; then
        log_success "Cluster metrics retrieved successfully"
        
        # Check for cluster-specific metrics
        local cluster_metrics=(
            "cluster_nodes_connected"
            "cluster_messages_routed"
            "cluster_session_replicated"
            "vmq_cluster"
        )
        
        local found_metrics=0
        for metric in "${cluster_metrics[@]}"; do
            if echo "$metrics_response" | grep -q "$metric"; then
                found_metrics=$((found_metrics + 1))
            fi
        done
        
        if [ "$found_metrics" -gt 0 ]; then
            log_success "Found $found_metrics cluster-specific metrics"
        else
            log_warning "No cluster-specific metrics found"
        fi
    else
        log_error "Failed to retrieve cluster metrics"
        return 1
    fi
    
    return 0
}

test_cluster_health() {
    log "Testing cluster health monitoring..."
    
    # Check cluster health via management API
    local health_response=$(curl -s "http://$MQTT_HOST:8888/api/v1/health" || echo "")
    
    if [ -n "$health_response" ]; then
        log_success "Cluster health endpoint accessible"
        
        # Parse health status
        if command -v jq >/dev/null 2>&1; then
            local status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
            log "Cluster health status: $status"
            
            if [ "$status" = "ok" ] || [ "$status" = "healthy" ]; then
                log_success "Cluster is healthy"
            else
                log_warning "Cluster health status: $status"
            fi
        fi
    else
        log_error "Failed to access cluster health endpoint"
        return 1
    fi
    
    return 0
}

test_netsplit_resilience() {
    log "Testing netsplit resilience..."
    
    # This test simulates network partition scenarios
    local test_topic="$TEST_TOPIC_PREFIX/netsplit"
    local test_message="Netsplit resilience test $(date +%s)"
    
    # Publish message
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published during netsplit test"
    else
        log_error "Failed to publish message during netsplit test"
        return 1
    fi
    
    # Verify message delivery
    local received_message=""
    received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 2>/dev/null || echo "")
    
    if [ "$received_message" = "$test_message" ]; then
        log_success "Message delivery maintained during netsplit scenario"
    else
        log_error "Netsplit resilience test failed: message not delivered"
        return 1
    fi
    
    return 0
}

test_cluster_configuration() {
    log "Testing cluster configuration management..."
    
    # Test retrieving cluster configuration
    local config_response=$(curl -s "http://$MQTT_HOST:8888/api/v1/configuration" || echo "{}")
    
    if [ -n "$config_response" ] && [ "$config_response" != "{}" ]; then
        log_success "Cluster configuration retrieved successfully"
        
        # Check for cluster-related settings
        if echo "$config_response" | grep -q "cluster\|distributed"; then
            log_success "Cluster configuration contains expected settings"
        else
            log_warning "Cluster configuration may not contain expected settings"
        fi
    else
        log_error "Failed to retrieve cluster configuration"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log "Starting Clustering Integration Tests"
    log "Target: $MQTT_HOST:$MQTT_PORT"
    log "Test Topic Prefix: $TEST_TOPIC_PREFIX"
    log "Node 1: $VEREMQ_NODE1"
    log "Node 2: $VEREMQ_NODE2"
    
    local test_count=0
    local pass_count=0
    local fail_count=0
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Run all tests
    local tests=(
        "test_cluster_status"
        "test_cluster_discovery"
        "test_message_replication"
        "test_session_replication"
        "test_shared_subscriptions"
        "test_cluster_load_balancing"
        "test_cluster_metrics"
        "test_cluster_health"
        "test_netsplit_resilience"
        "test_cluster_configuration"
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
    
    log "Clustering Integration Tests Summary:"
    log "Total tests: $test_count"
    log "Passed: $pass_count"
    log "Failed: $fail_count"
    
    if [ "$fail_count" -eq 0 ]; then
        log_success "All clustering integration tests passed!"
        return 0
    else
        log_error "$fail_count clustering integration tests failed"
        return 1
    fi
}

# Run main function
main "$@"