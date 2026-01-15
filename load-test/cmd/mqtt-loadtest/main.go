package main

import (
	"encoding/json"
	"fmt"
	"math"
	mathrand "math/rand"
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
	syncMode     bool   // Synchronized burst mode (all devices at 15-min intervals)
	jitterSec    int    // Random jitter in seconds (default: ±5s)
	testMode     bool   // Test mode: generates predictable threshold/peak values
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
	ID              int
	ClientID        string
	client          mqtt.Client
	Config          ClientConfig
	Stats           *Stats
	Done            chan struct{}
	PublishCount    int64   // Track number of publishes for test mode
	mu              sync.Mutex  // Protect PublishCount
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

const (
	maxRetryAttempts = 5
	initialRetryDelay = 500 * time.Millisecond
)

func (c *MQTTLoadClient) Connect() error {
	opts := mqtt.NewClientOptions()
	opts.AddBroker(c.Config.Broker)
	opts.SetClientID(c.ClientID)
	opts.SetCleanSession(c.Config.Clean)
	opts.SetAutoReconnect(false)
	opts.SetConnectTimeout(15 * time.Second)
	opts.SetKeepAlive(60 * time.Second)

	if c.Config.Username != "" {
		opts.SetUsername(c.Config.Username)
	}
	if c.Config.Password != "" {
		opts.SetPassword(c.Config.Password)
	}

	var lastErr error
	retryDelay := initialRetryDelay

	for attempt := 1; attempt <= maxRetryAttempts; attempt++ {
		client := mqtt.NewClient(opts)
		token := client.Connect()

		if token.Wait() && token.Error() != nil {
			lastErr = token.Error()

			// Don't retry on the last attempt
			if attempt == maxRetryAttempts {
				atomic.AddInt64(&c.Stats.ConnectionsTotal, 1)
				atomic.AddInt64(&c.Stats.ConnectionsFailed, 1)
				c.Stats.mu.Lock()
				c.Stats.errors = append(c.Stats.errors, ErrorRecord{
					Time:     time.Now(),
					Type:     "connection",
					ClientID: c.ClientID,
					Message:  fmt.Sprintf("Attempt %d/%d failed: %s", attempt, maxRetryAttempts, lastErr.Error()),
				})
				c.Stats.mu.Unlock()
				return lastErr
			}

			// Exponential backoff with jitter
			jitter := time.Duration(mathrand.Float64() * float64(retryDelay) * 0.5)
			time.Sleep(retryDelay + jitter)
			retryDelay *= 2 // Exponential backoff: 1s, 2s, 4s, 8s
			continue
		}

		// Success
		atomic.AddInt64(&c.Stats.ConnectionsTotal, 1)
		atomic.AddInt64(&c.Stats.ConnectionsSuccess, 1)
		atomic.AddInt64(&c.Stats.ActiveClients, 1)

		c.client = client
		return nil
	}

	return lastErr
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

// StartPublishingSync publishes at synchronized 15-minute intervals (00:00, 00:15, 00:30, 00:45)
// with small random jitter to prevent exact timestamp collision
func (c *MQTTLoadClient) StartPublishingSync(interval time.Duration, jitter time.Duration) {
	// Calculate first interval boundary
	now := time.Now()
	var firstTick time.Time

	// Find the next 15-minute mark
	minutes := now.Minute()
	nextQuarter := ((minutes / 15) + 1) * 15
	if nextQuarter >= 60 {
		firstTick = now.Add(time.Duration(60-nextQuarter) * time.Minute)
		firstTick = time.Date(firstTick.Year(), firstTick.Month(), firstTick.Day(), firstTick.Hour(), 0, 0, 0, firstTick.Location())
	} else {
		firstTick = time.Date(now.Year(), now.Month(), now.Day(), now.Hour(), nextQuarter, 0, 0, now.Location())
	}

	// Add random jitter to this client (natural clock drift variation)
	// Each RTU has slightly different timing due to hardware/network differences
	randomJitter := time.Duration(mathrand.Float64() * float64(jitter) * 2)
	firstTick = firstTick.Add(randomJitter - jitter)

	// Calculate initial delay
	initialDelay := time.Until(firstTick)
	if initialDelay < 0 {
		initialDelay = 0
	}

	// Wait for first interval
	select {
	case <-c.Done:
		return
	case <-time.After(initialDelay):
		c.publish()
	}

	// Continue with interval ticker
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

	// Increment publish count for test mode
	c.mu.Lock()
	c.PublishCount++
	count := c.PublishCount
	c.mu.Unlock()

	var vr, vs, vt, ir, is_, it, in, pf1, pf2, pf3, tk1, tk2, i1f1, i2f1, i3f1, inf1, i1f2, i2f2, i3f2, inf2 float64
	var payload string
	var now time.Time
	var ts int64

	if testMode {
		// ============================================
		// TEST MODE: Predictable threshold/peak values
		// ============================================
		// Pattern cycles every 10 messages:
		// 1-3: Normal values
		// 4: Voltage High (threshold trigger)
		// 5: Voltage Low (threshold trigger)
		// 6: Current High (threshold trigger)
		// 7: Temperature High (threshold trigger)
		// 8: Power Factor Low (threshold trigger)
		// 9-10: Normal values with increasing STot (for peak detection)

		cycle := (count % 10)

		switch cycle {
		case 1, 2, 3, 9, 10:
			// Normal values
			vr, vs, vt = 230.0, 230.0, 230.0
			ir, is_, it = 150.0, 150.0, 150.0
			pf1, pf2, pf3 = 0.95, 0.95, 0.95
			tk1, tk2 = 35.0, 37.0
		case 4:
			// Voltage High: 260V (exceeds typical 250V threshold)
			vr, vs, vt = 260.0, 260.0, 260.0
			ir, is_, it = 150.0, 150.0, 150.0
			pf1, pf2, pf3 = 0.95, 0.95, 0.95
			tk1, tk2 = 35.0, 37.0
		case 5:
			// Voltage Low: 200V (below typical 210V threshold)
			vr, vs, vt = 200.0, 200.0, 200.0
			ir, is_, it = 150.0, 150.0, 150.0
			pf1, pf2, pf3 = 0.95, 0.95, 0.95
			tk1, tk2 = 35.0, 37.0
		case 6:
			// Current High: 250A (exceeds typical 200A threshold)
			vr, vs, vt = 230.0, 230.0, 230.0
			ir, is_, it = 250.0, 250.0, 250.0
			pf1, pf2, pf3 = 0.95, 0.95, 0.95
			tk1, tk2 = 35.0, 37.0
		case 7:
			// Temperature High: 70°C (exceeds typical 50°C threshold)
			vr, vs, vt = 230.0, 230.0, 230.0
			ir, is_, it = 150.0, 150.0, 150.0
			pf1, pf2, pf3 = 0.95, 0.95, 0.95
			tk1, tk2 = 70.0, 72.0
		case 8:
			// Power Factor Low: 0.75 (below typical 0.85 threshold)
			vr, vs, vt = 230.0, 230.0, 230.0
			ir, is_, it = 150.0, 150.0, 150.0
			pf1, pf2, pf3 = 0.75, 0.75, 0.75
			tk1, tk2 = 35.0, 37.0
		}

		in = (ir + is_ + it) * 0.02
		i1f1, i2f1, i3f1 = ir*0.8, is_*0.8, it*0.8
		inf1 = in * 0.4
		i1f2, i2f2, i3f2 = ir*0.7, is_*0.7, it*0.7
		inf2 = in * 0.3

		// Calculate power values
		pr, ps, pt := vr*ir*pf1, vs*is_*pf2, vt*it*pf3
		qr, qs, qt := vr*ir*math.Sqrt(1-pf1*pf1), vs*is_*math.Sqrt(1-pf2*pf2), vt*it*math.Sqrt(1-pf3*pf3)
		sr, ss, st := vr*ir, vs*is_, vt*it
		stot := sr + ss + st

		// For cycles 9-10, increase STot to trigger peak updates
		if cycle == 9 {
			stot = 100000.0 + float64(count%100)*5000.0 // 100-600 kVA in watts
			sr, ss, st = stot/3.0, stot/3.0, stot/3.0
		} else if cycle == 10 {
			stot = 500000.0 + float64(count%100)*10000.0 // 500-1500 kVA in watts
			sr, ss, st = stot/3.0, stot/3.0, stot/3.0
		}

		// Timestamp
		now = time.Now()
		ts = now.Unix()

		// Build JSON payload
		payload = fmt.Sprintf(`{
			"rtuId": "%s",
			"TS": %d,
			"VR": %.2f, "VS": %.2f, "VT": %.2f,
			"IR": %.2f, "IS": %.2f, "IT": %.2f, "IN": %.2f,
			"PF1": %.3f, "PF2": %.3f, "PF3": %.3f,
			"PR": %.2f, "PS": %.2f, "PT": %.2f,
			"QR": %.2f, "QS": %.2f, "QT": %.2f,
			"SR": %.2f, "SS": %.2f, "ST": %.2f, "STot": %.2f,
			"ITot": %.2f,
			"I1F1": %.2f, "I2F1": %.2f, "I3F1": %.2f, "INF1": %.2f,
			"I1F2": %.2f, "I2F2": %.2f, "I3F2": %.2f, "INF2": %.2f,
			"TK1": %.1f, "TK2": %.1f
		}`, c.Config.RTUID, ts,
			vr, vs, vt,
			ir, is_, it, in,
			pf1, pf2, pf3,
			pr, ps, pt,
			qr, qs, qt,
			sr, ss, st, stot,
			ir+is_+it,
			i1f1, i2f1, i3f1, inf1,
			i1f2, i2f2, i3f2, inf2,
			tk1, tk2)

	} else {
		// ============================================
		// NORMAL MODE: Random realistic values
		// ============================================
		vr = 220.0 + mathrand.Float64()*20
		vs = 220.0 + mathrand.Float64()*20
		vt = 220.0 + mathrand.Float64()*20

		ir = 80.0 + mathrand.Float64()*120
		is_ = 80.0 + mathrand.Float64()*120
		it = 80.0 + mathrand.Float64()*120
		in = (ir + is_ + it) * 0.02 + mathrand.Float64()*5

		pf1 = 0.90 + mathrand.Float64()*0.09
		pf2 = 0.90 + mathrand.Float64()*0.09
		pf3 = 0.90 + mathrand.Float64()*0.09

		i1f1 = ir*0.8 + mathrand.Float64()*20
		i2f1 = is_*0.8 + mathrand.Float64()*20
		i3f1 = it*0.8 + mathrand.Float64()*20
		inf1 = in * 0.4

		i1f2 = ir*0.7 + mathrand.Float64()*20
		i2f2 = is_*0.7 + mathrand.Float64()*20
		i3f2 = it*0.7 + mathrand.Float64()*20
		inf2 = in * 0.3

		tk1 = 25.0 + mathrand.Float64()*20
		tk2 = tk1 + mathrand.Float64()*5 + 1

		now = time.Now()
		ts = now.Unix()

		payload = fmt.Sprintf(`{
			"rtuId": "%s",
			"TS": %d,
			"VR": %.2f, "VS": %.2f, "VT": %.2f,
			"IR": %.2f, "IS": %.2f, "IT": %.2f, "IN": %.2f,
			"PF1": %.3f, "PF2": %.3f, "PF3": %.3f,
			"I1F1": %.2f, "I2F1": %.2f, "I3F1": %.2f, "INF1": %.2f,
			"I1F2": %.2f, "I2F2": %.2f, "I3F2": %.2f, "INF2": %.2f,
			"TK1": %.1f, "TK2": %.1f
		}`, c.Config.RTUID, ts,
			vr, vs, vt,
			ir, is_, it, in,
			pf1, pf2, pf3,
			i1f1, i2f1, i3f1, inf1,
			i1f2, i2f2, i3f2, inf2,
			tk1, tk2)
	}

	// Each RTU publishes to its own topic: thms/{rtuId}/data
	topic := fmt.Sprintf("%s/%s/data", c.Config.Topic, c.Config.RTUID)

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
	rootCmd.Flags().StringVarP(&topic, "topic", "t", "thms", "Base topic for RTU data (format: {topic}/{rtuId}/data)")
	rootCmd.Flags().StringVar(&rtuPrefix, "rtu-prefix", "25090100000", "RTU ID prefix (will append sequential number)")
	rootCmd.Flags().StringVarP(&username, "username", "u", "", "Username for authentication")
	rootCmd.Flags().StringVarP(&password, "password", "P", "", "Password for authentication")
	rootCmd.Flags().IntVar(&qosLevel, "qos", 0, "QoS level (0, 1, or 2)")
	rootCmd.Flags().BoolVar(&retain, "retain", false, "Set retain flag")
	rootCmd.Flags().BoolVar(&clean, "clean", true, "Use clean session")
	rootCmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")
	rootCmd.Flags().BoolVar(&syncMode, "sync", false, "Synchronized mode (all devices publish at same interval mark)")
	rootCmd.Flags().IntVar(&jitterSec, "jitter", 5, "Random jitter in seconds for sync mode (±jitter)")
	rootCmd.Flags().BoolVar(&testMode, "test-mode", false, "Test mode: generates predictable threshold/peak values for validation")
}

func runLoadTest(cmd *cobra.Command, args []string) {
	duration := time.Duration(durationSec) * time.Second
	interval := time.Duration(intervalSec) * time.Second
	jitter := time.Duration(jitterSec) * time.Second
	qos := byte(qosLevel)

	fmt.Printf("\n🚀 Starting MQTT Load Test\n")
	fmt.Printf("   Broker:   %s\n", broker)
	fmt.Printf("   Clients:  %d\n", clients)
	fmt.Printf("   Duration: %v\n", duration)
	fmt.Printf("   Interval: %v\n", interval)
	if testMode {
		fmt.Printf("   Mode:     🧪 TEST MODE (predictable threshold/peak values)\n")
		fmt.Printf("   Pattern:  10-msg cycle: normal x3, V-high, V-low, I-high, Temp-high, PF-low, peak x2\n")
	} else if syncMode {
		fmt.Printf("   Mode:     🔄 SYNCHRONIZED BURST (at :00, :15, :30, :45)\n")
		fmt.Printf("   Jitter:   ±%v\n", jitter)
	} else {
		fmt.Printf("   Mode:     ⏱ Continuous stream\n")
	}
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

	// Dynamic connection rate based on client count
	// Balanced for speed vs broker stability
	var maxConcurrentConns int
	var staggerDelay time.Duration

	if clients <= 500 {
		maxConcurrentConns = 200
		staggerDelay = 5 * time.Millisecond
	} else if clients <= 2000 {
		maxConcurrentConns = 400
		staggerDelay = 10 * time.Millisecond
	} else {
		// For 5K+ clients
		maxConcurrentConns = 600
		staggerDelay = 15 * time.Millisecond
	}

	fmt.Printf("🔧 Connection settings: %d concurrent, %v stagger\n", maxConcurrentConns, staggerDelay)

	semaphore := make(chan struct{}, maxConcurrentConns)

	for i := 0; i < clients; i++ {
		num := i + 1
		rtuID := fmt.Sprintf("25090100%04d", num)
		clientID := fmt.Sprintf("mqtt_client_%d", i+1)

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

		// Stagger connections to reduce auth service load
		time.Sleep(staggerDelay)

		wg.Add(1)
		go func(idx int) {
			defer wg.Done()

			// Acquire semaphore slot (blocks if max concurrent connections reached)
			semaphore <- struct{}{}
			defer func() { <-semaphore }() // Release slot when done

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
			if syncMode {
				c.StartPublishingSync(interval, jitter)
			} else {
				c.StartPublishing(interval)
			}
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
	mathrand.Seed(time.Now().UnixNano())

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
