using Prometheus;

namespace VerneMQWebhookAuth.Services;

/// <summary>
/// Custom Prometheus metrics for the webhook authentication service
/// </summary>
public static class AppMetrics
{
    // MQTT Authentication Metrics
    public static readonly Counter MqttAuthAttempts = Metrics.CreateCounter(
        "webhook_mqtt_auth_attempts_total",
        "Total number of MQTT authentication attempts",
        new CounterConfiguration
        {
            LabelNames = new[] { "result" }  // "success", "failure"
        });

    public static readonly Counter MqttPublishAuthAttempts = Metrics.CreateCounter(
        "webhook_mqtt_publish_auth_total",
        "Total number of MQTT publish authorization attempts",
        new CounterConfiguration
        {
            LabelNames = new[] { "result" }
        });

    public static readonly Counter MqttSubscribeAuthAttempts = Metrics.CreateCounter(
        "webhook_mqtt_subscribe_auth_total",
        "Total number of MQTT subscribe authorization attempts",
        new CounterConfiguration
        {
            LabelNames = new[] { "result" }
        });

    // Webhook Execution Metrics
    public static readonly Counter WebhookExecutions = Metrics.CreateCounter(
        "webhook_executions_total",
        "Total number of webhook executions",
        new CounterConfiguration
        {
            LabelNames = new[] { "status" }  // "success", "failed", "timeout"
        });

    public static readonly Histogram WebhookExecutionDuration = Metrics.CreateHistogram(
        "webhook_execution_duration_seconds",
        "Duration of webhook executions in seconds",
        new HistogramConfiguration
        {
            Buckets = Histogram.ExponentialBuckets(0.01, 2, 10)  // 10ms to ~10s
        });

    // Active Connections (Gauge)
    public static readonly Gauge ActiveConnections = Metrics.CreateGauge(
        "webhook_active_mqtt_connections",
        "Current number of active MQTT connections tracked by webhook service");

    // Dashboard Session Metrics
    public static readonly Counter DashboardLogins = Metrics.CreateCounter(
        "webhook_dashboard_logins_total",
        "Total number of dashboard login attempts",
        new CounterConfiguration
        {
            LabelNames = new[] { "result" }  // "success", "failure"
        });

    // User Management Metrics
    public static readonly Gauge TotalMqttUsers = Metrics.CreateGauge(
        "webhook_mqtt_users_total",
        "Total number of MQTT users configured");

    public static readonly Gauge ActiveMqttUsers = Metrics.CreateGauge(
        "webhook_mqtt_users_active",
        "Number of active MQTT users");

    // Webhook Configuration Metrics
    public static readonly Gauge TotalWebhooks = Metrics.CreateGauge(
        "webhook_configurations_total",
        "Total number of webhook configurations");

    public static readonly Gauge ActiveWebhooks = Metrics.CreateGauge(
        "webhook_configurations_active",
        "Number of active webhook configurations");

    // System Health Metrics
    public static readonly Gauge VerneMQConnectionStatus = Metrics.CreateGauge(
        "webhook_vernemq_connection_status",
        "VerneMQ broker connection status (1 = connected, 0 = disconnected)");

    public static readonly Gauge DatabaseConnectionStatus = Metrics.CreateGauge(
        "webhook_database_connection_status",
        "Database connection status (1 = connected, 0 = disconnected)");
}
