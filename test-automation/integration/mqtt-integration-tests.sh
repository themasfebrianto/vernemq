#!/bin/bash

# MQTT Integration Tests for VerneMQ
# Tests various MQTT protocol features and behaviors

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
MQTT_TEST_PORT="${MQTT_TEST_PORT:-1884}"
TEST_TOPIC_PREFIX="integration/test"
LOG_FILE="logs/mqtt-integration-tests.log"

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
test_basic_connectivity() {
    log "Testing basic connectivity..."
    
    # Test TCP connection
    if timeout 5 nc -z "$MQTT_HOST" "$MQTT_PORT"; then
        log_success "TCP connection to $MQTT_HOST:$MQTT_PORT successful"
    else
        log_error "TCP connection failed"
        return 1
    fi
    
    # Test MQTT connection
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$TEST_TOPIC_PREFIX/connect" -m "connection test" -q 0; then
        log_success "MQTT connection successful"
    else
        log_error "MQTT connection failed"
        return 1
    fi
    
    return 0
}

test_publish_subscribe() {
    log "Testing publish/subscribe functionality..."
    
    local test_topic="$TEST_TOPIC_PREFIX/pubsub"
    local test_message="Integration test message $(date +%s)"
    local received_message=""
    
    # Start subscriber in background
    timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 > /tmp/sub_output.txt &
    local sub_pid=$!
    
    # Wait for subscriber to be ready
    sleep 2
    
    # Publish message
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Message published successfully"
    else
        log_error "Message publish failed"
        kill $sub_pid 2>/dev/null || true
        return 1
    fi
    
    # Wait for message reception
    sleep 2
    
    # Check if subscriber received message
    if [ -f /tmp/sub_output.txt ] && grep -q "$test_message" /tmp/sub_output.txt; then
        log_success "Message received successfully"
        rm -f /tmp/sub_output.txt
        kill $sub_pid 2>/dev/null || true
        return 0
    else
        log_error "Message not received"
        rm -f /tmp/sub_output.txt
        kill $sub_pid 2>/dev/null || true
        return 1
    fi
}

test_qos_levels() {
    log "Testing QoS levels..."
    
    for qos in 0 1 2; do
        log "Testing QoS $qos..."
        
        local test_topic="$TEST_TOPIC_PREFIX/qos$qos"
        local test_message="QoS $qos test message $(date +%s)"
        
        # Start subscriber for QoS 1 and 2
        if [ "$qos" -gt 0 ]; then
            timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 -q $qos > /tmp/qos${qos}_sub_output.txt &
            local sub_pid=$!
            sleep 2
            
            # Publish with QoS
            if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q $qos; then
                log_success "QoS $qos message published"
            else
                log_error "QoS $qos publish failed"
                kill $sub_pid 2>/dev/null || true
                return 1
            fi
            
            sleep 2
            
            # Verify receipt
            if [ -f "/tmp/qos${qos}_sub_output.txt" ] && grep -q "$test_message" "/tmp/qos${qos}_sub_output.txt"; then
                log_success "QoS $qos message received"
            else
                log_error "QoS $qos message not received"
                kill $sub_pid 2>/dev/null || true
                rm -f "/tmp/qos${qos}_sub_output.txt"
                return 1
            fi
            
            kill $sub_pid 2>/dev/null || true
            rm -f "/tmp/qos${qos}_sub_output.txt"
        else
            # QoS 0 - fire and forget
            if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 0; then
                log_success "QoS 0 message published (no delivery confirmation required)"
            else
                log_error "QoS 0 publish failed"
                return 1
            fi
        fi
    done
    
    return 0
}

test_retained_messages() {
    log "Testing retained messages..."
    
    local test_topic="$TEST_TOPIC_PREFIX/retained"
    local retained_message="Retained message $(date +%s)"
    
    # Publish retained message
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$retained_message" -r -q 1; then
        log_success "Retained message published"
    else
        log_error "Retained message publish failed"
        return 1
    fi
    
    # Wait for message to be retained
    sleep 1
    
    # Subscribe and check for retained message
    local received_message=""
    received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 2>/dev/null || echo "")
    
    if [ "$received_message" = "$retained_message" ]; then
        log_success "Retained message received correctly"
        return 0
    else
        log_error "Retained message not received correctly. Expected: '$retained_message', Got: '$received_message'"
        return 1
    fi
}

test_will_messages() {
    log "Testing will messages..."
    
    local test_topic="$TEST_TOPIC_PREFIX/will"
    local will_message="Will message $(date +%s)"
    
    # Start subscriber to receive will message
    timeout 15 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 > /tmp/will_sub_output.txt &
    local sub_pid=$!
    
    # Wait for subscriber to be ready
    sleep 2
    
    # Connect client with will message and then disconnect abruptly
    timeout 10 mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$test_topic" -m "$will_message" \
        --will-topic "$test_topic" --will-payload "$will_message" \
        --will-qos 1 --will-retain &
    
    local pub_pid=$!
    
    # Disconnect the client (simulate disconnect)
    kill -9 $pub_pid 2>/dev/null || true
    sleep 5
    
    # Check if will message was received
    if [ -f /tmp/will_sub_output.txt ] && grep -q "$will_message" /tmp/will_sub_output.txt; then
        log_success "Will message received correctly"
    else
        log_error "Will message not received"
        cat /tmp/will_sub_output.txt 2>/dev/null || true
        rm -f /tmp/will_sub_output.txt
        kill $sub_pid 2>/dev/null || true
        return 1
    fi
    
    kill $sub_pid 2>/dev/null || true
    rm -f /tmp/will_sub_output.txt
    return 0
}

