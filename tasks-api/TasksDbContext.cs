using Microsoft.EntityFrameworkCore;
using TasksApi.Models;

namespace TasksApi.Data;

public class TasksDbContext(DbContextOptions<TasksDbContext> options) : DbContext(options)
{
    public DbSet<TodoTask> Tasks => Set<TodoTask>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<TodoTask>()
            .HasIndex(t => t.OwnerOid);
    }
}
