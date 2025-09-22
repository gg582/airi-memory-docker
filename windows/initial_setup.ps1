# Create network if it doesn't exist
if (-not (docker network ls --filter name=airi-net -q)) {
    docker network create airi-net
}

# Run Postgres container
docker run -d `
  --name airi-postgres `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=airi_memory_password `
  -e POSTGRES_DB=postgres `
  --network airi-net `
  -p 5434:5432 `
  ankane/pgvector:latest

Write-Host "Waiting for Postgres to be ready..."
# Wait until Postgres is accepting connections
do {
    Start-Sleep -Milliseconds 100
    $ready = docker exec airi-postgres pg_isready -U postgres -d postgres 2>$null
} until ($ready -match "accepting connections")

# Install vector extension
docker exec -i airi-postgres psql -U postgres -d postgres -h 127.0.0.1 -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Run memory-service container
docker run -d `
  --name airi-memory-service `
  -p 3001:3001 `
  -e DATABASE_URL="postgres://postgres:airi_memory_password@airi-postgres:5432/postgres" `
  --network airi-net `
  gg582/airi-memory-service:0.7.2-beta.3

