package coordinator

import (
	"context"
	"fmt"
	"net"
	"sync"
	"time"

	"loadtest/internal/config"
	"loadtest/internal/metrics"
	"loadtest/internal/test"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// DistributedCoordinator coordinates distributed load testing
type DistributedCoordinator struct {
	cfg    *config.Config
	logger *zap.Logger
	nodes  map[string]*NodeInfo
	mu     sync.RWMutex
	result *test.Result
}

// NodeInfo holds information about a connected node
type NodeInfo struct {
	ID         string
	Addr       string
	Port       int
	Connected  time.Time
	LastActive time.Time
	Tags       map[string]string
	Stats      *NodeStats
}

// NodeStats holds statistics from a node
type NodeStats struct {
	TotalRequests int64
	TotalErrors   int64
	Throughput    float64
}

// NewDistributedCoordinator creates a new distributed coordinator
func NewDistributedCoordinator(cfg *config.Config, logger *zap.Logger) *DistributedCoordinator {
	return &DistributedCoordinator{
		cfg:    cfg,
		logger: logger,
		nodes:  make(map[string]*NodeInfo),
	}
}

// Run executes the distributed load test
func (c *DistributedCoordinator) Run(ctx context.Context, cfg *config.Config, collector *metrics.Collector) (*test.Result, error) {
	c.logger.Info("starting distributed load test",
		zap.Strings("nodes", cfg.Distributed.Nodes),
		zap.Int("virtual_users", cfg.VirtualUsers))

	// Start coordinator server
	coord := NewCoordinator(cfg, c.logger)
	if err := coord.Start(); err != nil {
		return nil, fmt.Errorf("failed to start coordinator: %w", err)
	}
	defer coord.Stop()

	// Wait for nodes to connect
	c.logger.Info("waiting for nodes to connect...")
	if err := c.waitForNodes(ctx, len(cfg.Distributed.Nodes)); err != nil {
		return nil, err
	}

	// Distribute work to nodes
	c.logger.Info("distributing work to nodes")
	c.distributeWork()

	// Collect results from nodes
	c.logger.Info("collecting results from nodes")
	results := c.collectResults(ctx)

	// Aggregate results
	aggregated := c.aggregateResults(results)

	return aggregated, nil
}

// waitForNodes waits for nodes to connect
func (c *DistributedCoordinator) waitForNodes(ctx context.Context, expectedNodes int) error {
	timeout := time.After(2 * time.Minute)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-timeout:
			c.mu.RLock()
			connected := len(c.nodes)
			c.mu.RUnlock()
			if connected < expectedNodes {
				return fmt.Errorf("timeout waiting for nodes: got %d, expected %d", connected, expectedNodes)
			}
			return nil
		case <-ticker.C:
			c.mu.RLock()
			connected := len(c.nodes)
			c.mu.RUnlock()
			if connected >= expectedNodes {
				c.logger.Info("all nodes connected", zap.Int("nodes", connected))
				return nil
			}
			c.logger.Debug("waiting for nodes", zap.Int("connected", connected), zap.Int("expected", expectedNodes))
		}
	}
}

// distributeWork distributes test configuration to nodes
func (c *DistributedCoordinator) distributeWork() {
	c.mu.RLock()
	defer c.mu.RUnlock()

	for id, node := range c.nodes {
		// Calculate workload per node
		usersPerNode := c.cfg.VirtualUsers / len(c.nodes)
		if usersPerNode == 0 {
			usersPerNode = 1
		}

		c.logger.Info("distributing work to node",
			zap.String("node_id", id),
			zap.Int("virtual_users", usersPerNode))

		// In a real implementation, this would send the config to the node
		// For now, we just log it
		_ = node
	}
}

// collectResults collects results from all nodes
func (c *DistributedCoordinator) collectResults(ctx context.Context) []*test.Result {
	c.mu.RLock()
	nodeCount := len(c.nodes)
	c.mu.RUnlock()

	results := make([]*test.Result, 0, nodeCount)

	// In a real implementation, this would receive results from nodes
	// For now, return empty results
	return results
}

// aggregateResults aggregates results from multiple nodes
func (c *DistributedCoordinator) aggregateResults(results []*test.Result) *test.Result {
	totalRequests := int64(0)
	totalErrors := int64(0)

	for _, r := range results {
		totalRequests += r.TotalRequests
		totalErrors += r.TotalErrors
	}

	return &test.Result{
		TotalRequests: totalRequests,
		TotalErrors:   totalErrors,
	}
}

