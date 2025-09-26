# Function to check if Docker Desktop process is running
function Test-DockerProcess {
    try {
        if (Get-Process -Name "Docker Desktop" -ErrorAction Stop) {
            return $true
        }
    } catch {
        # Process not found
        return $false
    }
}

# Function to check if Docker daemon is ready
function Test-DockerDaemon {
    try {
        # Attempt a simple docker command that doesn't require containers
        docker info | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Start Docker Desktop if it's not running
Write-Host "Checking if Docker Desktop is running..."
if (-not (Test-DockerProcess)) {
    Write-Host "Docker Desktop is not running. Attempting to start it..."
    # IMPORTANT: Adjust the path to Docker Desktop.exe if necessary
    & "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    
    # Wait for the process to start
    do {
        Start-Sleep -Seconds 5
        Write-Host "Waiting for Docker Desktop process to start..."
    } until (Test-DockerProcess)
}

# Wait until the Docker daemon is fully ready
Write-Host "Waiting for Docker daemon to be ready..."
do {
    Start-Sleep -Seconds 5
    Write-Host "Checking Docker daemon status..."
} until (Test-DockerDaemon)

Write-Host "Docker Desktop and daemon are ready. Proceeding with setup."

# --- INITIAL SETUP (Network, Volumes, Container Creation, Migration) ---

# Create network if it doesn't exist
if (-not (docker network ls --filter name=airi-net -q)) {
    Write-Host "Creating Docker network 'airi-net'..."
    docker network create airi-net
}

# Create named volume for Postgres data
Write-Host "Creating Docker volume 'airi_db_volume'..."
docker volume create airi_db_volume | Out-Null

# Create named volume for memory-service data
Write-Host "Creating Docker volume 'airi_memory_volume'..."
docker volume create airi_memory_volume | Out-Null

# Check if 'airi-postgres' exists. If not, create and configure it.
if (-not (docker ps -a --filter name=airi-postgres -q)) {
    Write-Host "Creating and configuring airi-postgres container for the first time..."
    
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

    Write-Host "Waiting for Postgres to be ready for initial configuration..."
    # Wait until Postgres is accepting connections
    do {
        Start-Sleep -Milliseconds 100
        $ready = docker exec airi-postgres pg_isready -U postgres -d postgres 2>$null
    } until ($ready -match "accepting connections")

    Write-Host "Creating 'vector' extension..."
    docker exec -i `
        -e PGPASSWORD=airi_memory_password `
        airi-postgres psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

    # Download migration file to a tmp location
    Write-Host "Downloading migration file..."
    $TMPFILE = [System.IO.Path]::GetTempFileName()
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gg582/airi/refs/heads/experimental/rag-custom-build/services/memory-service/drizzle/0000_sharp_iceman.sql" `
        -OutFile $TMPFILE

    Write-Host "Applying migration..."
    Get-Content $TMPFILE | docker exec -i -e PGPASSWORD=airi_memory_password airi-postgres psql -U postgres -d postgres

    # Remove tmp migration file
    Write-Host "Removing temporary migration file..."
    Remove-Item $TMPFILE

    # Determine architecture
    Write-Host "Determining system architecture..."
    $ARCH = (docker info --format "{{.Architecture}}")
    if ($ARCH -eq "x86_64") {
        $ARCH = "amd64"
    } elseif ($ARCH -eq "aarch64") {
        $ARCH = "arm64"
    }

    # Run memory-service container
    Write-Host "Creating airi-memory-service container ($ARCH)..."
    docker run -d `
        --name airi-memory-service `
        -p 3001:3001 `
        -e DATABASE_URL="postgres://postgres:airi_memory_password@airi-postgres:5432/postgres" `
        --network airi-net `
        -v airi_memory_volume:/home/node/airi_memory:z `
        gg582/airi-memory-service:$ARCH-0.7.2-beta.3

    Write-Host "Initial container creation and configuration is complete."

} else {
    Write-Host "Containers already exist. Proceeding to simple startup sequence."
}

# --- CONTAINER STARTUP (Your requested addition) ---

Write-Host "Starting airi-postgres container..."
# Start Postgres container
docker start airi-postgres

Write-Host "Waiting for Postgres to be ready for connections..."
# Wait until Postgres is accepting connections
do {
    Start-Sleep -Milliseconds 100
    # Capture stderr and discard by redirecting to $null
    $ready = docker exec airi-postgres pg_isready -U postgres -d postgres 2>$null
} until ($ready -match "accepting connections")

Write-Host "Starting airi-memory-service container..."
# Start memory-service container
docker start airi-memory-service

Write-Host "All containers are now running."
