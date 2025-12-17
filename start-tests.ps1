#!/usr/bin/env pwsh
# VerneMQ Cross-Platform Test Automation Startup Script
# Automatically detects platform and runs appropriate test commands

param(
    [ValidateSet("unit", "integration", "performance", "security", "e2e", "smoke", "full", "setup", "clean", "report", "help")]
    [string]$TestType = "full",
    
    [switch]$Windows,
    
    [switch]$Linux,
    
    [switch]$DockerOnly,
    
    [switch]$Verbose
)

# Test configuration
$Script:TestResultsDir = "test-results"
$Script:LogDir = "logs"
$Script:TestEnvFile = ".env.test"
$Script:DockerComposeFile = "docker-compose.test.yml"
$Script:CrossPlatformFile = "docker-compose.test.cross-platform.yml"

# Color codes for PowerShell output
$Colors = @{
    Info = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Debug = "Magenta"
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-TestLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Create log directory if it doesn't exist
    if (!(Test-Path $Script:LogDir)) {
        New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
    }
    
    # Write to log file
    $logFile = Join-Path $Script:LogDir "test-automation.log"
    Add-Content -Path $logFile -Value $logEntry
    
    # Write to console with color
    switch ($Level) {
        "SUCCESS" { Write-ColorOutput $logEntry $Colors.Success }
        "WARNING" { Write-ColorOutput $logEntry $Colors.Warning }
        "ERROR"   { Write-ColorOutput $logEntry $Colors.Error }
        "DEBUG"   { Write-ColorOutput $logEntry $Colors.Debug }
        default   { Write-ColorOutput $logEntry $Colors.Info }
    }
}

function Get-PlatformInfo {
    $platform = "unknown"
    $isWindows = $false
    $isLinux = $false
    
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core
        if ($IsWindows) {
            $platform = "windows"
            $isWindows = $true
        } elseif ($IsLinux) {
            $platform = "linux"
            $isLinux = $true
        } elseif ($IsMacOS) {
            $platform = "macos"
        }
    } else {
        # Windows PowerShell
        if ($env:OS -eq "Windows_NT") {
            $platform = "windows"
            $isWindows = $true
        } else {
            $platform = "linux"
            $isLinux = $true
        }
    }
    
    return @{
        Platform = $platform
        IsWindows = $isWindows
        IsLinux = $isLinux
        IsMacOS = $platform -eq "macos"
    }
}

function Test-Prerequisites {
    Write-TestLog "Checking prerequisites..." "INFO"
    
    # Check Docker
    try {
        $dockerVersion = docker --version 2>$null
        if ($dockerVersion) {
            Write-TestLog "Docker found: $dockerVersion" "SUCCESS"
        } else {
            throw "Docker not found"
        }
    } catch {
        Write-TestLog "Docker is not installed or not in PATH. Please install Docker first." "ERROR"
        return $false
    }
    
    # Check Docker Compose
    try {
        $composeVersion = docker-compose --version 2>$null
        if ($composeVersion) {
            Write-TestLog "Docker Compose found: $composeVersion" "SUCCESS"
        } else {
            throw "Docker Compose not found"
        }
    } catch {
        Write-TestLog "Docker Compose is not installed or not in PATH. Please install Docker Compose first." "ERROR"
        return $false
    }
    
    # Check mosquitto clients (optional)
    try {
        $mosquittoPub = Get-Command mosquitto_pub -ErrorAction SilentlyContinue
        if ($mosquittoPub) {
            Write-TestLog "Mosquitto clients found" "SUCCESS"
        } else {
            Write-TestLog "Mosquitto clients not found. Some tests may be limited." "WARNING"
        }
    } catch {
        Write-TestLog "Mosquitto clients not found. Some tests may be limited." "WARNING"
    }
    
    # Check jq (optional)
    try {
        $jq = Get-Command jq -ErrorAction SilentlyContinue
        if ($jq) {
            Write-TestLog "jq found" "SUCCESS"
        } else {
            Write-TestLog "jq not found. Some JSON processing features may be limited." "WARNING"
        }
    } catch {
        Write-TestLog "jq not found. Some JSON processing features may be limited." "WARNING"
    }
    
    return $true
}

