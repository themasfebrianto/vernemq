@echo off
REM VerneMQ Comprehensive Test Automation Suite for Windows
REM This script orchestrates all test phases for VerneMQ

setlocal EnableDelayedExpansion

REM Configuration
set TEST_ENV_FILE=.env.test
set DOCKER_COMPOSE_FILE=docker-compose.test.yml
set TEST_RESULTS_DIR=test-results
set LOG_DIR=logs

REM Default parameters
set ACTION=%1
if "%ACTION%"=="" set ACTION=full

echo ========================================
echo VerneMQ Test Automation Suite (Windows)
echo ========================================
echo.

REM Function to show usage
goto :show_usage
:show_usage
echo Usage: %0 [OPTIONS]
echo.
echo Options:
echo   unit          Run unit tests only
echo   integration   Run integration tests only
echo   performance   Run performance tests only
echo   security      Run security tests only
echo   e2e           Run end-to-end tests only
echo   smoke         Run smoke tests only
echo   full          Run all tests (default)
echo   setup         Setup test environment
echo   clean         Clean up test environment
echo   report        Generate test report
echo   help          Show this help message
echo.
echo Environment variables:
echo   VERNEMQ_TEST_TIMEOUT    Test timeout in seconds (default: 300)
echo   VERNEMQ_TEST_PARALLEL   Number of parallel test workers (default: 4)
echo   VERNEMQ_TEST_VERBOSE    Enable verbose output (default: false)
echo.
goto :end

REM Check prerequisites
:check_prerequisites
echo [INFO] Checking prerequisites...
echo.

REM Check if Docker is installed
docker --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not installed. Please install Docker first.
    goto :end
)

REM Check if Docker Compose is installed
docker-compose --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker Compose is not installed. Please install Docker Compose first.
    goto :end
)

REM Check if mosquitto clients are available
where mosquitto_pub >nul 2>&1
if errorlevel 1 (
    echo [WARNING] Mosquitto clients not found. Please install mosquitto-clients.
    echo You can download from: https://mosquitto.org/download/
) else (
    echo [SUCCESS] Mosquitto clients found.
)

echo [SUCCESS] Prerequisites check passed.
echo.
goto :eof

REM Setup test environment
:setup_test_environment
echo [INFO] Setting up test environment...
echo.

REM Create required directories
if not exist "%TEST_RESULTS_DIR%" mkdir "%TEST_RESULTS_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM Setup test environment file
if not exist "%TEST_ENV_FILE%" (
    echo [INFO] Creating test environment file...
    (
        echo # VerneMQ Test Environment Configuration
        echo TEST_ENV=testing
        echo VERNEMQ_NODENAME=VerneMQ@test
        echo VERNEMQ_DISTRIBUTED_COOKIE=test_cookie_change_me
        echo VERNEMQ_ALLOW_ANONYMOUS=on
        echo VERNEMQ_MAX_CONNECTIONS=1000
        echo VERNEMQ_LOG_CONSOLE=file
        echo VERNEMQ_LOG_ERROR=file
        echo VERNEMQ_METRICS_ENABLED=on
        echo VERNEMQ_LISTENER_TCP_DEFAULT=127.0.0.1:1883
        echo VERNEMQ_LISTENER_TCP_TEST=127.0.0.1:1884
        echo VERNEMQ_WEBSOCKET_ENABLED=on
        echo VERNEMQ_WEBSOCKET_LISTENERS_DEFAULT=on
        echo VERNEMQ_HTTP_PUB_ENABLED=on
        echo VERNEMQ_HTTP_PUB_LISTENERS_DEFAULT=on
    ) > "%TEST_ENV_FILE%"
    echo [SUCCESS] Test environment file created.
)

echo [SUCCESS] Test environment setup completed.
echo.
goto :eof

REM Run unit tests
:run_unit_tests
echo [INFO] Running unit tests...
echo.

REM Run Erlang/OTP unit tests
echo [INFO] Running Erlang/OTP EUnit tests...
./rebar3 eunit --verbose
if errorlevel 1 (
    echo [ERROR] EUnit tests failed
    goto :end
)

echo [INFO] Running Common Test suites...
./rebar3 ct --verbose
if errorlevel 1 (
    echo [ERROR] Common Test suites failed
    goto :end
)

echo [SUCCESS] Unit tests completed.
echo.

REM Copy test results
if not exist "%TEST_RESULTS_DIR%\unit" mkdir "%TEST_RESULTS_DIR%\unit"
xcopy "_build\test\logs\*" "%TEST_RESULTS_DIR%\unit\" /E /I /Y >nul 2>&1

goto :eof

REM Run integration tests
:run_integration_tests
echo [INFO] Running integration tests...
echo.

