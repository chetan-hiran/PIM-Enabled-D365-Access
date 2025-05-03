#!/bin/bash

set -e  # exit on any error

export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Waiting for apt/dpkg lock to be released..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "[INFO] Lock detected, waiting 5 seconds..."
    sleep 5
done

echo "[INFO] Updating system and installing Docker and dependencies..."
sudo apt-get update -y
sudo apt-get install -y docker.io docker-compose curl unzip wget

echo "[INFO] Installing Azure CLI and AzCopy..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
wget -O azcopy_v10.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy_v10.tar.gz
sudo cp ./azcopy_linux_amd64_*/azcopy /usr/bin/
sudo chmod +x /usr/bin/azcopy

echo "[INFO] Logging into Azure using Managed Identity..."
managedIdentity="ac9124e3-66d3-4362-8ef2-15c274cf9834"
az login --identity --client-id "$managedIdentity" > /dev/null

STORAGE_ACCOUNT="staicoachconfigdev"
CONTAINER_NAME="config"
FILES=("dev.docker-compose.yaml" "caddy.yaml" "livekit.yaml" "redis.conf" ".env")
azcopy login --identity --identity-client-id "$managedIdentity"

echo "[INFO] Downloading configuration files from blob storage using azcopy..."
for file in "${FILES[@]}"; do
    azcopy copy "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${file}" "$HOME/${file}"
done

echo "[INFO] Starting docker-compose..."
docker-compose -f "$HOME/dev.docker-compose.yaml" up -d

echo "[INFO] Setup complete."
