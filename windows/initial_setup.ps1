# Create network if it doesn't exist
if (-not (docker network ls --filter name=airi-net -q)) {
    docker network create airi-net
}

# Create named volume for Postgres data
docker volume create airi_db_volume | Out-Null

# Run Postgres container
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

Write-Host "Creating 'vector' extension..."
docker exec -i `
    -e PGPASSWORD=airi_memory_password `
    airi-postgres psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Download migration file to a tmp location and apply inside container
$TMPFILE = [System.IO.Path]::GetTempFileName()
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gg582/airi/refs/heads/experimental/rag-custom-build/services/memory-service/drizzle/0000_sharp_iceman.sql" `
    -OutFile $TMPFILE

Write-Host "Applying migration..."
Get-Content $TMPFILE | docker exec -i -e PGPASSWORD=airi_memory_password airi-postgres psql -U postgres -d postgres

# Remove tmp migration file
Remove-Item $TMPFILE

# Determine architecture
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
    -v airi_memory_volume:/home/node/airi_memory:z `
    gg582/airi-memory-service:$ARCH-0.7.2-beta.3
