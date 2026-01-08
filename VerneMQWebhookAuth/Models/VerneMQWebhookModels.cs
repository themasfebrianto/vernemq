using System.Text.Json.Serialization;

namespace VerneMQWebhookAuth.Models;

/// <summary>
/// Base request from VerneMQ webhook
/// </summary>
public class VerneMQBaseRequest
{
    [JsonPropertyName("mountpoint")]
    public string? MountPoint { get; set; }
    
    [JsonPropertyName("client_id")]
    public string? ClientId { get; set; }
    
    [JsonPropertyName("username")]
    public string? Username { get; set; }
    
    [JsonPropertyName("peer_addr")]
    public string? PeerAddr { get; set; }
    
    [JsonPropertyName("peer_port")]
    public int? PeerPort { get; set; }
}

/// <summary>
/// Request for auth_on_register webhook
/// </summary>
public class AuthOnRegisterRequest : VerneMQBaseRequest
{
    [JsonPropertyName("password")]
    public string? Password { get; set; }
    
    [JsonPropertyName("clean_session")]
    public bool? CleanSession { get; set; }
}

/// <summary>
/// Request for auth_on_publish webhook
/// </summary>
public class AuthOnPublishRequest : VerneMQBaseRequest
{
    [JsonPropertyName("qos")]
    public int? Qos { get; set; }
    
    [JsonPropertyName("topic")]
    public string? Topic { get; set; }
    
    [JsonPropertyName("payload")]
    public string? Payload { get; set; }
    
    [JsonPropertyName("retain")]
    public bool? Retain { get; set; }
}

/// <summary>
/// Request for auth_on_subscribe webhook
/// </summary>
public class AuthOnSubscribeRequest : VerneMQBaseRequest
{
    [JsonPropertyName("topics")]
    public List<TopicSubscription>? Topics { get; set; }
}

public class TopicSubscription
{
    [JsonPropertyName("topic")]
    public string? Topic { get; set; }
    
    [JsonPropertyName("qos")]
    public int? Qos { get; set; }
}

/// <summary>
/// Response for VerneMQ webhooks
/// </summary>
public class VerneMQResponse
{
    public object Result { get; set; } = "ok";
}

/// <summary>
/// Error response
/// </summary>
public class VerneMQErrorResult
{
    public string Error { get; set; } = "not_authorized";
}

/// <summary>
/// Request for on_client_offline and on_client_wakeup hooks
/// </summary>
public class ClientStatusRequest : VerneMQBaseRequest
{
}

