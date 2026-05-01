#!/bin/bash
# =============================================================
# DVSA PROJECT - SETUP SCRIPT
# Run this once to install all required tools
# =============================================================

echo "=========================================="
echo " DVSA Environment Setup"
echo "=========================================="

# 1. Update package list
echo "[1/6] Updating package list..."
sudo apt-get update -qq

# 2. Install basic tools
echo "[2/6] Installing curl, jq, python3, unzip..."
sudo apt-get install -y curl jq python3 python3-pip unzip

# 3. Install AWS CLI v2
echo "[3/6] Installing AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip
else
    echo "   AWS CLI already installed: $(aws --version)"
fi

# 4. Install Python packages
echo "[4/6] Installing Python packages..."
pip3 install pyjwt requests --quiet

# 5. Verify installations
echo "[5/6] Verifying installations..."
echo "   curl    : $(curl --version | head -1)"
echo "   jq      : $(jq --version)"
echo "   python3 : $(python3 --version)"
echo "   aws     : $(aws --version)"

# 6. Configure AWS CLI profile (credentials entered interactively)
echo "[6/6] Configure AWS CLI..."
echo ""
echo "   Run the following command and enter your credentials:"
echo "   aws configure"
echo ""
echo "   You will be prompted for:"
echo "   - AWS Access Key ID"
echo "   - AWS Secret Access Key"
echo "   - Default region: us-east-1"
echo "   - Default output format: json"
echo ""
echo "=========================================="
echo " Setup complete! Next: run 'aws configure'"
echo "=========================================="
