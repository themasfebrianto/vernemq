#!/bin/bash

# Load Tests for VerneMQ
# Tests system behavior under various load conditions

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
TEST_TOPIC_PREFIX="performance/load"
LOG_FILE="logs/load-tests.log"
RESULTS_DIR="logs/load-test-results"

# Load test parameters
MAX_CONNECTIONS="${MAX_CONNECTIONS:-100}"
MESSAGE_RATE="${MESSAGE_RATE:-10}"
TEST_DURATION="${TEST_DURATION:-60}"
CONNECTION_RATE="${CONNECTION_RATE:-5}"

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

# Performance monitoring functions
monitor_system_resources() {
    local duration=$1
    local output_file="$RESULTS_DIR/system-resources-$duration.log"
    
    log "Monitoring system resources for ${duration}s..."
    
    {
        echo "Timestamp,CPU_Usage,Memory_Usage,Disk_IO,Network_IO"
        for i in $(seq 1 $duration); do
            local timestamp=$(date +%s)
            local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
            local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
            local disk_io=$(iostat -x 1 1 | tail -n +4 | awk '{sum+=$10} END {print sum}' 2>/dev/null || echo "0")
            local network_io=$(cat /proc/net/dev | grep eth0 | awk '{print $2+$10}' 2>/dev/null || echo "0")
            
            echo "$timestamp,$cpu_usage,$mem_usage,$disk_io,$network_io"
            sleep 1
        done
    } > "$output_file" &
    
    echo $!
}

# Load test functions
test_connection_load() {
    log "Testing connection load handling..."
    
    local test_name="connection-load"
    local results_file="$RESULTS_DIR/$test_name.csv"
    local connections_successful=0
    local connections_failed=0
    local start_time=$(date +%s)
    
    # Create results file
    echo "Timestamp,Connections_Successful,Connections_Failed,Active_Connections,Duration" > "$results_file"
    
    log "Attempting to establish $MAX_CONNECTIONS connections..."
    
    # Monitor system resources during the test
    local monitor_pid=$(monitor_system_resources $TEST_DURATION)
    
    # Attempt to establish connections
    for i in $(seq 1 $MAX_CONNECTIONS); do
        local current_time=$(date +%s)
        local duration=$((current_time - start_time))
        
        # Try to establish connection
        if timeout 5 mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/connection-test" \
            -m "Connection test $i" \
            -i "load-test-connection-$i" \
            -q 0 >/dev/null 2>&1; then
            connections_successful=$((connections_successful + 1))
        else
            connections_failed=$((connections_failed + 1))
        fi
        
        # Log progress every 10 connections
        if [ $((i % 10)) -eq 0 ]; then
            log "Connection progress: $i/$MAX_CONNECTIONS successful=$connections_successful failed=$connections_failed"
            echo "$current_time,$connections_successful,$connections_failed,$i,$duration" >> "$results_file"
        fi
        
        sleep 0.1
    done
    
    # Wait for monitoring to complete
    wait $monitor_pid
    
    log "Connection Load Test Results:"
    log "Total attempted: $MAX_CONNECTIONS"
    log "Successful: $connections_successful"
    log "Failed: $connections_failed"
    log "Success rate: $(echo "scale=2; $connections_successful * 100 / $MAX_CONNECTIONS" | bc)%"
    
    # Evaluate results
    local success_rate=$(echo "$connections_successful * 100 / $MAX_CONNECTIONS" | bc)
    if [ "$success_rate" -ge 95 ]; then
        log_success "Connection load test passed: $success_rate% success rate"
        return 0
    else
        log_error "Connection load test failed: only $success_rate% success rate"
        return 1
    fi
}

