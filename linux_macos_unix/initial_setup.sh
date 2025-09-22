#!/bin/bash
set -e

# Cleanup existing containers and network
echo "Cleaning up existing containers and network..."
docker stop airi-postgres airi-memory-service >/dev/null 2>&1 || true
docker rm airi-postgres airi-memory-service >/dev/null 2>&1 || true
docker network rm airi-net >/dev/null 2>&1 || true

mkdir -p "$HOME/airi_memory"
docker network create airi-net

# Start Postgres with pgvector
docker run -d \
  --name airi-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=airi_memory_password \
  -e POSTGRES_DB=postgres \
  --network airi-net \
  -p 5434:5432 \
  ankane/pgvector:latest

echo "Waiting for Postgres to be ready..."
until docker exec airi-postgres pg_isready -U postgres -d postgres >/dev/null 2>&1; do
  sleep 0.1
done

echo "Creating 'vector' extension..."
docker exec -i -e PGPASSWORD=airi_memory_password airi-postgres \
  psql -U postgres -d postgres -h airi-postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Download migration file to tmp and apply
TMPFILE=$(mktemp)
echo "Downloading migration to $TMPFILE ..."
curl -sL \
  "https://raw.githubusercontent.com/gg582/airi/refs/heads/experimental/rag-custom-build/services/memory-service/drizzle/0000_sharp_iceman.sql" \
  -o "$TMPFILE"

echo "Applying migration..."
docker exec -i -e PGPASSWORD=airi_memory_password airi-postgres \
  psql -U postgres -d postgres -h airi-postgres < "$TMPFILE"

rm -f "$TMPFILE"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  ia64)   ARCH=amd64 ;;
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
esac

# Run memory service
docker run -d \
  --name airi-memory-service \
  -p 3001:3001 \
  -e DATABASE_URL="postgres://postgres:airi_memory_password@airi-postgres:5432/postgres" \
  --network airi-net \
  -v "$HOME/airi_memory:/home/node/airi_memory:z" \
  --user $(id -u):$(id -g) \
  gg582/airi-memory-service:$ARCH-0.7.2-beta.3
