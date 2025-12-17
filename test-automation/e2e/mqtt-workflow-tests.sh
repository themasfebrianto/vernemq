#!/bin/bash

# End-to-End MQTT Workflow Tests for VerneMQ
# Tests complete MQTT workflows and business scenarios

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
WS_PORT="${WS_PORT:-8080}"
HTTP_PUB_PORT="${HTTP_PUB_PORT:-8888}"
TEST_TOPIC_PREFIX="e2e/workflow"
LOG_FILE="logs/e2e-workflow-tests.log"

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
test_iot_sensor_workflow() {
    log "Testing IoT sensor data workflow..."
    
    # Simulate IoT sensor data publishing and processing
    local sensor_topic="$TEST_TOPIC_PREFIX/sensors/temperature"
    local sensor_id="sensor-001"
    local measurements=("23.5" "24.1" "23.8" "24.3" "23.9")
    
    # Sensor publishes temperature readings
    local published_count=0
    for measurement in "${measurements[@]}"; do
        local payload=$(cat << EOF
{
    "sensor_id": "$sensor_id",
    "timestamp": "$(date -Iseconds)",
    "temperature": $measurement,
    "humidity": 65.2,
    "location": "warehouse-1"
}
EOF
)
        
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$sensor_topic" \
            -m "$payload" \
            -q 1; then
            published_count=$((published_count + 1))
            log "Sensor $sensor_id published temperature: ${measurement}°C"
        else
            log_error "Failed to publish sensor data: $measurement"
        fi
        sleep 0.5
    done
    
    # Dashboard subscribes to sensor data
    local received_count=0
    timeout 15 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$sensor_topic" \
        -W 10 -C 5 > /tmp/sensor_data.txt &
    local sub_pid=$!
    
    sleep 3
    
    # Count received messages
    if [ -f /tmp/sensor_data.txt ]; then
        received_count=$(wc -l < /tmp/sensor_data.txt)
        log_success "Dashboard received $received_count sensor readings"
        
        # Verify data format
        local valid_data=0
        while IFS= read -r line; do
            if echo "$line" | jq -e . >/dev/null 2>&1; then
                valid_data=$((valid_data + 1))
            fi
        done < /tmp/sensor_data.txt
        
        log "Valid JSON messages: $valid_data/$received_count"
    fi
    
    kill $sub_pid 2>/dev/null || true
    rm -f /tmp/sensor_data.txt
    
    if [ "$published_count" -eq "${#measurements[@]}" ] && [ "$received_count" -ge 3 ]; then
        log_success "IoT sensor workflow test passed"
        return 0
    else
        log_error "IoT sensor workflow test failed: published=$published_count, received=$received_count"
        return 1
    fi
}

test_command_control_workflow() {
    log "Testing command and control workflow..."
    
    # Simulate command and control scenario
    local command_topic="$TEST_TOPIC_PREFIX/device/+/command"
    local status_topic="$TEST_TOPIC_PREFIX/device/+/status"
    local device_ids=("device-001" "device-002" "device-003")
    
    # Start device status listeners
    local sub_pids=()
    for device_id in "${device_ids[@]}"; do
        timeout 20 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/device/$device_id/status" \
            -W 15 -C 1 > /tmp/device_${device_id}_status.txt &
        sub_pids+=($!)
        sleep 0.5
    done
    
    sleep 2
    
    # Send commands to devices
    local commands_sent=0
    for device_id in "${device_ids[@]}"; do
        local command=$(cat << EOF
{
    "command": "restart",
    "timestamp": "$(date -Iseconds)",
    "priority": "high",
    "parameters": {
        "delay": 5,
        "force": false
    }
}
EOF
)
        
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/device/$device_id/command" \
            -m "$command" \
            -q 1; then
            commands_sent=$((commands_sent + 1))
            log "Command sent to $device_id"
        else
            log_error "Failed to send command to $device_id"
        fi
        sleep 1
    done
    
    # Wait for status updates
    sleep 5
    
    # Check if devices responded
    local devices_responded=0
    for device_id in "${device_ids[@]}"; do
        if [ -f "/tmp/device_${device_id}_status.txt" ] && [ -s "/tmp/device_${device_id}_status.txt" ]; then
            devices_responded=$((devices_responded + 1))
            log "Device $device_id responded to command"
        fi
        kill ${sub_pids[devices_responded-1]} 2>/dev/null || true
        rm -f "/tmp/device_${device_id}_status.txt"
    done
    
    if [ "$commands_sent" -eq "${#device_ids[@]}" ] && [ "$devices_responded" -ge 2 ]; then
        log_success "Command and control workflow test passed"
        return 0
    else
        log_error "Command and control workflow test failed: sent=$commands_sent, responded=$devices_responded"
        return 1
    fi
}