test_message_rate_load() {
    log "Testing message rate under load..."
    
    local test_name="message-rate-load"
    local results_file="$RESULTS_DIR/$test_name.csv"
    local messages_sent=0
    local messages_failed=0
    local start_time=$(date +%s)
    
    # Create results file
    echo "Timestamp,Messages_Sent,Messages_Failed,Rate,Duration" > "$results_file"
    
    log "Sending messages at $MESSAGE_RATE messages/second for $TEST_DURATION seconds..."
    
    # Monitor system resources during the test
    local monitor_pid=$(monitor_system_resources $TEST_DURATION)
    
    # Send messages at specified rate
    local interval=$(echo "scale=3; 1.0 / $MESSAGE_RATE" | bc)
    
    for i in $(seq 1 $((TEST_DURATION * MESSAGE_RATE))); do
        local current_time=$(date +%s)
        local duration=$((current_time - start_time))
        
        # Send message
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/rate-test" \
            -m "Rate test message $i at $(date +%s%3N)" \
            -q 1 >/dev/null 2>&1; then
            messages_sent=$((messages_sent + 1))
        else
            messages_failed=$((messages_failed + 1))
        fi
        
        # Log progress every second
        if [ $((i % MESSAGE_RATE)) -eq 0 ]; then
            local current_rate=$(echo "scale=2; $messages_sent / $duration" | bc)
            log "Message rate progress: $messages_sent sent, $messages_failed failed, rate=${current_rate}msg/s"
            echo "$current_time,$messages_sent,$messages_failed,$current_rate,$duration" >> "$results_file"
        fi
        
        sleep $interval
    done
    
    # Wait for monitoring to complete
    wait $monitor_pid
    
    log "Message Rate Load Test Results:"
    log "Duration: $TEST_DURATION seconds"
    log "Target rate: $MESSAGE_RATE messages/second"
    log "Messages sent: $messages_sent"
    log "Messages failed: $messages_failed"
    log "Actual rate: $(echo "scale=2; $messages_sent / $TEST_DURATION" | bc) messages/second"
    log "Success rate: $(echo "scale=2; $messages_sent * 100 / (messages_sent + messages_failed)" | bc)%"
    
    # Evaluate results
    local actual_rate=$(echo "$messages_sent / $TEST_DURATION" | bc)
    local target_achievement=$(echo "scale=2; $actual_rate * 100 / $MESSAGE_RATE" | bc)
    
    if [ "$target_achievement" -ge 80 ]; then
        log_success "Message rate load test passed: $target_achievement% of target rate achieved"
        return 0
    else
        log_error "Message rate load test failed: only $target_achievement% of target rate achieved"
        return 1
    fi
}

test_concurrent_subscribers() {
    log "Testing concurrent subscriber handling..."
    
    local test_name="concurrent-subscribers"
    local results_file="$RESULTS_DIR/$test_name.csv"
    local subscribers_active=0
    local messages_received=0
    local start_time=$(date +%s)
    
    # Create results file
    echo "Timestamp,Subscribers_Active,Messages_Received,Duration" > "$results_file"
    
    log "Starting $MAX_CONNECTIONS concurrent subscribers..."
    
    # Start subscribers in background
    local subscriber_pids=()
    for i in $(seq 1 $MAX_CONNECTIONS); do
        timeout $TEST_DURATION mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/subscriber-test" \
            -W 1 -C 1000 \
            -i "subscriber-$i" > /tmp/subscriber_$i.txt &
        subscriber_pids+=($!)
        subscribers_active=$((subscribers_active + 1))
        
        sleep 0.1
    done
    
    log "Started $subscribers_active subscribers, now sending messages..."
    
    # Monitor system resources during the test
    local monitor_pid=$(monitor_system_resources $TEST_DURATION)
    
    # Send messages to be received by subscribers
    local messages_per_second=20
    local message_interval=$(echo "scale=3; 1.0 / $messages_per_second" | bc)
    
    for i in $(seq 1 $((TEST_DURATION * messages_per_second))); do
        local current_time=$(date +%s)
        local duration=$((current_time - start_time))
        
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/subscriber-test" \
            -m "Message $i for subscribers at $(date +%s%3N)" \
            -q 1 >/dev/null 2>&1
        
        # Log progress every 5 seconds
        if [ $((i % (messages_per_second * 5))) -eq 0 ]; then
            # Count received messages from all subscribers
            messages_received=0
            for j in $(seq 1 $MAX_CONNECTIONS); do
                if [ -f "/tmp/subscriber_$j.txt" ]; then
                    messages_received=$((messages_received + $(wc -l < "/tmp/subscriber_$j.txt")))
                fi
            done
            
            log "Subscriber test progress: $subscribers_active active, $messages_received messages received"
            echo "$current_time,$subscribers_active,$messages_received,$duration" >> "$results_file"
        fi
        
        sleep $message_interval
    done
    
    # Wait for monitoring to complete
    wait $monitor_pid
    
    # Final message count
    messages_received=0
    for j in $(seq 1 $MAX_CONNECTIONS); do
        if [ -f "/tmp/subscriber_$j.txt" ]; then
            messages_received=$((messages_received + $(wc -l < "/tmp/subscriber_$j.txt")))
        fi
        kill ${subscriber_pids[j-1]} 2>/dev/null || true
        rm -f "/tmp/subscriber_$j.txt"
    done
    
    log "Concurrent Subscribers Test Results:"
    log "Active subscribers: $subscribers_active"
    log "Messages received: $messages_received"
    log "Messages expected: $((TEST_DURATION * messages_per_second))"
    log "Delivery rate: $(echo "scale=2; $messages_received * 100 / ($TEST_DURATION * $messages_per_second)" | bc)%"
    
    # Evaluate results
    local delivery_rate=$(echo "$messages_received * 100 / ($TEST_DURATION * $messages_per_second)" | bc)
    if [ "$delivery_rate" -ge 90 ]; then
        log_success "Concurrent subscribers test passed: $delivery_rate% delivery rate"
        return 0
    else
        log_error "Concurrent subscribers test failed: only $delivery_rate% delivery rate"
        return 1
    fi
}

