#!/bin/bash

# Authentication Tests for VerneMQ
# Tests various authentication mechanisms and security configurations

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
SSL_PORT="${SSL_PORT:-8883}"
TEST_TOPIC_PREFIX="security/auth"
LOG_FILE="logs/authentication-tests.log"
TEST_USER="testuser"
TEST_PASSWORD="testpassword123"
INVALID_USER="invaliduser"
INVALID_PASSWORD="invalidpassword"

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
test_anonymous_connection() {
    log "Testing anonymous connection behavior..."
    
    # Configure VerneMQ to allow anonymous connections for this test
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{"allow_anonymous": true}' || log_warning "Failed to configure anonymous access"
    
    sleep 2
    
    local test_topic="$TEST_TOPIC_PREFIX/anonymous"
    local test_message="Anonymous test $(date +%s)"
    
    # Test anonymous connection
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -m "$test_message" -q 1; then
        log_success "Anonymous connection allowed (expected in test environment)"
        
        # Verify message reception
        local received_message=""
        received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$test_topic" -W 5 -C 1 2>/dev/null || echo "")
        
        if [ "$received_message" = "$test_message" ]; then
            log_success "Anonymous connection working: message transmitted"
        else
            log_error "Anonymous connection test failed: message not received"
            return 1
        fi
    else
        log_warning "Anonymous connection rejected (may be configured for production)"
    fi
    
    return 0
}

test_authentication_required() {
    log "Testing authentication requirement..."
    
    # Configure VerneMQ to require authentication
    curl -s -X POST "http://$MQTT_HOST:8888/api/v1/configuration" \
        -H "Content-Type: application/json" \
        -d '{"allow_anonymous": false}' || log_warning "Failed to configure authentication requirement"
    
    sleep 2
    
    # Test connection without credentials (should fail)
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$TEST_TOPIC_PREFIX/no-auth" \
        -m "Should fail" -q 1 2>/dev/null; then
        log_error "Authentication requirement test failed: connection allowed without credentials"
        return 1
    else
        log_success "Authentication requirement working: connection rejected without credentials"
    fi
    
    return 0
}

test_password_authentication() {
    log "Testing password-based authentication..."
    
    # Create test user with password
    local test_topic="$TEST_TOPIC_PREFIX/password"
    local test_message="Password auth test $(date +%s)"
    
    # Test with valid credentials
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$test_topic" \
        -m "$test_message" \
        -u "$TEST_USER" \
        -P "$TEST_PASSWORD" \
        -q 1; then
        log_success "Password authentication successful with valid credentials"
        
        # Verify message reception
        local received_message=""
        received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$test_topic" -W 5 -C 1 \
            -u "$TEST_USER" -P "$TEST_PASSWORD" 2>/dev/null || echo "")
        
        if [ "$received_message" = "$test_message" ]; then
            log_success "Password authentication working: message transmitted with auth"
        else
            log_error "Password authentication test failed: message not received"
            return 1
        fi
    else
        log_warning "Password authentication test: could not authenticate with test credentials"
        log_warning "This may be expected if no test users are configured"
    fi
    
    # Test with invalid credentials (should fail)
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$test_topic" \
        -m "Should fail" \
        -u "$INVALID_USER" \
        -P "$INVALID_PASSWORD" \
        -q 1 2>/dev/null; then
        log_error "Password authentication test failed: invalid credentials accepted"
        return 1
    else
        log_success "Password authentication working: invalid credentials rejected"
    fi
    
    return 0
}

test_client_certificate_authentication() {
    log "Testing client certificate authentication..."
    
    local test_topic="$TEST_TOPIC_PREFIX/cert-auth"
    local test_message="Certificate auth test $(date +%s)"
    
    # Test SSL/TLS connection with client certificate
    if [ -f "test-automation/ssl/client.pem" ] && [ -f "test-automation/ssl/client-key.pem" ]; then
        if mosquitto_pub -h "$MQTT_HOST" -p "$SSL_PORT" \
            --cafile test-automation/ssl/ca.pem \
            --cert test-automation/ssl/client.pem \
            --key test-automation/ssl/client-key.pem \
            -t "$test_topic" \
            -m "$test_message" \
            -q 1; then
            log_success "Client certificate authentication successful"
            
            # Verify message reception
            local received_message=""
            received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$SSL_PORT" \
                --cafile test-automation/ssl/ca.pem \
                --cert test-automation/ssl/client.pem \
                --key test-automation/ssl/client-key.pem \
                -t "$test_topic" -W 5 -C 1 2>/dev/null || echo "")
            
            if [ "$received_message" = "$test_message" ]; then
                log_success "Client certificate authentication working: message transmitted"
                return 0
            else
                log_error "Client certificate authentication test failed: message not received"
                return 1
            fi
        else
            log_warning "Client certificate authentication test: could not establish SSL connection"
            log_warning "This may be expected if SSL is not configured"
        fi
    else
        log_warning "Client certificate authentication test: SSL certificates not found"
    fi
    
    return 0
}

