using Hangfire.Dashboard;

namespace AppointMe.Api.Hangfire;

/// <summary>
/// Grants Hangfire dashboard access only to authenticated users.
///
/// The dashboard is mapped after UseAuthentication, so the cookie principal is
/// available here — log in to the app, then open /admin/jobs. Hangfire's
/// default filter (LocalRequestsOnlyAuthorizationFilter) would block everything
/// behind a reverse proxy or tunnel, and an empty filter list leaves the
/// dashboard open to anyone who can reach the API — which, in the Podman
/// deployment, is the whole internet via the Cloudflare Tunnel. Requiring an
/// authenticated user is the minimal safe middle ground for this sandbox.
/// </summary>
internal sealed class AuthenticatedUserDashboardFilter : IDashboardAuthorizationFilter
{
    public bool Authorize(DashboardContext context)
    {
        var httpContext = context.GetHttpContext();
        return httpContext.User.Identity?.IsAuthenticated == true;
    }
}
