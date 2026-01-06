using Microsoft.AspNetCore.SignalR;

namespace VerneMQWebhookAuth.Hubs;

/// <summary>
/// SignalR hub for real-time webhook updates
/// </summary>
public class WebhookHub : Hub
{
    /// <summary>
    /// Join a webhook-specific group to receive updates for that webhook
    /// </summary>
    /// <param name="webhookId">The webhook ID to join</param>
    public async Task JoinWebhookGroup(string webhookId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"webhook_{webhookId}");
        await SendMessageToGroup($"webhook_{webhookId}", "Joined webhook group", $"Successfully joined webhook group for ID: {webhookId}");
    }

    /// <summary>
    /// Leave a webhook-specific group
    /// </summary>
    /// <param name="webhookId">The webhook ID to leave</param>
    public async Task LeaveWebhookGroup(string webhookId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"webhook_{webhookId}");
        await SendMessageToGroup($"webhook_{webhookId}", "Left webhook group", $"Successfully left webhook group for ID: {webhookId}");
    }

    /// <summary>
    /// Join a general notifications group
    /// </summary>
    public async Task JoinNotifications()
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, "notifications");
        await SendMessageToGroup("notifications", "Connected", "Successfully joined notifications group");
    }

    /// <summary>
    /// Send a message to a specific group
    /// </summary>
    /// <param name="groupName">The group name</param>
    /// <param name="title">Message title</param>
    /// <param name="message">Message content</param>
    public async Task SendMessageToGroup(string groupName, string title, string message)
    {
        await Clients.Group(groupName).SendAsync("ReceiveMessage", new
        {
            Title = title,
            Message = message,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Send webhook execution update to a specific group
    /// </summary>
    /// <param name="webhookId">Webhook ID</param>
    /// <param name="execution">Execution details</param>
    public async Task SendExecutionUpdate(string webhookId, object execution)
    {
        await Clients.Group($"webhook_{webhookId}").SendAsync("ExecutionUpdate", execution);
    }

    /// <summary>
    /// Send system status update to all connected clients
    /// </summary>
    /// <param name="status">System status</param>
    public async Task BroadcastSystemStatus(object status)
    {
        await Clients.All.SendAsync("SystemStatusUpdate", status);
    }

    /// <summary>
    /// Called when a client connects
    /// </summary>
    public override async Task OnConnectedAsync()
    {
        await base.OnConnectedAsync();

        // Auto-join notifications group for all clients
        await JoinNotifications();

        // Send welcome message
        await Clients.Caller.SendAsync("ReceiveMessage", new
        {
            Title = "Connected",
            Message = "Welcome to Webhook Management System",
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Called when a client disconnects
    /// </summary>
    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        await base.OnDisconnectedAsync(exception);

        if (exception != null)
        {
            // Log disconnection with exception details
            Console.WriteLine($"Client disconnected: {Context.ConnectionId}, Exception: {exception.Message}");
        }
    }
}