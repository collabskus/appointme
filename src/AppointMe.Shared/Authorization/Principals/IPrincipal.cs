using AppointMe.Shared.Authorization.Permissions;
using AppointMe.Shared.Authorization.Roles;

namespace AppointMe.Shared.Authorization.Principals;

public interface IPrincipal
{
    public bool HasRole(Role role);
    public bool HasPermission(Permission permission);
}