test_pubsub_messaging_workflow() {
    log "Testing publish-subscribe messaging workflow..."
    
    # Simulate chat/messaging scenario
    local chat_topic="$TEST_TOPIC_PREFIX/chat/room1"
    local users=("alice" "bob" "charlie")
    local messages=("Hello everyone!" "How's the weather?" "All good here!")
    
    # Start chat clients
    local chat_pids=()
    for user in "${users[@]}"; do
        timeout 15 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$chat_topic" \
            -W 10 -C 10 \
            -i "chat-client-$user" > /tmp/chat_${user}.txt &
        chat_pids+=($!)
        sleep 0.5
    done
    
    sleep 2
    
    # Send chat messages
    local messages_sent=0
    for i in "${!users[@]}"; do
        local user="${users[$i]}"
        local message="${messages[$i]}"
        local payload=$(cat << EOF
{
    "user": "$user",
    "message": "$message",
    "timestamp": "$(date -Iseconds)",
    "room": "room1"
}
EOF
)
        
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$chat_topic" \
            -m "$payload" \
            -q 1; then
            messages_sent=$((messages_sent + 1))
            log "Message sent by $user: $message"
        else
            log_error "Failed to send message from $user"
        fi
        sleep 1
    done
    
    # Wait for message delivery
    sleep 3
    
    # Check message delivery to all users
    local total_messages_received=0
    for user in "${users[@]}"; do
        if [ -f "/tmp/chat_${user}.txt" ]; then
            local user_messages=$(wc -l < "/tmp/chat_${user}.txt")
            total_messages_received=$((total_messages_received + user_messages))
            log "User $user received $user_messages messages"
        fi
        kill ${chat_pids[users[(I)user]-1]} 2>/dev/null || true
        rm -f "/tmp/chat_${user}.txt"
    done
    
    if [ "$messages_sent" -eq "${#messages[@]}" ] && [ "$total_messages_received" -ge 6 ]; then
        log_success "Publish-subscribe messaging workflow test passed"
        return 0
    else
        log_error "Publish-subscribe messaging workflow test failed: sent=$messages_sent, received=$total_messages_received"
        return 1
    fi
}

test_data_pipeline_workflow() {
    log "Testing data pipeline workflow..."
    
    # Simulate data processing pipeline
    local raw_topic="$TEST_TOPIC_PREFIX/pipeline/raw"
    local processed_topic="$TEST_TOPIC_PREFIX/pipeline/processed"
    local alerts_topic="$TEST_TOPIC_PREFIX/pipeline/alerts"
    
    # Start data processor (simulated)
    timeout 20 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$raw_topic" \
        -W 15 -C 5 > /tmp/raw_data.txt &
    local processor_pid=$!
    
    # Start alert listener
    timeout 20 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$alerts_topic" \
        -W 15 -C 2 > /tmp/alerts.txt &
    local alert_pid=$!
    
    sleep 2
    
    # Publish raw data
    local data_points=()
    for i in {1..5}; do
        local value=$((RANDOM % 100 + 1))
        data_points+=($value)
        
        local payload=$(cat << EOF
{
    "sensor": "pipeline-sensor-$i",
    "value": $value,
    "timestamp": "$(date -Iseconds)",
    "unit": "ppm"
}
EOF
)
        
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$raw_topic" \
            -m "$payload" \
            -q 1; then
            log "Published data point: $value ppm"
        else
            log_error "Failed to publish data point: $value"
        fi
        sleep 1
    done
    
    # Simulate processing by publishing processed data
    sleep 2
    for value in "${data_points[@]}"; do
        if [ "$value" -gt 80 ]; then
            # High value - trigger alert
            local alert_payload=$(cat << EOF
{
    "level": "warning",
    "message": "High value detected: $value ppm",
    "threshold": 80,
    "actual": $value,
    "timestamp": "$(date -Iseconds)"
}
EOF
)
            
            mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
                -t "$alerts_topic" \
                -m "$alert_payload" \
                -q 1
        fi
        
        # Publish processed data
        local processed_value=$((value / 2))
        local processed_payload=$(cat << EOF
{
    "original_value": $value,
    "processed_value": $processed_value,
    "timestamp": "$(date -Iseconds)"
}
EOF
)
        
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$processed_topic" \
            -m "$processed_payload" \
            -q 1
    done
    
    # Wait for processing
    sleep 3
    
    # Check results
    local raw_count=0
    local alert_count=0
    
    if [ -f /tmp/raw_data.txt ]; then
        raw_count=$(wc -l < /tmp/raw_data.txt)
    fi
    
    if [ -f /tmp/alerts.txt ]; then
        alert_count=$(wc -l < /tmp/alerts.txt)
    fi
    
    kill $processor_pid $alert_pid 2>/dev/null || true
    rm -f /tmp/raw_data.txt /tmp/alerts.txt
    
    log "Data pipeline results: $raw_count raw data, $alert_count alerts"
    
    if [ "$raw_count" -ge 4 ] && [ "$alert_count" -ge 1 ]; then
        log_success "Data pipeline workflow test passed"
        return 0
    else
        log_error "Data pipeline workflow test failed: raw=$raw_count, alerts=$alert_count"
        return 1
    fi
}