echo [INFO] Starting test infrastructure...
docker-compose -f "%DOCKER_COMPOSE_FILE%" up -d
if errorlevel 1 (
    echo [ERROR] Failed to start test infrastructure
    goto :end
)

echo [INFO] Waiting for services to be ready...
timeout /t 120 /nobreak >nul
docker-compose -f "%DOCKER_COMPOSE_FILE%" exec -T vernemq /opt/vernemq/bin/vmq-admin cluster status >nul 2>&1
if errorlevel 1 (
    echo [WARNING] VerneMQ not ready, waiting more...
    timeout /t 30 /nobreak >nul
)

echo [INFO] Running MQTT integration tests...
call test-automation\integration\mqtt-integration-tests.sh
if errorlevel 1 (
    echo [ERROR] MQTT integration tests failed
    goto :end
)

echo [INFO] Running plugin integration tests...
call test-automation\integration\plugin-integration-tests.sh
if errorlevel 1 (
    echo [ERROR] Plugin integration tests failed
    goto :end
)

echo [INFO] Running clustering integration tests...
call test-automation\integration\clustering-integration-tests.sh
if errorlevel 1 (
    echo [ERROR] Clustering integration tests failed
    goto :end
)

echo [SUCCESS] Integration tests completed.
echo.

REM Copy test results
if not exist "%TEST_RESULTS_DIR%\integration" mkdir "%TEST_RESULTS_DIR%\integration"
docker-compose -f "%DOCKER_COMPOSE_FILE%" logs vernemq > "%TEST_RESULTS_DIR%\integration\vernemq.log"
docker-compose -f "%DOCKER_COMPOSE_FILE%" logs > "%TEST_RESULTS_DIR%\integration\docker-compose.log"

goto :eof

REM Run performance tests
:run_performance_tests
echo [INFO] Running performance tests...
echo.

echo [INFO] Running load tests...
call test-automation\performance\load-tests.sh
if errorlevel 1 (
    echo [ERROR] Load tests failed
    goto :end
)

echo [SUCCESS] Performance tests completed.
echo.

REM Copy test results
if not exist "%TEST_RESULTS_DIR%\performance" mkdir "%TEST_RESULTS_DIR%\performance"
xcopy "%LOG_DIR%\*" "%TEST_RESULTS_DIR%\performance\" /Y >nul 2>&1

goto :eof

REM Run security tests
:run_security_tests
echo [INFO] Running security tests...
echo.

echo [INFO] Running authentication tests...
call test-automation\security\authentication-tests.sh
if errorlevel 1 (
    echo [ERROR] Authentication tests failed
    goto :end
)

echo [SUCCESS] Security tests completed.
echo.

REM Copy test results
if not exist "%TEST_RESULTS_DIR%\security" mkdir "%TEST_RESULTS_DIR%\security"
xcopy "%LOG_DIR%\*" "%TEST_RESULTS_DIR%\security\" /Y >nul 2>&1

goto :eof

REM Run end-to-end tests
:run_e2e_tests
echo [INFO] Running end-to-end tests...
echo.

echo [INFO] Running MQTT workflow tests...
call test-automation\e2e\mqtt-workflow-tests.sh
if errorlevel 1 (
    echo [ERROR] MQTT workflow tests failed
    goto :end
)

echo [SUCCESS] End-to-end tests completed.
echo.

REM Copy test results
if not exist "%TEST_RESULTS_DIR%\e2e" mkdir "%TEST_RESULTS_DIR%\e2e"
xcopy "%LOG_DIR%\*" "%TEST_RESULTS_DIR%\e2e\" /Y >nul 2>&1

goto :eof

REM Run smoke tests
:run_smoke_tests
echo [INFO] Running smoke tests...
echo.

echo [INFO] Starting VerneMQ for smoke tests...
docker-compose -f "%DOCKER_COMPOSE_FILE%" up -d vernemq

echo [INFO] Waiting for VerneMQ to be ready...
timeout /t 60 /nobreak >nul

echo [INFO] Running basic connectivity test...
mosquitto_pub -h localhost -p 1883 -t 'smoke/test' -m 'smoke test message'
if errorlevel 1 (
    echo [ERROR] Basic connectivity test failed
    goto :end
)

mosquitto_sub -h localhost -p 1883 -t 'smoke/test' -W 1 -C 1
if errorlevel 1 (
    echo [ERROR] Message reception test failed
    goto :end
)

echo [INFO] Running management API test...
curl -s http://localhost:8888/api/v1/status | findstr . >nul
if errorlevel 1 (
    echo [ERROR] Management API test failed
    goto :end
)

