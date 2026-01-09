package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"github.com/spf13/cobra"
)

var (
	// Flags
	broker       string
	clients      int
	durationSec  int
	intervalSec  int
	topic        string
	rtuPrefix    string // RTU ID prefix
	username     string
	password     string
	qosLevel     int
	retain       bool
	clean        bool
	verbose      bool
)

// Statistics tracking
type Stats struct {
	StartTime          time.Time
	ConnectionsTotal   int64
	ConnectionsSuccess int64
	ConnectionsFailed  int64
	PublishesTotal     int64
	PublishesSuccess   int64
	PublishesFailed    int64
	ActiveClients      int64
	mu                 sync.RWMutex
	errors             []ErrorRecord
}

type ErrorRecord struct {
	Time      time.Time
	Type      string
	ClientID  string
	Message   string
}

type TestReport struct {
	Duration        time.Duration `json:"duration"`
	Broker          string        `json:"broker"`
	Topic           string        `json:"topic"`
	QoS             byte          `json:"qos"`

	Connections     ConnectionStats `json:"connections"`
	Publishes       PublishStats   `json:"publishes"`
	Errors          []ErrorRecord  `json:"errors,omitempty"`
}

type ConnectionStats struct {
	Total       int64   `json:"total"`
	Success     int64   `json:"success"`
	Failed      int64   `json:"failed"`
	SuccessRate float64 `json:"success_rate"`
}

type PublishStats struct {
	Total       int64   `json:"total"`
	Success     int64   `json:"success"`
	Failed      int64   `json:"failed"`
	SuccessRate float64 `json:"success_rate"`
	PerSecond   float64 `json:"per_second"`
}

// MQTT Client wrapper
type MQTTLoadClient struct {
	ID       int
	ClientID string
	client   mqtt.Client
	Config   ClientConfig
	Stats    *Stats
	Done     chan struct{}
}

type ClientConfig struct {
	Broker   string
	Topic    string
	RTUID    string // Unique RTU ID for each client
	Username string
	Password string
	QoS      byte
	Retain   bool
	Clean    bool
}

func (c *MQTTLoadClient) Connect() error {
	opts := mqtt.NewClientOptions()
	opts.AddBroker(c.Config.Broker)
	opts.SetClientID(c.ClientID)
	opts.SetCleanSession(c.Config.Clean)
	opts.SetAutoReconnect(false)
	opts.SetConnectTimeout(30 * time.Second)
	opts.SetKeepAlive(60 * time.Second)

	if c.Config.Username != "" {
		opts.SetUsername(c.Config.Username)
	}
	if c.Config.Password != "" {
		opts.SetPassword(c.Config.Password)
	}

	client := mqtt.NewClient(opts)

	token := client.Connect()
	if token.Wait() && token.Error() != nil {
		atomic.AddInt64(&c.Stats.ConnectionsTotal, 1)
		atomic.AddInt64(&c.Stats.ConnectionsFailed, 1)
		c.Stats.mu.Lock()
		c.Stats.errors = append(c.Stats.errors, ErrorRecord{
			Time:     time.Now(),
			Type:     "connection",
			ClientID: c.ClientID,
			Message:  token.Error().Error(),
		})
		c.Stats.mu.Unlock()
		return token.Error()
	}

	atomic.AddInt64(&c.Stats.ConnectionsTotal, 1)
	atomic.AddInt64(&c.Stats.ConnectionsSuccess, 1)
	atomic.AddInt64(&c.Stats.ActiveClients, 1)

	c.client = client
	return nil
}

func (c *MQTTLoadClient) StartPublishing(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-c.Done:
			return
		case <-ticker.C:
			c.publish()
		}
	}
}

