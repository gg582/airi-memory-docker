#!/bin/bash
docker network create airi-net
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
docker exec -i airi-postgres psql -U postgres -d postgres -h localhost -c "CREATE EXTENSION IF NOT EXISTS vector;"
docker run -d \
  --name airi-memory-service \
  -p 3001:3001 \
  -e DATABASE_URL="postgres://postgres:airi_memory_password@airi-postgres:5432/postgres" \
  --network airi-net \
  gg582/airi-memory-service:0.7.2-beta.3

