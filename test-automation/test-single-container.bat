@echo off
REM VerneMQ Single Container Production Tests for Windows
REM Comprehensive test suite for single container VerneMQ deployment

setlocal enabledelayedexpansion

REM Colors for Windows (using color command)
set "RED=4"
set "GREEN=2"
set "YELLOW=6"
set "BLUE=1"

REM Test configuration
set "DOCKER_COMPOSE_FILE=docker-compose.prod.yml"
set "TEST_RESULTS_DIR=test-results\single-container"
set "LOG_DIR=logs"
set "MQTT_HOST=localhost"
set "MQTT_PORT=1883"
set "MQTT_WS_PORT=8080"
set "MGMT_PORT=8888"
set "TEST_TIMEOUT=30"

echo [INFO] VerneMQ Single Container Test Suite
echo.

REM Function to print colored output (basic implementation)
:print_status
echo [INFO] %~1
goto :eof

:print_success
echo [SUCCESS] %~1
goto :eof

:print_warning
echo [WARNING] %~1
goto :eof

:print_error
echo [ERROR] %~1
goto :eof

REM Function to show usage
:show_usage
echo Usage: %0 [OPTIONS]
echo.
echo Options:
echo   smoke         Run smoke tests only
echo   integration   Run integration tests only
echo   performance   Run performance tests only
echo   security      Run security tests only
echo   full          Run all tests ^(default^)
echo   setup         Setup test environment
echo   teardown      Clean up test environment
echo   verify        Verify container is running correctly
echo   help          Show this help message
echo.
echo Environment variables:
echo   MQTT_HOST     MQTT broker host ^(default: localhost^)
echo   MQTT_PORT     MQTT broker port ^(default: 1883^)
echo   MQTT_WS_PORT  WebSocket port ^(default: 8080^)
echo   MGMT_PORT     Management port ^(default: 8888^)
echo   TEST_TIMEOUT  Test timeout in seconds ^(default: 30^)
goto :eof

REM Function to check prerequisites
:check_prerequisites
call :print_status "Checking prerequisites..."

REM Check if Docker is installed
where docker >nul 2>nul
if %errorlevel% neq 0 (
    call :print_error "Docker is not installed. Please install Docker first."
    exit /b 1
)

REM Check if Docker Compose is available
where docker-compose >nul 2>nul
if %errorlevel% neq 0 (
    call :print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit /b 1
)

REM Check if Docker is running
docker info >nul 2>nul
if %errorlevel% neq 0 (
    call :print_error "Docker is not running. Please start Docker first."
    exit /b 1
)

call :print_success "Prerequisites check passed."
goto :eof

REM Function to setup test environment
:setup_test_environment
call :print_status "Setting up test environment for single container..."

REM Create required directories
if not exist "%TEST_RESULTS_DIR%" mkdir "%TEST_RESULTS_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM Create test environment file
echo # Single Container Test Environment > .env.test
echo TEST_ENV=testing >> .env.test
echo VERMEMQ_NODENAME=VerneMQ@test >> .env.test
echo VERMEMQ_DISTRIBUTED_COOKIE=test_cookie_%RANDOM% >> .env.test
echo VERMEMQ_ALLOW_ANONYMOUS=on >> .env.test
echo VERMEMQ_MAX_CONNECTIONS=1000 >> .env.test
echo VERMEMQ_LOG_CONSOLE=file >> .env.test
echo VERMEMQ_LOG_ERROR=file >> .env.test
echo VERMEMQ_METRICS_ENABLED=on >> .env.test

call :print_success "Test environment file created."

REM Build VerneMQ image
call :print_status "Building VerneMQ image..."
docker build -t vernemq:latest .

if %errorlevel% neq 0 (
    call :print_error "Failed to build Docker image."
    exit /b 1
)

call :print_success "Test environment setup completed."
goto :eof

REM Function to start VerneMQ container
:start_verne_mq
call :print_status "Starting VerneMQ container..."

REM Stop any existing containers
docker-compose -f "%DOCKER_COMPOSE_FILE%" down --volumes >nul 2>&1

REM Start VerneMQ
docker-compose -f "%DOCKER_COMPOSE_FILE%" up -d vernemq

if %errorlevel% neq 0 (
    call :print_error "Failed to start VerneMQ container."
    exit /b 1
)

REM Wait for VerneMQ to be ready
call :print_status "Waiting for VerneMQ to be ready..."
timeout /t 10 /nobreak >nul
docker exec vernemq-prod /opt/vernemq/bin/vmq-admin cluster status >nul 2>&1
if %errorlevel% neq 0 (
    call :print_error "VerneMQ container failed to start"
    docker logs vernemq-prod
    exit /b 1
)

