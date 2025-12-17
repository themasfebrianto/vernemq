#!/bin/bash

# Quick Verification Script for VerneMQ Single Container Setup
# This script performs a fast verification that the setup is working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[VERIFY]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

echo "========================================"
echo "VerneMQ Single Container Setup Verification"
echo "========================================"
echo

# Check if Docker is available
print_status "Checking Docker availability..."
if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker is not installed or not in PATH"
    exit 1
fi
print_success "Docker is available"

# Check if Docker Compose is available
print_status "Checking Docker Compose availability..."
if ! command -v docker-compose >/dev/null 2>&1; then
    print_error "Docker Compose is not installed or not in PATH"
    exit 1
fi
print_success "Docker Compose is available"

# Check if Docker daemon is running
print_status "Checking Docker daemon..."
if ! docker info >/dev/null 2>&1; then
    print_error "Docker daemon is not running"
    exit 1
fi
print_success "Docker daemon is running"

# Validate Docker Compose configuration
print_status "Validating Docker Compose configuration..."
if docker-compose -f docker-compose.prod.yml config >/dev/null 2>&1; then
    print_success "Docker Compose configuration is valid"
else
    print_error "Docker Compose configuration has errors"
    exit 1
fi

# Check required ports
print_status "Checking required ports availability..."
PORTS=(1883 8883 8080 8083 8888 8889)
for port in "${PORTS[@]}"; do
    if nc -z localhost "$port" 2>/dev/null; then
        print_warning "Port $port is already in use"
    else
        print_success "Port $port is available"
    fi
done

# Check if environment template exists
print_status "Checking environment template..."
if [ -f ".env.prod.template" ]; then
    print_success "Environment template exists"
else
    print_error "Environment template (.env.prod.template) is missing"
    exit 1
fi

# Check if Dockerfile exists
print_status "Checking Dockerfile..."
if [ -f "Dockerfile" ]; then
    print_success "Dockerfile exists"
else
    print_error "Dockerfile is missing"
    exit 1
fi

# Check test scripts
print_status "Checking test scripts..."
if [ -f "test-automation/test-single-container.sh" ]; then
    print_success "Linux test script exists"
else
    print_warning "Linux test script is missing"
fi

if [ -f "test-automation/test-single-container.bat" ]; then
    print_success "Windows test script exists"
else
    print_warning "Windows test script is missing"
fi

# Check if Kubernetes files are removed (should be deleted)
print_status "Checking for removed Kubernetes configurations..."
if [ -d "k8s" ]; then
    print_error "Kubernetes directory still exists"
    exit 1
else
    print_success "Kubernetes configurations properly removed"
fi

# Summary
echo
echo "========================================"
echo "Verification Summary"
echo "========================================"
print_success "All basic checks passed!"
echo
print_status "Next steps:"
echo "1. Copy environment template: cp .env.prod.template .env.prod"
echo "2. Edit .env.prod with your production settings"
echo "3. Update DISTRIBUTED_COOKIE with a secure value"
echo "4. Run: docker-compose -f docker-compose.prod.yml up -d"
echo "5. Test with: ./test-automation/test-single-container.sh verify"
echo
print_status "Available test commands:"
echo "- Linux/macOS: ./test-automation/test-single-container.sh [smoke|integration|performance|security|full]"
echo "- Windows: test-automation\\test-single-container.bat [smoke|integration|full]"
echo
print_success "VerneMQ single container setup is ready for deployment!"