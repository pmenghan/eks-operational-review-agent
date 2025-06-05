#!/bin/bash

# Script to upload the EKS Operations Agent package to S3

# Configuration
S3_BUCKET="your-s3-bucket-name"
S3_KEY="eks-operations-agent.zip"
SOURCE_PATH="https://raw.githubusercontent.com/pmenghan/eks-operational-review-agent/main/eks-operations-agent.zip"
TEMP_DIR="/tmp/eks-agent-$(date +%s)"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "curl is not installed. Please install it first."
    exit 1
fi

# Create temporary directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || exit 1

# Download the package
echo "Downloading package from GitHub..."
if ! curl -L -o "$S3_KEY" "$SOURCE_PATH"; then
    echo "Failed to download the package from GitHub"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Verify file exists and has size greater than 0
if [ ! -s "$S3_KEY" ]; then
    echo "Downloaded file is empty or does not exist"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Upload to S3
echo "Uploading package to S3..."
if aws s3 cp "$S3_KEY" "s3://${S3_BUCKET}/${S3_KEY}"; then
    echo "Upload successful!"
    echo "Package available at: s3://${S3_BUCKET}/${S3_KEY}"
    echo ""
    echo "To deploy on EC2, use the following commands:"
    echo "aws s3 cp s3://${S3_BUCKET}/${S3_KEY} ."
    echo "unzip ${S3_KEY}"
    echo "cd eks-operations-agent"
    echo "sudo ./deploy_s3.sh"
else
    echo "Upload failed. Please check your AWS credentials and S3 bucket permissions."
fi

# Cleanup
rm -rf "$TEMP_DIR"