test_sustained_load() {
    log "Testing sustained load over time..."
    
    local test_name="sustained-load"
    local results_file="$RESULTS_DIR/$test_name.csv"
    local total_messages=0
    local total_failures=0
    local start_time=$(date +%s)
    
    # Create results file
    echo "Timestamp,Messages_Sent,Total_Failures,Success_Rate,Duration" > "$results_file"
    
    log "Running sustained load test for $TEST_DURATION seconds..."
    
    # Extended test duration for sustained load
    local extended_duration=$((TEST_DURATION * 2))
    
    # Monitor system resources during the test
    local monitor_pid=$(monitor_system_resources $extended_duration)
    
    # Send messages continuously at moderate rate
    local sustained_rate=5
    local message_interval=$(echo "scale=3; 1.0 / $sustained_rate" | bc)
    
    for i in $(seq 1 $((extended_duration * sustained_rate))); do
        local current_time=$(date +%s)
        local duration=$((current_time - start_time))
        
        # Send message
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/sustained-load" \
            -m "Sustained load message $i at $(date +%s%3N)" \
            -q 1 >/dev/null 2>&1; then
            total_messages=$((total_messages + 1))
        else
            total_failures=$((total_failures + 1))
        fi
        
        # Log progress every 30 seconds
        if [ $((i % (sustained_rate * 30))) -eq 0 ]; then
            local success_rate=$(echo "scale=2; $total_messages * 100 / (total_messages + total_failures)" | bc)
            log "Sustained load progress: $total_messages sent, $total_failures failed, ${success_rate}% success rate"
            echo "$current_time,$total_messages,$total_failures,$success_rate,$duration" >> "$results_file"
        fi
        
        sleep $message_interval
    done
    
    # Wait for monitoring to complete
    wait $monitor_pid
    
    local total_attempts=$((total_messages + total_failures))
    local final_success_rate=$(echo "scale=2; $total_messages * 100 / $total_attempts" | bc)
    
    log "Sustained Load Test Results:"
    log "Duration: $extended_duration seconds"
    log "Total messages sent: $total_messages"
    log "Total failures: $total_failures"
    log "Final success rate: $final_success_rate%"
    log "Average rate: $(echo "scale=2; $total_messages / $extended_duration" | bc) messages/second"
    
    # Evaluate results
    if [ "$final_success_rate" -ge 95 ]; then
        log_success "Sustained load test passed: $final_success_rate% success rate maintained"
        return 0
    else
        log_error "Sustained load test failed: only $final_success_rate% success rate"
        return 1
    fi
}

