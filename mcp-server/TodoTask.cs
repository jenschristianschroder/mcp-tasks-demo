using System.Text.Json.Serialization;

namespace McpServer.Models;

public class TodoTask
{
    public int Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public TodoStatus Status { get; set; }
    public DateTimeOffset? DueDate { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum TodoStatus
{
    Open,
    InProgress,
    Done,
    Cancelled
}

public record CreateTaskRequest(string Title, string? Description, DateTimeOffset? DueDate);
public record UpdateTaskRequest(string? Title, string? Description, TodoStatus? Status, DateTimeOffset? DueDate);