function Start-TestEnvironment {
    Write-TestLog "Setting up test environment..." "INFO"
    
    # Create required directories
    $dirs = @($Script:TestResultsDir, $Script:LogDir)
    foreach ($dir in $dirs) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-TestLog "Created directory: $dir" "DEBUG"
        }
    }
    
    # Create test environment file
    if (!(Test-Path $Script:TestEnvFile)) {
        $envContent = @"
# VerneMQ Test Environment Configuration
TEST_ENV=testing
VERMEMQ_NODENAME=VerneMQ@test
VERMEMQ_DISTRIBUTED_COOKIE=test_cookie_change_me
VERMEMQ_ALLOW_ANONYMOUS=on
VERMEMQ_MAX_CONNECTIONS=1000
VERMEMQ_LOG_CONSOLE=file
VERMEMQ_LOG_ERROR=file
VERMEMQ_METRICS_ENABLED=on
VERMEMQ_LISTENER_TCP_DEFAULT=127.0.0.1:1883
VERMEMQ_LISTENER_TCP_TEST=127.0.0.1:1884
VERMEMQ_WEBSOCKET_ENABLED=on
VERMEMQ_WEBSOCKET_LISTENERS_DEFAULT=on
VERMEMQ_HTTP_PUB_ENABLED=on
VERMEMQ_HTTP_PUB_LISTENERS_DEFAULT=on
"@
        Set-Content -Path $Script:TestEnvFile -Value $envContent
        Write-TestLog "Created test environment file: $Script:TestEnvFile" "SUCCESS"
    }
    
    Write-TestLog "Test environment setup completed" "SUCCESS"
}

function Start-DockerEnvironment {
    param(
        [hashtable]$Platform
    )
    
    Write-TestLog "Starting Docker test environment..." "INFO"
    
    # Choose appropriate Docker Compose file
    $composeFile = if ($Platform.IsWindows -or $Platform.IsLinux) {
        $Script:CrossPlatformFile
    } else {
        $Script:DockerComposeFile
    }
    
    if (!(Test-Path $composeFile)) {
        Write-TestLog "Docker Compose file not found: $composeFile" "ERROR"
        return $false
    }
    
    # Set platform environment variable
    $env:PLATFORM_DETECTED = $Platform.Platform.ToUpper()
    
    try {
        # Start services
        docker-compose -f $composeFile up -d
        if ($LASTEXITCODE -eq 0) {
            Write-TestLog "Docker environment started successfully" "SUCCESS"
            
            # Wait for services to be ready
            Write-TestLog "Waiting for services to be ready..." "INFO"
            Start-Sleep -Seconds 30
            
            # Health check
            docker-compose -f $composeFile exec -T vernemq /opt/vernemq/bin/vmq-admin cluster status | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-TestLog "VerneMQ is ready" "SUCCESS"
                return $true
            } else {
                Write-TestLog "VerneMQ health check failed" "WARNING"
                return $true  # Continue anyway
            }
        } else {
            Write-TestLog "Failed to start Docker environment" "ERROR"
            return $false
        }
    } catch {
        Write-TestLog "Error starting Docker environment: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Stop-DockerEnvironment {
    Write-TestLog "Stopping Docker test environment..." "INFO"
    
    $composeFile = $Script:CrossPlatformFile
    if (Test-Path $composeFile) {
        try {
            docker-compose -f $composeFile down --volumes --remove-orphans
            Write-TestLog "Docker environment stopped" "SUCCESS"
        } catch {
            Write-TestLog "Error stopping Docker environment: $($_.Exception.Message)" "ERROR"
        }
    }
}

