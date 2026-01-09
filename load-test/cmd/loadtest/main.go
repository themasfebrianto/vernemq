package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"loadtest/internal/coordinator"
	"loadtest/internal/test"
	"loadtest/internal/config"
	"loadtest/internal/reporter"
	"loadtest/internal/metrics"
	"github.com/spf13/cobra"
	"go.uber.org/zap"
)

var (
	version = "1.0.0"
	logger  *zap.Logger
)

func init() {
	var err error
	logger, err = zap.NewProduction()
	if err != nil {
		panic(err)
	}
	defer logger.Sync()
}

var rootCmd = &cobra.Command{
	Use:     "loadtest",
	Version: version,
	Short:   "High-performance distributed load testing tool",
	Long: `Loadtest is a high-performance, distributed load testing tool written in Go.
It supports various HTTP methods, concurrent request generation, distributed 
testing across multiple nodes, and comprehensive statistics reporting.`,
}

var runCmd = &cobra.Command{
	Use:   "run [config file]",
	Short: "Run a load test",
	Long: `Run a load test with the specified configuration file.
Supports various test types including stress testing, endurance testing, 
and spike testing through configuration.`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		cfg, err := config.Load(args[0])
		if err != nil {
			logger.Fatal("failed to load config", zap.Error(err))
		}

		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		// Handle graceful shutdown
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

		go func() {
			<-sigChan
			logger.Info("received shutdown signal, stopping test...")
			cancel()
		}()

		var testRunner test.Runner
		if cfg.Distributed.Enabled {
			testRunner = coordinator.NewDistributedCoordinator(cfg, logger)
		} else {
			testRunner = test.NewLocalRunner(cfg, logger)
		}

		metricsCollector := metrics.NewCollector()
		testReporter := reporter.NewReporter(cfg.Report.Output)

		startTime := time.Now()
		result, err := testRunner.Run(ctx, cfg, metricsCollector)
		duration := time.Since(startTime)

		if err != nil {
			logger.Fatal("test failed", zap.Error(err))
		}

		result.Duration = duration
		result.StartTime = startTime

		// Generate report
		reporterResult := &reporter.Result{
			Statistics:     metricsCollector.GetStatistics(),
			TotalRequests:  result.TotalRequests,
			TotalErrors:    result.TotalErrors,
			Duration:       result.Duration,
			StartTime:      result.StartTime,
			EndTime:        result.EndTime,
			Samples:        result.Samples,
		}
		if err := testReporter.Generate(reporterResult); err != nil {
			logger.Fatal("failed to generate report", zap.Error(err))
		}

		// Print summary to console
		testReporter.PrintSummary(reporterResult)

		logger.Info("test completed successfully",
			zap.Duration("duration", duration),
			zap.Int64("total_requests", result.TotalRequests),
			zap.Float64("requests_per_second", float64(result.TotalRequests)/duration.Seconds()))
	},
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start coordinator node for distributed testing",
	Long: `Start a coordinator node that manages distributed load testing.
Other nodes can connect to this coordinator to participate in the test.`,
	Run: func(cmd *cobra.Command, args []string) {
		cfg, err := config.LoadCoordinator()
		if err != nil {
			logger.Fatal("failed to load coordinator config", zap.Error(err))
		}

		coord := coordinator.NewCoordinator(cfg, logger)
		if err := coord.Start(); err != nil {
			logger.Fatal("failed to start coordinator", zap.Error(err))
		}

		// Wait for shutdown signal
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		coord.Stop()
		logger.Info("coordinator stopped")
	},
}

var nodeCmd = &cobra.Command{
	Use:   "node",
	Short: "Start a worker node for distributed testing",
	Long: `Start a worker node that connects to a coordinator and 
executes load test requests as directed.`,
	Run: func(cmd *cobra.Command, args []string) {
		cfg, err := config.LoadNode()
		if err != nil {
			logger.Fatal("failed to load node config", zap.Error(err))
		}

		node := coordinator.NewWorkerNode(cfg, logger)
		if err := node.Start(); err != nil {
			logger.Fatal("failed to start worker node", zap.Error(err))
		}

		// Wait for shutdown signal
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		node.Stop()
		logger.Info("worker node stopped")
	},
}

func main() {
	rootCmd.AddCommand(runCmd)
	rootCmd.AddCommand(serveCmd)
	rootCmd.AddCommand(nodeCmd)

	// Add common flags to run command
	runCmd.Flags().StringP("config", "c", "", "config file path")
	runCmd.Flags().Int("virtual-users", 0, "number of virtual users")
	runCmd.Flags().Duration("duration", 0, "test duration")
	runCmd.Flags().String("target", "", "target URL")
	runCmd.Flags().Duration("ramp-up", 0, "ramp-up duration")

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
