using AppointMe.Shared.Authorization.Permissions;
using AppointMe.Shared.Authorization.Roles;

namespace AppointMe.Shared.Authorization.Principals;

public sealed record SystemPrincipal : IPrincipal
{
    public bool HasRole(Role role) => true;
    public bool HasPermission(Permission permission) => true;
}
