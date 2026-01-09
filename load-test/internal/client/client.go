package client

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"loadtest/internal/config"
)

// HTTPMethod represents supported HTTP methods
type HTTPMethod string

const (
	MethodGet     HTTPMethod = "GET"
	MethodPost    HTTPMethod = "POST"
	MethodPut     HTTPMethod = "PUT"
	MethodPatch   HTTPMethod = "PATCH"
	MethodDelete  HTTPMethod = "DELETE"
	MethodHead    HTTPMethod = "HEAD"
	MethodOptions HTTPMethod = "OPTIONS"
)

// Request represents a load test request
type Request struct {
	Method     HTTPMethod
	URL        string
	Headers    map[string]string
	Body       []byte
	Timeout    time.Duration
	Name       string
}

// Response represents a load test response
type Response struct {
	StatusCode    int
	Body          []byte
	Headers       map[string]string
	Latency       time.Duration
	ContentLength int64
	Error         error
}

// Client is the HTTP client for load testing
type Client struct {
	client    *http.Client
	targetCfg config.TargetConfig
	authCfg   config.AuthConfig
	baseURL   string
}

// NewClient creates a new HTTP client
func NewClient(targetCfg config.TargetConfig, authCfg config.AuthConfig) *Client {
	transport := &http.Transport{
		MaxIdleConns:        targetCfg.MaxIdle,
		MaxIdleConnsPerHost: targetCfg.MaxIdle,
		MaxConnsPerHost:     targetCfg.MaxConns,
		IdleConnTimeout:     90 * time.Second,
		DisableCompression:  false,
		DisableKeepAlives:   !targetCfg.KeepAlive,
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: false,
		},
		// Use DialContext for better control
		DialContext: (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
	}

	client := &http.Client{
		Transport: transport,
		Timeout:   targetCfg.Timeout,
	}

	baseURL := fmt.Sprintf("%s://%s:%d%s",
		targetCfg.Protocol,
		targetCfg.Host,
		targetCfg.Port,
		targetCfg.Path)

	return &Client{
		client:    client,
		targetCfg: targetCfg,
		authCfg:   authCfg,
		baseURL:   baseURL,
	}
}

// getAuthHeaders returns authentication headers based on auth type
func (c *Client) getAuthHeaders() map[string]string {
	headers := make(map[string]string)

	switch c.authCfg.Type {
	case "bearer":
		if c.authCfg.Token != "" {
			headers["Authorization"] = "Bearer " + c.authCfg.Token
		}
	case "basic":
		if c.authCfg.Username != "" && c.authCfg.Password != "" {
			// Basic auth would be handled at transport level
		}
	case "api_key":
		if c.authCfg.APIKey != "" {
			headers["X-API-Key"] = c.authCfg.APIKey
		}
	}

	return headers
}

// NewRequest creates a new request from config
func (c *Client) NewRequest(reqCfg config.RequestConfig) *Request {
	url := c.baseURL + reqCfg.Endpoint

	// Read body from file if specified
	body := []byte(reqCfg.Body)
	if reqCfg.BodyFile != "" {
		data, err := readFile(reqCfg.BodyFile)
		if err == nil {
			body = data
		}
	}

	// Merge headers - start with auth headers
	headers := c.getAuthHeaders()
	// Add request-specific headers
	for k, v := range reqCfg.Headers {
		headers[k] = v
	}

	timeout := reqCfg.Timeout
	if timeout == 0 {
		timeout = c.targetCfg.Timeout
	}

	return &Request{
		Method:  HTTPMethod(reqCfg.Method),
		URL:     url,
		Headers: headers,
		Body:    body,
		Timeout: timeout,
		Name:    reqCfg.Name,
	}
}

// Execute executes a request and returns the response
func (c *Client) Execute(ctx context.Context, req *Request) (*Response, error) {
	start := time.Now()

	var bodyReader io.Reader
	if len(req.Body) > 0 {
		bodyReader = bytes.NewReader(req.Body)
	}

	httpReq, err := http.NewRequestWithContext(ctx, string(req.Method), req.URL, bodyReader)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	for k, v := range req.Headers {
		httpReq.Header.Set(k, v)
	}

	// Handle basic auth if configured
	if c.authCfg.Type == "basic" && c.authCfg.Username != "" && c.authCfg.Password != "" {
		httpReq.SetBasicAuth(c.authCfg.Username, c.authCfg.Password)
	}

	// Execute request
	httpResp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer httpResp.Body.Close()

	// Read response body
	respBody, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	latency := time.Since(start)

	return &Response{
		StatusCode:    httpResp.StatusCode,
		Body:          respBody,
		Headers:       extractHeaders(httpResp.Header),
		Latency:       latency,
		ContentLength: httpResp.ContentLength,
	}, nil
}

// ExecuteWithRedirect executes a request following redirects
func (c *Client) ExecuteWithRedirect(ctx context.Context, req *Request, maxRedirects int) (*Response, error) {
	var lastResp *Response

	for i := 0; i < maxRedirects; i++ {
		resp, err := c.Execute(ctx, req)
		if err != nil {
			return nil, err
		}

		lastResp = resp

		// Check if redirect
		if resp.StatusCode >= 300 && resp.StatusCode < 400 {
			redirectURL, ok := resp.Headers["Location"]
			if !ok {
				break
			}

			// Handle relative URLs
			if !strings.HasPrefix(redirectURL, "http") {
				baseURL, _ := url.Parse(req.URL)
				redirectURL = baseURL.ResolveReference(&url.URL{Path: redirectURL}).String()
			}

			req.URL = redirectURL
			continue
		}

		break
	}

	return lastResp, nil
}

// Close closes the client and releases resources
func (c *Client) Close() {
	c.client.CloseIdleConnections()
}

// SetTimeout sets the request timeout
func (c *Client) SetTimeout(timeout time.Duration) {
	c.client.Timeout = timeout
}

// GetBaseURL returns the base URL
func (c *Client) GetBaseURL() string {
	return c.baseURL
}

// Helper functions

func readFile(path string) ([]byte, error) {
	return []byte{}, nil // Implementation would read from filesystem
}

func extractHeaders(header http.Header) map[string]string {
	headers := make(map[string]string)
	for k, v := range header {
		if len(v) > 0 {
			headers[k] = v[0]
		}
	}
	return headers
}

// ValidateMethod validates if the method is supported
func ValidateMethod(method string) bool {
	switch HTTPMethod(method) {
	case MethodGet, MethodPost, MethodPut, MethodPatch, MethodDelete, MethodHead, MethodOptions:
		return true
	default:
		return false
	}
}