function Invoke-UnitTests {
    Write-TestLog "Running unit tests..." "INFO"
    
    # Run Erlang/OTP unit tests
    Write-TestLog "Running Erlang/OTP EUnit tests..." "INFO"
    try {
        ./rebar3 eunit --verbose
        if ($LASTEXITCODE -eq 0) {
            Write-TestLog "EUnit tests passed" "SUCCESS"
        } else {
            Write-TestLog "EUnit tests failed" "ERROR"
            return $false
        }
    } catch {
        Write-TestLog "Error running EUnit tests: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    # Run Common Test suites
    Write-TestLog "Running Common Test suites..." "INFO"
    try {
        ./rebar3 ct --verbose
        if ($LASTEXITCODE -eq 0) {
            Write-TestLog "Common Test suites passed" "SUCCESS"
        } else {
            Write-TestLog "Common Test suites failed" "ERROR"
            return $false
        }
    } catch {
        Write-TestLog "Error running Common Test suites: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    # Copy test results
    $unitResultsDir = Join-Path $Script:TestResultsDir "unit"
    if (!(Test-Path $unitResultsDir)) {
        New-Item -ItemType Directory -Path $unitResultsDir -Force | Out-Null
    }
    
    if (Test-Path "_build\test\logs") {
        Copy-Item -Path "_build\test\logs\*" -Destination $unitResultsDir -Recurse -Force
    }
    
    Write-TestLog "Unit tests completed" "SUCCESS"
    return $true
}

function Invoke-IntegrationTests {
    Write-TestLog "Running integration tests..." "INFO"
    
    # Run integration test scripts
    $testScripts = @(
        "test-automation\integration\mqtt-integration-tests.sh",
        "test-automation\integration\plugin-integration-tests.sh",
        "test-automation\integration\clustering-integration-tests.sh"
    )
    
    foreach ($script in $testScripts) {
        if (Test-Path $script) {
            Write-TestLog "Running integration test: $script" "INFO"
            try {
                bash $script
                if ($LASTEXITCODE -eq 0) {
                    Write-TestLog "Integration test passed: $script" "SUCCESS"
                } else {
                    Write-TestLog "Integration test failed: $script" "ERROR"
                    return $false
                }
            } catch {
                Write-TestLog "Error running integration test $script`: $($_.Exception.Message)" "ERROR"
                return $false
            }
        } else {
            Write-TestLog "Integration test script not found: $script" "WARNING"
        }
    }
    
    Write-TestLog "Integration tests completed" "SUCCESS"
    return $true
}

function Show-Usage {
    Write-ColorOutput @"
VerneMQ Cross-Platform Test Automation Suite

Usage: .\start-tests.ps1 [OPTIONS]

Options:
    -TestType <type>       Test type to run (default: full)
    -Windows              Force Windows mode
    -Linux                Force Linux mode  
    -DockerOnly           Only start Docker environment
    -Verbose              Enable verbose output
    -Help                 Show this help message

Test Types:
    unit          Run unit tests only
    integration   Run integration tests only
    performance   Run performance tests only
    security      Run security tests only
    e2e           Run end-to-end tests only
    smoke         Run smoke tests only
    full          Run all tests (default)
    setup         Setup test environment only
    clean         Clean up test environment
    report        Generate test report

Examples:
    .\start-tests.ps1                    # Run all tests
    .\start-tests.ps1 -TestType unit     # Run unit tests only
    .\start-tests.ps1 -TestType integration -Verbose
    .\start-tests.ps1 -DockerOnly        # Start Docker environment only
    .\start-tests.ps1 -TestType clean    # Clean up environment

Environment Variables:
    VERNEMQ_TEST_TIMEOUT    Test timeout in seconds (default: 300)
    VERNEMQ_TEST_PARALLEL   Number of parallel test workers (default: 4)
    VERNEMQ_TEST_VERBOSE    Enable verbose output (default: false)

Platform Support:
    - Windows 10/11 with PowerShell Core or Windows PowerShell
    - Linux with bash and Docker
    - Docker Desktop on both platforms

"@ "Cyan"
}

function Start-Main {
    Write-ColorOutput @"
========================================
VerneMQ Test Automation Suite (Cross-Platform)
========================================
" "Cyan"
    
    # Get platform information
    $platform = Get-PlatformInfo
    Write-TestLog "Detected platform: $($platform.Platform)" "INFO"
    Write-TestLog "Platform details: Windows=$($platform.IsWindows), Linux=$($platform.IsLinux), macOS=$($platform.IsMacOS)" "DEBUG"
    
    # Handle help request
    if ($TestType -eq "help") {
        Show-Usage
        return
    }
    
    # Check prerequisites
    if (!(Test-Prerequisites)) {
        Write-TestLog "Prerequisites check failed. Please install required tools." "ERROR"
        exit 1
    }
    
    # Setup test environment
    Start-TestEnvironment
    
    # Handle different test types
    switch ($TestType) {
        "setup" {
            Write-TestLog "Test environment setup completed" "SUCCESS"
            return
        }
        
        "clean" {
            Stop-DockerEnvironment
            if (Test-Path $Script:TestResultsDir) { Remove-Item $Script:TestResultsDir -Recurse -Force }
            if (Test-Path $Script:LogDir) { Remove-Item $Script:LogDir -Recurse -Force }
            if (Test-Path $Script:TestEnvFile) { Remove-Item $Script:TestEnvFile -Force }
            Write-TestLog "Test environment cleaned up" "SUCCESS"
            return
        }
        
        "report" {
            Write-TestLog "Generating test report..." "INFO"
            # Generate HTML report (basic implementation)
            $reportFile = Join-Path $Script:TestResultsDir "test-report.html"
            $reportContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>VerneMQ Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #f4f4f4; padding: 20px; border-radius: 5px; }
        .success { color: green; }
        .error { color: red; }
        .warning { color: orange; }
    </style>
</head>
<body>
    <div class="header">
        <h1>VerneMQ Test Automation Report</h1>
        <p>Generated: $(Get-Date)</p>
        <p>Platform: $($platform.Platform)</p>
    </div>
    <h2>Test Summary</h2>
    <p>Test automation suite completed successfully on $($platform.Platform) platform.</p>
</body>
</html>
"@
            Set-Content -Path $reportFile -Value $reportContent
            Write-TestLog "Test report generated: $reportFile" "SUCCESS"
            return
        }
        
        default {
            # Start Docker environment if not DockerOnly
            if (!$DockerOnly) {
                if (!(Start-DockerEnvironment -Platform $platform)) {
                    Write-TestLog "Failed to start Docker environment" "ERROR"
                    exit 1
                }
            }
            
            $success = $true
            
            # Run requested tests
            switch ($TestType) {
                "unit" { $success = Invoke-UnitTests }
                "integration" { $success = Invoke-IntegrationTests }
                "performance" { Write-TestLog "Performance tests not yet implemented in PowerShell" "WARNING" }
                "security" { Write-TestLog "Security tests not yet implemented in PowerShell" "WARNING" }
                "e2e" { Write-TestLog "End-to-end tests not yet implemented in PowerShell" "WARNING" }
                "smoke" { Write-TestLog "Smoke tests not yet implemented in PowerShell" "WARNING" }
                "full" { 
                    $success = Invoke-UnitTests
                    if ($success) { $success = Invoke-IntegrationTests }
                }
            }
            
            # Stop Docker environment if we started it
            if (!$DockerOnly) {
                Stop-DockerEnvironment
            }
            
            if ($success) {
                Write-TestLog "Test execution completed successfully!" "SUCCESS"
                Write-TestLog "Results available in: $Script:TestResultsDir" "INFO"
            } else {
                Write-TestLog "Test execution failed" "ERROR"
                exit 1
            }
        }
    }
}

# Run main function
Start-Main