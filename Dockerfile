# ---- Build stage ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project files first for better Docker layer caching
COPY src/NEFMP.Ebilling.Domain/NEFMP.Ebilling.Domain.csproj src/NEFMP.Ebilling.Domain/
COPY src/NEFMP.Ebilling.Api/NEFMP.Ebilling.Api.csproj src/NEFMP.Ebilling.Api/
RUN dotnet restore src/NEFMP.Ebilling.Api/NEFMP.Ebilling.Api.csproj

# Copy everything else and build
COPY src/ src/
RUN dotnet publish src/NEFMP.Ebilling.Api/NEFMP.Ebilling.Api.csproj -c Release -o /app --no-restore

# ---- Runtime stage ----
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

# Railway sets PORT at runtime; Program.cs reads it directly, no hardcoding needed here.
ENTRYPOINT ["dotnet", "NEFMP.Ebilling.Api.dll"]
