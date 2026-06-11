using AppointMe.Shared.Authorization.Permissions;
using AppointMe.Shared.Authorization.Roles;

namespace AppointMe.Shared.Authorization.Principals;

public sealed record AnonymousPrincipal : IPrincipal
{
    public bool HasRole(Role role) => false;
    public bool HasPermission(Permission permission) => false;
}