func (c *MQTTLoadClient) publish() {
	if c.client == nil {
		return
	}

	// Generate RTU data payload
	now := time.Now()
	timestamp := now.Format("2006-01-02T15:04:05-07:00")

	// Simulate realistic electrical measurements
	voltageL1 := 230.0 + rand.Float64()*20 - 10 // 220-240V
	voltageL2 := 230.0 + rand.Float64()*20 - 10
	voltageL3 := 230.0 + rand.Float64()*20 - 10

	currentL1 := 100.0 + rand.Float64()*100 // 100-200A
	currentL2 := 100.0 + rand.Float64()*100
	currentL3 := 100.0 + rand.Float64()*100
	currentN := currentL1 + currentL2 + currentL3 - rand.Float64()*50
	currentTotal := currentL1 + currentL2 + currentL3

	pfL1 := 0.9 + rand.Float64()*0.09 // 0.9-0.99
	pfL2 := 0.9 + rand.Float64()*0.09
	pfL3 := 0.9 + rand.Float64()*0.09

	activatePowerL1 := voltageL1 * currentL1 * pfL1
	activatePowerL2 := voltageL2 * currentL2 * pfL2
	activatePowerL3 := voltageL3 * currentL3 * pfL3

	reactivePowerL1 := activatePowerL1 * 0.3
	reactivePowerL2 := activatePowerL2 * 0.3
	reactivePowerL3 := activatePowerL3 * 0.3

	apparentPowerL1 := voltageL1 * currentL1
	apparentPowerL2 := voltageL2 * currentL2
	apparentPowerL3 := voltageL3 * currentL3
	apparentPowerTotal := apparentPowerL1 + apparentPowerL2 + apparentPowerL3

	currentL1F1 := currentL1 * 0.8 + rand.Float64()*20
	currentL2F1 := currentL2 * 0.8 + rand.Float64()*20
	currentL3F1 := currentL3 * 0.8 + rand.Float64()*20
	currentNF1 := currentN * 0.4

	currentL1F2 := currentL1 * 0.7 + rand.Float64()*20
	currentL2F2 := currentL2 * 0.7 + rand.Float64()*20
	currentL3F2 := currentL3 * 0.7 + rand.Float64()*20
	currentNF2 := currentN * 0.3

	temp1 := 25.0 + rand.Float64()*15 // 25-40°C
	temp2 := 25.0 + rand.Float64()*15

	// Create CSV payload
	payload := fmt.Sprintf("%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f",
		timestamp,
		c.Config.RTUID,
		voltageL1, voltageL2, voltageL3,
		currentL1, currentL2, currentL3, currentN, currentTotal,
		pfL1, pfL2, pfL3,
		activatePowerL1, activatePowerL2, activatePowerL3,
		reactivePowerL1, reactivePowerL2, reactivePowerL3,
		apparentPowerL1, apparentPowerL2, apparentPowerL3, apparentPowerTotal,
		currentL1F1, currentL2F1, currentL3F1, currentNF1,
		currentL1F2, currentL2F2, currentL3F2, currentNF2,
		temp1, temp2)

	// Each RTU publishes to its own topic
	topic := fmt.Sprintf("%s/%s", c.Config.Topic, c.Config.RTUID)

	token := c.client.Publish(topic, c.Config.QoS, c.Config.Retain, payload)
	atomic.AddInt64(&c.Stats.PublishesTotal, 1)

	if token.Wait() && token.Error() != nil {
		atomic.AddInt64(&c.Stats.PublishesFailed, 1)
		c.Stats.mu.Lock()
		c.Stats.errors = append(c.Stats.errors, ErrorRecord{
			Time:     time.Now(),
			Type:     "publish",
			ClientID: c.ClientID,
			Message:  token.Error().Error(),
		})
		c.Stats.mu.Unlock()
	} else {
		atomic.AddInt64(&c.Stats.PublishesSuccess, 1)
	}
}

func (c *MQTTLoadClient) Disconnect() {
	if c.client != nil && c.client.IsConnected() {
		c.client.Disconnect(250)
		atomic.AddInt64(&c.Stats.ActiveClients, -1)
	}
}

var rootCmd = &cobra.Command{
	Use:   "mqtt-loadtest",
	Short: "MQTT Load Tester for VerneMQ",
	Long: `High-performance MQTT load testing tool written in Go.
Tests MQTT broker capacity with multiple concurrent clients and publish rates.`,
	Run: runLoadTest,
}

func init() {
	rootCmd.Flags().StringVarP(&broker, "broker", "b", "tcp://localhost:1883", "MQTT broker address")
	rootCmd.Flags().IntVarP(&clients, "clients", "c", 10, "Number of concurrent clients (RTUs)")
	rootCmd.Flags().IntVarP(&intervalSec, "interval", "i", 5, "Publish interval per client (seconds)")
	rootCmd.Flags().IntVarP(&durationSec, "duration", "d", 60, "Test duration (seconds)")
	rootCmd.Flags().StringVarP(&topic, "topic", "t", "rtu/data", "Base topic for RTU data")
	rootCmd.Flags().StringVar(&rtuPrefix, "rtu-prefix", "25090100000", "RTU ID prefix (will append sequential number)")
	rootCmd.Flags().StringVarP(&username, "username", "u", "", "Username for authentication")
	rootCmd.Flags().StringVarP(&password, "password", "P", "", "Password for authentication")
	rootCmd.Flags().IntVar(&qosLevel, "qos", 0, "QoS level (0, 1, or 2)")
	rootCmd.Flags().BoolVar(&retain, "retain", false, "Set retain flag")
	rootCmd.Flags().BoolVar(&clean, "clean", true, "Use clean session")
	rootCmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")
}

