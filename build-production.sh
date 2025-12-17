#!/bin/bash

# VerneMQ Production Build Script
# This script builds and deploys VerneMQ for production use

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Docker is installed
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command_exists docker-compose; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Git is installed
    if ! command_exists git; then
        print_warning "Git is not installed. Build reference will be 'local'."
        VCS_REF="local"
    else
        VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
    fi
    
    print_success "Prerequisites check passed."
}

# Function to setup environment
setup_environment() {
    print_status "Setting up environment..."
    
    # Check if .env.prod file exists
    if [ ! -f ".env.prod" ]; then
        print_warning ".env.prod file not found. Creating from template..."
        cp .env.prod.template .env.prod
        print_warning "Please edit .env.prod file with your production settings before proceeding."
        print_warning "Especially update DISTRIBUTED_COOKIE with a secure value."
        
        read -p "Press Enter to continue after editing .env.prod file..."
    fi
    
    # Source the environment file
    if [ -f ".env.prod" ]; then
        export $(cat .env.prod | grep -v '^#' | xargs)
        print_success "Environment loaded from .env.prod"
    else
        print_warning "No .env.prod file found. Using default values."
    fi
    
    # Validate required environment variables
    if [ "$DISTRIBUTED_COOKIE" = "CHANGE_THIS_SECRET_COOKIE_VALUE" ]; then
        print_error "You must change DISTRIBUTED_COOKIE in .env.prod file for security!"
        exit 1
    fi
}

# Function to build the Docker image
build_image() {
    print_status "Building VerneMQ Docker image..."
    
    # Set build arguments
    BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Build the image
    docker build \
        --build-arg BUILD_DATE=$BUILD_DATE \
        --build-arg VCS_REF=$VCS_REF \
        -t vernemq:latest \
        -f Dockerfile .
    
    if [ $? -eq 0 ]; then
        print_success "Docker image built successfully."
    else
        print_error "Failed to build Docker image."
        exit 1
    fi
}

# Function to create required directories
create_directories() {
    print_status "Creating required directories..."
    
    # Create directory structure for volumes
    mkdir -p ssl
    mkdir -p nginx/ssl
    mkdir -p nginx/conf.d
    mkdir -p sql
    mkdir -p logs
    
    print_success "Directory structure created."
}

# Function to generate SSL certificates (optional)
generate_ssl_certificates() {
    if [ "$GENERATE_SSL" = "true" ]; then
        print_status "Generating SSL certificates for development/testing..."
        
        # Generate self-signed certificate for testing
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ssl/server.key \
            -out ssl/server.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
            2>/dev/null || {
            print_warning "OpenSSL not available. Skipping SSL certificate generation."
            print_warning "If you need SSL, manually place your certificates in ./ssl/ directory"
        }
        
        print_success "SSL certificates generated in ./ssl/ directory."
    fi
}

# Function to run tests (if available)
run_tests() {
    print_status "Running tests..."
    
    # Check if tests directory exists
    if [ -d "test" ] || [ -d "apps" ]; then
        print_status "Building and testing..."
        # Add your test commands here
        # For now, just check if the image can be run
        docker run --rm vernemq:latest /opt/vernemq/bin/vmq-admin cluster status || {
            print_warning "Could not run initial test, but continuing..."
        }
    else
        print_status "No tests found, skipping..."
    fi
}

# Function to deploy
deploy() {
    print_status "Deploying VerneMQ production stack..."
    
    # Deploy with Docker Compose
    docker-compose -f docker-compose.prod.yml up -d
    
    if [ $? -eq 0 ]; then
        print_success "VerneMQ deployed successfully!"
        print_status "Waiting for services to be ready..."
        sleep 10
        
        # Check service health
        docker-compose -f docker-compose.prod.yml ps
        
        print_status "VerneMQ is now running on:"
        print_status "  - MQTT TCP: localhost:1883"
        print_status "  - MQTT WebSocket: localhost:8080"
        print_status "  - Management: localhost:8888"
        
        if [ "$GENERATE_SSL" = "true" ]; then
            print_status "  - MQTT SSL: localhost:8883"
            print_status "  - MQTT WebSocket SSL: localhost:8083"
        fi
        
        print_success "Check logs with: docker-compose -f docker-compose.prod.yml logs -f vernemq"
        
    else
        print_error "Deployment failed."
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  build     Build the Docker image only"
    echo "  deploy    Deploy the production stack"
    echo "  full      Build and deploy (default)"
    echo "  test      Run tests"
    echo "  clean     Clean up containers and images"
    echo "  help      Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  GENERATE_SSL=true   Generate self-signed SSL certificates"
    echo ""
    echo "Files:"
    echo "  .env.prod           Production environment configuration"
    echo "  vernemq-production.conf.template  Configuration template"
    echo ""
}

# Function to clean up
clean_up() {
    print_status "Cleaning up containers and images..."
    
    # Stop and remove containers
    docker-compose -f docker-compose.prod.yml down
    
    # Remove images
    docker rmi vernemq:latest 2>/dev/null || true
    
    # Clean up unused volumes
    docker volume prune -f
    
    # Clean up unused networks
    docker network prune -f
    
    print_success "Cleanup completed."
}

# Main execution
main() {
    local action="${1:-full}"
    
    case "$action" in
        build)
            check_prerequisites
            setup_environment
            create_directories
            build_image
            ;;
        deploy)
            check_prerequisites
            setup_environment
            deploy
            ;;
        full)
            check_prerequisites
            setup_environment
            create_directories
            generate_ssl_certificates
            build_image
            run_tests
            deploy
            ;;
        test)
            check_prerequisites
            build_image
            run_tests
            ;;
        clean)
            clean_up
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown action: $action"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"