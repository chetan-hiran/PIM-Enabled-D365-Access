#!/bin/bash

set -e  # exit on any error
echo "[INFO] Updating system and installing Docker and dependencies..."
apt-get update -y
apt-get install -y docker.io docker-compose curl unzip wget

echo "[INFO] Installing Azure CLI and AzCopy..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
wget -O azcopy_v10.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy_v10.tar.gz
cp ./azcopy_linux_amd64_*/azcopy /usr/bin/
chmod +x /usr/bin/azcopy


echo "[INFO] Logging into Azure using Managed Identity..."

echo "[INFO] Setup complete."
