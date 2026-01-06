# Use the official .NET 8.0 runtime as the base image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

# Use the official .NET 8.0 SDK as the build environment
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project file and restore dependencies
COPY ["VerneMQWebhookAuth.csproj", "./"]
RUN dotnet restore "VerneMQWebhookAuth.csproj"

# Copy source code and build the application
COPY . .
RUN dotnet build "VerneMQWebhookAuth.csproj" -c Release -o /app/build

# Publish the application
FROM build AS publish
RUN dotnet publish "VerneMQWebhookAuth.csproj" -c Release -o /app/publish

# Create the final image
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Create necessary directories
RUN mkdir -p /app/logs

# Set environment variables for production
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=http://+:80

# Switch to non-root user for security
USER app

ENTRYPOINT ["dotnet", "VerneMQWebhookAuth.dll"]
