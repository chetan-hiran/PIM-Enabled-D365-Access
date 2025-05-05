#!/bin/bash

# deploy-docker-compose.sh
# Script to deploy docker-compose services on Azure VMSS
# This script is designed to be used with VMSS Custom Script Extension

# Log function for better debugging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/deploy-docker-compose.log
}

log "Starting deployment script for AI.Coach docker services"

# Configuration parameters (should be passed as environment variables to VMSS extension)
# STORAGE_ACCOUNT_NAME - Name of the Azure Storage account
# STORAGE_CONTAINER_NAME - Name of the blob container
# ENVIRONMENT - Environment to deploy (dev, prod, etc.)
STORAGE_ACCOUNT_NAME="staicoachconfigdev"
STORAGE_CONTAINER_NAME="config"
ENVIRONMENT=${ENVIRONMENT:-"dev"}

if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    log "Error: STORAGE_ACCOUNT_NAME environment variable is not set"
    exit 1
fi

log "Using Storage Account: $STORAGE_ACCOUNT_NAME"
log "Using Container: $STORAGE_CONTAINER_NAME"
log "Using Environment: $ENVIRONMENT"

# Set working directory
WORKDIR="/opt/ai-coach"
mkdir -p $WORKDIR
cd $WORKDIR

log "Working directory set to $WORKDIR"

# Install required dependencies
log "Installing required dependencies..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common jq netcat-openbsd

# Install Azure CLI if not already installed
if ! command -v az &> /dev/null; then
    log "Installing Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    log "Azure CLI installed successfully"
else
    log "Azure CLI is already installed"
fi

# Install Docker and Docker Compose if not already installed
if ! command -v docker &> /dev/null; then
    log "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    log "Docker installed successfully"
else
    log "Docker is already installed"
fi

if ! command -v docker-compose &> /dev/null; then
    log "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    log "Docker Compose installed successfully"
else
    log "Docker Compose is already installed"
fi

# Function to download a file from Azure Blob Storage using Managed Identity
download_blob() {
    local blob_name=$1
    local output_file=$2
    local max_retries=2
    local retry_count=0
    local wait_time=5

    log "Downloading $blob_name to $output_file..."
    
    while [ $retry_count -lt $max_retries ]; do
        # Use managed identity to get a token for the storage account
        # If running outside Azure VM with managed identity, az CLI will fall back to interactive login
        az storage blob download --auth-mode login \
            --account-name $STORAGE_ACCOUNT_NAME \
            --container-name $STORAGE_CONTAINER_NAME \
            --name "$blob_name" \
            --file "$output_file" \
            --output none 2>/dev/null
            
        if [ $? -eq 0 ]; then
            log "Successfully downloaded $blob_name"
            return 0
        else
            retry_count=$((retry_count+1))
            log "Failed to download $blob_name (Attempt: $retry_count/$max_retries). Retrying in $wait_time seconds..."
            sleep $wait_time
            wait_time=$((wait_time*2)) # Exponential backoff
        fi
    done

    log "ERROR: Failed to download $blob_name after $max_retries attempts"
    return 1
}

# Download configuration files
log "Downloading configuration files from Azure Blob Storage..."
mkdir -p $WORKDIR/caddy_data

# Download Docker Compose file
if ! download_blob "${ENVIRONMENT}.docker-compose.yaml" "$WORKDIR/docker-compose.yaml"; then
    log "Failed to download docker-compose.yaml. Exiting."
    exit 1
fi

# Download Caddy config
if ! download_blob "caddy.yaml" "$WORKDIR/caddy.yaml"; then
    log "Failed to download caddy.yaml. Exiting."
    exit 1
fi

# Download LiveKit config
if ! download_blob "livekit.yaml" "$WORKDIR/livekit.yaml"; then
    log "Failed to download livekit.yaml. Exiting."
    exit 1
fi

# Download Redis config
if ! download_blob "redis.conf" "$WORKDIR/redis.conf"; then
    log "Failed to download redis.conf. Exiting."
    exit 1
fi

log "All configuration files downloaded successfully"

# Pull Docker images in advance to avoid delays during startup
log "Pulling Docker images..."
docker pull livekit/caddyl4
docker pull livekit/livekit-server:latest
docker pull redis:7-alpine
log "Docker images pulled successfully"

# Deploy with Docker Compose
log "Deploying services with Docker Compose..."
cd $WORKDIR
docker-compose -f docker-compose.yaml down || true
docker-compose -f docker-compose.yaml up -d

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    log "Services deployed successfully"
else
    log "Error: Some services failed to start. Check the logs with 'docker-compose logs'"
    exit 1
fi

# Add health check script
cat > $WORKDIR/health-check.sh << 'EOF'
#!/bin/bash

# Function to check if a port is open
check_port() {
    local port=$1
    nc -z localhost $port
    return $?
}

# Check all services
services_status=0

# Check Caddy (port 80)
if ! check_port 80; then
    echo "Caddy is not running on port 80"
    services_status=1
fi

# Check LiveKit (port 7880)
if ! check_port 7880; then
    echo "LiveKit is not running on port 7880"
    services_status=1
fi

# Check Redis (port 6379)
if ! check_port 6379; then
    echo "Redis is not running on port 6379"
    services_status=1
fi

exit $services_status
EOF

chmod +x $WORKDIR/health-check.sh
log "Health check script created"

# Create a systemd service to ensure docker-compose starts on boot
cat > /etc/systemd/system/ai-coach.service << EOF
[Unit]
Description=AI Coach Docker Compose Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORKDIR
ExecStart=/usr/local/bin/docker-compose -f docker-compose.yaml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.yaml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable ai-coach.service
systemctl start ai-coach.service

log "Systemd service created and started"
log "Deployment completed successfully"

exit 0