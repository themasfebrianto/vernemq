namespace VerneMQWebhookAuth.Models;

/// <summary>
/// Base request from VerneMQ webhook
/// </summary>
public class VerneMQBaseRequest
{
    public string? MountPoint { get; set; }
    public string? ClientId { get; set; }
    public string? Username { get; set; }
    public string? PeerAddr { get; set; }
    public int? PeerPort { get; set; }
}

/// <summary>
/// Request for auth_on_register webhook
/// </summary>
public class AuthOnRegisterRequest : VerneMQBaseRequest
{
    public string? Password { get; set; }
    public bool? CleanSession { get; set; }
}

/// <summary>
/// Request for auth_on_publish webhook
/// </summary>
public class AuthOnPublishRequest : VerneMQBaseRequest
{
    public int? Qos { get; set; }
    public string? Topic { get; set; }
    public string? Payload { get; set; }
    public bool? Retain { get; set; }
}

/// <summary>
/// Request for auth_on_subscribe webhook
/// </summary>
public class AuthOnSubscribeRequest : VerneMQBaseRequest
{
    public List<TopicSubscription>? Topics { get; set; }
}

public class TopicSubscription
{
    public string? Topic { get; set; }
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
