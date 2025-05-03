#!/bin/bash

set -e  # exit on any error

echo "[INFO] Updating system and installing Docker and dependencies..."
apt-get update -y
apt-get install -y docker.io docker-compose curl unzip

echo "[INFO] Installing Azure CLI and AzCopy..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
wget -O azcopy_v10.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy_v10.tar.gz
cp ./azcopy_linux_amd64_*/azcopy /usr/bin/
chmod +x /usr/bin/azcopy

echo "[INFO] Logging into Azure using Managed Identity..."

$managedIdentity = "ac9124e3-66d3-4362-8ef2-15c274cf9834"
az login --identity --client-id $managedIdentity | Out-Null

echo "[INFO] Creating app directory..."
mkdir -p /opt/app
cd /opt/app

STORAGE_ACCOUNT="staicoachconfigdev"
CONTAINER_NAME="config"
FILES=("dev.docker-compose.yaml" "caddy.yaml" "livekit.yaml" "redis.conf", ".env")

echo "[INFO] Downloading configuration files from blob storage using azcopy..."
for file in "${FILES[@]}"; do
    azcopy copy "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${file}" .
done

echo "[INFO] Starting docker-compose..."
docker-compose -f dev.docker-compose.yaml up -d

echo "[INFO] Setup complete."