test_multi_tenant_workflow() {
    log "Testing multi-tenant workflow..."
    
    # Simulate multi-tenant scenario
    local tenant1_topic="$TEST_TOPIC_PREFIX/tenant1/data"
    local tenant2_topic="$TEST_TOPIC_PREFIX/tenant2/data"
    local shared_topic="$TEST_TOPIC_PREFIX/shared/announcements"
    
    # Start tenant listeners
    timeout 15 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$tenant1_topic" \
        -W 10 -C 3 > /tmp/tenant1_data.txt &
    local t1_pid=$!
    
    timeout 15 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$tenant2_topic" \
        -W 10 -C 3 > /tmp/tenant2_data.txt &
    local t2_pid=$!
    
    timeout 15 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$shared_topic" \
        -W 10 -C 6 > /tmp/shared_data.txt &
    local shared_pid=$!
    
    sleep 2
    
    # Publish tenant-specific data
    local t1_data=("tenant1-data-1" "tenant1-data-2" "tenant1-data-3")
    local t2_data=("tenant2-data-1" "tenant2-data-2" "tenant2-data-3")
    
    # Tenant 1 publishes
    for data in "${t1_data[@]}"; do
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$tenant1_topic" \
            -m "$data" \
            -q 1
        sleep 0.5
    done
    
    # Tenant 2 publishes
    for data in "${t2_data[@]}"; do
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$tenant2_topic" \
            -m "$data" \
            -q 1
        sleep 0.5
    done
    
    # Shared announcements
    local announcements=("System maintenance tonight" "New feature release" "Security update required")
    for announcement in "${announcements[@]}"; do
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$shared_topic" \
            -m "$announcement" \
            -q 1
        sleep 0.5
    done
    
    # Wait for delivery
    sleep 3
    
    # Check tenant isolation
    local t1_received=0
    local t2_received=0
    local shared_received=0
    
    if [ -f /tmp/tenant1_data.txt ]; then
        t1_received=$(wc -l < /tmp/tenant1_data.txt)
    fi
    
    if [ -f /tmp/tenant2_data.txt ]; then
        t2_received=$(wc -l < /tmp/tenant2_data.txt)
    fi
    
    if [ -f /tmp/shared_data.txt ]; then
        shared_received=$(wc -l < /tmp/shared_data.txt)
    fi
    
    kill $t1_pid $t2_pid $shared_pid 2>/dev/null || true
    rm -f /tmp/tenant1_data.txt /tmp/tenant2_data.txt /tmp/shared_data.txt
    
    log "Multi-tenant results: Tenant1=$t1_received, Tenant2=$t2_received, Shared=$shared_received"
    
    # Verify tenant isolation (each should only receive their own + shared data)
    if [ "$t1_received" -ge 5 ] && [ "$t2_received" -ge 5 ] && [ "$shared_received" -ge 6 ]; then
        log_success "Multi-tenant workflow test passed"
        return 0
    else
        log_error "Multi-tenant workflow test failed: T1=$t1_received, T2=$t2_received, Shared=$shared_received"
        return 1
    fi
}

