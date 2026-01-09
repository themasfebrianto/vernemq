package metrics

import (
	"fmt"
	"time"
)

// Statistics holds all collected statistics
type Statistics struct {
	// Request metrics
	TotalRequests   int
	SuccessRequests int
	ErrorCount      int
	ErrorRate       float64

	// Latency metrics (in microseconds)
	MinLatency  float64
	MaxLatency  float64
	AvgLatency  float64
	StdDev      float64
	Median      float64
	P90         float64
	P95         float64
	P99         float64
	P99_9       float64

	// Throughput metrics
	Throughput    float64 // requests per second
	BytesSent     int64
	BytesReceived int64

	// Status code distribution
	StatusCodes map[int]int

	// Time information
	StartTime  time.Time
	Duration   time.Duration

	// Request breakdown by name
	RequestStats map[string]*RequestStatistics

	// RPS history
	RPSHistory []RPSDataPoint
}

// RequestStatistics holds statistics for a specific request
type RequestStatistics struct {
	Name          string
	Count         int
	SuccessCount  int
	ErrorCount    int
	ErrorRate     float64
	MinLatency    float64
	MaxLatency    float64
	AvgLatency    float64
	StdDev        float64
	Percentiles   map[float64]float64
	BytesSent     int64
	BytesReceived int64
}

// RPSDataPoint represents requests per second at a point in time
type RPSDataPoint struct {
	Timestamp time.Duration
	Requests  int
}

// ToLatencyMs converts microseconds to milliseconds
func (s *Statistics) ToLatencyMs(us float64) float64 {
	return us / 1000.0
}

// LatencySummary returns a human-readable latency summary
func (s *Statistics) LatencySummary() string {
	return fmt.Sprintf("Min: %.2fms | Avg: %.2fms | P50: %.2fms | P90: %.2fms | P95: %.2fms | P99: %.2fms | Max: %.2fms",
		s.ToLatencyMs(s.MinLatency),
		s.ToLatencyMs(s.AvgLatency),
		s.ToLatencyMs(s.Median),
		s.ToLatencyMs(s.P90),
		s.ToLatencyMs(s.P95),
		s.ToLatencyMs(s.P99),
		s.ToLatencyMs(s.MaxLatency))
}

// ThroughputSummary returns a human-readable throughput summary
func (s *Statistics) ThroughputSummary() string {
	return fmt.Sprintf("%.2f req/s | %.2f KB/s sent | %.2f KB/s received",
		s.Throughput,
		float64(s.BytesSent)/1024.0,
		float64(s.BytesReceived)/1024.0)
}

// ErrorSummary returns a human-readable error summary
func (s *Statistics) ErrorSummary() string {
	return fmt.Sprintf("%d errors (%.2f%%)", s.ErrorCount, s.ErrorRate)
}

// Merge merges another statistics into this one
func (s *Statistics) Merge(other *Statistics) {
	s.TotalRequests += other.TotalRequests
	s.SuccessRequests += other.SuccessRequests
	s.ErrorCount += other.ErrorCount
	s.BytesSent += other.BytesSent
	s.BytesReceived += other.BytesReceived

	// Calculate weighted average for latencies
	totalCount := s.TotalRequests + other.TotalRequests
	if totalCount > 0 {
		s.AvgLatency = (s.AvgLatency*float64(s.TotalRequests) + other.AvgLatency*float64(other.TotalRequests)) / float64(totalCount)
	}

	s.ErrorRate = float64(s.ErrorCount) / float64(s.TotalRequests) * 100
	s.Throughput = float64(s.TotalRequests) / s.Duration.Seconds()

	// Merge status codes
	for code, count := range other.StatusCodes {
		s.StatusCodes[code] += count
	}
}

// CalculateRequestStats calculates statistics per request type
func (s *Statistics) CalculateRequestStats(samples []Sample) {
	s.RequestStats = make(map[string]*RequestStatistics)

	// Group samples by request name
	groups := make(map[string][]Sample)
	for _, sample := range samples {
		groups[sample.RequestName] = append(groups[sample.RequestName], sample)
	}

	// Calculate stats for each group
	for name, group := range groups {
		stats := &RequestStatistics{
			Name:        name,
			Count:       len(group),
			Percentiles: make(map[float64]float64),
		}

		var latencies []float64
		for _, sample := range group {
			latencies = append(latencies, float64(sample.Latency.Microseconds()))
			stats.BytesSent += sample.BytesSent
			stats.BytesReceived += sample.BytesReceived

			if sample.Success {
				stats.SuccessCount++
			} else {
				stats.ErrorCount++
			}
		}

		if len(latencies) > 0 {
			stats.MinLatency = minFloat(latencies)
			stats.MaxLatency = maxFloat(latencies)
			stats.AvgLatency = avgFloat(latencies)
			stats.StdDev = stdDevFloat(latencies, stats.AvgLatency)

			// Calculate percentiles
			stats.Percentiles[50] = percentile(latencies, 50)
			stats.Percentiles[90] = percentile(latencies, 90)
			stats.Percentiles[95] = percentile(latencies, 95)
			stats.Percentiles[99] = percentile(latencies, 99)
		}

		if stats.Count > 0 {
			stats.ErrorRate = float64(stats.ErrorCount) / float64(stats.Count) * 100
		}

		s.RequestStats[name] = stats
	}
}