// Coordinator represents a coordinator server
type Coordinator struct {
	cfg      *config.Config
	logger   *zap.Logger
	listener net.Listener
	stopChan chan struct{}
}

// NewCoordinator creates a new coordinator
func NewCoordinator(cfg *config.Config, logger *zap.Logger) *Coordinator {
	return &Coordinator{
		cfg:      cfg,
		logger:   logger,
		stopChan: make(chan struct{}),
	}
}

// Start starts the coordinator server
func (c *Coordinator) Start() error {
	addr := fmt.Sprintf("%s:%d", c.cfg.Distributed.BindAddr, c.cfg.Distributed.BindPort)

	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %w", addr, err)
	}

	c.listener = listener
	c.logger.Info("coordinator started", zap.String("address", addr))

	// Start accepting connections
	go c.acceptConnections()

	return nil
}

// acceptConnections accepts incoming node connections
func (c *Coordinator) acceptConnections() {
	for {
		select {
		case <-c.stopChan:
			return
		default:
			conn, err := c.listener.Accept()
			if err != nil {
				c.logger.Warn("failed to accept connection", zap.Error(err))
				continue
			}

			c.logger.Info("new node connected", zap.String("remote_addr", conn.RemoteAddr().String()))
			go c.handleConnection(conn)
		}
	}
}

// handleConnection handles a node connection
func (c *Coordinator) handleConnection(conn net.Conn) {
	defer conn.Close()

	// Read node registration
	// In a real implementation, this would handle node registration protocol
	_ = conn

	c.logger.Debug("handling node connection")
}

// Stop stops the coordinator
func (c *Coordinator) Stop() {
	close(c.stopChan)
	if c.listener != nil {
		c.listener.Close()
	}
	c.logger.Info("coordinator stopped")
}

// WorkerNode represents a worker node
type WorkerNode struct {
	cfg      *config.Config
	logger   *zap.Logger
	client   *CoordinatorClient
	stopChan chan struct{}
}

// CoordinatorClient is a client for connecting to coordinator
type CoordinatorClient struct {
	coordinatorAddr string
	nodeID          string
	logger          *zap.Logger
}

// NewWorkerNode creates a new worker node
func NewWorkerNode(cfg *config.Config, logger *zap.Logger) *WorkerNode {
	return &WorkerNode{
		cfg:      cfg,
		logger:   logger,
		stopChan: make(chan struct{}),
	}
}

// Start starts the worker node
func (n *WorkerNode) Start() error {
	n.logger.Info("starting worker node",
		zap.String("coordinator", n.cfg.Distributed.Coordinator),
		zap.String("node_id", n.cfg.Distributed.NodeID))

	// Connect to coordinator
	client := NewCoordinatorClient(n.cfg.Distributed.Coordinator, n.cfg.Distributed.NodeID, n.logger)
	if err := client.Connect(); err != nil {
		return fmt.Errorf("failed to connect to coordinator: %w", err)
	}

	n.client = client

	// Start receiving work
	go n.receiveWork()

	return nil
}

// receiveWork receives work from coordinator
func (n *WorkerNode) receiveWork() {
	for {
		select {
		case <-n.stopChan:
			return
		default:
			// In a real implementation, this would receive and execute work
			time.Sleep(time.Second)
		}
	}
}

// Stop stops the worker node
func (n *WorkerNode) Stop() {
	close(n.stopChan)
	if n.client != nil {
		n.client.Disconnect()
	}
	n.logger.Info("worker node stopped")
}

// NewCoordinatorClient creates a new coordinator client
func NewCoordinatorClient(coordinatorAddr, nodeID string, logger *zap.Logger) *CoordinatorClient {
	return &CoordinatorClient{
		coordinatorAddr: coordinatorAddr,
		nodeID:          nodeID,
		logger:          logger,
	}
}

// Connect connects to the coordinator
func (c *CoordinatorClient) Connect() error {
	c.logger.Info("connecting to coordinator", zap.String("address", c.coordinatorAddr))
	// In a real implementation, this would establish a connection
	return nil
}

// Disconnect disconnects from the coordinator
func (c *CoordinatorClient) Disconnect() {
	c.logger.Info("disconnecting from coordinator")
}

// SendResults sends test results to coordinator
func (c *CoordinatorClient) SendResults(result *test.Result) error {
	c.logger.Debug("sending results to coordinator")
	// In a real implementation, this would send results
	return nil
}

// GenerateNodeID generates a unique node ID
func GenerateNodeID() string {
	return fmt.Sprintf("node-%s", uuid.New().String()[:8])
}