test_memory_usage_under_load() {
    log "Testing memory usage under load..."
    
    local test_name="memory-usage"
    local results_file="$RESULTS_DIR/$test_name.csv"
    local start_time=$(date +%s)
    
    # Create results file
    echo "Timestamp,Memory_Usage_MB,VerneMQ_Memory_MB,GC_Events,Duration" > "$results_file"
    
    log "Monitoring memory usage during load test..."
    
    # Run load test while monitoring memory
    local monitor_duration=30
    local monitor_pid=$(monitor_system_resources $monitor_duration)
    
    # Generate load
    for i in $(seq 1 100); do
        local current_time=$(date +%s)
        local duration=$((current_time - start_time))
        
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TEST_TOPIC_PREFIX/memory-test" \
            -m "Memory test message $i" \
            -q 1 >/dev/null 2>&1
        
        # Get VerneMQ-specific memory usage
        local vernemq_memory=$(docker exec vernemq-test ps aux | grep vernemq | awk '{print $6}' 2>/dev/null || echo "0")
        
        # Get system memory usage
        local system_memory=$(free -m | awk 'NR==2{print $3}')
        
        # Log memory usage
        echo "$current_time,$system_memory,$vernemq_memory,0,$duration" >> "$results_file"
        
        sleep 0.2
    done
    
    # Wait for monitoring to complete
    wait $monitor_pid
    
    log "Memory Usage Test Results:"
    
    # Analyze memory usage
    if [ -f "$results_file" ]; then
        local avg_memory=$(awk -F',' 'NR>1 {sum+=$2; count++} END {print int(sum/count)}' "$results_file")
        local max_memory=$(awk -F',' 'NR>1 {if($2>max) max=$2} END {print max}' "$results_file")
        local vmq_memory=$(awk -F',' 'NR>1 {sum+=$3; count++} END {print int(sum/count)}' "$results_file")
        
        log "Average system memory usage: ${avg_memory}MB"
        log "Maximum system memory usage: ${max_memory}MB"
        log "Average VerneMQ memory usage: ${vmq_memory}MB"
        
        # Memory usage evaluation
        if [ "$max_memory" -lt 1000 ]; then  # Less than 1GB
            log_success "Memory usage under load is acceptable: ${max_memory}MB peak"
            return 0
        else
            log_error "High memory usage detected: ${max_memory}MB peak"
            return 1
        fi
    else
        log_error "Failed to collect memory usage data"
        return 1
    fi
}

# Main test execution
main() {
    log "Starting Load Tests for VerneMQ"
    log "Target: $MQTT_HOST:$MQTT_PORT"
    log "Test Parameters:"
    log "  Max Connections: $MAX_CONNECTIONS"
    log "  Message Rate: $MESSAGE_RATE messages/second"
    log "  Test Duration: $TEST_DURATION seconds"
    log "  Connection Rate: $CONNECTION_RATE connections/second"
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    local test_count=0
    local pass_count=0
    local fail_count=0
    
    # Run all load tests
    local tests=(
        "test_connection_load"
        "test_message_rate_load"
        "test_concurrent_subscribers"
        "test_sustained_load"
        "test_memory_usage_under_load"
    )
    
    for test in "${tests[@]}"; do
        test_count=$((test_count + 1))
        log "Running load test $test_count: $test"
        
        if $test; then
            pass_count=$((pass_count + 1))
            log_success "Load test $test_count passed"
        else
            fail_count=$((fail_count + 1))
            log_error "Load test $test_count failed"
        fi
        
        log "----------------------------------------"
        sleep 3
    done
    
    log "Load Tests Summary:"
    log "Total tests: $test_count"
    log "Passed: $pass_count"
    log "Failed: $fail_count"
    log "Results saved in: $RESULTS_DIR"
    
    if [ "$fail_count" -eq 0 ]; then
        log_success "All load tests passed!"
        return 0
    else
        log_error "$fail_count load tests failed"
        return 1
    fi
}

# Run main function
main "$@"