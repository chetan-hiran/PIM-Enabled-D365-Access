#!/bin/bash

set -e  # Exit on any error
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Waiting for dpkg/apt lock..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "[INFO] Another apt process is running. Waiting..."
    sleep 5
done

echo "[INFO] Updating system and installing Docker and dependencies..."
apt-get update -y
apt-get install -y docker.io docker-compose curl unzip wget

echo "[INFO] Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

echo "[INFO] Installing AzCopy..."
wget -O azcopy_v10.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy_v10.tar.gz
cp ./azcopy_linux_amd64_*/azcopy /usr/bin/
chmod +x /usr/bin/azcopy
rm -rf azcopy_v10.tar.gz azcopy_linux_amd64_*

echo "[INFO] Logging into Azure using Managed Identity..."
MANAGED_IDENTITY="ac9124e3-66d3-4362-8ef2-15c274cf9834"
az login --identity --client-id "$MANAGED_IDENTITY" >/dev/null

echo "[INFO] Creating app directory..."
mkdir -p /opt/app
cd /opt/app

STORAGE_ACCOUNT="staicoachconfigdev"
CONTAINER_NAME="config"
FILES=("dev.docker-compose.yaml" "caddy.yaml" "livekit.yaml" "redis.conf" ".env")

echo "[INFO] Downloading configuration files from blob storage using AzCopy..."
for file in "${FILES[@]}"; do
    azcopy copy "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${file}" .
done

echo "[INFO] Starting docker-compose..."
docker-compose -f dev.docker-compose.yaml up -d

echo "[INFO] Setup complete."
