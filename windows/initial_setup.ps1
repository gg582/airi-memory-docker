# Create network if it doesn't exist
if (-not (docker network ls --filter name=airi-net -q)) {
    docker network create airi-net
}

# Run Postgres container with a named volume for persistence
docker volume create airi_db_volume | Out-Null
docker run -d `
    --name airi-postgres `
    -e POSTGRES_USER=postgres `
    -e POSTGRES_PASSWORD=airi_memory_password `
    -e POSTGRES_DB=postgres `
    --network airi-net `
    -p 5434:5432 `
    -v airi_db_volume:/var/lib/postgresql/data `
    ankane/pgvector:latest

Write-Host "Waiting for Postgres to be ready..."
# Wait until Postgres is accepting connections
do {
    Start-Sleep -Milliseconds 100
    $ready = docker exec airi-postgres pg_isready -U postgres -d postgres 2>$null
} until ($ready -match "accepting connections")

# Install vector extension
docker exec -i `
    -e PGPASSWORD=airi_memory_password `
    airi-postgres psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Determine the architecture
$ARCH = (docker info --format "{{.Architecture}}")
if ($ARCH -eq "x86_64") {
    $ARCH = "amd64"
} elseif ($ARCH -eq "aarch64") {
    $ARCH = "arm64"
}

# Run memory-service container
docker run -d `
    --name airi-memory-service `
    -p 3001:3001 `
    -e DATABASE_URL="postgres://postgres:airi_memory_password@airi-postgres:5432/postgres" `
    --network airi-net `
    gg582/airi-memory-service:$ARCH-0.7.2-beta.3