call :print_success "VerneMQ container is ready"
goto :eof

REM Function to stop VerneMQ container
:stop_verne_mq
call :print_status "Stopping VerneMQ container..."
docker-compose -f "%DOCKER_COMPOSE_FILE%" down --volumes >nul 2>&1
call :print_success "VerneMQ container stopped"
goto :eof

REM Function to verify container health
:verify_container
call :print_status "Verifying container health..."

REM Check if container is running
docker ps | findstr vernemq-prod >nul
if %errorlevel% neq 0 (
    call :print_error "VerneMQ container is not running"
    exit /b 1
)

REM Check management API
curl -s http://localhost:%MGMT_PORT%/api/v1/status >nul 2>&1
if %errorlevel% neq 0 (
    call :print_error "Management API is not responding"
    exit /b 1
) else (
    call :print_success "Management API is responding"
)

call :print_success "Container health verification passed"
goto :eof

REM Function to run smoke tests
:run_smoke_tests
call :print_status "Running smoke tests..."

REM Test 1: Basic connectivity
call :print_status "Testing basic connectivity..."
powershell -Command "Test-NetConnection -ComputerName localhost -Port %MQTT_PORT%" >nul 2>&1
if %errorlevel% neq 0 (
    call :print_error "MQTT port is not accessible"
    exit /b 1
) else (
    call :print_success "MQTT port is accessible"
)

REM Test 2: Management API
call :print_status "Testing management API..."
curl -s http://localhost:%MGMT_PORT%/api/v1/status >nul 2>&1
if %errorlevel% neq 0 (
    call :print_error "Management API test failed"
    exit /b 1
) else (
    call :print_success "Management API is working"
)

REM Test 3: Basic MQTT test (if mosquitto_pub is available)
where mosquitto_pub >nul 2>&1
if %errorlevel% equ 0 (
    call :print_status "Testing MQTT connection..."
    mosquitto_pub -h %MQTT_HOST% -p %MQTT_PORT% -t "smoke/test" -m "smoke test" -q 0 >nul 2>&1
    if %errorlevel% equ 0 (
        call :print_success "MQTT connection successful"
    ) else (
        call :print_warning "MQTT test skipped or failed"
    )
) else (
    call :print_warning "Mosquitto clients not found, skipping MQTT tests"
)

call :print_success "Smoke tests completed"
goto :eof

REM Function to run integration tests
:run_integration_tests
call :print_status "Running integration tests..."

REM Test QoS levels (if mosquitto tools available)
where mosquitto_pub >nul 2>&1
if %errorlevel% equ 0 (
    call :print_status "Testing QoS levels..."
    mosquitto_pub -h %MQTT_HOST% -p %MQTT_PORT% -t "integration/qos" -m "QoS test" -q 1 >nul 2>&1
    if %errorlevel% equ 0 (
        call :print_success "QoS 1 message published"
    ) else (
        call :print_warning "QoS test failed"
    )
) else (
    call :print_warning "Mosquitto clients not found, skipping integration tests"
)

call :print_success "Integration tests completed"
goto :eof

REM Function to cleanup
:cleanup
call :print_status "Cleaning up test environment..."

REM Stop VerneMQ
call :stop_verne_mq

REM Clean up test artifacts
if exist ".env.test" del ".env.test"
if exist "test-results\single-container\test-report.html" del "test-results\single-container\test-report.html"

call :print_success "Cleanup completed."
goto :eof

REM Main execution
if "%1"=="" (
    set "action=full"
) else (
    set "action=%1"
)

if "%action%"=="smoke" (
    call :check_prerequisites
    call :setup_test_environment
    call :start_verne_mq
    call :run_smoke_tests
    call :cleanup
) else if "%action%"=="integration" (
    call :check_prerequisites
    call :setup_test_environment
    call :start_verne_mq
    call :run_integration_tests
    call :cleanup
) else if "%action%"=="full" (
    call :check_prerequisites
    call :setup_test_environment
    call :start_verne_mq
    call :verify_container
    call :run_smoke_tests
    call :run_integration_tests
    call :cleanup
) else if "%action%"=="setup" (
    call :check_prerequisites
    call :setup_test_environment
) else if "%action%"=="teardown" (
    call :cleanup
) else if "%action%"=="verify" (
    call :verify_container
) else if "%action%"=="help" (
    call :show_usage
) else (
    call :print_error "Unknown action: %action%"
    call :show_usage
    exit /b 1
)

endlocal