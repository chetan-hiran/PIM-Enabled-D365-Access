#!/bin/bash

# azure-blob-downloader.sh
# Script to list and download files from Azure Blob Storage
# Uses managed identity authentication for secure access to Azure resources

# Log function for better debugging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting Azure Blob Storage downloader script"

# Configuration parameters (should be passed as environment variables)
# STORAGE_ACCOUNT_NAME - Name of the Azure Storage account
# STORAGE_CONTAINER_NAME - Name of the blob container
# FILES - Array of specific file names to download
# MANAGED_IDENTITY_ID - Resource ID of the user-assigned managed identity (optional)

STORAGE_ACCOUNT_NAME="staicoachconfigdev"
STORAGE_CONTAINER_NAME="config"
FILES=("dev.docker-compose.yaml" "caddy.yaml" "livekit.yaml" "redis.conf" ".env")
MANAGED_IDENTITY_ID="ac9124e3-66d3-4362-8ef2-15c274cf9834"

# Validate required parameters
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    log "Error: STORAGE_ACCOUNT_NAME environment variable is not set"
    exit 1
fi

# Check for Azure CLI
if ! command -v az &> /dev/null; then
    log "Azure CLI not found. Installing..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    if ! command -v az &> /dev/null; then
        log "Failed to install Azure CLI. Please install manually and retry."
        exit 1
    fi
    log "Azure CLI installed successfully"
fi

if [ -n "$MANAGED_IDENTITY_ID" ]; then
    log "Using Managed Identity: $MANAGED_IDENTITY_ID"
    IDENTITY_FLAG="--identity $MANAGED_IDENTITY_ID"
else
    log "Using system-assigned managed identity"
    IDENTITY_FLAG="--auth-mode login"
fi

# List blobs in the container
blob_list=$(az storage blob list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STORAGE_CONTAINER_NAME" \
    $IDENTITY_FLAG \
    --query "[].name" -o tsv 2>/dev/null)

if [ $? -ne 0 ]; then
    log "ERROR: Failed to list blobs in container $STORAGE_CONTAINER_NAME"
    exit 1
fi

if [ -z "$blob_list" ]; then
    log "No files found in the container"
else
    log "Available files in container:"
    echo "$blob_list" | while read -r file; do
        log "  - $file"
    done
fi

# Optional: Download specific files
for filename in "${FILES[@]}"; do
    log "Downloading $filename..."
    az storage blob download \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$STORAGE_CONTAINER_NAME" \
        --name "$filename" \
        --file "$filename" \
        $IDENTITY_FLAG \
        --output none
    if [ $? -eq 0 ]; then
        log "Downloaded $filename successfully"
    else
        log "Failed to download $filename"
    fi
done
