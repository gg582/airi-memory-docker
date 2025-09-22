#!/bin/bash
set -e

mkdir -p "$HOME/airi_memory"
docker network create airi-net || true

docker run -d \
  --name airi-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=airi_memory_password \
  -e POSTGRES_DB=postgres \
  --network airi-net \
  -p 5434:5432 \
  ankane/pgvector:latest

echo "Waiting for Postgres to be ready..."
until docker exec airi-postgres pg_isready -U postgres -d postgres; do
  sleep 0.1
done

echo "Creating 'vector' extension..."
docker exec -i -e PGPASSWORD=airi_memory_password airi-postgres \
psql -U postgres -d postgres -h airi-postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

echo "Dumping database to a backup file..."
docker exec -i -e PGPASSWORD=airi_memory_password airi-postgres \
pg_dump -U postgres -d postgres > "$HOME/airi_memory/embedded_pg_backup.sql"

ARCH=$(arch)
if [ "$ARCH" = "ia64" ]; then
    ARCH=amd64
elif [ "$ARCH" = "x86_64" ]; then
    ARCH=amd64
elif [ "$ARCH" = "aarch64" ]; then
    ARCH=arm64
fi

docker run -d \
  --name airi-memory-service \
  -p 3001:3001 \
  -e DATABASE_URL="postgres://postgres:airi_memory_password@airi-postgres:5432/postgres" \
  --network airi-net \
  -v "$HOME/airi_memory:/airi_memory:z" \
  --user $(id -u):$(id -g) \
  gg582/airi-memory-service:$ARCH-0.7.2-beta.3
