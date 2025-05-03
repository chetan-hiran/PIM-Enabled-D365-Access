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

echo "[INFO] Setup complete."
