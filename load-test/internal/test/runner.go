package test

import (
	"context"
	"math/rand"
	"sync"
	"time"

	"loadtest/internal/client"
	"loadtest/internal/config"
	"loadtest/internal/metrics"
	"go.uber.org/zap"
)

// Runner interface for test execution
type Runner interface {
	Run(ctx context.Context, cfg *config.Config, collector *metrics.Collector) (*Result, error)
}

// Result represents test execution result
type Result struct {
	TotalRequests int64
	TotalErrors   int64
	Duration      time.Duration
	StartTime     time.Time
	EndTime       time.Time
	Samples       []metrics.Sample
}

// LocalRunner runs tests locally
type LocalRunner struct {
	logger *zap.Logger
}

// NewLocalRunner creates a new local runner
func NewLocalRunner(cfg *config.Config, logger *zap.Logger) *LocalRunner {
	return &LocalRunner{logger: logger}
}

// Run executes the load test locally
func (r *LocalRunner) Run(ctx context.Context, cfg *config.Config, collector *metrics.Collector) (*Result, error) {
	r.logger.Info("starting load test",
		zap.Int("virtual_users", cfg.VirtualUsers),
		zap.Duration("duration", cfg.Duration),
		zap.Duration("ramp_up", cfg.RampUp))

	startTime := time.Now()
	collector.Start()

	// Create HTTP client
	httpClient := client.NewClient(cfg.Target, cfg.Auth)

	// Create virtual users
	var wg sync.WaitGroup

	// Calculate ramp up interval
	rampUpInterval := time.Duration(0)
	if cfg.RampUp > 0 && cfg.VirtualUsers > 0 {
		rampUpInterval = cfg.RampUp / time.Duration(cfg.VirtualUsers)
	}

	// Create request queue with weighted selection
	requestQueue := createWeightedRequestQueue(cfg.Requests)

	r.logger.Info("virtual users ready, starting test")

	// Start virtual users
	for i := 0; i < cfg.VirtualUsers; i++ {
		wg.Add(1)
		go func(userID int) {
			defer wg.Done()

			// Ramp up delay
			if rampUpInterval > 0 {
				time.Sleep(time.Duration(userID) * rampUpInterval)
			}

			r.runVirtualUser(ctx, userID, cfg, httpClient, collector, requestQueue, &wg)
		}(i)

		// Limit concurrent user startup
		if i%10 == 0 {
			time.Sleep(time.Millisecond * 100)
		}
	}

	// Wait for test duration or context cancellation
	testTicker := time.NewTicker(time.Second)
	defer testTicker.Stop()

	for {
		select {
		case <-ctx.Done():
			r.logger.Info("context cancelled, stopping test")
			goto done
		case <-testTicker.C:
			if time.Since(startTime) >= cfg.Duration {
				r.logger.Info("test duration completed")
				goto done
			}
		}
	}

done:
	r.logger.Info("waiting for virtual users to complete...")
	wg.Wait()

	collector.Stop()
	endTime := time.Now()

	// Collect results
	samples := collector.GetSamples()
	stats := collector.GetStatistics()

	result := &Result{
		TotalRequests: int64(stats.TotalRequests),
		TotalErrors:   int64(stats.ErrorCount),
		Duration:      endTime.Sub(startTime),
		StartTime:     startTime,
		EndTime:       endTime,
		Samples:       samples,
	}

	r.logger.Info("load test completed",
		zap.Int64("total_requests", result.TotalRequests),
		zap.Int64("total_errors", result.TotalErrors),
		zap.Duration("duration", result.Duration))

	return result, nil
}

