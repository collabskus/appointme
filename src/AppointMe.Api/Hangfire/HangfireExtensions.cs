using AppointMe.Shared.Jobs;
using Hangfire;
using Hangfire.SqlServer;

namespace AppointMe.Api.Hangfire;

public static class HangfireExtensions
{
    extension(IServiceCollection services)
    {
        public IServiceCollection AddAppointMeHangfire(IConfiguration configuration)
        {
            var connectionString = configuration.GetConnectionString("AppointMeSql")
                                   ?? throw new InvalidOperationException("Connection string 'AppointMeSql' not found");

            services.AddSingleton<SystemContextJobFilter>();

            services.AddHangfire((serviceProvider, config) => config
                .UseSimpleAssemblyNameTypeSerializer()
                .UseRecommendedSerializerSettings()
                .UseSqlServerStorage(connectionString, new SqlServerStorageOptions
                {
                    SchemaName = "hangfire",
                    PrepareSchemaIfNecessary = true,
                })
                .UseFilter(serviceProvider.GetRequiredService<SystemContextJobFilter>()));

            services.AddHangfireServer();
            services.AddSingleton<IRecurringJobScheduler, HangfireRecurringJobScheduler>();
            services.AddHostedService<RecurringJobsHostedService>();

            return services;
        }
    }

    extension(IApplicationBuilder app)
    {
        public IApplicationBuilder UseAppointMeHangfireDashboard()
        {
            app.UseHangfireDashboard("/admin/jobs", new DashboardOptions
            {
                // Authenticated users only. The default (local requests only)
                // is useless behind the tunnel, and an empty list would expose
                // the dashboard publicly in the Podman deployment.
                Authorization = [new AuthenticatedUserDashboardFilter()],
            });
            return app;
        }
    }
}
