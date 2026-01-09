package reporter

import (
	"encoding/json"
	"fmt"
	"os"
	"text/tabwriter"
	"time"

	"loadtest/internal/metrics"
)

// Reporter generates load test reports
type Reporter interface {
	Generate(result *Result) error
	PrintSummary(result *Result)
}

// Result represents the complete test result
type Result struct {
	Statistics     *metrics.Statistics
	TotalRequests  int64
	TotalErrors    int64
	Duration       time.Duration
	StartTime      time.Time
	EndTime        time.Time
	NodeID         string
	Distributed    bool
	Samples        []metrics.Sample
}

// ConsoleReporter prints results to console
type ConsoleReporter struct{}

// NewConsoleReporter creates a new console reporter
func NewConsoleReporter() *ConsoleReporter {
	return &ConsoleReporter{}
}

// Generate generates a console report
func (r *ConsoleReporter) Generate(result *Result) error {
	r.PrintSummary(result)
	return nil
}

// PrintSummary prints the summary to console
func (r *ConsoleReporter) PrintSummary(result *Result) {
	stats := result.Statistics

	fmt.Println("\n========================================")
	fmt.Println("         LOAD TEST RESULTS")
	fmt.Println("========================================")
	fmt.Println()

	// Test information
	fmt.Println("Test Information:")
	fmt.Printf("  Start Time:      %s\n", result.StartTime.Format(time.RFC3339))
	fmt.Printf("  Duration:        %v\n", result.Duration)
	fmt.Printf("  Total Requests:  %d\n", result.TotalRequests)
	fmt.Printf("  Virtual Users:   %d\n", stats.TotalRequests/int(int(result.Duration.Seconds())))
	fmt.Println()

	// Performance summary
	fmt.Println("Performance Summary:")
	fmt.Printf("  Throughput:      %.2f req/s\n", stats.Throughput)
	fmt.Printf("  Total Bytes:     %.2f KB sent, %.2f KB received\n",
		float64(stats.BytesSent)/1024, float64(stats.BytesReceived)/1024)
	fmt.Println()

	// Latency summary
	fmt.Println("Latency Distribution (in milliseconds):")
	fmt.Printf("  Min:            %.2f ms\n", stats.ToLatencyMs(stats.MinLatency))
	fmt.Printf("  Average:        %.2f ms\n", stats.ToLatencyMs(stats.AvgLatency))
	fmt.Printf("  Std Dev:        %.2f ms\n", stats.ToLatencyMs(stats.StdDev))
	fmt.Printf("  Median (P50):   %.2f ms\n", stats.ToLatencyMs(stats.Median))
	fmt.Printf("  P90:            %.2f ms\n", stats.ToLatencyMs(stats.P90))
	fmt.Printf("  P95:            %.2f ms\n", stats.ToLatencyMs(stats.P95))
	fmt.Printf("  P99:            %.2f ms\n", stats.ToLatencyMs(stats.P99))
	fmt.Printf("  P99.9:          %.2f ms\n", stats.ToLatencyMs(stats.P99_9))
	fmt.Printf("  Max:            %.2f ms\n", stats.ToLatencyMs(stats.MaxLatency))
	fmt.Println()

	// Error summary
	fmt.Println("Error Summary:")
	fmt.Printf("  Total Errors:   %d\n", result.TotalErrors)
	fmt.Printf("  Error Rate:     %.2f%%\n", stats.ErrorRate)
	fmt.Println()

	// Status codes
	fmt.Println("Status Code Distribution:")
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	for code, count := range stats.StatusCodes {
		percentage := float64(count) / float64(stats.TotalRequests) * 100
		fmt.Fprintf(w, "  %d\t%d\t(%.2f%%)\n", code, count, percentage)
	}
	w.Flush()
	fmt.Println()

	// Per-request stats
	if len(stats.RequestStats) > 0 {
		fmt.Println("Per-Request Statistics:")
		w = tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
		fmt.Fprintf(w, "  Name\t\tCount\tErrors\tError Rate\tAvg Lat\tP90 Lat\n")
		fmt.Fprintf(w, "  ----\t\t-----\t------\t----------\t-------\t-------\n")
		for name, stat := range stats.RequestStats {
			fmt.Fprintf(w, "  %s\t%d\t%d\t%.2f%%\t%.2fms\t%.2fms\n",
				name, stat.Count, stat.ErrorCount, stat.ErrorRate,
				stat.AvgLatency/1000, stat.Percentiles[90]/1000)
		}
		w.Flush()
		fmt.Println()
	}

	fmt.Println("========================================")
}

// JSONReporter generates JSON reports
type JSONReporter struct {
	OutputPath string
}