// runVirtualUser runs a single virtual user
func (r *LocalRunner) runVirtualUser(
	ctx context.Context,
	userID int,
	cfg *config.Config,
	httpClient *client.Client,
	collector *metrics.Collector,
	requestQueue []config.RequestConfig,
	wg *sync.WaitGroup,
) {
	r.logger.Debug("virtual user started", zap.Int("user_id", userID))

	for {
		select {
		case <-ctx.Done():
			return
		default:
			// Get next request
			reqCfg := requestQueue[rand.Intn(len(requestQueue))]

			// Create request
			req := httpClient.NewRequest(reqCfg)

			// Execute request
			start := time.Now()
			resp, err := httpClient.Execute(ctx, req)
			latency := time.Since(start)

			// Record result
			if err != nil {
				collector.RecordError(req, err)
			} else {
				collector.Record(metrics.Sample{
					Latency:       latency,
					StatusCode:    resp.StatusCode,
					Success:       resp.StatusCode >= 200 && resp.StatusCode < 400,
					RequestName:   req.Name,
					BytesSent:     int64(len(req.Body)),
					BytesReceived: int64(len(resp.Body)),
				})
			}

			// Think time between requests
			if reqCfg.ThinkTime > 0 {
				select {
				case <-ctx.Done():
					return
				case <-time.After(reqCfg.ThinkTime):
				}
			}
		}
	}
}

// createWeightedRequestQueue creates a request queue with weighted selection
func createWeightedRequestQueue(requests []config.RequestConfig) []config.RequestConfig {
	var queue []config.RequestConfig

	for _, req := range requests {
		weight := req.Weight
		if weight <= 0 {
			weight = 1
		}
		for i := 0; i < weight; i++ {
			queue = append(queue, req)
		}
	}

	if len(queue) == 0 {
		// Default request
		queue = append(queue, config.RequestConfig{
			Name:     "default",
			Method:   "GET",
			Endpoint: "/",
		})
	}

	return queue
}

// StressRunner is optimized for stress testing
type StressRunner struct {
	*LocalRunner
}

// NewStressRunner creates a new stress test runner
func NewStressRunner(cfg *config.Config, logger *zap.Logger) *StressRunner {
	return &StressRunner{
		LocalRunner: NewLocalRunner(cfg, logger),
	}
}

// Run executes stress test
func (r *StressRunner) Run(ctx context.Context, cfg *config.Config, collector *metrics.Collector) (*Result, error) {
	// Increase concurrency for stress testing
	cfgCopy := *cfg
	cfgCopy.VirtualUsers = cfg.VirtualUsers * 2 // Double virtual users for stress

	return r.LocalRunner.Run(ctx, &cfgCopy, collector)
}

// EnduranceRunner is optimized for endurance testing
type EnduranceRunner struct {
	*LocalRunner
	reportInterval time.Duration
}

// NewEnduranceRunner creates a new endurance test runner
func NewEnduranceRunner(cfg *config.Config, logger *zap.Logger) *EnduranceRunner {
	return &EnduranceRunner{
		LocalRunner:    NewLocalRunner(cfg, logger),
		reportInterval: 30 * time.Second,
	}
}

// Run executes endurance test
func (r *EnduranceRunner) Run(ctx context.Context, cfg *config.Config, collector *metrics.Collector) (*Result, error) {
	r.logger.Info("starting endurance test",
		zap.Duration("duration", cfg.Duration),
		zap.Int("virtual_users", cfg.VirtualUsers))

	// Run with periodic progress reporting
	progressTicker := time.NewTicker(r.reportInterval)
	defer progressTicker.Stop()

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case <-progressTicker.C:
				stats := collector.GetStatistics()
				r.logger.Info("endurance test progress",
					zap.Duration("elapsed", time.Since(collector.GetStatistics().StartTime)),
					zap.Int64("requests", int64(stats.TotalRequests)),
					zap.Float64("error_rate", stats.ErrorRate))
			}
		}
	}()

	return r.LocalRunner.Run(ctx, cfg, collector)
}

// SpikeRunner is optimized for spike testing
type SpikeRunner struct {
	*LocalRunner
}

// NewSpikeRunner creates a new spike test runner
func NewSpikeRunner(cfg *config.Config, logger *zap.Logger) *SpikeRunner {
	return &SpikeRunner{
		LocalRunner: NewLocalRunner(cfg, logger),
	}
}

// Run executes spike test
func (r *SpikeRunner) Run(ctx context.Context, cfg *config.Config, collector *metrics.Collector) (*Result, error) {
	r.logger.Info("starting spike test",
		zap.Int("initial_users", cfg.VirtualUsers),
		zap.Int("spike_users", cfg.VirtualUsers*5),
		zap.Duration("spike_duration", cfg.Duration/3))

	// Execute spike pattern: ramp up -> spike -> ramp down
	// For now, just run as a basic test
	return r.LocalRunner.Run(ctx, cfg, collector)
}
