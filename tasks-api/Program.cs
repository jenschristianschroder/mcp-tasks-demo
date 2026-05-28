using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Identity.Web;
using TasksApi.Data;
using TasksApi.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));

builder.Services.AddAuthorization();
builder.Services.AddDbContext<TasksDbContext>(o =>
    o.UseNpgsql(builder.Configuration.GetConnectionString("TasksDb")));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<TasksDbContext>();
    db.Database.Migrate();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthentication();
app.UseAuthorization();

var tasks = app.MapGroup("/tasks").RequireAuthorization();

tasks.MapGet("/", async (TasksDbContext db, HttpContext ctx) =>
{
    var oid = ctx.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;
    return await db.Tasks.Where(t => t.OwnerOid == oid).ToListAsync();
});

tasks.MapGet("/{id:int}", async (int id, TasksDbContext db, HttpContext ctx) =>
{
    var oid = ctx.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;
    var task = await db.Tasks.FindAsync(id);
    if (task is null || task.OwnerOid != oid) return Results.NotFound();
    return Results.Ok(task);
});

tasks.MapPost("/", async (CreateTaskRequest req, TasksDbContext db, HttpContext ctx) =>
{
    var oid = ctx.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value
        ?? throw new InvalidOperationException("Missing oid claim");
    var task = new TodoTask
    {
        Title = req.Title,
        Description = req.Description,
        DueDate = req.DueDate,
        Status = TodoStatus.Open,
        OwnerOid = oid,
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow
    };
    db.Tasks.Add(task);
    await db.SaveChangesAsync();
    return Results.Created($"/tasks/{task.Id}", task);
});

tasks.MapPut("/{id:int}", async (int id, UpdateTaskRequest req, TasksDbContext db, HttpContext ctx) =>
{
    var oid = ctx.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;
    var task = await db.Tasks.FindAsync(id);
    if (task is null || task.OwnerOid != oid) return Results.NotFound();

    if (req.Title is not null) task.Title = req.Title;
    if (req.Description is not null) task.Description = req.Description;
    if (req.Status is not null) task.Status = req.Status.Value;
    if (req.DueDate is not null) task.DueDate = req.DueDate;
    task.UpdatedAt = DateTimeOffset.UtcNow;

    await db.SaveChangesAsync();
    return Results.Ok(task);
});

tasks.MapDelete("/{id:int}", async (int id, TasksDbContext db, HttpContext ctx) =>
{
    var oid = ctx.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;
    var task = await db.Tasks.FindAsync(id);
    if (task is null || task.OwnerOid != oid) return Results.NotFound();
    db.Tasks.Remove(task);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

app.Run();