func runLoadTest(cmd *cobra.Command, args []string) {
	duration := time.Duration(durationSec) * time.Second
	interval := time.Duration(intervalSec) * time.Second
	qos := byte(qosLevel)

	fmt.Printf("\n🚀 Starting MQTT Load Test\n")
	fmt.Printf("   Broker:   %s\n", broker)
	fmt.Printf("   Clients:  %d\n", clients)
	fmt.Printf("   Duration: %v\n", duration)
	fmt.Printf("   Interval: %v\n", interval)
	fmt.Printf("   Topic:    %s\n", topic)
	if username != "" {
		fmt.Printf("   Auth:     %s:***\n", username)
	}
	fmt.Printf("   Press Ctrl+C to stop early\n\n")

	stats := &Stats{
		StartTime: time.Now(),
		errors:    make([]ErrorRecord, 0),
	}

	// Create clients
	fmt.Println("📡 Connecting clients...")
	clientList := make([]*MQTTLoadClient, clients)
	var wg sync.WaitGroup

	for i := 0; i < clients; i++ {
		// Generate unique RTU ID: rtuPrefix + sequential number (with leading zeros)
		rtuID := fmt.Sprintf("%s%d", rtuPrefix, i+1)
		clientID := fmt.Sprintf("rtu_%s", rtuID)

		clientList[i] = &MQTTLoadClient{
			ID:       i + 1,
			ClientID: clientID,
			Config: ClientConfig{
				Broker:   broker,
				Topic:    topic,
				RTUID:    rtuID,
				Username: username,
				Password: password,
				QoS:      qos,
				Retain:   retain,
				Clean:    clean,
			},
			Stats: stats,
			Done:  make(chan struct{}),
		}

		// Stagger connections
		time.Sleep(50 * time.Millisecond)

		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			if err := clientList[idx].Connect(); err != nil && verbose {
				fmt.Printf("⚠️  Client %d failed to connect: %v\n", idx+1, err)
			}
		}(i)
	}

	wg.Wait()

	connSuccess := atomic.LoadInt64(&stats.ConnectionsSuccess)
	connFailed := atomic.LoadInt64(&stats.ConnectionsFailed)

	fmt.Printf("\n✅ Connected: %d/%d\n", connSuccess, clients)
	if connFailed > 0 {
		fmt.Printf("⚠️  Failed: %d\n", connFailed)
	}

	// Start publishing
	fmt.Println("\n📤 Starting publish phase...\n")

	// Progress reporter
	stopProgress := make(chan struct{})
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-stopProgress:
				return
			case <-ticker.C:
				displayProgress(stats)
			}
		}
	}()

	// Start publishers
	for _, client := range clientList {
		wg.Add(1)
		go func(c *MQTTLoadClient) {
			defer wg.Done()
			c.StartPublishing(interval)
		}(client)
	}

	// Wait for duration or interrupt
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	// Handle interrupt
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	select {
	case <-time.After(duration):
		fmt.Println("\n\n⏰ Test duration completed")
	case <-sigChan:
		fmt.Println("\n\n⚠️  Test interrupted by user")
	case <-done:
	}

	// Stop all clients
	close(stopProgress)
	fmt.Println("\n🛑 Stopping clients...")

	for _, client := range clientList {
		close(client.Done)
		client.Disconnect()
	}

	// Wait a bit for graceful disconnect
	time.Sleep(500 * time.Millisecond)

	// Display final report
	displayFinalReport(stats)
}

func displayProgress(stats *Stats) {
	elapsed := time.Since(stats.StartTime).Seconds()
	connSuccess := atomic.LoadInt64(&stats.ConnectionsSuccess)
	connFailed := atomic.LoadInt64(&stats.ConnectionsFailed)
	active := atomic.LoadInt64(&stats.ActiveClients)
	pubSuccess := atomic.LoadInt64(&stats.PublishesSuccess)

	perSec := 0.0
	if elapsed > 0 {
		perSec = float64(pubSuccess) / elapsed
	}

	fmt.Printf("\r⏱ %.1fs | 🔗 %d/%d | 👥 %d active | 📤 %d pubs (%.1f/s)    ",
		elapsed, connSuccess, connSuccess+connFailed, active, pubSuccess, perSec)
}

