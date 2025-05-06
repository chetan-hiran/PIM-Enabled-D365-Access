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
# DOWNLOAD_PATH - Local directory to save downloaded files (defaults to $HOME/aicoach)
# MANAGED_IDENTITY_ID - Resource ID of the user-assigned managed identity (optional)

STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME:-"staicoacheastus2dev"}
STORAGE_CONTAINER_NAME=${STORAGE_CONTAINER_NAME:-"config"}
DOWNLOAD_PATH=${DOWNLOAD_PATH:-"/opt/aicoach"}
MANAGED_IDENTITY_ID=${MANAGED_IDENTITY_ID:-"ac9124e3-66d3-4362-8ef2-15c274cf9834"}

# Validate required parameters
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    log "Error: STORAGE_ACCOUNT_NAME environment variable is not set"
    exit 1
fi

if [ -z "$STORAGE_CONTAINER_NAME" ]; then
    log "Error: STORAGE_CONTAINER_NAME environment variable is not set"
    exit 1
fi

# Create download directory if it doesn't exist
mkdir -p "$DOWNLOAD_PATH"
log "Files will be downloaded to: $DOWNLOAD_PATH"

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
    log "Using User-Assigned Managed Identity: $MANAGED_IDENTITY_ID"
    IDENTITY_FLAG="--identity $MANAGED_IDENTITY_ID"
else
    log "Using system-assigned managed identity"
    IDENTITY_FLAG="--auth-mode login"
fi

az login --identity --client-id "$MANAGED_IDENTITY_ID" > /dev/null
if [ $? -ne 0 ]; then
    log "ERROR: Failed to authenticate with Azure using managed identity"
    exit 1
fi
log "Authenticated with Azure using managed identity"


# List blobs in the container
log "Attempting to list blobs in container $STORAGE_CONTAINER_NAME"
blob_list_result=$(az storage blob list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STORAGE_CONTAINER_NAME" \
    --auth-mode login \
    --query "[].name" -o tsv 2>&1)
az_status=$?

if [ $az_status -ne 0 ]; then
    log "ERROR: Failed to list blobs in container $STORAGE_CONTAINER_NAME. Error message: $blob_list_result"
    exit 1
fi

blob_list=$blob_list_result

if [ -z "$blob_list" ]; then
    log "No files found in the container $STORAGE_CONTAINER_NAME"
    exit 0
else
    log "Found files in container $STORAGE_CONTAINER_NAME. Starting download..."
    file_count=0
    success_count=0
    failed_files=()
    
    while IFS= read -r filename; do
        # Skip empty lines
        [ -z "$filename" ] && continue
        
        log "Downloading: $filename"
        file_count=$((file_count + 1))
        
        # Create directory structure if needed
        file_dir=$(dirname "$DOWNLOAD_PATH/$filename")
        mkdir -p "$file_dir"
        
        # Download the file with retry logic
        max_retries=3
        retry_count=0
        download_success=false
        
        while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
            az storage blob download \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --container-name "$STORAGE_CONTAINER_NAME" \
                --name "$filename" \
                --file "$DOWNLOAD_PATH/$filename" \
                $IDENTITY_FLAG \
                --output none
                
            if [ $? -eq 0 ]; then
                log "Successfully downloaded: $filename"
                success_count=$((success_count + 1))
                download_success=true
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    log "Retry $retry_count/$max_retries: Failed to download $filename. Retrying in 3 seconds..."
                    sleep 3
                else
                    log "ERROR: Failed to download $filename after $max_retries attempts"
                    failed_files+=("$filename")
                fi
            fi
        done
    done <<< "$blob_list"
    
    # Summary
    log "Download complete. Successfully downloaded $success_count out of $file_count files."
    
    if [ ${#failed_files[@]} -gt 0 ]; then
        log "WARNING: Failed to download ${#failed_files[@]} files:"
        for failed_file in "${failed_files[@]}"; do
            log "  - $failed_file"
        done
        exit 1
    fi
fi

log "Azure Blob Storage downloader script completed successfully"
exit 0
