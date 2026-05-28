using System.ComponentModel;
using McpServer.Models;
using McpServer.Services;
using ModelContextProtocol.Server;

namespace McpServer.Tools;

[McpServerToolType]
public class TaskTools(TasksApiClient api)
{
    [McpServerTool(Name = "list_tasks")]
    [Description("List all to-do tasks owned by the signed-in user.")]
    public async Task<IReadOnlyList<TodoTask>> ListTasksAsync(CancellationToken ct)
        => await api.ListAsync(ct);

    [McpServerTool(Name = "get_task")]
    [Description("Get a single task by its numeric id.")]
    public async Task<TodoTask?> GetTaskAsync(
        [Description("The task id")] int id,
        CancellationToken ct)
        => await api.GetAsync(id, ct);

    [McpServerTool(Name = "create_task")]
    [Description("Create a new to-do task. Returns the created task with its assigned id.")]
    public async Task<TodoTask> CreateTaskAsync(
        [Description("Short, action-oriented title (max 200 chars)")] string title,
        [Description("Optional longer description")] string? description,
        [Description("Optional ISO-8601 due date, e.g. 2026-06-15T17:00:00Z")] DateTimeOffset? dueDate,
        CancellationToken ct)
        => await api.CreateAsync(new CreateTaskRequest(title, description, dueDate), ct);

    [McpServerTool(Name = "update_task")]
    [Description("Update an existing task. Only supplied fields are changed.")]
    public async Task<TodoTask?> UpdateTaskAsync(
        [Description("The task id to update")] int id,
        [Description("New title (optional)")] string? title,
        [Description("New description (optional)")] string? description,
        [Description("New status: Open, InProgress, Done, Cancelled (optional)")] TodoStatus? status,
        [Description("New due date (optional)")] DateTimeOffset? dueDate,
        CancellationToken ct)
        => await api.UpdateAsync(id, new UpdateTaskRequest(title, description, status, dueDate), ct);

    [McpServerTool(Name = "delete_task")]
    [Description("Delete a task by id. Returns true if deleted, false if not found.")]
    public async Task<bool> DeleteTaskAsync(
        [Description("The task id to delete")] int id,
        CancellationToken ct)
        => await api.DeleteAsync(id, ct);
}