func displayFinalReport(stats *Stats) {
	elapsed := time.Since(stats.StartTime)

	connTotal := atomic.LoadInt64(&stats.ConnectionsTotal)
	connSuccess := atomic.LoadInt64(&stats.ConnectionsSuccess)
	connFailed := atomic.LoadInt64(&stats.ConnectionsFailed)
	pubTotal := atomic.LoadInt64(&stats.PublishesTotal)
	pubSuccess := atomic.LoadInt64(&stats.PublishesSuccess)
	pubFailed := atomic.LoadInt64(&stats.PublishesFailed)

	connRate := 0.0
	if connTotal > 0 {
		connRate = float64(connSuccess) / float64(connTotal) * 100
	}

	pubRate := 0.0
	if pubTotal > 0 {
		pubRate = float64(pubSuccess) / float64(pubTotal) * 100
	}

	perSec := 0.0
	if elapsed.Seconds() > 0 {
		perSec = float64(pubSuccess) / elapsed.Seconds()
	}

	fmt.Println("\n" + strings.Repeat("=", 60))
	fmt.Println("           MQTT LOAD TEST RESULTS")
	fmt.Println(strings.Repeat("=", 60))

	fmt.Println("\nTest Configuration:")
	fmt.Printf("  Duration:     %.1fs\n", elapsed.Seconds())
	fmt.Printf("  Target:       %s\n", broker)
	fmt.Printf("  Topic:        %s\n", topic)
	fmt.Printf("  QoS:          %d\n", qosLevel)

	fmt.Println("\nConnection Statistics:")
	fmt.Printf("  Total:        %d\n", connTotal)
	fmt.Printf("  Successful:   %d (%.2f%%)\n", connSuccess, connRate)
	fmt.Printf("  Failed:       %d\n", connFailed)

	fmt.Println("\nPublish Statistics:")
	fmt.Printf("  Total:        %d\n", pubTotal)
	fmt.Printf("  Successful:   %d (%.2f%%)\n", pubSuccess, pubRate)
	fmt.Printf("  Failed:       %d\n", pubFailed)
	fmt.Printf("  Rate:         %.2f msg/s\n", perSec)

	stats.mu.RLock()
	errorCount := len(stats.errors)
	stats.mu.RUnlock()

	if errorCount > 0 {
		fmt.Printf("\n⚠️  Errors:      %d\n", errorCount)
		stats.mu.RLock()
		recentErrors := stats.errors
		if len(recentErrors) > 10 {
			recentErrors = recentErrors[len(recentErrors)-10:]
		}
		fmt.Println("\nRecent Errors:")
		for _, err := range recentErrors {
			fmt.Printf("  [%s] %s: %s\n", err.Type, err.ClientID, err.Message)
		}
		stats.mu.RUnlock()
	}

	fmt.Println("\n" + strings.Repeat("=", 60))
	fmt.Printf("Test completed at %s\n", time.Now().Format(time.RFC3339))
	fmt.Println(strings.Repeat("=", 60) + "\n")

	// Output JSON report if needed
	if os.Getenv("MQTT_LOADTEST_JSON") != "" {
		report := TestReport{
			Duration: elapsed,
			Broker:   broker,
			Topic:    topic,
			QoS:      byte(qosLevel),
			Connections: ConnectionStats{
				Total:       connTotal,
				Success:     connSuccess,
				Failed:      connFailed,
				SuccessRate: connRate,
			},
			Publishes: PublishStats{
				Total:       pubTotal,
				Success:     pubSuccess,
				Failed:      pubFailed,
				SuccessRate: pubRate,
				PerSecond:   perSec,
			},
		}

		stats.mu.RLock()
		report.Errors = stats.errors
		stats.mu.RUnlock()

		jsonData, _ := json.MarshalIndent(report, "", "  ")
		fmt.Println("\nJSON Report:")
		fmt.Println(string(jsonData))
	}
}

// Helper function to repeat strings
func repeat(s string, count int) string {
	result := ""
	for i := 0; i < count; i++ {
		result += s
	}
	return result
}

func main() {
	rand.Seed(time.Now().UnixNano())

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
