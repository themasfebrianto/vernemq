# =============================================================================
# VerneMQ Load Test Runner
# =============================================================================
# Run this script to execute MQTT load tests against your local VerneMQ instance
# 
# Usage:
#   .\run-load-test.ps1               # Run with default (light) preset
#   .\run-load-test.ps1 -Preset light  # 5 clients, 2s interval, 60s
#   .\run-load-test.ps1 -Preset medium # 20 clients, 500ms interval, 120s  
#   .\run-load-test.ps1 -Preset heavy  # 50 clients, 100ms interval, 300s
#   .\run-load-test.ps1 -Custom -Clients 30 -Interval 200 -Duration 120
# =============================================================================

param(
    [ValidateSet("light", "medium", "heavy")]
    [string]$Preset = "light",
    
    [switch]$Custom,
    [int]$Clients = 10,
    [int]$Interval = 1000,
    [int]$Duration = 60,
    [string]$MqttHost = "localhost",
    [int]$Port = 1883,
    [ValidateSet(0, 1, 2)]
    [int]$QoS = 1
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
Write-Host "         VerneMQ Load Test Runner                           " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Check if Node.js is installed
try {
    $nodeVersion = node --version
    Write-Host "[OK] Node.js installed: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Node.js is not installed. Please install Node.js first." -ForegroundColor Red
    Write-Host "Download from: https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Check if node_modules exists, if not run npm install
if (-not (Test-Path "node_modules")) {
    Write-Host "[INFO] Installing dependencies..." -ForegroundColor Yellow
    npm install
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to install dependencies" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Dependencies installed" -ForegroundColor Green
}

# Check if VerneMQ is running
Write-Host ""
Write-Host "[INFO] Checking VerneMQ status..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8888/health" -Method GET -TimeoutSec 5
    if ($response.status -eq "OK") {
        Write-Host "[OK] VerneMQ is running and healthy" -ForegroundColor Green
    }
} catch {
    Write-Host "[WARNING] Cannot reach VerneMQ health endpoint. Make sure VerneMQ is running." -ForegroundColor Yellow
    Write-Host "         Run 'docker-compose up -d' in the vernemq directory first." -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne "y") {
        exit 1
    }
}

# Build command based on preset or custom
Write-Host ""
if ($Custom) {
    Write-Host "[INFO] Running CUSTOM load test..." -ForegroundColor Cyan
    Write-Host "       Clients:  $Clients" -ForegroundColor White
    Write-Host "       Interval: ${Interval}ms" -ForegroundColor White
    Write-Host "       Duration: ${Duration}s" -ForegroundColor White
    Write-Host "       Host:     ${MqttHost}:${Port}" -ForegroundColor White
    Write-Host "       QoS:      $QoS" -ForegroundColor White
    Write-Host ""
    
    $cmd = "node worker.js --host $MqttHost --port $Port --clients $Clients --interval $Interval --duration $Duration --qos $QoS"
} else {
    Write-Host "[INFO] Running $($Preset.ToUpper()) preset load test..." -ForegroundColor Cyan
    
    switch ($Preset) {
        "light" {
            Write-Host "       5 clients, 2s interval, 60s duration" -ForegroundColor White
        }
        "medium" {
            Write-Host "       20 clients, 500ms interval, 120s duration" -ForegroundColor White
        }
        "heavy" {
            Write-Host "       50 clients, 100ms interval, 300s duration" -ForegroundColor White
        }
    }
    Write-Host ""
    
    $cmd = "npm run $Preset"
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Run the load test
Invoke-Expression $cmd

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "         Load Test Complete!                                " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Check the Monitoring dashboard at: http://localhost:5000" -ForegroundColor Yellow
Write-Host "Check Grafana metrics at: http://localhost:3030" -ForegroundColor Yellow
Write-Host ""
