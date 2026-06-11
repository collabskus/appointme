using AppointMe.Identity.Database;
using AppointMe.Identity.Entra;
using AppointMe.Identity.Keycloak;
using AppointMe.Identity.Users;
using AppointMe.Shared.Authorization.Permissions;
using AppointMe.Shared.Configuration;
using AppointMe.Shared.Database;
using AppointMe.Shared.Database.Migrations;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Wolverine.Attributes;

[assembly: WolverineModule]

namespace AppointMe.Identity.Configuration;

public static class IdentityModule
{
    extension(IServiceCollection services)
    {
        public IServiceCollection AddIdentityModule(IConfiguration configuration)
        {
            services
                .AddDbContext<IdentityDbContext>((serviceProvider, options) =>
                {
                    options.UseSqlServer(serviceProvider.GetRequiredService<ConnectionStrings>().AppointMeSql,
                        builder =>
                        {
                            builder.MigrationsHistoryTable("__EFMigrationsHistory",
                                IdentityDbContext.DefaultSchema);
                        });
                })
                .AddDatabaseMigration<IdentityDbContext>()
                .AddEndpoints(ModuleAssembly.Instance)
                .AddSingleton<IDbConnectionFactory, SqlConnectionFactory>(serviceProvider =>
                    new SqlConnectionFactory(serviceProvider.GetRequiredService<ConnectionStrings>().AppointMeSql))
                .AddPermissions(ModuleAssembly.Instance)
                .AddScoped<IUserIdentityRegistry, UserIdentityRegistry>();

            var provider = configuration["Authentication:Provider"] ?? "Keycloak";
            switch (provider)
            {
                case "Keycloak":
                    services.AddKeycloakIdentityProvider();
                    break;
                case "EntraExternalId":
                    services.AddEntraIdentityProvider();
                    break;
                default:
                    throw new InvalidOperationException(
                        $"Unknown Authentication:Provider '{provider}'. Expected 'Keycloak' or 'EntraExternalId'.");
            }

            return services;
        }
    }
}
