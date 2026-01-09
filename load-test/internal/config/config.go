package config

import (
	"fmt"
	"time"

	"github.com/spf13/viper"
)

// Config represents the load test configuration
type Config struct {
	Target      TargetConfig      `mapstructure:"target"`
	VirtualUsers int              `mapstructure:"virtual_users"`
	Duration    time.Duration     `mapstructure:"duration"`
	RampUp      time.Duration     `mapstructure:"ramp_up"`
	Requests    []RequestConfig   `mapstructure:"requests"`
	Headers     map[string]string `mapstructure:"headers"`
	Auth        AuthConfig        `mapstructure:"auth"`
	Distributed DistributedConfig `mapstructure:"distributed"`
	Report      ReportConfig      `mapstructure:"report"`
	Scenarios   []ScenarioConfig  `mapstructure:"scenarios"`
}

// TargetConfig holds the target server configuration
type TargetConfig struct {
	BaseURL    string        `mapstructure:"base_url"`
	Protocol   string        `mapstructure:"protocol"`
	Host       string        `mapstructure:"host"`
	Port       int           `mapstructure:"port"`
	Path       string        `mapstructure:"path"`
	Timeout    time.Duration `mapstructure:"timeout"`
	KeepAlive  bool          `mapstructure:"keep_alive"`
	MaxConns   int           `mapstructure:"max_connections"`
	MaxIdle    int           `mapstructure:"max_idle_connections"`
}

// RequestConfig holds individual request configuration
type RequestConfig struct {
	Name       string            `mapstructure:"name"`
	Method     string            `mapstructure:"method"`
	Endpoint   string            `mapstructure:"endpoint"`
	Body       string            `mapstructure:"body"`
	BodyFile   string            `mapstructure:"body_file"`
	Weight     int               `mapstructure:"weight"`
	Headers    map[string]string `mapstructure:"headers"`
	ThinkTime  time.Duration     `mapstructure:"think_time"`
	Timeout    time.Duration     `mapstructure:"timeout"`
	Expected   ExpectedConfig    `mapstructure:"expected"`
}

// ExpectedConfig holds response expectations
type ExpectedConfig struct {
	StatusCodes []int  `mapstructure:"status_codes"`
	MaxLatency  int64  `mapstructure:"max_latency_ms"`
	ContentType string `mapstructure:"content_type"`
}

// AuthConfig holds authentication configuration
type AuthConfig struct {
	Type     string `mapstructure:"type"`
	Username string `mapstructure:"username"`
	Password string `mapstructure:"password"`
	Token    string `mapstructure:"token"`
	APIKey   string `mapstructure:"api_key"`
}

// DistributedConfig holds distributed testing configuration
type DistributedConfig struct {
	Enabled       bool              `mapstructure:"enabled"`
	Coordinator   string            `mapstructure:"coordinator"`
	NodeID        string            `mapstructure:"node_id"`
	Nodes         []string          `mapstructure:"nodes"`
	BindAddr      string            `mapstructure:"bind_addr"`
	BindPort      int               `mapstructure:"bind_port"`
	AdvertiseAddr string            `mapstructure:"advertise_addr"`
	AdvertisePort int               `mapstructure:"advertise_port"`
	JoinAttempts  int               `mapstructure:"join_attempts"`
	RetryInterval time.Duration     `mapstructure:"retry_interval"`
	Tags          map[string]string `mapstructure:"tags"`
}

// ReportConfig holds reporting configuration
type ReportConfig struct {
	Output     string        `mapstructure:"output"`
	Format     string        `mapstructure:"format"`
	Interval   time.Duration `mapstructure:"interval"`
	Percentiles []float64    `mapstructure:"percentiles"`
	Detailed   bool          `mapstructure:"detailed"`
	OutputDir  string        `mapstructure:"output_dir"`
	Filename   string        `mapstructure:"filename"`
}

// ScenarioConfig holds scenario configuration for different test types
type ScenarioConfig struct {
	Name        string          `mapstructure:"name"`
	Type        string          `mapstructure:"type"`
	VirtualUsers int            `mapstructure:"virtual_users"`
	Duration    time.Duration   `mapstructure:"duration"`
	RampUp      time.Duration   `mapstructure:"ramp_up"`
	RampDown    time.Duration   `mapstructure:"ramp_down"`
	Requests    []RequestConfig `mapstructure:"requests"`
}

// Load loads configuration from the specified file path
func Load(path string) (*Config, error) {
	v := viper.New()

	v.SetConfigFile(path)
	v.SetConfigType("yaml")

	// Allow environment variable overrides
	v.AutomaticEnv()

	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	// Set defaults
	setDefaults(&cfg)

	return &cfg, nil
}

// setDefaults sets default configuration values
func setDefaults(cfg *Config) {
	if cfg.Target.Protocol == "" {
		cfg.Target.Protocol = "http"
	}
	if cfg.Target.Timeout == 0 {
		cfg.Target.Timeout = 30 * time.Second
	}
	if cfg.Target.MaxConns == 0 {
		cfg.Target.MaxConns = 100
	}
	if cfg.Target.MaxIdle == 0 {
		cfg.Target.MaxIdle = 100
	}
	if cfg.Duration == 0 {
		cfg.Duration = 60 * time.Second
	}
	if cfg.RampUp == 0 {
		cfg.RampUp = 10 * time.Second
	}
	if cfg.Report.Format == "" {
		cfg.Report.Format = "console"
	}
	if cfg.Report.Output == "" {
		cfg.Report.Output = "stdout"
	}
	if len(cfg.Report.Percentiles) == 0 {
		cfg.Report.Percentiles = []float64{50, 90, 95, 99, 99.9}
	}
}

// LoadCoordinator loads coordinator configuration
func LoadCoordinator() (*Config, error) {
	v := viper.New()

	v.SetConfigName("coordinator")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./configs")
	v.AddConfigPath("/etc/loadtest")

	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read coordinator config: %w", err)
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &cfg, nil
}

// LoadNode loads worker node configuration
func LoadNode() (*Config, error) {
	v := viper.New()

	v.SetConfigName("node")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./configs")
	v.AddConfigPath("/etc/loadtest")

	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read node config: %w", err)
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &cfg, nil
}

// GetFullURL returns the full URL for a request endpoint
func (c *Config) GetFullURL(endpoint string) string {
	return fmt.Sprintf("%s://%s:%d%s%s",
		c.Target.Protocol,
		c.Target.Host,
		c.Target.Port,
		c.Target.Path,
		endpoint)
}