echo [INFO] Stopping VerneMQ...
docker-compose -f "%DOCKER_COMPOSE_FILE%" stop vernemq

echo [SUCCESS] Smoke tests completed.
echo.
goto :eof

REM Generate test report
:generate_test_report
echo [INFO] Generating test report...
echo.

set REPORT_FILE=%TEST_RESULTS_DIR%\test-report.html

echo ^<!DOCTYPE html^> > "%REPORT_FILE%"
echo ^<html^> >> "%REPORT_FILE%"
echo ^<head^> >> "%REPORT_FILE%"
echo     ^<title^>VerneMQ Test Report^</title^> >> "%REPORT_FILE%"
echo     ^<style^> >> "%REPORT_FILE%"
echo         body { font-family: Arial, sans-serif; margin: 40px; } >> "%REPORT_FILE%"
echo         .header { background-color: #f4f4f4; padding: 20px; border-radius: 5px; } >> "%REPORT_FILE%"
echo         .summary { margin: 20px 0; } >> "%REPORT_FILE%"
echo         .test-section { margin: 20px 0; border: 1px solid #ddd; padding: 15px; border-radius: 5px; } >> "%REPORT_FILE%"
echo         .success { color: green; } >> "%REPORT_FILE%"
echo         .failure { color: red; } >> "%REPORT_FILE%"
echo         .warning { color: orange; } >> "%REPORT_FILE%"
echo         table { width: 100%%; border-collapse: collapse; margin: 10px 0; } >> "%REPORT_FILE%"
echo         th, td { border: 1px solid #ddd; padding: 8px; text-align: left; } >> "%REPORT_FILE%"
echo         th { background-color: #f2f2f2; } >> "%REPORT_FILE%"
echo     ^</style^> >> "%REPORT_FILE%"
echo ^</head^> >> "%REPORT_FILE%"
echo ^<body^> >> "%REPORT_FILE%"
echo     ^<div class="header"^> >> "%REPORT_FILE%"
echo         ^<h1^>VerneMQ Test Automation Report^</h1^> >> "%REPORT_FILE%"
echo         ^<p^>Generated: %date% %time%^</p^> >> "%REPORT_FILE%"
echo     ^</div^> >> "%REPORT_FILE%"
echo ^</body^> >> "%REPORT_FILE%"
echo ^</html^> >> "%REPORT_FILE%"

echo [SUCCESS] Test report generated: %REPORT_FILE%
echo.
goto :eof

REM Clean up test environment
:cleanup_test_environment
echo [INFO] Cleaning up test environment...
echo.

if exist "%DOCKER_COMPOSE_FILE%" (
    docker-compose -f "%DOCKER_COMPOSE_FILE%" down --volumes --remove-orphans
)

if exist "%TEST_RESULTS_DIR%" (
    rmdir /s /q "%TEST_RESULTS_DIR%"
)

if exist "%LOG_DIR%" (
    rmdir /s /q "%LOG_DIR%"
)

if exist "%TEST_ENV_FILE%" (
    del "%TEST_ENV_FILE%"
)

echo [SUCCESS] Test environment cleaned up.
echo.
goto :eof

REM Main execution
:main
if "%ACTION%"=="unit" (
    call :check_prerequisites
    call :run_unit_tests
) else if "%ACTION%"=="integration" (
    call :check_prerequisites
    call :setup_test_environment
    call :run_integration_tests
) else if "%ACTION%"=="performance" (
    call :check_prerequisites
    call :setup_test_environment
    call :run_performance_tests
) else if "%ACTION%"=="security" (
    call :check_prerequisites
    call :setup_test_environment
    call :run_security_tests
) else if "%ACTION%"=="e2e" (
    call :check_prerequisites
    call :setup_test_environment
    call :run_e2e_tests
) else if "%ACTION%"=="smoke" (
    call :check_prerequisites
    call :setup_test_environment
    call :run_smoke_tests
) else if "%ACTION%"=="full" (
    call :check_prerequisites
    call :setup_test_environment
    call :run_unit_tests
    call :run_integration_tests
    call :run_performance_tests
    call :run_security_tests
    call :run_e2e_tests
    call :run_smoke_tests
) else if "%ACTION%"=="setup" (
    call :check_prerequisites
    call :setup_test_environment
) else if "%ACTION%"=="clean" (
    call :cleanup_test_environment
) else if "%ACTION%"=="report" (
    call :generate_test_report
) else if "%ACTION%"=="help" (
    goto :show_usage
) else (
    echo [ERROR] Unknown action: %ACTION%
    echo.
    goto :show_usage
)

echo ========================================
echo Test execution completed!
echo ========================================
echo.
goto :end

:end
pause
exit /b 0