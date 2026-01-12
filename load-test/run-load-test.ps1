# =============================================================================
# VerneMQ MQTT Load Test Runner
# =============================================================================
# Run this script to execute MQTT load tests against VerneMQ broker
#
# Usage:
#   .\run-load-test.ps1                    # Run with default settings
#   .\run-load-test.ps1 -Preset basic      # Basic load test (50 clients, 60s)
#   .\run-load-test.ps1 -Preset stress     # Stress test (1000 clients, 300s)
#   .\run-load-test.ps1 -Preset 10k        # 10K connection test (10000 clients)
#   .\run-load-test.ps1 -Preset realworld  # Real-world simulation (2000 RTUs, 15-min interval)
#   .\run-load-test.ps1 -Preset syncburst  # Synchronized burst (2000 RTUs at :00, :15, :30, :45)
#   .\run-load-test.ps1 -Custom -Clients 100 -Duration 300
# =============================================================================

param(
    [ValidateSet("basic", "stress", "endurance", "spike", "10k", "realworld", "syncburst")]
    [string]$Preset = "basic",

    [switch]$Custom,
    [int]$Clients = 50,
    [int]$Duration = 60,
    [int]$Interval = 5,
    [string]$Broker = "tcp://localhost:1883",
    [string]$Topic = "thms",
    [string]$RtuPrefix = "25090100000",
    [string]$Username = "devuser",
    [string]$Password = "password",
    [int]$Qos = 0,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "         VerneMQ MQTT Load Test Runner                     " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Check if Go is installed
try {
    $goVersion = go version
    Write-Host "[OK] Go installed: $goVersion" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Go is not installed. Using pre-built binary if available." -ForegroundColor Yellow
}

# Build the mqtt-loadtest binary if needed
$mqttLoadtestPath = Join-Path $scriptDir "mqtt-loadtest.exe"
if (-not (Test-Path $mqttLoadtestPath)) {
    Write-Host "[INFO] Building mqtt-loadtest binary..." -ForegroundColor Yellow
    go build -o mqtt-loadtest.exe ./cmd/mqtt-loadtest
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to build mqtt-loadtest binary" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] MQTT Loadtest binary built successfully" -ForegroundColor Green
} else {
    Write-Host "[OK] MQTT Loadtest binary found" -ForegroundColor Green
}

# Build command based on preset or custom
Write-Host ""
if ($Custom) {
    Write-Host "[INFO] Running CUSTOM MQTT load test..." -ForegroundColor Cyan
    Write-Host "       Broker:    $Broker" -ForegroundColor White
    Write-Host "       Clients:   $Clients" -ForegroundColor White
    Write-Host "       Duration:  ${Duration}s" -ForegroundColor White
    Write-Host "       Interval:  ${Interval}s" -ForegroundColor White
    Write-Host "       Topic:     $Topic" -ForegroundColor White
    Write-Host "       RTU Prefix: $RtuPrefix" -ForegroundColor White
    if ($Username) {
        Write-Host "       Auth:      ${Username}:***" -ForegroundColor White
    }
    Write-Host ""

    $cmd = ".\mqtt-loadtest.exe -b $Broker -c $Clients -d $Duration -i $Interval -t $Topic --rtu-prefix $RtuPrefix --qos $Qos"
    if ($Username) {
        $cmd += " -u $Username -P $Password"
    }
    if ($Verbose) {
        $cmd += " --verbose"
    }
} else {
    Write-Host "[INFO] Running $($Preset.ToUpper()) preset MQTT load test..." -ForegroundColor Cyan

    switch ($Preset) {
        "basic" {
            Write-Host "       50 clients, 60s duration, 5s interval" -ForegroundColor White
            $cmd = ".\mqtt-loadtest.exe -b $Broker -c 50 -d 60 -i 5 -t $Topic --rtu-prefix $RtuPrefix"
        }
        "stress" {
            Write-Host "       1000 clients, 300s duration, 1s interval" -ForegroundColor White
            $cmd = ".\mqtt-loadtest.exe -b $Broker -c 1000 -d 300 -i 1 -t $Topic --rtu-prefix $RtuPrefix"
        }
        "endurance" {
            Write-Host "       100 clients, 3600s duration, 10s interval" -ForegroundColor White
            $cmd = ".\mqtt-loadtest.exe -b $Broker -c 100 -d 3600 -i 10 -t $Topic --rtu-prefix $RtuPrefix"
        }
        "spike" {
            Write-Host "       2000 clients, 120s duration, 2s interval" -ForegroundColor White
            $cmd = ".\mqtt-loadtest.exe -b $Broker -c 2000 -d 120 -i 2 -t $Topic --rtu-prefix $RtuPrefix"
        }
        "10k" {
            Write-Host "       10000 clients, 600s duration, 5s interval" -ForegroundColor White
            $cmd = ".\mqtt-loadtest.exe -b $Broker -c 10000 -d 600 -i 5 -t $Topic --rtu-prefix $RtuPrefix"
        }
        "realworld" {
            Write-Host "       2000 clients, 3600s duration, 900s interval (15-min real-world simulation)" -ForegroundColor White
            $cmd = ".\mqtt-loadtest.exe -b $Broker -c 2000 -d 3600 -i 900 -t $Topic --rtu-prefix $RtuPrefix"
        }
        "syncburst" {
            Write-Host "       2000 clients, 3600s duration, 900s SYNC interval (burst at :00, :15, :30, :45)" -ForegroundColor Green
            Write-Host "       Simulates real smart meter behavior with synchronized reporting" -ForegroundColor Gray
            $cmd = ".\mqtt-loadtest.exe -b $Broker -c 2000 -d 3600 -i 900 --sync --jitter 5 -t $Topic --rtu-prefix $RtuPrefix"
        }
    }
    Write-Host ""

    # Add auth parameters for all presets
    if ($Username) {
        $cmd += " -u $Username -P $Password"
    }

    if ($Verbose) {
        $cmd += " --verbose"
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Command: $cmd" -ForegroundColor Yellow
Write-Host ""

# Run the load test
Invoke-Expression $cmd

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "         MQTT Load Test Complete!                          " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