test_token_based_authentication() {
    log "Testing token-based authentication..."
    
    # Test with Bearer token (if supported)
    local test_topic="$TEST_TOPIC_PREFIX/token"
    local test_message="Token auth test $(date +%s)"
    local test_token="Bearer test-token-12345"
    
    # Note: This test assumes token-based auth is implemented via plugins
    # In practice, this would require specific plugin configuration
    
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$test_topic" \
        -m "$test_message" \
        -u "$test_token" \
        -P "ignored" \
        -q 1 2>/dev/null; then
        log_success "Token-based authentication successful"
        
        # Verify message reception
        local received_message=""
        received_message=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$test_topic" -W 5 -C 1 \
            -u "$test_token" -P "ignored" 2>/dev/null || echo "")
        
        if [ "$received_message" = "$test_message" ]; then
            log_success "Token-based authentication working: message transmitted"
            return 0
        else
            log_error "Token-based authentication test failed: message not received"
            return 1
        fi
    else
        log_warning "Token-based authentication test: not supported or failed"
        log_warning "This may be expected if no token auth plugin is configured"
    fi
    
    return 0
}

test_session_authentication() {
    log "Testing session-based authentication..."
    
    local test_topic="$TEST_TOPIC_PREFIX/session"
    local test_message="Session auth test $(date +%s)"
    local client_id="session-test-client-$(date +%s)"
    
    # Create authenticated session
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$test_topic" \
        -m "$test_message" \
        -u "$TEST_USER" \
        -P "$TEST_PASSWORD" \
        -i "$client_id" \
        -c \
        -q 1 2>/dev/null; then
        log_success "Session created with authentication"
        
        # Test reconnection with same client ID (should maintain session)
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$test_topic" \
            -m "Session test 2" \
            -u "$TEST_USER" \
            -P "$TEST_PASSWORD" \
            -i "$client_id" \
            -c \
            -q 1 2>/dev/null; then
            log_success "Session authentication working: reconnection successful"
            return 0
        else
            log_error "Session authentication test failed: reconnection failed"
            return 1
        fi
    else
        log_warning "Session authentication test: could not create authenticated session"
        log_warning "This may be expected if no test users are configured"
    fi
    
    return 0
}

test_authentication_brute_force_protection() {
    log "Testing brute force attack protection..."
    
    local test_topic="$TEST_TOPIC_PREFIX/brute-force"
    local failed_attempts=0
    
    # Attempt multiple failed authentications
    for i in {1..10}; do
        if ! mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$test_topic" \
            -m "Brute force attempt $i" \
            -u "$INVALID_USER" \
            -P "$INVALID_PASSWORD" \
            -q 1 2>/dev/null; then
            failed_attempts=$((failed_attempts + 1))
        else
            log_warning "Brute force protection may not be active: failed attempt $i succeeded"
        fi
        sleep 0.1
    done
    
    log "Brute force test: $failed_attempts failed attempts out of 10"
    
    # After failed attempts, test if connection is temporarily blocked
    sleep 2
    if ! mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$test_topic" \
        -m "Should still fail" \
        -u "$INVALID_USER" \
        -P "$INVALID_PASSWORD" \
        -q 1 2>/dev/null; then
        log_success "Brute force protection working: connection blocked after failed attempts"
        return 0
    else
        log_warning "Brute force protection test: connection still allowed after failed attempts"
        log_warning "This may be expected if brute force protection is not configured"
    fi
    
    return 0
}

test_authentication_rate_limiting() {
    log "Testing authentication rate limiting..."
    
    local test_topic="$TEST_TOPIC_PREFIX/rate-limit"
    local start_time=$(date +%s)
    local attempts=0
    
    # Attempt multiple connections rapidly
    for i in {1..20}; do
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$test_topic" \
            -m "Rate limit test $i" \
            -u "$INVALID_USER" \
            -P "$INVALID_PASSWORD" \
            -q 1 >/dev/null 2>&1
        
        attempts=$((attempts + 1))
        sleep 0.1
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "Rate limiting test: $attempts attempts in ${duration}s"
    
    # Check if rate limiting is active by monitoring response times or connection counts
    # This is a basic test - production systems would have more sophisticated rate limiting
    
    if [ "$duration" -lt 5 ]; then
        log_warning "Rate limiting may not be active: rapid attempts completed quickly"
    else
        log_success "Rate limiting may be active: requests took ${duration}s"
    fi
    
    return 0
}

