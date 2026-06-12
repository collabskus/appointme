# Build context is the repo root, not src/AppointMe.Api.
#
# Plain multi-stage Dockerfile syntax — builds identically under Podman/Buildah
# (rootful or rootless) and Docker/BuildKit. All base images are fully
# qualified: Podman on Fedora enforces short-name resolution, and an
# unqualified name like `node:22-alpine` can fail or prompt in a
# non-interactive `podman-compose build`.

# Stage 1: frontend bundle
FROM docker.io/library/node:22-alpine AS frontend
WORKDIR /src
COPY src/AppointMe.Frontend/package.json src/AppointMe.Frontend/yarn.lock ./
RUN yarn install --frozen-lockfile
COPY src/AppointMe.Frontend/ ./
RUN yarn build

# Stage 2: API publish
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY . .
RUN dotnet restore AppointMe.sln
RUN ASPNETCORE_ENVIRONMENT=Codegen \
    dotnet run --project src/AppointMe.Api/AppointMe.Api.csproj \
    -c $BUILD_CONFIGURATION --no-restore --no-launch-profile -- codegen write
RUN dotnet publish src/AppointMe.Api/AppointMe.Api.csproj \
    -c $BUILD_CONFIGURATION \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

# Stage 3: runtime
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app/publish ./
COPY --from=frontend /src/dist ./wwwroot
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
USER $APP_UID
ENTRYPOINT ["dotnet", "AppointMe.Api.dll"]