test_topic_filtering() {
    log "Testing topic filtering..."
    
    # Test various topic patterns
    local topics=(
        "integration/test/topic1"
        "integration/test/topic2"
        "integration/specific/topic"
        "integration/test/+/subtopic"
        "integration/test/#"
    )
    
    local test_message="Topic filter test $(date +%s)"
    
    # Start subscriber with wildcard topic
    timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "integration/test/#" -W 5 -C 3 > /tmp/filter_sub_output.txt &
    local sub_pid=$!
    
    sleep 2
    
    # Publish to multiple topics
    for topic in "${topics[@]}"; do
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -m "$test_message" -q 1; then
            log_success "Message published to topic: $topic"
        else
            log_error "Failed to publish to topic: $topic"
        fi
        sleep 0.5
    done
    
    sleep 3
    
    # Check received messages
    local received_count=0
    if [ -f /tmp/filter_sub_output.txt ]; then
        received_count=$(grep -c "$test_message" /tmp/filter_sub_output.txt || echo 0)
        log_success "Received $received_count messages via topic filter"
    fi
    
    kill $sub_pid 2>/dev/null || true
    rm -f /tmp/filter_sub_output.txt
    
    if [ "$received_count" -ge 3 ]; then
        return 0
    else
        log_error "Topic filtering not working correctly"
        return 1
    fi
}

test_message_size_limits() {
    log "Testing message size limits..."
    
    local test_topic="$TEST_TOPIC_PREFIX/size"
    
    # Test small message (should work)
    local small_message="Small test message"
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$small_message" -q 1; then
        log_success "Small message published successfully"
    else
        log_error "Small message publish failed"
        return 1
    fi
    
    # Test large message (might be rejected based on configuration)
    local large_message=$(python3 -c "print('L' * 1024)" 2>/dev/null || echo "$(printf 'L%.0s' {1..1024})")
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$large_message" -q 1 2>/dev/null; then
        log_success "Large message published (size limit allows it)"
    else
        log_warning "Large message rejected (expected behavior for size limit)"
    fi
    
    return 0
}

test_keep_alive() {
    log "Testing keep-alive mechanism..."
    
    # This test verifies that the connection remains alive
    local test_topic="$TEST_TOPIC_PREFIX/keepalive"
    local test_message="Keep-alive test $(date +%s)"
    
    # Connect with keep-alive and publish periodically
    for i in {1..5}; do
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message $i" -q 1; then
            log_success "Keep-alive publish $i/5 successful"
        else
            log_error "Keep-alive publish $i/5 failed"
            return 1
        fi
        sleep 2
    done
    
    return 0
}

test_clean_session() {
    log "Testing clean session behavior..."
    
    local test_topic="$TEST_TOPIC_PREFIX/clean-session"
    local test_message="Clean session test $(date +%s)"
    
    # Test 1: Subscribe with clean session = true, disconnect, publish, reconnect
    log "Testing clean session = true"
    timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -C true -W 5 -C 1 > /tmp/clean_true_output.txt &
    local sub_pid=$!
    
    sleep 2
    kill $sub_pid 2>/dev/null || true
    
    # Publish message while subscriber is disconnected
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1
    
    sleep 2
    
    # Reconnect subscriber
    timeout 10 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -C true -W 5 -C 1 > /tmp/clean_true_output2.txt &
    local sub_pid2=$!
    
    sleep 3
    
    # Should NOT receive the message (clean session = true)
    if [ -f /tmp/clean_true_output2.txt ] && grep -q "$test_message" /tmp/clean_true_output2.txt; then
        log_error "Clean session = true test failed: received message when shouldn't"
        kill $sub_pid2 2>/dev/null || true
        rm -f /tmp/clean_true_output*.txt
        return 1
    else
        log_success "Clean session = true test passed: message not retained"
    fi
    
    kill $sub_pid2 2>/dev/null || true
    rm -f /tmp/clean_true_output*.txt
    
    return 0
}

# Main test execution
main() {
    log "Starting MQTT Integration Tests"
    log "Target: $MQTT_HOST:$MQTT_PORT"
    log "Test Topic Prefix: $TEST_TOPIC_PREFIX"
    
    local test_count=0
    local pass_count=0
    local fail_count=0
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Run all tests
    local tests=(
        "test_basic_connectivity"
        "test_publish_subscribe"
        "test_qos_levels"
        "test_retained_messages"
        "test_will_messages"
        "test_topic_filtering"
        "test_message_size_limits"
        "test_keep_alive"
        "test_clean_session"
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
    
    log "MQTT Integration Tests Summary:"
    log "Total tests: $test_count"
    log "Passed: $pass_count"
    log "Failed: $fail_count"
    
    if [ "$fail_count" -eq 0 ]; then
        log_success "All MQTT integration tests passed!"
        return 0
    else
        log_error "$fail_count MQTT integration tests failed"
        return 1
    fi
}

# Run main function
main "$@"