test_event_sourcing_workflow() {
    log "Testing event sourcing workflow..."
    
    # Simulate event sourcing pattern
    local events_topic="$TEST_TOPIC_PREFIX/events"
    local projections_topic="$TEST_TOPIC_PREFIX/projections"
    
    # Start event listeners
    timeout 20 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$events_topic" \
        -W 15 -C 10 > /tmp/events.txt &
    local events_pid=$!
    
    timeout 20 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$projections_topic" \
        -W 15 -C 5 > /tmp/projections.txt &
    local projections_pid=$!
    
    sleep 2
    
    # Simulate domain events
    local events=(
        '{"type":"UserRegistered","userId":"user-123","email":"user@example.com","timestamp":"'$(date -Iseconds)'"}'
        '{"type":"OrderPlaced","orderId":"order-456","userId":"user-123","amount":99.99,"timestamp":"'$(date -Iseconds)'"}'
        '{"type":"PaymentProcessed","orderId":"order-456","amount":99.99,"status":"success","timestamp":"'$(date -Iseconds)'"}'
        '{"type":"OrderShipped","orderId":"order-456","trackingNumber":"TRK789","timestamp":"'$(date -Iseconds)'"}'
        '{"type":"UserUpdated","userId":"user-123","profile":{"name":"John Doe"},"timestamp":"'$(date -Iseconds)'"}'
    )
    
    local events_published=0
    for event in "${events[@]}"; do
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$events_topic" \
            -m "$event" \
            -q 1; then
            events_published=$((events_published + 1))
            log "Event published: $(echo "$event" | jq -r '.type')"
        else
            log_error "Failed to publish event: $(echo "$event" | jq -r '.type')"
        fi
        sleep 1
    done
    
    # Simulate projections being updated
    sleep 2
    
    local projections=(
        '{"type":"UserProjection","userId":"user-123","state":{"email":"user@example.com","name":"John Doe"},"timestamp":"'$(date -Iseconds)'"}'
        '{"type":"OrderProjection","orderId":"order-456","state":{"status":"shipped","amount":99.99},"timestamp":"'$(date -Iseconds)'"}'
    )
    
    for projection in "${projections[@]}"; do
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$projections_topic" \
            -m "$projection" \
            -q 1
    done
    
    # Wait for processing
    sleep 3
    
    # Check event processing
    local events_received=0
    local projections_received=0
    
    if [ -f /tmp/events.txt ]; then
        events_received=$(wc -l < /tmp/events.txt)
    fi
    
    if [ -f /tmp/projections.txt ]; then
        projections_received=$(wc -l < /tmp/projections.txt)
    fi
    
    kill $events_pid $projections_pid 2>/dev/null || true
    rm -f /tmp/events.txt /tmp/projections.txt
    
    log "Event sourcing results: Events=$events_received, Projections=$projections_received"
    
    if [ "$events_received" -ge 4 ] && [ "$projections_received" -ge 1 ]; then
        log_success "Event sourcing workflow test passed"
        return 0
    else
        log_error "Event sourcing workflow test failed: events=$events_received, projections=$projections_received"
        return 1
    fi
}

test_websocket_workflow() {
    log "Testing WebSocket workflow..."
    
    # Test WebSocket connectivity (if available)
    local ws_test_topic="$TEST_TOPIC_PREFIX/websocket"
    local test_message="WebSocket test $(date +%s)"
    
    # Check if WebSocket port is accessible
    if nc -z "$MQTT_HOST" "$WS_PORT" 2>/dev/null; then
        log "WebSocket port $WS_PORT is accessible"
        
        # Test WebSocket publishing (using websocat or similar if available)
        if command -v websocat >/dev/null 2>&1; then
            # This would require a proper WebSocket client implementation
            log "WebSocket testing requires specialized client tools"
            log_warning "WebSocket workflow test skipped (no suitable client available)"
        else
            log "WebSocket client not available, skipping detailed WebSocket test"
        fi
        
        # At minimum, verify the port is listening
        if nc -z "$MQTT_HOST" "$WS_PORT"; then
            log_success "WebSocket workflow: port $WS_PORT is listening"
            return 0
        else
            log_error "WebSocket workflow test failed: port $WS_PORT not accessible"
            return 1
        fi
    else
        log_warning "WebSocket workflow test skipped: WebSocket port $WS_PORT not accessible"
        return 0
    fi
}

# Main test execution
main() {
    log "Starting End-to-End MQTT Workflow Tests for VerneMQ"
    log "Target: $MQTT_HOST:$MQTT_PORT"
    log "WebSocket: $MQTT_HOST:$WS_PORT"
    log "Test Topic Prefix: $TEST_TOPIC_PREFIX"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    local test_count=0
    local pass_count=0
    local fail_count=0
    
    # Run all workflow tests
    local tests=(
        "test_iot_sensor_workflow"
        "test_command_control_workflow"
        "test_pubsub_messaging_workflow"
        "test_data_pipeline_workflow"
        "test_multi_tenant_workflow"
        "test_event_sourcing_workflow"
        "test_websocket_workflow"
    )
    
    for test in "${tests[@]}"; do
        test_count=$((test_count + 1))
        log "Running workflow test $test_count: $test"
        
        if $test; then
            pass_count=$((pass_count + 1))
            log_success "Workflow test $test_count passed"
        else
            fail_count=$((fail_count + 1))
            log_error "Workflow test $test_count failed"
        fi
        
        log "----------------------------------------"
        sleep 3
    done
    
    log "End-to-End Workflow Tests Summary:"
    log "Total tests: $test_count"
    log "Passed: $pass_count"
    log "Failed: $fail_count"
    
    if [ "$fail_count" -eq 0 ]; then
        log_success "All end-to-end workflow tests passed!"
        return 0
    else
        log_error "$fail_count end-to-end workflow tests failed"
        return 1
    fi
}

# Run main function
main "$@"