// NewJSONReporter creates a new JSON reporter
func NewJSONReporter(outputPath string) *JSONReporter {
	return &JSONReporter{OutputPath: outputPath}
}

// Generate generates a JSON report
func (r *JSONReporter) Generate(result *Result) error {
	report := JSONReport{
		Metadata: Metadata{
			Tool:        "loadtest",
			Version:     "1.0.0",
			StartTime:   result.StartTime.Format(time.RFC3339),
			EndTime:     result.EndTime.Format(time.RFC3339),
			DurationSec: result.Duration.Seconds(),
			Distributed: result.Distributed,
			NodeID:      result.NodeID,
		},
		Summary: Summary{
			TotalRequests:   result.TotalRequests,
			TotalErrors:     result.TotalErrors,
			RequestsPerSec:  result.Statistics.Throughput,
			BytesSentKB:     float64(result.Statistics.BytesSent) / 1024,
			BytesRecvKB:     float64(result.Statistics.BytesReceived) / 1024,
			ErrorRate:       result.Statistics.ErrorRate,
		},
		Latency: LatencySummary{
			MinMs:     result.Statistics.ToLatencyMs(result.Statistics.MinLatency),
			AvgMs:     result.Statistics.ToLatencyMs(result.Statistics.AvgLatency),
			MaxMs:     result.Statistics.ToLatencyMs(result.Statistics.MaxLatency),
			StdDevMs:  result.Statistics.ToLatencyMs(result.Statistics.StdDev),
			MedianMs:  result.Statistics.ToLatencyMs(result.Statistics.Median),
			P90Ms:     result.Statistics.ToLatencyMs(result.Statistics.P90),
			P95Ms:     result.Statistics.ToLatencyMs(result.Statistics.P95),
			P99Ms:     result.Statistics.ToLatencyMs(result.Statistics.P99),
			P999Ms:    result.Statistics.ToLatencyMs(result.Statistics.P99_9),
		},
		StatusCodes: result.Statistics.StatusCodes,
	}

	// Convert samples to JSON-friendly format
	for _, sample := range result.Samples {
		report.Samples = append(report.Samples, SampleData{
			Timestamp:   sample.Timestamp.Milliseconds(),
			LatencyMs:   sample.Latency.Milliseconds(),
			StatusCode:  sample.StatusCode,
			Success:     sample.Success,
			RequestName: sample.RequestName,
			ErrorMsg:    sample.ErrorMsg,
		})
	}

	// Convert request stats
	for name, stat := range result.Statistics.RequestStats {
		report.RequestStats[name] = RequestStatData{
			Count:        stat.Count,
			SuccessCount: stat.SuccessCount,
			ErrorCount:   stat.ErrorCount,
			ErrorRate:    stat.ErrorRate,
			AvgLatMs:     stat.AvgLatency / 1000,
			P90Ms:        stat.Percentiles[90] / 1000,
		}
	}

	// Write to file or stdout
	var data []byte
	var err error
	if r.OutputPath == "" || r.OutputPath == "stdout" {
		data, err = json.MarshalIndent(report, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(data))
	} else {
		data, err = json.MarshalIndent(report, "", "  ")
		if err != nil {
			return err
		}
		return os.WriteFile(r.OutputPath, data, 0644)
	}

	return nil
}

// PrintSummary prints the summary to console for JSON reporter
func (r *JSONReporter) PrintSummary(result *Result) {
	// JSON reporter already prints via Generate
}

// HTMLReporter generates HTML reports with charts
type HTMLReporter struct {
	OutputPath string
}

// NewHTMLReporter creates a new HTML reporter
func NewHTMLReporter(outputPath string) *HTMLReporter {
	return &HTMLReporter{OutputPath: outputPath}
}

