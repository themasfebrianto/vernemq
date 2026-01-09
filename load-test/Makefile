.PHONY: build clean test run-basic run-stress run-endurance run-spike run-distributed

# Build the loadtest binary
build:
	go build -o loadtest ./cmd/loadtest

# Clean build artifacts
clean:
	rm -f loadtest
	rm -rf results/

# Run all tests
test:
	go test ./... -v

# Run basic load test
run-basic: build
	./loadtest run configs/basic.yaml

# Run stress test
run-stress: build
	./loadtest run configs/stress-test.yaml

# Run endurance test
run-endurance: build
	./loadtest run configs/endurance-test.yaml

# Run spike test
run-spike: build
	./loadtest run configs/spike-test.yaml

# Run distributed test
run-distributed: build
	./loadtest run configs/distributed.yaml

# Start coordinator for distributed testing
serve-coordinator: build
	./loadtest serve --config configs/coordinator.yaml

# Start worker node for distributed testing
start-node: build
	./loadtest node --config configs/node.yaml

# Install dependencies
deps:
	go mod download

# Update dependencies
update-deps:
	go get -u ./...
	go mod tidy

# Build with race detector
build-race:
	go build -race -o loadtest-race ./cmd/loadtest

# Format code
fmt:
	go fmt ./...

# Lint code
lint:
	golangci-lint run ./...

# Generate coverage report
coverage:
	go test ./... -coverprofile=coverage.out
	go tool cover -html=coverage.out -o coverage.html

# Help
help:
	@echo "Available targets:"
	@echo "  build          - Build the loadtest binary"
	@echo "  clean          - Clean build artifacts"
	@echo "  test           - Run all tests"
	@echo "  run-basic      - Run basic load test"
	@echo "  run-stress     - Run stress test"
	@echo "  run-endurance  - Run endurance test"
	@echo "  run-spike      - Run spike test"
	@echo "  run-distributed- Run distributed test"
	@echo "  serve-coordinator - Start coordinator for distributed testing"
	@echo "  start-node     - Start worker node for distributed testing"
	@echo "  deps           - Install dependencies"
	@echo "  update-deps    - Update dependencies"
	@echo "  build-race     - Build with race detector"
	@echo "  fmt            - Format code"
	@echo "  lint           - Lint code"
	@echo "  coverage       - Generate coverage report"
	@echo "  help           - Show this help message"