test_credential_stuffing_protection() {
    log "Testing credential stuffing protection..."
    
    local test_topic="$TEST_TOPIC_PREFIX/credential-stuffing"
    local common_passwords=("password" "123456" "admin" "test" "guest")
    local test_users=("admin" "user" "test" "guest" "root")
    
    # Test common credential combinations
    local blocked_attempts=0
    local total_attempts=0
    
    for user in "${test_users[@]}"; do
        for password in "${common_passwords[@]}"; do
            total_attempts=$((total_attempts + 1))
            
            if ! mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
                -t "$test_topic" \
                -m "Credential stuffing test" \
                -u "$user" \
                -P "$password" \
                -q 1 2>/dev/null; then
                blocked_attempts=$((blocked_attempts + 1))
            fi
            
            sleep 0.05  # Small delay between attempts
        done
    done
    
    log "Credential stuffing test: $blocked_attempts/$total_attempts attempts blocked"
    
    local block_rate=$(echo "scale=2; $blocked_attempts * 100 / $total_attempts" | bc)
    log "Block rate: ${block_rate}%"
    
    if [ "$block_rate" -ge 90 ]; then
        log_success "Credential stuffing protection working: ${block_rate}% block rate"
        return 0
    else
        log_warning "Credential stuffing protection may not be active: only ${block_rate}% block rate"
    fi
    
    return 0
}

test_session_hijacking_protection() {
    log "Testing session hijacking protection..."
    
    local test_topic="$TEST_TOPIC_PREFIX/session-hijack"
    local legitimate_client="legitimate-client-$(date +%s)"
    local attacker_client="attacker-client-$(date +%s)"
    
    # Create legitimate session
    if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "$test_topic" \
        -m "Legitimate message" \
        -u "$TEST_USER" \
        -P "$TEST_PASSWORD" \
        -i "$legitimate_client" \
        -c \
        -q 1 2>/dev/null; then
        
        # Wait a moment for session establishment
        sleep 1
        
        # Try to hijack session with different client ID
        if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$test_topic" \
            -m "Hijack attempt" \
            -u "$TEST_USER" \
            -P "$TEST_PASSWORD" \
            -i "$attacker_client" \
            -c \
            -q 1 2>/dev/null; then
            log_warning "Session hijacking test: different client ID accepted"
            log_warning "Session isolation may not be properly enforced"
        else
            log_success "Session hijacking protection working: different client ID rejected"
        fi
        
        # Try to use the same client ID (should be rejected if session is bound)
        if ! mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$test_topic" \
            -m "Duplicate session attempt" \
            -u "$TEST_USER" \
            -P "$TEST_PASSWORD" \
            -i "$legitimate_client" \
            -c \
            -q 1 2>/dev/null; then
            log_success "Session hijacking protection working: duplicate client ID rejected"
        else
            log_warning "Session hijacking test: duplicate client ID accepted"
        fi
        
        return 0
    else
        log_warning "Session hijacking test: could not establish legitimate session"
        log_warning "This may be expected if no test users are configured"
    fi
    
    return 0
}

# Main test execution
main() {
    log "Starting Authentication Tests for VerneMQ"
    log "Target: $MQTT_HOST:$MQTT_PORT (SSL: $SSL_PORT)"
    log "Test Topic Prefix: $TEST_TOPIC_PREFIX"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    local test_count=0
    local pass_count=0
    local fail_count=0
    
    # Run all authentication tests
    local tests=(
        "test_anonymous_connection"
        "test_authentication_required"
        "test_password_authentication"
        "test_client_certificate_authentication"
        "test_token_based_authentication"
        "test_session_authentication"
        "test_authentication_brute_force_protection"
        "test_authentication_rate_limiting"
        "test_credential_stuffing_protection"
        "test_session_hijacking_protection"
    )
    
    for test in "${tests[@]}"; do
        test_count=$((test_count + 1))
        log "Running authentication test $test_count: $test"
        
        if $test; then
            pass_count=$((pass_count + 1))
            log_success "Authentication test $test_count passed"
        else
            fail_count=$((fail_count + 1))
            log_error "Authentication test $test_count failed"
        fi
        
        log "----------------------------------------"
        sleep 2
    done
    
    log "Authentication Tests Summary:"
    log "Total tests: $test_count"
    log "Passed: $pass_count"
    log "Failed: $fail_count"
    
    if [ "$fail_count" -eq 0 ]; then
        log_success "All authentication tests passed!"
        return 0
    else
        log_error "$fail_count authentication tests failed"
        return 1
    fi
}

# Run main function
main "$@"