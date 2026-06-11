using AppointMe.Crm.Customers;
using AppointMe.Shared.Authorization.Permissions.DefaultGrants;
using AppointMe.Shared.Authorization.Roles;

namespace AppointMe.Crm.Authorization;

public sealed class CrmDefaultGrantPolicy : IDefaultGrantPolicy
{
    public IReadOnlyCollection<RolePermissionGrant> DefaultGrants =>
    [
        new(Role.Owner,
            CustomerPermissions.View,
            CustomerPermissions.Create,
            CustomerPermissions.Update,
            CustomerPermissions.Delete
        ),
        new(Role.Manager,
            CustomerPermissions.View,
            CustomerPermissions.Create,
            CustomerPermissions.Update
        ),
        new(Role.Staff,
            CustomerPermissions.View
        ),
        new(Role.Receptionist,
            CustomerPermissions.View,
            CustomerPermissions.Create,
            CustomerPermissions.Update
        )
    ];
}