// Generate generates an HTML report
func (r *HTMLReporter) Generate(result *Result) error {
	stats := result.Statistics

	html := fmt.Sprintf(`<!DOCTYPE html>
<html>
<head>
    <title>Load Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .metric { display: inline-block; margin: 10px; padding: 10px; background: #f5f5f5; border-radius: 5px; }
        .value { font-size: 24px; font-weight: bold; color: #007bff; }
        .label { font-size: 12px; color: #666; }
        table { width: 100%%; border-collapse: collapse; }
        th, td { padding: 10px; border: 1px solid #ddd; text-align: left; }
        th { background: #f5f5f5; }
        .success { color: green; }
        .error { color: red; }
    </style>
</head>
<body>
    <h1>Load Test Results</h1>
    
    <div class="section">
        <h2>Summary</h2>
        <div class="metric">
            <div class="value">%.2f</div>
            <div class="label">Requests/sec</div>
        </div>
        <div class="metric">
            <div class="value">%d</div>
            <div class="label">Total Requests</div>
        </div>
        <div class="metric">
            <div class="value">%.2f%%</div>
            <div class="label">Error Rate</div>
        </div>
    </div>

    <div class="section">
        <h2>Latency (ms)</h2>
        <div class="metric">
            <div class="value">%.2f</div>
            <div class="label">Average</div>
        </div>
        <div class="metric">
            <div class="value">%.2f</div>
            <div class="label">P95</div>
        </div>
        <div class="metric">
            <div class="value">%.2f</div>
            <div class="label">P99</div>
        </div>
        <div class="metric">
            <div class="value">%.2f</div>
            <div class="label">Max</div>
        </div>
    </div>

    <div class="section">
        <h2>Status Codes</h2>
        <table>
            <tr><th>Code</th><th>Count</th><th>Percentage</th></tr>
`,
		stats.Throughput,
		result.TotalRequests,
		stats.ErrorRate,
		stats.ToLatencyMs(stats.AvgLatency),
		stats.ToLatencyMs(stats.P95),
		stats.ToLatencyMs(stats.P99),
		stats.ToLatencyMs(stats.MaxLatency),
	)

	// Add status code rows
	for code, count := range stats.StatusCodes {
		percentage := float64(count) / float64(stats.TotalRequests) * 100
		html += fmt.Sprintf("            <tr><td>%d</td><td>%d</td><td>%.2f%%</td></tr>\n", code, count, percentage)
	}

	html += `        </table>
    </div>
</body>
</html>`

	if r.OutputPath == "" || r.OutputPath == "stdout" {
		fmt.Println(html)
	} else {
		return os.WriteFile(r.OutputPath, []byte(html), 0644)
	}

	return nil
}

// PrintSummary prints the summary to console for HTML reporter
func (r *HTMLReporter) PrintSummary(result *Result) {
	// HTML reporter generates full HTML report via Generate
}

// NewReporter creates a reporter based on format
func NewReporter(format string) Reporter {
	switch format {
	case "json":
		return &JSONReporter{}
	case "html":
		return &HTMLReporter{}
	default:
		return &ConsoleReporter{}
	}
}

// JSON report structures

type Metadata struct {
	Tool        string  `json:"tool"`
	Version     string  `json:"version"`
	StartTime   string  `json:"start_time"`
	EndTime     string  `json:"end_time"`
	DurationSec float64 `json:"duration_seconds"`
	Distributed bool    `json:"distributed"`
	NodeID      string  `json:"node_id,omitempty"`
}

type Summary struct {
	TotalRequests   int64   `json:"total_requests"`
	TotalErrors     int64   `json:"total_errors"`
	RequestsPerSec  float64 `json:"requests_per_second"`
	BytesSentKB     float64 `json:"bytes_sent_kb"`
	BytesRecvKB     float64 `json:"bytes_received_kb"`
	ErrorRate       float64 `json:"error_rate_percent"`
}

type LatencySummary struct {
	MinMs    float64 `json:"min_ms"`
	AvgMs    float64 `json:"avg_ms"`
	MaxMs    float64 `json:"max_ms"`
	StdDevMs float64 `json:"std_dev_ms"`
	MedianMs float64 `json:"median_ms"`
	P90Ms    float64 `json:"p90_ms"`
	P95Ms    float64 `json:"p95_ms"`
	P99Ms    float64 `json:"p99_ms"`
	P999Ms   float64 `json:"p999_ms"`
}

type SampleData struct {
	Timestamp   int64  `json:"timestamp_ms"`
	LatencyMs   int64  `json:"latency_ms"`
	StatusCode  int    `json:"status_code"`
	Success     bool   `json:"success"`
	RequestName string `json:"request_name,omitempty"`
	ErrorMsg    string `json:"error_message,omitempty"`
}

type RequestStatData struct {
	Count        int     `json:"count"`
	SuccessCount int     `json:"success_count"`
	ErrorCount   int     `json:"error_count"`
	ErrorRate    float64 `json:"error_rate_percent"`
	AvgLatMs     float64 `json:"avg_latency_ms"`
	P90Ms        float64 `json:"p90_latency_ms"`
}

type JSONReport struct {
	Metadata     Metadata                `json:"metadata"`
	Summary      Summary                 `json:"summary"`
	Latency      LatencySummary          `json:"latency"`
	StatusCodes  map[int]int             `json:"status_codes"`
	Samples      []SampleData            `json:"samples,omitempty"`
	RequestStats map[string]RequestStatData `json:"request_stats,omitempty"`
}
