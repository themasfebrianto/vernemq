package metrics

import (
	"math"
	"sync"
	"time"

	"loadtest/internal/client"
)

// Sample represents a single response sample
type Sample struct {
	Timestamp    time.Duration
	Latency      time.Duration
	StatusCode   int
	Success      bool
	RequestName  string
	ErrorMsg     string
	BytesSent    int64
	BytesReceived int64
}

// Collector collects and aggregates metrics
type Collector struct {
	mu          sync.RWMutex
	samples     []Sample
	startTime   time.Time
	buckets     map[int64][]Sample // time bucket -> samples
	windowSize  time.Duration
	bucketSize  time.Duration
}

// NewCollector creates a new metrics collector
func NewCollector() *Collector {
	return &Collector{
		samples:    make([]Sample, 0),
		buckets:    make(map[int64][]Sample),
		windowSize: 5 * time.Minute,
		bucketSize: time.Second,
	}
}

// Start starts the collector
func (c *Collector) Start() {
	c.startTime = time.Now()
}

// Stop stops the collector
func (c *Collector) Stop() {
	// Nothing to do
}

// Record records a response sample
func (c *Collector) Record(sample Sample) {
	c.mu.Lock()
	defer c.mu.Unlock()

	sample.Timestamp = time.Since(c.startTime)
	c.samples = append(c.samples, sample)

	// Add to time bucket
	bucket := int64(sample.Timestamp.Seconds())
	c.buckets[bucket] = append(c.buckets[bucket], sample)
}

// RecordResponse records a response
func (c *Collector) RecordResponse(req *client.Request, resp *client.Response) {
	sample := Sample{
		Latency:      resp.Latency,
		StatusCode:   resp.StatusCode,
		Success:      resp.StatusCode >= 200 && resp.StatusCode < 400,
		RequestName:  req.Name,
		BytesSent:    int64(len(req.Body)),
		BytesReceived: int64(len(resp.Body)),
	}

	if resp.Error != nil {
		sample.Success = false
		sample.ErrorMsg = resp.Error.Error()
	}

	c.Record(sample)
}

// RecordError records an error
func (c *Collector) RecordError(req *client.Request, err error) {
	sample := Sample{
		Latency:     0,
		StatusCode:  0,
		Success:     false,
		RequestName: req.Name,
		ErrorMsg:    err.Error(),
	}

	c.Record(sample)
}

// GetStatistics returns aggregated statistics
func (c *Collector) GetStatistics() *Statistics {
	c.mu.RLock()
	defer c.mu.RUnlock()

	stats := &Statistics{
		TotalRequests: len(c.samples),
		StartTime:     c.startTime,
	}

	// Calculate latencies
	var latencies []float64
	var errors []Sample

	for _, s := range c.samples {
		latencies = append(latencies, float64(s.Latency.Microseconds()))

		if !s.Success {
			errors = append(errors, s)
		}

		stats.BytesSent += s.BytesSent
		stats.BytesReceived += s.BytesReceived
	}

	if len(latencies) > 0 {
		stats.MinLatency = minFloat(latencies)
		stats.MaxLatency = maxFloat(latencies)
		stats.AvgLatency = avgFloat(latencies)
		stats.StdDev = stdDevFloat(latencies, stats.AvgLatency)
		stats.Median = percentile(latencies, 50)
		stats.P90 = percentile(latencies, 90)
		stats.P95 = percentile(latencies, 95)
		stats.P99 = percentile(latencies, 99)
		stats.P99_9 = percentile(latencies, 99.9)
	}

	stats.ErrorCount = len(errors)
	if stats.TotalRequests > 0 {
		stats.ErrorRate = float64(stats.ErrorCount) / float64(stats.TotalRequests) * 100
	}

	// Calculate status code distribution
	stats.StatusCodes = make(map[int]int)
	for _, s := range c.samples {
		stats.StatusCodes[s.StatusCode]++
	}

	// Calculate throughput per second
	duration := time.Since(c.startTime)
	if duration > 0 {
		stats.Throughput = float64(stats.TotalRequests) / duration.Seconds()
	}

	// Calculate requests per second over time
	stats.RPSHistory = c.calculateRPSHistory()

	return stats
}

// GetSamples returns all samples
func (c *Collector) GetSamples() []Sample {
	c.mu.RLock()
	defer c.mu.RUnlock()

	result := make([]Sample, len(c.samples))
	copy(result, c.samples)
	return result
}

// GetTimeWindow returns samples within the time window
func (c *Collector) GetTimeWindow(window time.Duration) []Sample {
	c.mu.RLock()
	defer c.mu.RUnlock()

	cutoff := time.Since(c.startTime) - window
	var result []Sample

	for _, s := range c.samples {
		if s.Timestamp >= cutoff {
			result = append(result, s)
		}
	}

	return result
}

// Reset resets the collector
func (c *Collector) Reset() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.samples = make([]Sample, 0)
	c.buckets = make(map[int64][]Sample)
	c.startTime = time.Now()
}

// calculateRPSHistory calculates requests per second over time
func (c *Collector) calculateRPSHistory() []RPSDataPoint {
	c.mu.RLock()
	defer c.mu.RUnlock()

	var result []RPSDataPoint

	// Group by second
	seconds := make(map[int64]int)
	for _, s := range c.samples {
		sec := int64(s.Timestamp.Seconds())
		seconds[sec]++
	}

	// Convert to data points
	var minSec, maxSec int64
	for sec := range seconds {
		if minSec == 0 || sec < minSec {
			minSec = sec
		}
		if sec > maxSec {
			maxSec = sec
		}
	}

	for sec := minSec; sec <= maxSec; sec++ {
		result = append(result, RPSDataPoint{
			Timestamp: time.Duration(sec) * time.Second,
			Requests:  seconds[sec],
		})
	}

	return result
}

// Helper functions

func minFloat(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	min := vals[0]
	for _, v := range vals[1:] {
		if v < min {
			min = v
		}
	}
	return min
}

func maxFloat(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	max := vals[0]
	for _, v := range vals[1:] {
		if v > max {
			max = v
		}
	}
	return max
}

func avgFloat(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range vals {
		sum += v
	}
	return sum / float64(len(vals))
}

func stdDevFloat(vals []float64, mean float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range vals {
		sum += (v - mean) * (v - mean)
	}
	return math.Sqrt(sum / float64(len(vals)))
}

func percentile(vals []float64, p float64) float64 {
	if len(vals) == 0 {
		return 0
	}

	// Sort values
	sorted := make([]float64, len(vals))
	copy(sorted, vals)
	for i := 0; i < len(sorted)/2; i++ {
		sorted[i], sorted[len(sorted)-1-i] = sorted[len(sorted)-1-i], sorted[i]
	}

	// Calculate percentile
	index := int(float64(len(sorted)) * p / 100)
	if index >= len(sorted) {
		index = len(sorted) - 1
	}
	if index < 0 {
		index = 0
	}

	return sorted[index]
}
