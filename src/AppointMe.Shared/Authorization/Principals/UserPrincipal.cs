using AppointMe.Shared.Authorization.Permissions;
using AppointMe.Shared.Authorization.Roles;
using AppointMe.Shared.Companies;

namespace AppointMe.Shared.Authorization.Principals;

public sealed record UserPrincipal(CompanyId CompanyId, IReadOnlySet<Role> Roles, IReadOnlySet<Permission> Permissions)
    : IPrincipal
{
    public bool HasRole(Role role) => Roles.Contains(role);
    public bool HasPermission(Permission permission) => Permissions.Contains(permission);
}
