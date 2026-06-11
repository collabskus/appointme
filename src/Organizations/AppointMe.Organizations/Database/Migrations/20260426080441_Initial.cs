using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AppointMe.Organizations.Database.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "organizations");

            migrationBuilder.CreateTable(
                name: "Companies",
                schema: "organizations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(250)", maxLength: 250, nullable: false),
                    TimeZone = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    RegisteredBy = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    RegistrationDate = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    PrimaryOwnerEmployeeId = table.Column<Guid>(type: "uniqueidentifier", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Companies", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "EmployeeInvitations",
                schema: "organizations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Email = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Roles = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    Status = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    InvitedBy = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    InvitedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    AcceptedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmployeeInvitations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_EmployeeInvitations_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalSchema: "organizations",
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Employees",
                schema: "organizations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    FirstName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    LastName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    Email = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Roles = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    UserId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    RegistrationDate = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    SearchKey = table.Column<string>(type: "nvarchar(max)", nullable: true, computedColumnSql: "LOWER(CONCAT([FirstName], ' ', ISNULL([LastName], ''), ' ', [Email]))", stored: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Employees", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Employees_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalSchema: "organizations",
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "RolePermissionOverrides",
                schema: "organizations",
                columns: table => new
                {
                    CompanyId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    Role = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    PermissionCode = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    IsGranted = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RolePermissionOverrides", x => new { x.CompanyId, x.Role, x.PermissionCode });
                    table.ForeignKey(
                        name: "FK_RolePermissionOverrides_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalSchema: "organizations",
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Companies_PrimaryOwnerEmployeeId",
                schema: "organizations",
                table: "Companies",
                column: "PrimaryOwnerEmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeInvitations_CompanyId_Email",
                schema: "organizations",
                table: "EmployeeInvitations",
                columns: new[] { "CompanyId", "Email" },
                unique: true,
                filter: "[Status] = 'Pending'");

            migrationBuilder.CreateIndex(
                name: "IX_Employees_CompanyId_Email",
                schema: "organizations",
                table: "Employees",
                columns: new[] { "CompanyId", "Email" },
                unique: true,
                filter: "[IsDeleted] = 0");

            migrationBuilder.AddForeignKey(
                name: "FK_Companies_Employees_PrimaryOwnerEmployeeId",
                schema: "organizations",
                table: "Companies",
                column: "PrimaryOwnerEmployeeId",
                principalSchema: "organizations",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Companies_Employees_PrimaryOwnerEmployeeId",
                schema: "organizations",
                table: "Companies");

            migrationBuilder.DropTable(
                name: "EmployeeInvitations",
                schema: "organizations");

            migrationBuilder.DropTable(
                name: "RolePermissionOverrides",
                schema: "organizations");

            migrationBuilder.DropTable(
                name: "Employees",
                schema: "organizations");

            migrationBuilder.DropTable(
                name: "Companies",
                schema: "organizations");
        }
    }
}
