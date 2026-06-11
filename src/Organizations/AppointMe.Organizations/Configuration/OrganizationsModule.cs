using AppointMe.Organizations.Companies;
using AppointMe.Organizations.Contracts.Companies;
using AppointMe.Organizations.Contracts.Employees;
using AppointMe.Organizations.Database;
using AppointMe.Organizations.Employees;
using AppointMe.Organizations.Employees.Database;
using AppointMe.Organizations.Infrastructure;
using AppointMe.Organizations.Settings.Permissions.Infrastructure;
using AppointMe.Shared.Authorization.Permissions;
using AppointMe.Shared.Authorization.Permissions.OverrideConflicts;
using AppointMe.Shared.Configuration;
using AppointMe.Shared.Database;
using AppointMe.Shared.Database.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Wolverine.Attributes;

[assembly: WolverineModule]

namespace AppointMe.Organizations.Configuration;

public static class OrganizationsModule
{
    extension(IServiceCollection services)
    {
        public IServiceCollection AddOrganizationsModule()
        {
            return services
                .AddDbContext<OrganizationsDbContext>((serviceProvider, options) =>
                {
                    options.UseSqlServer(serviceProvider.GetRequiredService<ConnectionStrings>().AppointMeSql,
                        builder =>
                        {
                            builder.MigrationsHistoryTable("__EFMigrationsHistory",
                                OrganizationsDbContext.DefaultSchema);
                        });
                })
                .AddDatabaseMigration<OrganizationsDbContext>()
                .AddEndpoints(ModuleAssembly.Instance)
                .AddSingleton<IDbConnectionFactory, SqlConnectionFactory>(serviceProvider =>
                    new SqlConnectionFactory(serviceProvider.GetRequiredService<ConnectionStrings>().AppointMeSql))
                .AddScoped<TeamRepository>()
                .AddScoped<UserPrincipalFactory>()
                .AddScoped<RolePermissionOverridesCache>()
                .AddScoped<ICompanyRehydrationSource, CompanyRehydrationSource>()
                .AddScoped<IEmployeeRehydrationSource, EmployeeRehydrationSource>()
                .AddSingleton<IOverrideConflictPolicy, DenyWinsPolicy>()
                .AddSingleton<PermissionResolver>()
                .AddPermissions(ModuleAssembly.Instance);
        }
    }
}
