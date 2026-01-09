# =============================================================================
# Go Load Test Runner
# =============================================================================
# Run this script to execute HTTP load tests using the Go-based load tester
# 
# Usage:
#   .\run-load-test.ps1                    # Run with default (basic) preset
#   .\run-load-test.ps1 -Preset basic      # Basic load test (50 VUs, 60s)
#   .\run-load-test.ps1 -Preset stress     # Stress test (push to breaking point)
#   .\run-load-test.ps1 -Preset endurance  # Endurance test (long duration)
#   .\run-load-test.ps1 -Preset spike      # Spike test (sudden traffic surge)
#   .\run-load-test.ps1 -Custom -VUs 100 -Duration 120 -Config .\configs\basic.yaml
# =============================================================================

param(
    [ValidateSet("basic", "stress", "endurance", "spike", "distributed")]
    [string]$Preset = "basic",
    
    [switch]$Custom,
    [int]$VUs = 50,
    [int]$Duration = 60,
    [string]$Config = "",
    [string]$Target = "http://localhost:8080",
    [int]$RampUp = 10
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
Write-Host "         Go Load Test Runner                               " -ForegroundColor Cyan
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
    Write-Host "[ERROR] Go is not installed. Please install Go first." -ForegroundColor Red
    Write-Host "Download from: https://go.dev/dl/" -ForegroundColor Yellow
    exit 1
}

# Build the loadtest binary if it doesn't exist
$loadtestPath = Join-Path $scriptDir "loadtest.exe"
if (-not (Test-Path $loadtestPath)) {
    Write-Host "[INFO] Building loadtest binary..." -ForegroundColor Yellow
    go build -o loadtest.exe ./cmd/loadtest
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to build loadtest binary" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Loadtest binary built successfully" -ForegroundColor Green
} else {
    Write-Host "[OK] Loadtest binary found" -ForegroundColor Green
}

# Build command based on preset or custom
Write-Host ""
if ($Custom) {
    Write-Host "[INFO] Running CUSTOM load test..." -ForegroundColor Cyan
    Write-Host "       Virtual Users: $VUs" -ForegroundColor White
    Write-Host "       Duration:      ${Duration}s" -ForegroundColor White
    Write-Host "       Ramp Up:       ${RampUp}s" -ForegroundColor White
    Write-Host "       Target:        $Target" -ForegroundColor White
    Write-Host ""
    
    if ($Config -and (Test-Path $Config)) {
        $cmd = ".\loadtest.exe run `"$Config`""
    } else {
        $cmd = ".\loadtest.exe run configs\basic.yaml --virtual-users=$VUs --duration=${Duration}s --ramp-up=${RampUp}s --target=$Target"
    }
} else {
    Write-Host "[INFO] Running $($Preset.ToUpper()) preset load test..." -ForegroundColor Cyan
    
    switch ($Preset) {
        "basic" {
            Write-Host "       50 virtual users, 60s duration, 10s ramp-up" -ForegroundColor White
            $configFile = "configs\basic.yaml"
        }
        "stress" {
            Write-Host "       Stress test configuration" -ForegroundColor White
            $configFile = "configs\stress-test.yaml"
        }
        "endurance" {
            Write-Host "       Endurance test configuration" -ForegroundColor White
            $configFile = "configs\endurance-test.yaml"
        }
        "spike" {
            Write-Host "       Spike test configuration" -ForegroundColor White
            $configFile = "configs\spike-test.yaml"
        }
        "distributed" {
            Write-Host "       Distributed test configuration" -ForegroundColor White
            $configFile = "configs\distributed.yaml"
        }
    }
    Write-Host ""
    
    $cmd = ".\loadtest.exe run $configFile"
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Run the load test
Invoke-Expression $cmd

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "         Load Test Complete!                               " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Results have been saved to the results directory." -ForegroundColor Yellow
Write-Host ""
