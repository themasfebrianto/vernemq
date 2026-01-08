# Prometheus & Grafana Implementation Analysis

## Executive Summary

This document provides a comprehensive analysis of the Prometheus and Grafana monitoring implementation in the VerneMQ webhook authentication dashboard. The monitoring stack is **production-ready** with proper Docker integration, auto-provisioning, and VerneMQ metrics collection.

### ✅ Improvements Implemented (2026-01-08)

Based on the initial analysis, the following enhancements have been applied:

1. **Webhook-Auth `/metrics` Endpoint** - Added `prometheus-net.AspNetCore` for HTTP metrics
2. **Custom Application Metrics** - Created `AppMetrics.cs` for tracking MQTT auth attempts
3. **Health Checks** - Added to Prometheus and Grafana containers
4. **Resource Limits** - Memory/CPU limits added to monitoring containers
5. **Secure Credentials** - Grafana password now via environment variable
6. **Alerting Rules** - Created `alerts.yml` with VerneMQ and webhook monitoring rules
7. **Data Retention** - Prometheus retention policy (15 days / 5GB)
8. **Useful Plugins** - Grafana clock and piechart panels auto-installed

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Components Analysis](#components-analysis)
3. [Configuration Deep Dive](#configuration-deep-dive)
4. [Metrics Collection](#metrics-collection)
5. [Dashboard Implementation](#dashboard-implementation)
6. [Integration Points](#integration-points)
7. [Strengths](#strengths)
8. [Areas for Improvement](#areas-for-improvement)
9. [Recommendations](#recommendations)

---

## Architecture Overview

### Monitoring Stack Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Docker Network                              │
│                       (vernemq-network)                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │  VerneMQ    │───▶│  Prometheus  │───▶│      Grafana         │  │
│  │ (port 8888) │    │ (port 9090)  │    │    (port 3030)       │  │
│  └─────────────┘    └──────────────┘    └──────────────────────┘  │
│        │                   │                       │               │
│        │                   │              ┌────────┴────────┐      │
│        ▼                   ▼              │   Provisioning  │      │
│  /metrics endpoint   prometheus_data     ├─────────────────┤      │
│                       (volume)           │  - datasources  │      │
│                                          │  - dashboards   │      │
│  ┌─────────────┐                        └─────────────────┘      │
│  │webhook-auth │                                                   │
│  │ (port 5000) │◀── /metrics endpoint                             │
│  └─────────────┘                                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **VerneMQ** → Exposes Prometheus metrics at `vernemq:8888/metrics`
2. **Webhook-Auth** → Exposes application metrics at `webhook-auth:80/metrics`
3. **Prometheus** → Scrapes both targets every 15 seconds
4. **Grafana** → Queries Prometheus for visualization

---

## Components Analysis

### 1. Docker Compose Configuration (`docker-compose.yml`)

**Location:** `d:\LCS\vernemq\docker-compose.yml` (Lines 65-108)

#### Prometheus Service
```yaml
prometheus:
  image: prom/prometheus:latest
  container_name: prometheus
  ports:
    - "9090:9090"
  volumes:
    - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - prometheus_data:/prometheus
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
    - '--web.console.libraries=/etc/prometheus/console_libraries'
    - '--web.console.templates=/etc/prometheus/consoles'
    - '--web.enable-lifecycle'
  restart: always
  networks:
    - vernemq-network
```

| Aspect | Status | Details |
|--------|--------|---------|
| Image | ✅ Good | Uses `prom/prometheus:latest` |
| Port Mapping | ✅ Good | Exposed on standard port 9090 |
| Configuration | ✅ Good | Read-only config mount |
| Data Persistence | ✅ Good | Named volume `prometheus_data` |
| Hot Reload | ✅ Good | `--web.enable-lifecycle` enabled |
| Restart Policy | ✅ Good | `restart: always` |
| Network | ✅ Good | Proper network isolation |

#### Grafana Service
```yaml
grafana:
  image: grafana/grafana:latest
  container_name: grafana
  ports:
    - "3030:3000"
  environment:
    - GF_SECURITY_ADMIN_USER=admin
    - GF_SECURITY_ADMIN_PASSWORD=admin
    - GF_USERS_ALLOW_SIGN_UP=false
    - GF_AUTH_ANONYMOUS_ENABLED=true
    - GF_AUTH_ANONYMOUS_ORG_NAME=Main Org.
    - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
    - GF_SECURITY_ALLOW_EMBEDDING=true
    - GF_SERVER_SERVE_FROM_SUB_PATH=false
  volumes:
    - grafana_data:/var/lib/grafana
    - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
  depends_on:
    - prometheus
  restart: always
  networks:
    - vernemq-network
```

| Aspect | Status | Details |
|--------|--------|---------|
| Image | ✅ Good | Uses `grafana/grafana:latest` |
| Port Mapping | ✅ Good | Port 3030 → 3000 (avoids conflicts) |
| Anonymous Access | ✅ Good | Enabled for embedding |
| Embedding | ✅ Good | `GF_SECURITY_ALLOW_EMBEDDING=true` |
| Provisioning | ✅ Good | Auto-provisioned datasources & dashboards |
| Data Persistence | ✅ Good | Named volume `grafana_data` |
| Dependencies | ✅ Good | Waits for Prometheus |
| Credentials | ⚠️ Warning | Default admin/admin credentials |

---

### 2. Prometheus Configuration (`prometheus.yml`)

**Location:** `d:\LCS\vernemq\monitoring\prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'vernemq'
    static_configs:
      - targets: ['vernemq:8888']
    metrics_path: /metrics

  - job_name: 'webhook-auth'
    static_configs:
      - targets: ['webhook-auth:80']
    metrics_path: /metrics
```

| Aspect | Status | Details |
|--------|--------|---------|
| Scrape Interval | ✅ Good | 15s is appropriate for real-time monitoring |
| Self-Monitoring | ✅ Good | Prometheus monitors itself |
| VerneMQ Target | ✅ Good | Correct container name and port |
| Webhook-Auth Target | ⚠️ Check | Target defined but no metrics endpoint implemented |
| Service Discovery | ❌ Missing | Static configs only (acceptable for simple setup) |
| Alerting Rules | ❌ Missing | No alertmanager configuration |

---

### 3. Grafana Provisioning

#### Datasource Configuration
**Location:** `d:\LCS\vernemq\monitoring\grafana\provisioning\datasources\datasources.yml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
```

| Aspect | Status | Details |
|--------|--------|---------|
| API Version | ✅ Good | Version 1 (current) |
| Datasource Type | ✅ Good | Prometheus |
| Access Mode | ✅ Good | Proxy (recommended) |
| URL | ✅ Good | Uses Docker internal DNS |
| Default | ✅ Good | Set as default datasource |

#### Dashboard Provisioning
**Location:** `d:\LCS\vernemq\monitoring\grafana\provisioning\dashboards\dashboards.yml`

```yaml
apiVersion: 1

providers:
  - name: 'VerneMQ Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards
```

| Aspect | Status | Details |
|--------|--------|---------|
| Provider Type | ✅ Good | File-based provisioning |
| Editable | ✅ Good | Dashboards are editable |
| Folder Organization | ⚠️ Basic | No folder structure |

---

### 4. Pre-Built Dashboard (`vernemq-dashboard.json`)

**Location:** `d:\LCS\vernemq\monitoring\grafana\provisioning\dashboards\vernemq-dashboard.json`

#### Dashboard Panels

| Panel ID | Title | Type | Metrics Used |
|----------|-------|------|--------------|
| 1 | Total Connections | stat | `sum(vernemq_mqtt_connect_received)` |
| 2 | Messages Received | stat | `sum(vernemq_mqtt_publish_received)` |
| 3 | Total Subscriptions | stat | `sum(vernemq_mqtt_subscribe_received)` |
| 4 | Webhook Auth Requests | stat | `sum(vernemq_webhooks_on_register_requests)` |
| 5 | Message Rate (per second) | timeseries | `rate(vernemq_mqtt_publish_received[1m])`, `rate(vernemq_mqtt_publish_sent[1m])` |
| 6 | Connection Rate (per second) | timeseries | `rate(vernemq_mqtt_connect_received[1m])`, `rate(vernemq_mqtt_disconnect_received[1m])` |
| 7 | Scheduler Utilization (%) | timeseries | `vernemq_system_utilization_scheduler_*` |
| 8 | Webhook Requests Rate | timeseries | `rate(vernemq_webhooks_on_*_requests[1m])` |

#### Dashboard Configuration

| Aspect | Status | Details |
|--------|--------|---------|
| Refresh Rate | ✅ Good | 5 seconds auto-refresh |
| Time Range | ✅ Good | Default 1 hour |
| Schema Version | ✅ Good | Version 38 (modern) |
| Tags | ✅ Good | vernemq, mqtt, iot |
| UID | ✅ Good | `vernemq-mqtt` (stable) |
| Plugin Version | ✅ Good | 10.0.0 compatible |

---

### 5. Legacy Dashboard (`VerneMQ Node Metrics.json`)

**Location:** `d:\LCS\vernemq\metrics_scripts\grafana\VerneMQ Node Metrics.json`

This is an **older/legacy dashboard** (3316 lines, Grafana 4.1.2 compatible) with more extensive metrics:

#### Key Panels
- Connected Clients (`socket_open - socket_close`)
- Queue Processes (`queue_processes`)
- Current MQTT Receive Rate (`rate(mqtt_publish_received[30s])`)
- Current MQTT Send Rate (`rate(mqtt_publish_sent[30s])`)
- VerneMQ Node Uptime (`system_wallclock`)
- Erlang VM Utilization (`system_utilization`)
- Connect/Disconnect Rate
- Queue Setup/Teardown Rate

| Aspect | Status | Details |
|--------|--------|---------|
| Grafana Version | ⚠️ Outdated | Designed for Grafana 4.1.2 |
| Metric Names | ⚠️ Legacy | Uses old metric names (without `vernemq_` prefix) |
| Datasource | ❌ Issue | Requires `DS_PROMETHEUS_FORWARDER` variable |
| Panel Types | ⚠️ Outdated | Uses deprecated `singlestat` panel type |

---

## Metrics Collection

### SystemController Implementation

**Location:** `d:\LCS\vernemq\VerneMQWebhookAuth\Controllers\SystemController.cs`

The webhook-auth service integrates with VerneMQ metrics via direct HTTP calls:

```csharp
// Get VerneMQ broker metrics
[HttpGet("vernemq-metrics")]
public async Task<ActionResult<VerneMQMetricsDto>> GetVerneMQMetrics()
{
    // Fetches from VerneMQ status.json endpoint
    var statusUrl = $"http://{vernemqHost}:{vernemqPort}/status.json";
    
    // Also fetches Prometheus metrics for detailed data
    var metricsUrl = $"http://{vernemqHost}:{vernemqPort}/metrics";
}
```

#### Parsed Prometheus Metrics

| Metric Name | DTO Property | Data Type |
|-------------|--------------|-----------|
| `vernemq_mqtt_connect_received` | ActiveConnections | int |
| `vernemq_mqtt_publish_received` | MessagesReceived | long |
| `vernemq_mqtt_publish_sent` | MessagesSent | long |
| `vernemq_mqtt_subscribe_received` | TotalSubscriptions | int |

---

## Integration Points

### 1. Dashboard UI Integration

The webhook-auth dashboard fetches metrics via:
- **API Endpoint:** `/api/system/vernemq-metrics`
- **Called From:** `dashboard.js` → `Monitoring.loadVerneMQMetrics()`

### 2. External Access URLs

| Service | Internal URL | External URL |
|---------|--------------|--------------|
| Prometheus | http://prometheus:9090 | http://localhost:9090 |
| Grafana | http://grafana:3000 | http://localhost:3030 |
| VerneMQ Metrics | http://vernemq:8888/metrics | http://localhost:8888/metrics |

### 3. Grafana Embedding Support

Grafana is configured for iframe embedding:
- `GF_SECURITY_ALLOW_EMBEDDING=true`
- `GF_AUTH_ANONYMOUS_ENABLED=true`
- `GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer`

---

## Strengths

### ✅ What's Done Well

1. **Proper Docker Orchestration**
   - All services on the same network
   - Correct service dependencies
   - Named volumes for persistence

2. **Auto-Provisioning**
   - Datasources auto-configured
   - Dashboards auto-loaded on startup
   - No manual setup required

3. **Modern Dashboard**
   - Uses current Grafana schema (v38)
   - Timeseries panels (not deprecated graphs)
   - Proper refresh intervals

4. **Embedding Ready**
   - Anonymous access for viewers
   - Embedding enabled
   - CORS-friendly configuration

5. **VerneMQ Native Metrics**
   - Uses VerneMQ's built-in Prometheus endpoint
   - Correct metric names with `vernemq_` prefix
   - Webhook-specific metrics included

6. **Application Integration**
   - SystemController parses VerneMQ metrics
   - Dashboard UI displays real-time data
   - Both status.json and /metrics endpoints used

---

## Areas for Improvement

### ⚠️ Issues & Gaps

1. **Security Concerns**
   ```yaml
   # Default credentials - CHANGE FOR PRODUCTION
   GF_SECURITY_ADMIN_USER=admin
   GF_SECURITY_ADMIN_PASSWORD=admin
   ```

2. **Missing Webhook-Auth Metrics Endpoint**
   - Prometheus is configured to scrape `webhook-auth:80/metrics`
   - No `/metrics` endpoint implemented in the .NET application
   - Will result in scrape failures

3. **No Alerting Configuration**
   - No Alertmanager integration
   - No alert rules defined
   - No notification channels configured

4. **Legacy Dashboard Not Integrated**
   - `VerneMQ Node Metrics.json` in `metrics_scripts/grafana/` is not provisioned
   - Contains useful additional panels but requires migration

5. **Missing Dashboard Links in UI**
   - No direct links to Prometheus/Grafana in the webhook dashboard
   - Users must know the URLs manually

6. **No Health Checks for Monitoring Stack**
   - Prometheus container has no health check
   - Grafana container has no health check

7. **No Resource Limits**
   - Prometheus and Grafana have no memory/CPU limits
   - Could impact system stability under load

---

## Recommendations

### 🔧 Immediate Actions (High Priority)

1. **Change Default Grafana Credentials**
   ```yaml
   environment:
     - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-changeme}
   ```

2. **Add Health Checks**
   ```yaml
   prometheus:
     healthcheck:
       test: ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
       interval: 30s
       timeout: 10s
       retries: 3
   
   grafana:
     healthcheck:
       test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/api/health"]
       interval: 30s
       timeout: 10s
       retries: 3
   ```

3. **Implement Webhook-Auth Metrics Endpoint**
   ```csharp
   // Add to SystemController.cs
   [HttpGet("/metrics")]
   [AllowAnonymous]
   public IActionResult GetPrometheusMetrics()
   {
       // Implement prometheus-net or custom metrics
   }
   ```
   
   Or add the `prometheus-net` NuGet package:
   ```bash
   dotnet add package prometheus-net.AspNetCore
   ```

### 🔧 Medium Priority

4. **Add Resource Limits**
   ```yaml
   prometheus:
     deploy:
       resources:
         limits:
           memory: 1G
           cpus: '1.0'
   
   grafana:
     deploy:
       resources:
         limits:
           memory: 512M
           cpus: '0.5'
   ```

5. **Add Prometheus Alerting**
   Create `monitoring/prometheus/alerts.yml`:
   ```yaml
   groups:
     - name: vernemq_alerts
       rules:
         - alert: VerneMQDown
           expr: up{job="vernemq"} == 0
           for: 1m
           labels:
             severity: critical
           annotations:
             summary: "VerneMQ is down"
   ```

6. **Migrate Legacy Dashboard**
   - Update `VerneMQ Node Metrics.json` to Grafana 10+ format
   - Replace `singlestat` panels with `stat` panels
   - Update metric names to use `vernemq_` prefix

### 🔧 Nice to Have

7. **Add Dashboard Links to Webhook UI**
   ```html
   <!-- In _MonitoringTab.cshtml -->
   <a href="http://localhost:9090" target="_blank">Prometheus</a>
   <a href="http://localhost:3030" target="_blank">Grafana</a>
   ```

8. **Add Retention Policy**
   ```yaml
   prometheus:
     command:
       - '--storage.tsdb.retention.time=15d'
       - '--storage.tsdb.retention.size=10GB'
   ```

9. **Add Grafana Plugins**
   ```yaml
   grafana:
     environment:
       - GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel
   ```

---

## Summary Score Card

| Category | Score | Notes |
|----------|-------|-------|
| Docker Integration | 9/10 | Excellent setup, minor health check gaps |
| Prometheus Config | 7/10 | Good basics, missing alerting |
| Grafana Setup | 8/10 | Well provisioned, security needs attention |
| Dashboard Quality | 8/10 | Modern and functional |
| VerneMQ Integration | 9/10 | Native Prometheus support used correctly |
| Security | 5/10 | Default credentials, anonymous access |
| Production Readiness | 7/10 | Good foundation, needs hardening |

### Overall Assessment: **7.5/10** ✅ **FUNCTIONAL BUT NEEDS HARDENING**

The monitoring stack is well-designed and functional for development/staging. For production deployment, focus on:
1. Security hardening (credentials, access control)
2. Adding alerting capabilities
3. Implementing webhook-auth `/metrics` endpoint
4. Adding health checks and resource limits

---

## File References

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definitions |
| `monitoring/prometheus.yml` | Prometheus scrape configuration |
| `monitoring/grafana/provisioning/datasources/datasources.yml` | Datasource auto-provisioning |
| `monitoring/grafana/provisioning/dashboards/dashboards.yml` | Dashboard provider config |
| `monitoring/grafana/provisioning/dashboards/vernemq-dashboard.json` | Pre-built VerneMQ dashboard |
| `metrics_scripts/grafana/VerneMQ Node Metrics.json` | Legacy dashboard (not provisioned) |
| `VerneMQWebhookAuth/Controllers/SystemController.cs` | API for fetching VerneMQ metrics |
| `VerneMQWebhookAuth/wwwroot/js/dashboard.js` | Frontend metrics display |

---

*Analysis generated on: 2026-01-08*  
*VerneMQ Version: Latest*  
*Grafana Dashboard Schema: v38*  
*Prometheus Configuration: v2*
