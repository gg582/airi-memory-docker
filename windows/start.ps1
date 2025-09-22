# Start Postgres container
docker start airi-postgres

# Wait until Postgres is accepting connections
do {
    Start-Sleep -Milliseconds 100
    $ready = docker exec airi-postgres pg_isready -U postgres -d postgres 2>$null
} until ($ready -match "accepting connections")

# Start memory-service container
docker start airi-memory-service

